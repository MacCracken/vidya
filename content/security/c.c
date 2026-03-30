#define _GNU_SOURCE
// Vidya — Security Practices in C
//
// C trusts the programmer completely — no bounds checking, no type
// safety at runtime, no garbage collector. Security in C means:
// validate every buffer size, use safe string functions, check every
// return value, and assume all input is hostile.

#include <assert.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
// explicit_bzero (POSIX) or volatile writes survive optimization.
static void secure_zero(void *buf, size_t len) {
    volatile unsigned char *p = (volatile unsigned char *)buf;
    for (size_t i = 0; i < len; i++) {
        p[i] = 0;
    }
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

    // Safe: fits within buffer
    assert(safe_copy(buf, sizeof(buf), "hello") == 0);
    assert(strcmp(buf, "hello") == 0);

    // Rejected: would overflow
    assert(safe_copy(buf, sizeof(buf), "this is way too long") == -1);

    // Edge case: exactly fills buffer
    assert(safe_copy(buf, sizeof(buf), "1234567") == 0);  // 7 chars + \0 = 8

    // Edge case: one too many
    assert(safe_copy(buf, sizeof(buf), "12345678") == -1); // 8 chars + \0 = 9 > 8
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

    assert(safe_add_u32(100, 200, &result) == 0);
    assert(result == 300);
    assert(safe_add_u32(UINT32_MAX, 1, &result) == -1);

    assert(safe_mul_u32(1000, 1000, &result) == 0);
    assert(result == 1000000);
    assert(safe_mul_u32(65536, 65536, &result) == -1);  // overflow

    // Buffer allocation: width * height * bytes_per_pixel
    assert(safe_mul_u32(65536, 65536, &result) == -1);
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
static int path_is_safe(const char *user_input) {
    // Reject any path containing ".." components
    if (strstr(user_input, "..") != NULL) {
        return 0;  // unsafe
    }
    // Reject absolute paths
    if (user_input[0] == '/') {
        return 0;  // unsafe
    }
    return 1;  // safe
}

static void test_path_traversal(void) {
    assert(path_is_safe("photo.jpg") == 1);
    assert(path_is_safe("subdir/file.txt") == 1);
    assert(path_is_safe("../../etc/passwd") == 0);
    assert(path_is_safe("../secret") == 0);
    assert(path_is_safe("/etc/passwd") == 0);
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
