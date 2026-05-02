/* Vidya — Explicit GPU Synchronization in C
 *
 * Timeline semaphores — monotonic counters with signal/wait/wait_all.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

typedef struct { uint64_t compute, transfer; } Timelines;

static int sig(Timelines *t, int sem, uint64_t value) {
    if (sem == 0) { if (value <= t->compute)  return 0; t->compute  = value; return 1; }
    if (sem == 1) { if (value <= t->transfer) return 0; t->transfer = value; return 1; }
    return 0;
}

static int wait_for(const Timelines *t, int sem, uint64_t target) {
    if (sem == 0) return t->compute  >= target;
    if (sem == 1) return t->transfer >= target;
    return 0;
}

static int wait_all(const Timelines *t, uint64_t c, uint64_t tr) {
    return wait_for(t, 0, c) && wait_for(t, 1, tr);
}

int main(void) {
    Timelines t = {0, 0};

    assert(t.compute == 0 && t.transfer == 0);
    assert(wait_for(&t, 0, 0));

    assert(sig(&t, 0, 5));
    assert(t.compute == 5);

    assert(wait_for(&t, 0, 3));
    assert(wait_for(&t, 0, 5));
    assert(!wait_for(&t, 0, 10));

    assert(!sig(&t, 0, 3));
    assert(t.compute == 5);
    assert(!sig(&t, 0, 5));

    sig(&t, 1, 3);
    assert(t.transfer == 3);
    assert(wait_all(&t, 5, 3));
    assert(!wait_all(&t, 5, 4));
    assert(!wait_all(&t, 6, 3));
    assert(wait_all(&t, 0, 0));

    Timelines t2 = {0, 0};
    for (uint64_t i = 1; i <= 10; i++) sig(&t2, 0, i);
    assert(t2.compute == 10);
    assert(wait_for(&t2, 0, 10));
    assert(!wait_for(&t2, 0, 11));

    printf("explicit_gpu_synchronization: 19/19 ok\n");
    return 0;
}
