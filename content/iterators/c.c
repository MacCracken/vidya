// Vidya — Iterators in C
//
// C has no iterator abstraction. Iteration is done with for loops,
// pointer arithmetic, and callbacks (function pointers). Arrays are
// iterated by index or pointer; linked structures by following pointers.

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Callback-based iteration (closest to iterators) ────────────────

typedef void (*IntCallback)(int value, void *ctx);

void for_each(const int *arr, size_t len, IntCallback fn, void *ctx) {
    for (size_t i = 0; i < len; i++) {
        fn(arr[i], ctx);
    }
}

// ── Filter + map with callbacks ────────────────────────────────────

typedef int (*IntPredicate)(int value);
typedef int (*IntTransform)(int value);

size_t filter_map(const int *src, size_t src_len,
                  IntPredicate pred, IntTransform transform,
                  int *dst, size_t dst_cap) {
    size_t count = 0;
    for (size_t i = 0; i < src_len && count < dst_cap; i++) {
        if (pred(src[i])) {
            dst[count++] = transform(src[i]);
        }
    }
    return count;
}

int is_even(int x) { return x % 2 == 0; }
int square(int x) { return x * x; }

// ── Fold/reduce ────────────────────────────────────────────────────

typedef int (*IntFold)(int acc, int value);

int fold(const int *arr, size_t len, int init, IntFold fn) {
    int acc = init;
    for (size_t i = 0; i < len; i++) {
        acc = fn(acc, arr[i]);
    }
    return acc;
}

int add(int a, int b) { return a + b; }

int int_cmp(const void *a, const void *b) {
    return *(const int *)a - *(const int *)b;
}

// ── Sum callback context ──────────────────────────────────────────

typedef struct { int total; } SumCtx;

void sum_callback(int value, void *ctx) {
    ((SumCtx *)ctx)->total += value;
}

int main(void) {
    int numbers[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    size_t len = sizeof(numbers) / sizeof(numbers[0]);

    // ── Basic for loop iteration ───────────────────────────────────
    int sum = 0;
    for (size_t i = 0; i < len; i++) {
        sum += numbers[i];
    }
    assert(sum == 55);

    // ── Pointer-based iteration ────────────────────────────────────
    sum = 0;
    for (const int *p = numbers; p < numbers + len; p++) {
        sum += *p;
    }
    assert(sum == 55);

    // ── Callback iteration (for_each) ──────────────────────────────
    SumCtx ctx = {0};
    for_each(numbers, len, sum_callback, &ctx);
    assert(ctx.total == 55);

    // ── Filter + map ───────────────────────────────────────────────
    int results[10];
    size_t count = filter_map(numbers, len, is_even, square,
                              results, sizeof(results)/sizeof(results[0]));
    assert(count == 5);
    assert(results[0] == 4);   // 2*2
    assert(results[1] == 16);  // 4*4
    assert(results[2] == 36);  // 6*6
    assert(results[3] == 64);  // 8*8
    assert(results[4] == 100); // 10*10

    // ── Fold/reduce ────────────────────────────────────────────────
    int total = fold(numbers, len, 0, add);
    assert(total == 55);

    // ── String iteration (null-terminated) ─────────────────────────
    const char *str = "hello";
    int char_count = 0;
    for (const char *c = str; *c != '\0'; c++) {
        char_count++;
    }
    assert(char_count == 5);

    // ── Iterating with sentinel value ──────────────────────────────
    // Common C pattern: array terminated by special value
    const char *words[] = {"hello", "world", "from", "c", NULL};
    int word_count = 0;
    for (const char **w = words; *w != NULL; w++) {
        word_count++;
    }
    assert(word_count == 4);

    // ── Two-pointer technique ──────────────────────────────────────
    // Reverse an array in-place
    int arr[] = {1, 2, 3, 4, 5};
    int *left = arr;
    int *right = arr + 4;
    while (left < right) {
        int tmp = *left;
        *left = *right;
        *right = tmp;
        left++;
        right--;
    }
    assert(arr[0] == 5);
    assert(arr[4] == 1);

    // ── Linked list iteration ──────────────────────────────────────
    typedef struct Node {
        int value;
        struct Node *next;
    } Node;

    // Build: 1 -> 2 -> 3 -> NULL
    Node n3 = {3, NULL};
    Node n2 = {2, &n3};
    Node n1 = {1, &n2};

    sum = 0;
    for (const Node *node = &n1; node != NULL; node = node->next) {
        sum += node->value;
    }
    assert(sum == 6);

    // ── qsort: stdlib's generic sort ───────────────────────────────
    int unsorted[] = {5, 3, 1, 4, 2};
    qsort(unsorted, 5, sizeof(int), int_cmp);
    assert(unsorted[0] == 1);
    assert(unsorted[4] == 5);

    // ── bsearch: binary search on sorted array ─────────────────────
    int key = 3;
    int *found = bsearch(&key, unsorted, 5, sizeof(int), int_cmp);
    assert(found != NULL);
    assert(*found == 3);

    printf("All iterator examples passed.\n");
    return 0;
}
