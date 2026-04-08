// Vidya — Allocators in C
//
// Three allocation strategies implemented with static buffers:
//   1. Bump allocator (arena) — pointer increment, batch free
//   2. Slab allocator — fixed-size slots with embedded free list
//   3. Bitmap allocator — one bit per page, next-free hint
//
// These are the building blocks of kernel memory managers and
// high-performance runtimes. No malloc needed — all memory is
// statically allocated.

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ── Bump Allocator (Arena) ────────────────────────────────────────────
//
// Maintains a pointer that advances on each allocation. Individual frees
// are impossible — reset frees everything at once. O(1) alloc.
// Use for: compiler AST nodes, per-request scratch space, parsing.

#define BUMP_CAPACITY 4096

typedef struct {
    uint8_t memory[BUMP_CAPACITY];
    size_t offset;
    size_t alloc_count;
} BumpAllocator;

void bump_init(BumpAllocator *b) {
    memset(b->memory, 0, BUMP_CAPACITY);
    b->offset = 0;
    b->alloc_count = 0;
}

// Returns pointer into the arena, or NULL if out of memory.
void *bump_alloc(BumpAllocator *b, size_t size, size_t align) {
    // Round up to alignment
    size_t aligned = (b->offset + align - 1) & ~(align - 1);
    size_t end = aligned + size;
    if (end > BUMP_CAPACITY) {
        return NULL;
    }
    b->offset = end;
    b->alloc_count++;
    return &b->memory[aligned];
}

void bump_reset(BumpAllocator *b) {
    b->offset = 0;
    b->alloc_count = 0;
}

// ── Slab Allocator ────────────────────────────────────────────────────
//
// Pre-divides memory into fixed-size slots. Free slots store a pointer
// to the next free slot (embedded free list). Alloc = pop head.
// Free = push head. Both O(1). Zero external fragmentation.
// Used by the Linux kernel for task_struct, inode, dentry.

#define SLAB_SLOT_SIZE 64
#define SLAB_COUNT     16
#define SLAB_MEM_SIZE  (SLAB_SLOT_SIZE * SLAB_COUNT)

typedef struct {
    uint8_t memory[SLAB_MEM_SIZE];
    int free_head;  // index of first free slot, or -1
    int next[SLAB_COUNT]; // next[i] = index of next free slot after i
    int allocated;
} SlabAllocator;

void slab_init(SlabAllocator *s) {
    memset(s->memory, 0, SLAB_MEM_SIZE);
    s->allocated = 0;
    // Chain all slots into the free list
    for (int i = 0; i < SLAB_COUNT; i++) {
        s->next[i] = i + 1;
    }
    s->next[SLAB_COUNT - 1] = -1;
    s->free_head = 0;
}

// Returns slot index, or -1 if full.
int slab_alloc(SlabAllocator *s) {
    if (s->free_head == -1) {
        return -1;
    }
    int index = s->free_head;
    s->free_head = s->next[index];
    s->next[index] = -1;
    s->allocated++;
    // Zero the slot
    memset(&s->memory[index * SLAB_SLOT_SIZE], 0, SLAB_SLOT_SIZE);
    return index;
}

void slab_free(SlabAllocator *s, int index) {
    s->next[index] = s->free_head;
    s->free_head = index;
    s->allocated--;
}

void *slab_ptr(SlabAllocator *s, int index) {
    return &s->memory[index * SLAB_SLOT_SIZE];
}

// ── Bitmap Allocator ──────────────────────────────────────────────────
//
// One bit per page. Set = allocated, clear = free.
// A next_free hint accelerates sequential allocation.
// Used by physical memory managers (PMMs) in kernels.

#define BMP_NUM_PAGES 64
#define BMP_BYTES     ((BMP_NUM_PAGES + 7) / 8)

typedef struct {
    uint8_t bitmap[BMP_BYTES];
    int next_free;
    int allocated;
} BitmapAllocator;

void bmp_init(BitmapAllocator *b) {
    memset(b->bitmap, 0, BMP_BYTES);
    b->next_free = 0;
    b->allocated = 0;
}

static int bmp_test(BitmapAllocator *b, int page) {
    return (b->bitmap[page / 8] >> (page % 8)) & 1;
}

static void bmp_set(BitmapAllocator *b, int page) {
    b->bitmap[page / 8] |= (uint8_t)(1 << (page % 8));
}

static void bmp_clear(BitmapAllocator *b, int page) {
    b->bitmap[page / 8] &= (uint8_t)~(1 << (page % 8));
}

// Returns page index, or -1 if full.
int bmp_alloc(BitmapAllocator *b) {
    // Search from hint
    for (int i = b->next_free; i < BMP_NUM_PAGES; i++) {
        if (!bmp_test(b, i)) {
            bmp_set(b, i);
            b->next_free = i + 1;
            b->allocated++;
            return i;
        }
    }
    // Wrap around
    for (int i = 0; i < b->next_free; i++) {
        if (!bmp_test(b, i)) {
            bmp_set(b, i);
            b->next_free = i + 1;
            b->allocated++;
            return i;
        }
    }
    return -1;
}

void bmp_free(BitmapAllocator *b, int page) {
    bmp_clear(b, page);
    b->allocated--;
    if (page < b->next_free) {
        b->next_free = page;
    }
}

// ── Main ──────────────────────────────────────────────────────────────

int main(void) {
    printf("Allocators — three strategies for different patterns:\n\n");

    // Bump allocator
    printf("1. Bump Allocator (arena):\n");
    BumpAllocator bump;
    bump_init(&bump);

    void *ptrs[10];
    for (int i = 0; i < 10; i++) {
        ptrs[i] = bump_alloc(&bump, 24, 8);
        assert(ptrs[i] != NULL);
        assert(((uintptr_t)ptrs[i] & 7) == 0);  // 8-byte aligned
    }
    printf("   Allocated 10 x 24 bytes, all 8-byte aligned\n");
    printf("   Bump[%zu/%d bytes, %zu allocs]\n", bump.offset, BUMP_CAPACITY, bump.alloc_count);

    // Alignment after odd-size alloc
    bump_alloc(&bump, 3, 1);
    void *aligned_ptr = bump_alloc(&bump, 8, 8);
    assert(aligned_ptr != NULL);
    assert(((uintptr_t)aligned_ptr & 7) == 0);
    printf("   After 3-byte + 8-byte: aligned = %s\n",
           ((uintptr_t)aligned_ptr & 7) == 0 ? "true" : "false");

    bump_reset(&bump);
    assert(bump.offset == 0);
    printf("   After reset: Bump[%zu/%d bytes, %zu allocs]\n\n",
           bump.offset, BUMP_CAPACITY, bump.alloc_count);

    // Slab allocator
    printf("2. Slab Allocator (fixed-size objects):\n");
    SlabAllocator slab;
    slab_init(&slab);

    int slots[5];
    for (int i = 0; i < 5; i++) {
        slots[i] = slab_alloc(&slab);
        assert(slots[i] >= 0);
    }
    printf("   Allocated 5 slots: [%d, %d, %d, %d, %d]\n",
           slots[0], slots[1], slots[2], slots[3], slots[4]);
    printf("   Slab[%d/%d slots]\n", slab.allocated, SLAB_COUNT);

    slab_free(&slab, slots[1]);
    slab_free(&slab, slots[3]);
    printf("   Freed slots %d and %d\n", slots[1], slots[3]);
    printf("   Slab[%d/%d slots]\n", slab.allocated, SLAB_COUNT);

    int reused1 = slab_alloc(&slab);
    int reused2 = slab_alloc(&slab);
    assert(reused1 == slots[3]);  // LIFO: last freed = first reused
    assert(reused2 == slots[1]);
    printf("   Reallocated: slots %d and %d (reused)\n", reused1, reused2);

    // Write and read back
    uint32_t *data = (uint32_t *)slab_ptr(&slab, reused1);
    *data = 0xDEADBEEF;
    assert(*data == 0xDEADBEEF);
    printf("   Write/read: 0x%08X\n\n", *data);

    // Bitmap allocator
    printf("3. Bitmap Allocator (page frames):\n");
    BitmapAllocator bmp;
    bmp_init(&bmp);

    int p0 = bmp_alloc(&bmp);
    int p1 = bmp_alloc(&bmp);
    int p2 = bmp_alloc(&bmp);
    assert(p0 == 0 && p1 == 1 && p2 == 2);
    printf("   Allocated pages: %d, %d, %d\n", p0, p1, p2);
    printf("   Bitmap[%d/%d pages]\n", bmp.allocated, BMP_NUM_PAGES);

    bmp_free(&bmp, 1);
    printf("   Freed page 1\n");
    int reused_page = bmp_alloc(&bmp);
    assert(reused_page == 1);
    printf("   Reallocated: page %d (reused via hint retraction)\n", reused_page);

    int p3 = bmp_alloc(&bmp);
    assert(p3 == 3);
    printf("   Next alloc: page %d\n", p3);
    printf("   Bitmap[%d/%d pages]\n", bmp.allocated, BMP_NUM_PAGES);

    // Fill all remaining pages
    int count = 0;
    while (bmp_alloc(&bmp) != -1) {
        count++;
    }
    assert(bmp.allocated == BMP_NUM_PAGES);
    printf("   Filled all %d pages, next alloc = -1: %s\n",
           BMP_NUM_PAGES, bmp_alloc(&bmp) == -1 ? "true" : "false");

    printf("\nAll tests passed.\n");
    return 0;
}
