/* Vidya — GPU Memory Pooling in C
 *
 * Bump allocator over a 1024-byte pool.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define POOL_SIZE 1024

typedef struct { int64_t bump; } Pool;

static void pool_reset(Pool *p) { p->bump = 0; }
static int64_t pool_used(const Pool *p) { return p->bump; }
static int64_t pool_free(const Pool *p) { return POOL_SIZE - p->bump; }

static int64_t pool_alloc(Pool *p, int64_t size) {
    if (size == 0) return p->bump;
    if (p->bump + size > POOL_SIZE) return -1;
    int64_t off = p->bump;
    p->bump += size;
    return off;
}

static int64_t pool_alloc_aligned(Pool *p, int64_t size, int64_t align) {
    int64_t mask = align - 1;
    int64_t aligned = (p->bump + mask) & ~mask;
    if (aligned + size > POOL_SIZE) return -1;
    p->bump = aligned + size;
    return aligned;
}

int main(void) {
    Pool p = {0};
    assert(pool_used(&p) == 0);
    assert(pool_free(&p) == 1024);

    assert(pool_alloc(&p, 100) == 0);
    assert(pool_used(&p) == 100);

    assert(pool_alloc(&p, 200) == 100);
    assert(pool_used(&p) == 300);

    assert(pool_alloc(&p, 1000) == -1);
    assert(pool_used(&p) == 300);

    pool_reset(&p);
    assert(pool_used(&p) == 0);
    assert(pool_free(&p) == 1024);
    assert(pool_alloc(&p, 50) == 0);

    assert(pool_alloc_aligned(&p, 32, 16) == 64);
    assert(pool_used(&p) == 96);

    assert(pool_alloc(&p, 0) == 96);
    assert(pool_used(&p) == 96);

    pool_reset(&p);
    for (int i = 0; i < 10; i++) pool_alloc(&p, 8);
    assert(pool_used(&p) == 80);

    printf("gpu_memory_pooling: 16/16 ok\n");
    return 0;
}
