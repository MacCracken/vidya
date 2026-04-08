/* Virtual Memory — C Implementation
 *
 * Demonstrates virtual memory concepts:
 *   1. Page table entry (PTE) encoding and bit manipulation
 *   2. 4-level x86_64 address decomposition
 *   3. Page table walk simulation
 *   4. TLB cache simulation with hit/miss tracking
 *   5. Demand paging page fault detection
 *
 * In a real kernel, page tables live in physical memory and the MMU
 * walks them in hardware. Here we simulate the data structure layout.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Constants ───────────────────────────────────────────────────────── */

#define PAGE_SIZE        4096U
#define PAGE_SHIFT       12
#define ENTRIES_PER_TABLE 512  /* 9 bits per level */
#define PTE_PRESENT      (1ULL << 0)
#define PTE_WRITABLE     (1ULL << 1)
#define PTE_USER         (1ULL << 2)
#define PTE_ADDR_MASK    0x000FFFFFFFFFF000ULL  /* bits 12-51 */
#define TLB_CAPACITY     64
#define MAX_PAGE_TABLES  32

/* ── Page Table Entry ────────────────────────────────────────────────── */

/* A PTE is just a uint64_t with defined bit fields:
 *   [63]    NX (no execute)
 *   [51:12] physical frame address (40 bits = 1 TB addressable)
 *   [11:0]  flags (present, writable, user, accessed, dirty, etc.)
 */
typedef uint64_t pte_t;

static pte_t pte_new(uint64_t phys_addr, uint64_t flags) {
    return (phys_addr & PTE_ADDR_MASK) | flags;
}

static int pte_is_present(pte_t pte) {
    return (pte & PTE_PRESENT) != 0;
}

static uint64_t pte_address(pte_t pte) {
    return pte & PTE_ADDR_MASK;
}

static uint64_t pte_flags(pte_t pte) {
    return pte & 0xFFFULL;
}

/* ── Page Table (one level) ──────────────────────────────────────────── */

typedef struct {
    pte_t entries[ENTRIES_PER_TABLE];
} page_table_t;

/* ── Virtual Address Decomposition ───────────────────────────────────── */

typedef struct {
    unsigned pml4_idx;    /* bits 39-47 */
    unsigned pdpt_idx;    /* bits 30-38 */
    unsigned pd_idx;      /* bits 21-29 */
    unsigned pt_idx;      /* bits 12-20 */
    unsigned offset;      /* bits 0-11  */
} vaddr_parts_t;

static vaddr_parts_t decompose_vaddr(uint64_t vaddr) {
    vaddr_parts_t p;
    p.offset   = (unsigned)(vaddr & 0xFFF);
    p.pt_idx   = (unsigned)((vaddr >> 12) & 0x1FF);
    p.pd_idx   = (unsigned)((vaddr >> 21) & 0x1FF);
    p.pdpt_idx = (unsigned)((vaddr >> 30) & 0x1FF);
    p.pml4_idx = (unsigned)((vaddr >> 39) & 0x1FF);
    return p;
}

/* ── Physical Frame Allocator (bump) ─────────────────────────────────── */

typedef struct {
    uint64_t next_frame;
    unsigned allocated;
} phys_allocator_t;

static void phys_init(phys_allocator_t *a, uint64_t start) {
    a->next_frame = start;
    a->allocated = 0;
}

static uint64_t phys_alloc(phys_allocator_t *a) {
    uint64_t frame = a->next_frame;
    a->next_frame += PAGE_SIZE;
    a->allocated++;
    return frame;
}

/* ── TLB Simulation ──────────────────────────────────────────────────── */

typedef struct {
    uint64_t vpage;
    uint64_t pframe;
    int      valid;
} tlb_entry_t;

typedef struct {
    tlb_entry_t entries[TLB_CAPACITY];
    unsigned    count;
    unsigned    hits;
    unsigned    misses;
} tlb_t;

static void tlb_init(tlb_t *tlb) {
    memset(tlb, 0, sizeof(*tlb));
}

static int tlb_lookup(tlb_t *tlb, uint64_t vpage, uint64_t *out_pframe) {
    for (unsigned i = 0; i < tlb->count; i++) {
        if (tlb->entries[i].valid && tlb->entries[i].vpage == vpage) {
            *out_pframe = tlb->entries[i].pframe;
            tlb->hits++;
            return 1;
        }
    }
    tlb->misses++;
    return 0;
}

static void tlb_insert(tlb_t *tlb, uint64_t vpage, uint64_t pframe) {
    /* If full, evict slot 0 (simplistic) */
    unsigned slot;
    if (tlb->count < TLB_CAPACITY) {
        slot = tlb->count++;
    } else {
        slot = 0;
    }
    tlb->entries[slot].vpage  = vpage;
    tlb->entries[slot].pframe = pframe;
    tlb->entries[slot].valid  = 1;
}

static void tlb_flush_page(tlb_t *tlb, uint64_t vpage) {
    for (unsigned i = 0; i < tlb->count; i++) {
        if (tlb->entries[i].valid && tlb->entries[i].vpage == vpage) {
            tlb->entries[i].valid = 0;
            return;
        }
    }
}

/* ── MMU Simulation ──────────────────────────────────────────────────── */

typedef struct {
    page_table_t    tables[MAX_PAGE_TABLES];
    uint64_t        table_addrs[MAX_PAGE_TABLES]; /* "physical address" of each table */
    unsigned        table_count;
    uint64_t        cr3;                          /* PML4 physical address */
    phys_allocator_t phys;
    tlb_t           tlb;
    unsigned        page_faults;
} mmu_t;

/* Find the page_table_t for a given "physical address" */
static page_table_t *mmu_get_table(mmu_t *mmu, uint64_t addr) {
    for (unsigned i = 0; i < mmu->table_count; i++) {
        if (mmu->table_addrs[i] == addr) {
            return &mmu->tables[i];
        }
    }
    return NULL;
}

/* Allocate a new page table in our table array */
static uint64_t mmu_alloc_table(mmu_t *mmu) {
    assert(mmu->table_count < MAX_PAGE_TABLES);
    uint64_t addr = phys_alloc(&mmu->phys);
    unsigned idx = mmu->table_count++;
    mmu->table_addrs[idx] = addr;
    memset(&mmu->tables[idx], 0, sizeof(page_table_t));
    return addr;
}

static void mmu_init(mmu_t *mmu) {
    memset(mmu, 0, sizeof(*mmu));
    phys_init(&mmu->phys, 0x1000);   /* skip null page */
    tlb_init(&mmu->tlb);
    mmu->cr3 = mmu_alloc_table(mmu); /* PML4 */
}

/* Ensure an intermediate table entry exists; return next-level table address */
static uint64_t mmu_ensure_entry(mmu_t *mmu, uint64_t table_addr,
                                  unsigned index, uint64_t flags) {
    page_table_t *t = mmu_get_table(mmu, table_addr);
    assert(t != NULL);

    if (pte_is_present(t->entries[index])) {
        return pte_address(t->entries[index]);
    }

    uint64_t new_addr = mmu_alloc_table(mmu);
    /* Re-fetch: mmu_alloc_table may have moved the array (it doesn't here,
       but this pattern is defensive). */
    t = mmu_get_table(mmu, table_addr);
    t->entries[index] = pte_new(new_addr, flags | PTE_PRESENT);
    return new_addr;
}

static void mmu_map_page(mmu_t *mmu, uint64_t vaddr, uint64_t phys_frame,
                          uint64_t flags) {
    vaddr_parts_t p = decompose_vaddr(vaddr);

    uint64_t pdpt_addr = mmu_ensure_entry(mmu, mmu->cr3,   p.pml4_idx, flags);
    uint64_t pd_addr   = mmu_ensure_entry(mmu, pdpt_addr,  p.pdpt_idx, flags);
    uint64_t pt_addr   = mmu_ensure_entry(mmu, pd_addr,    p.pd_idx,   flags);

    page_table_t *pt = mmu_get_table(mmu, pt_addr);
    assert(pt != NULL);
    pt->entries[p.pt_idx] = pte_new(phys_frame, flags | PTE_PRESENT);

    tlb_flush_page(&mmu->tlb, vaddr & ~0xFFFULL);
}

/* Returns 1 on success, 0 on page fault */
static int mmu_translate(mmu_t *mmu, uint64_t vaddr, uint64_t *out_phys) {
    uint64_t vpage  = vaddr & ~0xFFFULL;
    uint64_t offset = vaddr & 0xFFF;
    uint64_t pframe;

    /* TLB fast path */
    if (tlb_lookup(&mmu->tlb, vpage, &pframe)) {
        *out_phys = pframe | offset;
        return 1;
    }

    /* Page table walk (4 levels) */
    vaddr_parts_t p = decompose_vaddr(vaddr);
    unsigned indices[4] = { p.pml4_idx, p.pdpt_idx, p.pd_idx, p.pt_idx };

    uint64_t current = mmu->cr3;
    for (int level = 0; level < 4; level++) {
        page_table_t *t = mmu_get_table(mmu, current);
        if (!t || !pte_is_present(t->entries[indices[level]])) {
            mmu->page_faults++;
            return 0;
        }
        current = pte_address(t->entries[indices[level]]);
    }

    tlb_insert(&mmu->tlb, vpage, current);
    *out_phys = current | offset;
    return 1;
}

/* ── Main ────────────────────────────────────────────────────────────── */

int main(void) {
    printf("Virtual Memory — x86_64 page table simulation:\n\n");

    mmu_t mmu;
    mmu_init(&mmu);

    /* ── 1. Address decomposition ────────────────────────────────────── */
    printf("1. Virtual address decomposition (48-bit, 4 levels):\n");
    uint64_t addrs[] = { 0x0000000000400078ULL, 0x00007FFFFFFFFFFF0ULL,
                         0xFFFF800000000000ULL };
    for (int i = 0; i < 3; i++) {
        vaddr_parts_t p = decompose_vaddr(addrs[i]);
        printf("   0x%016llX -> PML4[%u] PDPT[%u] PD[%u] PT[%u] + 0x%03X\n",
               (unsigned long long)addrs[i],
               p.pml4_idx, p.pdpt_idx, p.pd_idx, p.pt_idx, p.offset);
    }

    /* Verify decomposition of known address */
    vaddr_parts_t vp = decompose_vaddr(0x0000000000400078ULL);
    assert(vp.pml4_idx == 0);
    assert(vp.pdpt_idx == 0);
    assert(vp.pd_idx   == 2);
    assert(vp.pt_idx   == 0);
    assert(vp.offset   == 0x078);

    /* ── 2. Page table mapping ───────────────────────────────────────── */
    printf("\n2. Mapping virtual pages to physical frames:\n");
    struct { uint64_t vaddr; uint64_t paddr; const char *label; } mappings[] = {
        { 0x00400000, 0x00200000, "code segment"  },
        { 0x00401000, 0x00201000, "code page 2"   },
        { 0x00600000, 0x00300000, "data segment"  },
        { 0x7FFFF000, 0x00100000, "stack top"     },
    };
    uint64_t flags = PTE_PRESENT | PTE_WRITABLE | PTE_USER;
    for (int i = 0; i < 4; i++) {
        mmu_map_page(&mmu, mappings[i].vaddr, mappings[i].paddr, flags);
        printf("   mapped 0x%08llX -> 0x%08llX (%s)\n",
               (unsigned long long)mappings[i].vaddr,
               (unsigned long long)mappings[i].paddr,
               mappings[i].label);
    }
    printf("   Page tables allocated: %u frames (%u KB)\n",
           mmu.phys.allocated, mmu.phys.allocated * 4);

    /* ── 3. Address translation ──────────────────────────────────────── */
    printf("\n3. Address translation:\n");
    struct { uint64_t addr; const char *desc; } tests[] = {
        { 0x00400078, "code + offset"   },
        { 0x00400078, "same (TLB hit)"  },
        { 0x00401234, "code page 2"     },
        { 0x00600100, "data"            },
        { 0x7FFFF800, "stack"           },
        { 0x00500000, "unmapped"        },
    };
    for (int i = 0; i < 6; i++) {
        uint64_t phys;
        if (mmu_translate(&mmu, tests[i].addr, &phys)) {
            printf("   0x%08llX -> 0x%08llX (%s)\n",
                   (unsigned long long)tests[i].addr,
                   (unsigned long long)phys, tests[i].desc);
        } else {
            printf("   0x%08llX -> PAGE FAULT (%s)\n",
                   (unsigned long long)tests[i].addr, tests[i].desc);
        }
    }

    /* Verify translations */
    uint64_t result;
    assert(mmu_translate(&mmu, 0x00400078, &result) && result == 0x00200078);
    assert(mmu_translate(&mmu, 0x00600100, &result) && result == 0x00300100);
    assert(!mmu_translate(&mmu, 0x00500000, &result));

    /* ── 4. PTE bit layout ───────────────────────────────────────────── */
    printf("\n4. PTE bit layout:\n");
    pte_t example = pte_new(0x00200000, PTE_PRESENT | PTE_WRITABLE | PTE_USER);
    printf("   PTE value:   0x%016llX\n", (unsigned long long)example);
    printf("   Address:     0x%016llX\n", (unsigned long long)pte_address(example));
    printf("   Flags:       0x%03llX (P=%d W=%d U=%d)\n",
           (unsigned long long)pte_flags(example),
           pte_is_present(example),
           (int)((example >> 1) & 1),
           (int)((example >> 2) & 1));
    assert(pte_is_present(example));
    assert(pte_address(example) == 0x00200000);
    assert(pte_flags(example) == (PTE_PRESENT | PTE_WRITABLE | PTE_USER));

    /* ── 5. TLB statistics ───────────────────────────────────────────── */
    unsigned total = mmu.tlb.hits + mmu.tlb.misses;
    double hit_rate = total > 0 ? (double)mmu.tlb.hits / total * 100.0 : 0.0;
    printf("\n5. TLB statistics: %u hits, %u misses (%.0f%% hit rate)\n",
           mmu.tlb.hits, mmu.tlb.misses, hit_rate);
    printf("   Page faults: %u\n", mmu.page_faults);
    printf("   Page table frames used: %u\n", mmu.phys.allocated);

    assert(mmu.tlb.hits > 0);
    assert(mmu.page_faults >= 1);

    printf("\nAll assertions passed.\n");
    return 0;
}
