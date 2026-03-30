// Vidya — Performance in C
//
// C gives you the lowest-level control over performance: no GC, no
// runtime overhead, direct memory access. The key levers: cache-friendly
// data layout, avoiding allocation, minimizing branches, and knowing
// what the compiler optimizes.

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// ── Cache-friendly: struct of arrays vs array of structs ───────────

// Array of Structs (AoS) — each struct occupies a cache line
typedef struct {
    float x, y, z;
    float mass; // not always needed
} ParticleAoS;

// Struct of Arrays (SoA) — better when accessing only x,y,z
typedef struct {
    float *x;
    float *y;
    float *z;
    float *mass;
    size_t count;
} ParticlesSoA;

ParticlesSoA particles_new(size_t n) {
    ParticlesSoA p;
    p.x = calloc(n, sizeof(float));
    p.y = calloc(n, sizeof(float));
    p.z = calloc(n, sizeof(float));
    p.mass = calloc(n, sizeof(float));
    p.count = n;
    return p;
}

void particles_free(ParticlesSoA *p) {
    free(p->x); free(p->y); free(p->z); free(p->mass);
}

// ── Pre-allocation ─────────────────────────────────────────────────

typedef struct {
    int *data;
    size_t len;
    size_t cap;
} IntVec;

IntVec intvec_new(size_t cap) {
    IntVec v;
    v.data = malloc(cap * sizeof(int));
    v.len = 0;
    v.cap = cap;
    return v;
}

void intvec_push(IntVec *v, int value) {
    if (v->len == v->cap) {
        v->cap *= 2;
        v->data = realloc(v->data, v->cap * sizeof(int));
    }
    v->data[v->len++] = value;
}

void intvec_free(IntVec *v) { free(v->data); }

int main(void) {
    const int N = 10000;

    // ── Pre-allocated vs growing vector ────────────────────────────
    // Pre-allocated: one malloc, no reallocs
    IntVec preallocated = intvec_new(N);
    for (int i = 0; i < N; i++) {
        intvec_push(&preallocated, i);
    }
    assert((int)preallocated.len == N);
    intvec_free(&preallocated);

    // Growing: starts small, reallocs O(log N) times
    IntVec growing = intvec_new(1);
    for (int i = 0; i < N; i++) {
        intvec_push(&growing, i);
    }
    assert((int)growing.len == N);
    assert(growing.cap >= (size_t)N);
    intvec_free(&growing);

    // ── Stack vs heap allocation ───────────────────────────────────
    // Stack: essentially free (just move stack pointer)
    int stack_arr[1024];
    memset(stack_arr, 0, sizeof(stack_arr));
    assert(stack_arr[512] == 0);

    // Heap: involves malloc overhead
    int *heap_arr = calloc(1024, sizeof(int));
    assert(heap_arr != NULL);
    assert(heap_arr[512] == 0);
    free(heap_arr);

    // ── Cache-friendly access patterns ─────────────────────────────
    // Sequential access: fast (prefetcher works well)
    int *sequential = calloc(N, sizeof(int));
    long sum = 0;
    for (int i = 0; i < N; i++) {
        sequential[i] = i;
    }
    for (int i = 0; i < N; i++) {
        sum += sequential[i]; // sequential: cache-friendly
    }
    assert(sum == (long)N * (N - 1) / 2);
    free(sequential);

    // ── SoA: only read position data, skip mass ────────────────────
    ParticlesSoA particles = particles_new(1000);
    for (size_t i = 0; i < 1000; i++) {
        particles.x[i] = (float)i;
        particles.y[i] = (float)i * 2.0f;
        particles.z[i] = (float)i * 3.0f;
        particles.mass[i] = 1.0f;
    }

    // Sum positions: only touches x, y, z arrays (cache efficient)
    float pos_sum = 0.0f;
    for (size_t i = 0; i < particles.count; i++) {
        pos_sum += particles.x[i] + particles.y[i] + particles.z[i];
    }
    assert(pos_sum > 0.0f);
    particles_free(&particles);

    // ── Minimize function call overhead ─────────────────────────────
    // Use static inline for small hot functions
    // The compiler can inline these automatically at -O2

    // ── memcpy/memset: optimized by compiler ───────────────────────
    // These are intrinsics — often faster than manual loops
    char src[256], dst[256];
    memset(src, 'A', sizeof(src));
    memcpy(dst, src, sizeof(dst));
    assert(dst[128] == 'A');

    // ── Avoid branching in hot loops ───────────────────────────────
    // Branch-free min/max
    int a = 42, b = 17;
    // Branchless: works for positive values
    int min_val = b + ((a - b) & ((a - b) >> 31));
    // For general use, just use the ternary — compiler optimizes it
    int min_simple = a < b ? a : b;
    assert(min_val == 17 || min_simple == 17);

    // ── restrict: help the compiler optimize ───────────────────────
    // restrict tells the compiler pointers don't alias
    // void add_arrays(int *restrict dst, const int *restrict a, const int *restrict b, int n)
    // Allows vectorization that wouldn't be safe with potential aliasing

    // ── Use const: enables compiler optimizations ──────────────────
    const int constant = 42;
    // Compiler may propagate this value and eliminate loads
    assert(constant == 42);

    // ── Struct packing: reduce memory usage ────────────────────────
    struct Padded {
        char a;    // 1 + 3 padding
        int b;     // 4
        char c;    // 1 + 3 padding
    }; // = 12 bytes

    struct Packed {
        int b;     // 4
        char a;    // 1
        char c;    // 1 + 2 padding
    }; // = 8 bytes

    assert(sizeof(struct Packed) <= sizeof(struct Padded));

    // ── Small-N: linear search beats hash table ────────────────────
    struct { int key; const char *value; } small_table[] = {
        {1, "one"}, {2, "two"}, {3, "three"}, {4, "four"}, {5, "five"}
    };
    size_t table_len = sizeof(small_table) / sizeof(small_table[0]);

    const char *found = NULL;
    for (size_t i = 0; i < table_len; i++) {
        if (small_table[i].key == 3) {
            found = small_table[i].value;
            break;
        }
    }
    assert(found != NULL);
    assert(strcmp(found, "three") == 0);

    printf("All performance examples passed.\n");
    return 0;
}
