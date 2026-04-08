// Vidya — Ownership and Borrowing Concepts in C
//
// C has no ownership system. The programmer is responsible for every
// allocation, every free, every pointer's validity. This file shows
// the bugs that ownership prevents:
//   1. Use-after-free — accessing memory after free()
//   2. Double-free — freeing the same pointer twice
//   3. Dangling pointers — pointers to stack frames that no longer exist
//   4. Memory leaks — forgetting to free
//   5. Manual RAII patterns — the C workarounds
//
// Every bug shown here is a compile-time error in Rust.

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Use-After-Free ────────────────────────────────────────────────
// After free(), the pointer still holds the old address, but the
// memory may be reused by the allocator. Reading it is undefined
// behavior. Writing it corrupts unrelated data.
//
// Rust prevents this: after a move, the original binding is dead.

static void demonstrate_use_after_free_prevention(void) {
    // BAD pattern (commented out — UB):
    //   char *p = malloc(32);
    //   strcpy(p, "hello");
    //   free(p);
    //   printf("%s\n", p);  // UB: use-after-free

    // GOOD pattern: nullify after free
    char *p = malloc(32);
    assert(p != NULL);
    strcpy(p, "hello");
    assert(strcmp(p, "hello") == 0);
    free(p);
    p = NULL;  // prevent accidental reuse

    // Now any dereference of p would crash (SIGSEGV) rather than
    // silently reading garbage. Crash > corruption.
    assert(p == NULL);
}

// ── Double-Free ───────────────────────────────────────────────────
// Freeing the same pointer twice corrupts the allocator's free list.
// This can cause crashes, silent data corruption, or security exploits.
//
// Rust prevents this: ownership is affine — each value is freed
// exactly once when its owner goes out of scope.

static void demonstrate_double_free_prevention(void) {
    // BAD pattern (commented out — UB):
    //   char *a = malloc(16);
    //   char *b = a;  // alias
    //   free(a);
    //   free(b);  // double-free! b is the same pointer as a

    // GOOD pattern: clear aliases after free
    char *a = malloc(16);
    assert(a != NULL);
    strcpy(a, "data");
    char *b = a;  // alias — both point to same allocation

    assert(strcmp(b, "data") == 0);

    free(a);
    a = NULL;
    b = NULL;  // must also nullify the alias
    // Now neither can be double-freed.
}

// ── Dangling Pointers to Stack Frames ─────────────────────────────
// Returning a pointer to a local variable is a classic C bug. The
// stack frame is gone after return — the pointer is dangling.
//
// Rust prevents this with lifetimes: you can't return a reference
// that outlives the data it points to.

// BAD function (commented out — UB):
// char *bad_return_local(void) {
//     char buf[32];
//     strcpy(buf, "stack data");
//     return buf;  // dangling! buf is gone after return
// }

// GOOD pattern: caller provides the buffer
static void good_fill_buffer(char *buf, size_t buflen) {
    // The caller owns the buffer and its lifetime
    snprintf(buf, buflen, "safe: caller-owned buffer");
}

// GOOD pattern: return heap-allocated data (caller must free)
static char *good_return_heap(const char *data) {
    size_t len = strlen(data) + 1;
    char *result = malloc(len);
    if (result == NULL) return NULL;
    memcpy(result, data, len);
    return result;  // ownership transferred to caller
}

// ── Manual RAII: goto cleanup ─────────────────────────────────────
// C's nearest equivalent to RAII is the goto-cleanup pattern.
// All resources are freed through a single exit path.

typedef struct {
    char *name;
    int *data;
    size_t len;
} Dataset;

static int dataset_init(Dataset *ds, const char *name, size_t len) {
    ds->name = NULL;
    ds->data = NULL;
    ds->len = 0;

    ds->name = malloc(strlen(name) + 1);
    if (ds->name == NULL) goto fail;
    strcpy(ds->name, name);

    ds->data = calloc(len, sizeof(int));
    if (ds->data == NULL) goto fail;

    ds->len = len;
    return 0;

fail:
    // Cleanup partial allocation — like Rust's Drop running on error
    free(ds->name);
    ds->name = NULL;
    free(ds->data);
    ds->data = NULL;
    return -1;
}

static void dataset_free(Dataset *ds) {
    free(ds->name);
    ds->name = NULL;
    free(ds->data);
    ds->data = NULL;
    ds->len = 0;
}

// ── Ownership transfer convention ─────────────────────────────────
// C has no language-level ownership. By convention:
//   - Functions that return malloc'd memory "transfer ownership"
//   - The caller is responsible for freeing
//   - Document who owns what in comments

// Ownership: caller owns the returned string. Caller must free().
static char *string_concat(const char *a, const char *b) {
    size_t la = strlen(a);
    size_t lb = strlen(b);
    char *result = malloc(la + lb + 1);
    if (result == NULL) return NULL;
    memcpy(result, a, la);
    memcpy(result + la, b, lb + 1);
    return result;  // ownership transferred to caller
}

// ── Borrowing convention: const correctness ───────────────────────
// `const char *` signals "I'm borrowing this, I won't modify it."
// It's the closest C gets to Rust's shared borrow (&T).

static size_t safe_strlen(const char *s) {
    // const prevents us from modifying s — read-only borrow
    if (s == NULL) return 0;
    return strlen(s);
}

static void mutate_buffer(char *buf, size_t len) {
    // Non-const pointer: exclusive borrow (&mut T equivalent)
    // We're allowed to modify the data
    for (size_t i = 0; i < len; i++) {
        if (buf[i] >= 'a' && buf[i] <= 'z') {
            buf[i] = (char)(buf[i] - 32);  // uppercase
        }
    }
}

// ── Scope-based resource management with cleanup attribute ────────
// GCC/Clang support __attribute__((cleanup)) for RAII-like behavior.
// This is non-standard but widely used (systemd, GLib).

// Note: commented out for portability — concept demonstration only:
// static void free_ptr(char **pp) { free(*pp); }
// void example(void) {
//     __attribute__((cleanup(free_ptr))) char *p = malloc(32);
//     // p is automatically freed when it goes out of scope
// }

int main(void) {
    // ── Use-after-free prevention ─────────────────────────────────
    demonstrate_use_after_free_prevention();

    // ── Double-free prevention ────────────────────────────────────
    demonstrate_double_free_prevention();

    // ── Dangling pointer prevention ───────────────────────────────
    char buf[64];
    good_fill_buffer(buf, sizeof(buf));
    assert(strstr(buf, "safe") != NULL);

    char *heap_str = good_return_heap("heap owned");
    assert(strcmp(heap_str, "heap owned") == 0);
    free(heap_str);  // caller's responsibility

    // ── RAII via goto cleanup ─────────────────────────────────────
    Dataset ds;
    int err = dataset_init(&ds, "test", 10);
    assert(err == 0);
    assert(strcmp(ds.name, "test") == 0);
    assert(ds.len == 10);

    ds.data[0] = 42;
    ds.data[9] = 99;
    assert(ds.data[0] == 42);
    assert(ds.data[9] == 99);

    dataset_free(&ds);
    assert(ds.name == NULL);
    assert(ds.data == NULL);

    // ── Ownership transfer ────────────────────────────────────────
    char *joined = string_concat("hello", " world");
    assert(joined != NULL);
    assert(strcmp(joined, "hello world") == 0);
    free(joined);  // we own it, we free it

    // ── Const correctness (borrowing) ─────────────────────────────
    const char *immutable = "read only";
    assert(safe_strlen(immutable) == 9);
    assert(safe_strlen(NULL) == 0);

    char mutable_buf[] = "hello";
    mutate_buffer(mutable_buf, strlen(mutable_buf));
    assert(strcmp(mutable_buf, "HELLO") == 0);

    // ── Aliasing dangers ──────────────────────────────────────────
    // Two pointers to the same allocation — C allows this freely.
    // Rust's borrow checker prevents simultaneous mutable aliases.
    int *arr = malloc(3 * sizeof(int));
    assert(arr != NULL);
    arr[0] = 10;
    arr[1] = 20;
    arr[2] = 30;

    int *alias = arr;  // two pointers to same memory
    alias[1] = 99;     // mutation through alias
    assert(arr[1] == 99);  // visible through original — spooky action

    free(arr);
    // alias is now dangling — C doesn't know or care
    arr = NULL;
    alias = NULL;  // manual discipline

    printf("All ownership and borrowing examples passed.\n");
    return 0;
}
