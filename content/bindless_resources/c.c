/* Vidya — Bindless Resources in C
 *
 * In-memory descriptor table — "one global table per frame" pattern.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define TABLE_CAP 64

typedef struct {
    uint64_t slots[TABLE_CAP];
    uint32_t free_links[TABLE_CAP];
    uint32_t next_id;
    uint32_t free_head;
} Table;

static void table_init(Table *t) {
    memset(t, 0, sizeof *t);
    t->next_id = 1;
}

static uint32_t alloc_handle(Table *t, uint64_t desc) {
    if (t->free_head != 0) {
        uint32_t id = t->free_head;
        t->free_head = t->free_links[id];
        t->slots[id] = desc;
        return id;
    }
    if (t->next_id >= TABLE_CAP) return 0;
    uint32_t id = t->next_id++;
    t->slots[id] = desc;
    return id;
}

static uint64_t lookup_handle(const Table *t, uint32_t id) {
    if (id == 0 || id >= TABLE_CAP) return 0;
    return t->slots[id];
}

static int update_handle(Table *t, uint32_t id, uint64_t desc) {
    if (id == 0 || id >= TABLE_CAP) return 0;
    t->slots[id] = desc;
    return 1;
}

static int free_handle(Table *t, uint32_t id) {
    if (id == 0 || id >= TABLE_CAP) return 0;
    t->free_links[id] = t->free_head;
    t->free_head = id;
    t->slots[id] = 0;
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

    assert(update_handle(&t, id2, 0xAAAAAAAAAAAAAAAAULL) == 1);
    assert(lookup_handle(&t, id2) == 0xAAAAAAAAAAAAAAAAULL);
    assert(lookup_handle(&t, id1) == 0x1111111111111111ULL);
    assert(lookup_handle(&t, id3) == 0x3333333333333333ULL);

    free_handle(&t, id2);
    assert(lookup_handle(&t, id2) == 0);
    uint32_t id4 = alloc_handle(&t, 0x4444444444444444ULL);
    assert(id4 == id2);
    assert(lookup_handle(&t, id4) == 0x4444444444444444ULL);

    Table t2;
    table_init(&t2);
    for (uint32_t i = 1; i < TABLE_CAP; i++) alloc_handle(&t2, i);
    assert(alloc_handle(&t2, 0xDEADBEEF) == 0);

    printf("bindless_resources: 15/15 ok\n");
    return 0;
}
