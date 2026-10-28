// Vidya — Security Practices in C
//
// C trusts the programmer completely — no bounds checking, no type
// safety at runtime, no garbage collector. Security in C means:
// validate every buffer size, use safe string functions, check every
// return value, and assume all input is hostile.
#define _GNU_SOURCE

#include <assert.h>
#include <errno.h>
#include <limits.h>
#include <stdckdint.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// ── Constant-time comparison ──────────────────────────────────────────
// Prevents timing side-channel attacks on secret comparison.
// Examines every byte regardless of where they differ.
static int constant_time_eq(const void *a, const void *b, size_t len) {
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;
    unsigned char diff = 0;
    for (size_t i = 0; i < len; i++) {
        diff |= x[i] ^ y[i];
    }
    return diff == 0;  // 1 if equal, 0 if different
}

static void test_constant_time_comparison(void) {
    const char *secret  = "super_secret_token_2024";
    const char *correct = "super_secret_token_2024";
    const char *wrong   = "super_secret_token_2025";
    size_t len = strlen(secret);

    assert(constant_time_eq(secret, correct, len) == 1);
    assert(constant_time_eq(secret, wrong, len) == 0);
    assert(constant_time_eq("", "", 0) == 1);
}

// ── Secure memory zeroing ─────────────────────────────────────────────
// Plain memset can be optimized away if the buffer is never read again.
// C23 standardizes the fix: memset_explicit (<string.h>, C23 7.26.6.2)
// is never elided. Before C23 the options were non-standard —
// explicit_bzero (BSD/glibc extension, not POSIX), memset_s (optional
// Annex K, absent from glibc) or a volatile-pointer loop.
static void secure_zero(void *buf, size_t len) {
    memset_explicit(buf, 0, len);
}

static void test_secure_zeroing(void) {
    char password[] = "hunter2_secret";
    assert(strlen(password) == 14);

    secure_zero(password, sizeof(password));
    for (size_t i = 0; i < sizeof(password); i++) {
        assert(password[i] == 0);
    }
}

// ── Buffer overflow prevention ────────────────────────────────────────
// Always track buffer sizes and use bounded operations.
static int safe_copy(char *dst, size_t dst_size, const char *src) {
    size_t src_len = strlen(src);
    if (src_len >= dst_size) {  // >= because we need room for '\0'
        return -1;  // would overflow
    }
    memcpy(dst, src, src_len + 1);
    return 0;
}

static void test_buffer_overflow_prevention(void) {
    char buf[8];

    // The copy runs outside assert(): under -DNDEBUG assert's expression
    // is not evaluated, so assert(safe_copy(...) == 0) would never copy.
    // Safe: fits within buffer
    int rc = safe_copy(buf, sizeof(buf), "hello");
    assert(rc == 0);
    assert(strcmp(buf, "hello") == 0);

    // Rejected: would overflow
    rc = safe_copy(buf, sizeof(buf), "this is way too long");
    assert(rc == -1);

    // Edge case: exactly fills buffer
    rc = safe_copy(buf, sizeof(buf), "1234567");   // 7 chars + \0 = 8
    assert(rc == 0);

    // Edge case: one too many
    rc = safe_copy(buf, sizeof(buf), "12345678");  // 8 chars + \0 = 9 > 8
    assert(rc == -1);
}

// ── Format string safety ─────────────────────────────────────────────
// Never pass user input as a format string. Use %s explicitly.
static void test_format_string_safety(void) {
    const char *user_input = "%x%x%x%n";  // malicious format string

    // BAD: printf(user_input) — interprets %x as format specifiers
    //   printf(user_input);  // reads stack, %n writes to memory!

    // GOOD: printf("%s", user_input) — prints literal string
    char buf[64];
    int n = snprintf(buf, sizeof(buf), "%s", user_input);
    assert(n > 0);
    assert(strcmp(buf, "%x%x%x%n") == 0);  // literal, not interpreted
}

// ── Integer overflow checks ───────────────────────────────────────────
// The hand-written pre-checks below are portable to any C version. C23's
// <stdckdint.h> gives the same check as a language facility:
// ckd_add/ckd_sub/ckd_mul(&result, a, b) return true on overflow and work
// for any integer type, so there is no per-type helper to get wrong.
static int safe_add_u32(uint32_t a, uint32_t b, uint32_t *result) {
    if (a > UINT32_MAX - b) {
        return -1;  // would overflow
    }
    *result = a + b;
    return 0;
}

static int safe_mul_u32(uint32_t a, uint32_t b, uint32_t *result) {
    if (b != 0 && a > UINT32_MAX / b) {
        return -1;  // would overflow
    }
    *result = a * b;
    return 0;
}

static void test_integer_overflow(void) {
    uint32_t result;

    // Each checked operation writes *result, so it runs outside assert():
    // under -DNDEBUG assert's expression is not evaluated and result is
    // never set.
    int rc = safe_add_u32(100, 200, &result);
    assert(rc == 0);
    assert(result == 300);
    rc = safe_add_u32(UINT32_MAX, 1, &result);
    assert(rc == -1);

    rc = safe_mul_u32(1000, 1000, &result);
    assert(rc == 0);
    assert(result == 1000000);
    rc = safe_mul_u32(65536, 65536, &result);  // overflow
    assert(rc == -1);

    // Buffer allocation: width * height * bytes_per_pixel — check EVERY
    // multiply. 40000 * 40000 fits in u32; * 4 bytes per pixel does not.
    uint32_t pixels;
    rc = safe_mul_u32(40000, 40000, &pixels);
    assert(rc == 0);
    rc = safe_mul_u32(pixels, 4, &result);
    assert(rc == -1);

    // Same check with C23 checked arithmetic
    uint32_t bytes;
    bool overflowed = ckd_mul(&pixels, (uint32_t)40000, (uint32_t)40000);
    assert(!overflowed);
    overflowed = ckd_mul(&bytes, pixels, (uint32_t)4);
    assert(overflowed);  // true = overflowed
}

// ── Input validation ──────────────────────────────────────────────────
static int validate_username(const char *input, size_t max_len) {
    if (input == NULL || input[0] == '\0') {
        return -1;  // empty
    }
    size_t len = strnlen(input, max_len + 1);
    if (len > max_len) {
        return -1;  // too long
    }
    // Allowlist: alphanumeric and underscore only
    for (size_t i = 0; i < len; i++) {
        char c = input[i];
        int valid = (c >= 'a' && c <= 'z') ||
                    (c >= 'A' && c <= 'Z') ||
                    (c >= '0' && c <= '9') ||
                    (c == '_');
        if (!valid) {
            return -1;
        }
    }
    return 0;
}

static void test_input_validation(void) {
    assert(validate_username("alice_42", 32) == 0);
    assert(validate_username("", 32) == -1);
    assert(validate_username(NULL, 32) == -1);
    assert(validate_username("alice; DROP TABLE", 32) == -1);
    assert(validate_username("../etc/passwd", 32) == -1);
    assert(validate_username("<script>", 32) == -1);

    // Length check
    char long_name[64];
    memset(long_name, 'a', 33);
    long_name[33] = '\0';
    assert(validate_username(long_name, 32) == -1);
}

// ── Path traversal prevention ─────────────────────────────────────────
// A string test on the user's path is not containment. A "reject any '..'
// substring and a leading '/'" check passes "escape/passwd" when
// base/escape is a symlink to /etc (the open then reads /etc/passwd), and
// it rejects the harmless name "photo..jpg". Resolve instead: realpath(3)
// follows every symlink and collapses "." and "..", so check that the
// RESOLVED path is still under the resolved base.
//
// This is check-then-use: anyone who can write inside base can swap a
// component for a symlink between this check and the open. On Linux 5.6+,
// openat2(2) with RESOLVE_BENEATH has the kernel enforce containment
// during the open itself (an escape fails with EXDEV).
static int path_is_safe(const char *base, const char *user_input) {
    char rbase[PATH_MAX], joined[PATH_MAX], resolved[PATH_MAX];
    if (user_input[0] == '\0' || user_input[0] == '/') return 0;  // empty / absolute
    if (realpath(base, rbase) == NULL) return 0;
    int n = snprintf(joined, sizeof joined, "%s/%s", rbase, user_input);
    if (n < 0 || (size_t)n >= sizeof joined) return 0;            // would truncate
    if (realpath(joined, resolved) == NULL) {
        // A file about to be created does not exist yet: resolve its parent
        // and append the last name. A DANGLING symlink also fails realpath,
        // but that name exists and a write to it creates the link's target,
        // wherever it points, so a name that exists must resolve.
        struct stat st;
        if (errno != ENOENT || lstat(joined, &st) == 0) return 0;
        char *slash = strrchr(joined, '/');
        const char *name = slash + 1;
        if (name[0] == '\0' || strcmp(name, ".") == 0 || strcmp(name, "..") == 0) return 0;
        *slash = '\0';
        if (realpath(joined, resolved) == NULL) return 0;            // parent missing too
        size_t rl = strlen(resolved);
        if (rl + 1 + strlen(name) >= sizeof resolved) return 0;
        resolved[rl] = '/';
        strcpy(resolved + rl + 1, name);
    }
    // Compare on the separator: /srv/data-evil must not pass for /srv/data.
    size_t bl = strlen(rbase);
    return strncmp(resolved, rbase, bl) == 0 &&
           (resolved[bl] == '\0' || resolved[bl] == '/');
}

static void test_path_traversal(void) {
    const char *tmp = getenv("TMPDIR");
    char base[PATH_MAX];
    int n = snprintf(base, sizeof base, "%s/vidya-sec-XXXXXX", tmp && *tmp ? tmp : "/tmp");
    assert(n > 0 && (size_t)n < sizeof base);
    char *made = mkdtemp(base);
    assert(made != NULL);
    char sub[PATH_MAX + 16], link[PATH_MAX + 16], dangling[PATH_MAX + 16];
    snprintf(sub, sizeof sub, "%s/subdir", base);
    snprintf(link, sizeof link, "%s/escape", base);
    snprintf(dangling, sizeof dangling, "%s/dangling", base);
    int rc = mkdir(sub, 0700);
    assert(rc == 0);
    rc = symlink("/etc", link);                    // inside base, pointing out
    assert(rc == 0);
    rc = symlink("/nonexistent-vidya-dir/f", dangling);
    assert(rc == 0);

    assert(path_is_safe(base, "photo.jpg") == 1);        // not created yet
    assert(path_is_safe(base, "subdir/file.txt") == 1);
    assert(path_is_safe(base, "photo..jpg") == 1);       // ".." inside a name is fine
    assert(path_is_safe(base, "../../etc/passwd") == 0);
    assert(path_is_safe(base, "../secret") == 0);
    assert(path_is_safe(base, "/etc/passwd") == 0);
    assert(path_is_safe(base, "escape/passwd") == 0);    // no "..", still escapes
    assert(path_is_safe(base, "dangling") == 0);         // a write would follow it

    unlink(dangling);
    unlink(link);
    rmdir(sub);
    rmdir(base);
}

int main(void) {
    test_constant_time_comparison();
    test_secure_zeroing();
    test_buffer_overflow_prevention();
    test_format_string_safety();
    test_integer_overflow();
    test_input_validation();
    test_path_traversal();

    printf("All security examples passed.\n");
    return 0;
}
