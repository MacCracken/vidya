// Vidya — Memory Management in C
//
// C gives you direct control over memory: malloc/free for heap,
// stack allocation for locals, and pointer arithmetic for access.
// No garbage collector, no RAII — you free what you allocate, or leak.

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── RAII-like cleanup with a helper ────────────────────────────────

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} Buffer;

Buffer buffer_new(size_t cap) {
    Buffer b;
    b.data = malloc(cap);
    assert(b.data != NULL);
    b.len = 0;
    b.cap = cap;
    return b;
}

void buffer_append(Buffer *b, const char *s) {
    size_t slen = strlen(s);
    while (b->len + slen + 1 > b->cap) {
        b->cap *= 2;
        b->data = realloc(b->data, b->cap);
        assert(b->data != NULL);
    }
    memcpy(b->data + b->len, s, slen);
    b->len += slen;
    b->data[b->len] = '\0';
}

void buffer_free(Buffer *b) {
    free(b->data);
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

int main(void) {
    // ── Stack allocation: automatic, fast ──────────────────────────
    int stack_array[100]; // 400 bytes on stack, freed when function returns
    for (int i = 0; i < 100; i++) stack_array[i] = i;
    assert(stack_array[50] == 50);

    // ── Heap allocation: malloc/free ───────────────────────────────
    int *heap_array = malloc(100 * sizeof(int));
    assert(heap_array != NULL); // always check malloc
    for (int i = 0; i < 100; i++) heap_array[i] = i * i;
    assert(heap_array[10] == 100);
    free(heap_array);
    heap_array = NULL; // prevent use-after-free

    // ── calloc: zero-initialized allocation ────────────────────────
    int *zeroed = calloc(50, sizeof(int));
    assert(zeroed != NULL);
    assert(zeroed[0] == 0); // guaranteed zero
    assert(zeroed[49] == 0);
    free(zeroed);

    // ── realloc: resize allocation ─────────────────────────────────
    int *dynamic = malloc(4 * sizeof(int));
    assert(dynamic != NULL);
    dynamic[0] = 10;
    dynamic[1] = 20;
    dynamic[2] = 30;
    dynamic[3] = 40;

    // Grow the allocation
    dynamic = realloc(dynamic, 8 * sizeof(int));
    assert(dynamic != NULL);
    assert(dynamic[3] == 40); // old data preserved
    dynamic[4] = 50;
    assert(dynamic[4] == 50);
    free(dynamic);

    // ── String ownership: who frees? ───────────────────────────────
    // Convention: the allocator frees, or document ownership transfer

    // Caller-frees pattern
    char *owned = malloc(32);
    assert(owned != NULL);
    snprintf(owned, 32, "hello %s", "world");
    assert(strcmp(owned, "hello world") == 0);
    free(owned); // caller is responsible

    // ── Buffer struct: manual RAII ─────────────────────────────────
    Buffer buf = buffer_new(16);
    buffer_append(&buf, "hello");
    buffer_append(&buf, " ");
    buffer_append(&buf, "world");
    assert(strcmp(buf.data, "hello world") == 0);
    assert(buf.len == 11);
    buffer_free(&buf);
    assert(buf.data == NULL); // cleanup zeroed the pointer

    // ── Pointer arithmetic ─────────────────────────────────────────
    int arr[] = {10, 20, 30, 40, 50};
    int *p = arr;
    assert(*p == 10);       // dereference
    assert(*(p + 2) == 30); // pointer arithmetic
    assert(p[3] == 40);     // array indexing is syntactic sugar

    // Pointer difference
    int *end = arr + 5;
    assert(end - arr == 5); // number of elements

    // ── sizeof: compile-time size ──────────────────────────────────
    assert(sizeof(int) >= 4);
    assert(sizeof(char) == 1);
    assert(sizeof(arr) == 5 * sizeof(int)); // total array size

    // GOTCHA: sizeof on a pointer gives pointer size, not array size
    int *ptr = arr;
    assert(sizeof(ptr) == sizeof(int *)); // 4 or 8, not 20!

    // ── Struct layout and padding ──────────────────────────────────
    struct Compact {
        int x;   // 4 bytes
        int y;   // 4 bytes
        char c;  // 1 byte + padding
    };
    // Size includes alignment padding
    assert(sizeof(struct Compact) >= 9);

    // ── void* : generic pointer ────────────────────────────────────
    void *generic = malloc(sizeof(int));
    assert(generic != NULL);
    *(int *)generic = 42; // cast to typed pointer
    assert(*(int *)generic == 42);
    free(generic);

    // ── Common bugs (demonstrated safely) ──────────────────────────

    // 1. Double free: free the same pointer twice → undefined behavior
    // int *bad = malloc(4); free(bad); free(bad); // DON'T
    // Fix: set to NULL after free
    int *safe = malloc(sizeof(int));
    free(safe);
    safe = NULL;
    // free(NULL) is safe (no-op)
    free(safe);

    // 2. Use after free
    // int *uaf = malloc(4); free(uaf); *uaf = 1; // DON'T
    // Fix: set to NULL and check before use

    // 3. Memory leak: forget to free
    // int *leaked = malloc(100); // never freed
    // Fix: pair every malloc with free, use goto cleanup pattern

    // ── Stack vs heap tradeoff ─────────────────────────────────────
    // Stack: fast (pointer bump), automatic cleanup, limited size (~1-8MB)
    // Heap: slower (malloc overhead), manual cleanup, virtually unlimited

    // Large allocations should use heap
    int *large = calloc(1000000, sizeof(int));
    assert(large != NULL);
    large[999999] = 42;
    assert(large[999999] == 42);
    free(large);

    printf("All memory management examples passed.\n");
    return 0;
}
