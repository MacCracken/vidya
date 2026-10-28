// Vidya — Bindless Resources in C
//
// In-memory descriptor table — "one global table per frame" pattern.
// A handle is (generation << 8) | slot index. Freeing a slot bumps its
// generation, so a handle kept past free_handle stops resolving instead of
// silently reading whatever descriptor reuses the slot, and a second free
// of the same handle is rejected instead of corrupting the free list.
// (Real engines also defer the reuse by frames-in-flight; not modelled.)

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define TABLE_CAP 64
#define IDX_BITS  8                      /* TABLE_CAP <= 256 */
#define IDX_MASK  ((1u << IDX_BITS) - 1)

typedef struct {
    uint64_t slots[TABLE_CAP];
    uint32_t free_links[TABLE_CAP];      /* slot indices, 0 = end of list */
    uint32_t gens[TABLE_CAP];
    uint8_t  live[TABLE_CAP];
    uint32_t next_id;
    uint32_t free_head;
} Table;

static uint32_t make_handle(const Table *t, uint32_t idx) {
    return (t->gens[idx] << IDX_BITS) | idx;
}

/* Slot index of a handle that is still live, or 0 */
static uint32_t live_index(const Table *t, uint32_t h) {
    uint32_t idx = h & IDX_MASK;
    if (idx == 0 || idx >= TABLE_CAP || !t->live[idx]) return 0;
    if (t->gens[idx] != (h >> IDX_BITS)) return 0;   /* stale handle */
    return idx;
}

static void table_init(Table *t) {
    memset(t, 0, sizeof *t);
    t->next_id = 1;
}

static uint32_t alloc_handle(Table *t, uint64_t desc) {
    uint32_t idx;
    if (t->free_head != 0) {
        idx = t->free_head;
        t->free_head = t->free_links[idx];
    } else {
        if (t->next_id >= TABLE_CAP) return 0;
        idx = t->next_id++;
    }
    t->slots[idx] = desc;
    t->live[idx] = 1;
    return make_handle(t, idx);
}

static uint64_t lookup_handle(const Table *t, uint32_t id) {
    uint32_t idx = live_index(t, id);
    return idx ? t->slots[idx] : 0;
}

static int update_handle(Table *t, uint32_t id, uint64_t desc) {
    uint32_t idx = live_index(t, id);
    if (!idx) return 0;
    t->slots[idx] = desc;
    return 1;
}

static int free_handle(Table *t, uint32_t id) {
    uint32_t idx = live_index(t, id);
    if (!idx) return 0;                  /* double free or stale handle */
    t->live[idx] = 0;
    t->gens[idx] = (t->gens[idx] + 1) & (UINT32_MAX >> IDX_BITS);
    t->free_links[idx] = t->free_head;
    t->free_head = idx;
    t->slots[idx] = 0;
    return 1;
}

int main(void) {
    Table t;
    table_init(&t);

    uint32_t id1 = alloc_handle(&t, 0x1111111111111111ULL);
    uint32_t id2 = alloc_handle(&t, 0x2222222222222222ULL);
    uint32_t id3 = alloc_handle(&t, 0x3333333333333333ULL);
    assert(id1 == 1);
    assert(id2 == 2);
    assert(id3 == 3);

    assert(lookup_handle(&t, 0) == 0);

    assert(lookup_handle(&t, id1) == 0x1111111111111111ULL);
    assert(lookup_handle(&t, id2) == 0x2222222222222222ULL);
    assert(lookup_handle(&t, id3) == 0x3333333333333333ULL);

    // Mutating calls run outside assert(): under -DNDEBUG its expression
    // is not evaluated, and the update would vanish with the check.
    int rc = update_handle(&t, id2, 0xAAAAAAAAAAAAAAAAULL);
    assert(rc == 1);
    assert(lookup_handle(&t, id2) == 0xAAAAAAAAAAAAAAAAULL);
    assert(lookup_handle(&t, id1) == 0x1111111111111111ULL);
    assert(lookup_handle(&t, id3) == 0x3333333333333333ULL);

    free_handle(&t, id2);
    assert(lookup_handle(&t, id2) == 0);
    uint32_t id4 = alloc_handle(&t, 0x4444444444444444ULL);
    assert((id4 & IDX_MASK) == (id2 & IDX_MASK) && id4 != id2);  /* slot reused, new generation */
    assert(lookup_handle(&t, id4) == 0x4444444444444444ULL);
    assert(lookup_handle(&t, id2) == 0);   /* stale handle does not see the new resource */
    rc = free_handle(&t, id2);
    assert(rc == 0);                       /* double free rejected */

    Table t2;
    table_init(&t2);
    for (uint32_t i = 1; i < TABLE_CAP; i++) alloc_handle(&t2, i);
    uint32_t full = alloc_handle(&t2, 0xDEADBEEF);
    assert(full == 0);

    printf("bindless_resources: 17/17 ok\n");
    return 0;
}
