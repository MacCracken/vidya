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
    if (size < 0) return -1;           /* would move bump backwards */
    if (size == 0) return p->bump;
    /* subtraction form: a huge size cannot overflow the check */
    if (size > POOL_SIZE - p->bump) return -1;
    int64_t off = p->bump;
    p->bump += size;
    return off;
}

static int64_t pool_alloc_aligned(Pool *p, int64_t size, int64_t align) {
    /* The mask trick needs a power-of-two align: align 0 "aligns" to
     * offset 0, on top of live allocations; 24 gives a misaligned 104. */
    if (size < 0 || align <= 0 || (align & (align - 1)) != 0) return -1;
    int64_t mask = align - 1;
    int64_t aligned = (p->bump + mask) & ~mask;
    if (aligned > POOL_SIZE || size > POOL_SIZE - aligned) return -1;
    p->bump = aligned + size;
    return aligned;
}

int main(void) {
    Pool p = {0};
    assert(pool_used(&p) == 0);
    assert(pool_free(&p) == 1024);

    // pool_alloc moves the bump pointer, so it runs outside assert(): under
    // -DNDEBUG assert's expression is not evaluated and nothing would be
    // allocated.
    int64_t off = pool_alloc(&p, 100);
    assert(off == 0);
    assert(pool_used(&p) == 100);

    off = pool_alloc(&p, 200);
    assert(off == 100);
    assert(pool_used(&p) == 300);

    off = pool_alloc(&p, 1000);
    assert(off == -1);
    assert(pool_used(&p) == 300);

    pool_reset(&p);
    assert(pool_used(&p) == 0);
    assert(pool_free(&p) == 1024);
    off = pool_alloc(&p, 50);
    assert(off == 0);

    off = pool_alloc_aligned(&p, 32, 16);
    assert(off == 64);
    assert(pool_used(&p) == 96);

    off = pool_alloc_aligned(&p, 32, 0);
    assert(off == -1);
    off = pool_alloc_aligned(&p, 32, 24);
    assert(off == -1);
    off = pool_alloc(&p, -60);
    assert(off == -1);

    off = pool_alloc(&p, 0);
    assert(off == 96);
    assert(pool_used(&p) == 96);

    pool_reset(&p);
    for (int i = 0; i < 10; i++) pool_alloc(&p, 8);
    assert(pool_used(&p) == 80);

    printf("gpu_memory_pooling: 19/19 ok\n");
    return 0;
}
