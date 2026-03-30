#define _GNU_SOURCE
// Vidya — Kernel Topics in C
//
// C is THE kernel language. Linux, Windows NT, macOS XNU, FreeBSD —
// all written in C. These examples show the actual data structures
// kernels use: page table entries, MMIO via volatile pointers,
// interrupt descriptor layout, and ABI struct packing.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ── Page Table Entry (x86_64) ─────────────────────────────────────────
#define PTE_PRESENT     (1ULL << 0)
#define PTE_WRITABLE    (1ULL << 1)
#define PTE_USER        (1ULL << 2)
#define PTE_WRITE_THROUGH (1ULL << 3)
#define PTE_NO_CACHE    (1ULL << 4)
#define PTE_ACCESSED    (1ULL << 5)
#define PTE_DIRTY       (1ULL << 6)
#define PTE_HUGE_PAGE   (1ULL << 7)
#define PTE_NO_EXECUTE  (1ULL << 63)
#define PTE_ADDR_MASK   0x000FFFFFFFFFF000ULL

typedef uint64_t pte_t;

static pte_t pte_new(uint64_t phys_addr, uint64_t flags) {
    assert((phys_addr & ~PTE_ADDR_MASK) == 0);
    return (phys_addr & PTE_ADDR_MASK) | flags;
}

static int pte_present(pte_t pte)    { return (pte & PTE_PRESENT) != 0; }
static int pte_writable(pte_t pte)   { return (pte & PTE_WRITABLE) != 0; }
static int pte_user(pte_t pte)       { return (pte & PTE_USER) != 0; }
static int pte_no_execute(pte_t pte) { return (pte & PTE_NO_EXECUTE) != 0; }
static uint64_t pte_addr(pte_t pte)  { return pte & PTE_ADDR_MASK; }

static void test_page_table_entry(void) {
    pte_t code = pte_new(0x1000, PTE_PRESENT);
    assert(pte_present(code));
    assert(!pte_writable(code));
    assert(pte_addr(code) == 0x1000);

    pte_t data = pte_new(0x200000, PTE_PRESENT | PTE_WRITABLE | PTE_USER | PTE_NO_EXECUTE);
    assert(pte_present(data) && pte_writable(data));
    assert(pte_user(data) && pte_no_execute(data));
    assert(pte_addr(data) == 0x200000);

    pte_t unmapped = 0;
    assert(!pte_present(unmapped));

    // Cache control
    pte_t uncacheable = pte_new(0x3000, PTE_PRESENT | PTE_NO_CACHE | PTE_WRITE_THROUGH);
    assert(uncacheable & PTE_NO_CACHE);
    assert(uncacheable & PTE_WRITE_THROUGH);
}

// ── Virtual Address Decomposition ─────────────────────────────────────
typedef struct {
    uint16_t pml4, pdpt, pd, pt, offset;
} vaddr_parts_t;

static vaddr_parts_t decompose_vaddr(uint64_t vaddr) {
    return (vaddr_parts_t){
        .pml4   = (vaddr >> 39) & 0x1FF,
        .pdpt   = (vaddr >> 30) & 0x1FF,
        .pd     = (vaddr >> 21) & 0x1FF,
        .pt     = (vaddr >> 12) & 0x1FF,
        .offset = vaddr & 0xFFF,
    };
}

static void test_vaddr_decompose(void) {
    vaddr_parts_t p = decompose_vaddr(0x00007FFFFFFFFFFF);
    assert(p.pml4 == 0xFF);
    assert(p.offset == 0xFFF);

    vaddr_parts_t k = decompose_vaddr(0xFFFF800000000000ULL);
    assert(k.pml4 == 256);
}

// ── MMIO Register (volatile access) ──────────────────────────────────
// In a real kernel: volatile uint32_t *reg = (volatile uint32_t *)0xFE00_0000;
// Here we simulate with a struct.

typedef struct {
    volatile uint32_t value;
    const char *name;
} mmio_reg_t;

static void mmio_write(mmio_reg_t *reg, uint32_t val) {
    reg->value = val;
}

static uint32_t mmio_read(const mmio_reg_t *reg) {
    return reg->value;
}

static void mmio_set_bits(mmio_reg_t *reg, uint32_t mask) {
    mmio_write(reg, mmio_read(reg) | mask);
}

static void mmio_clear_bits(mmio_reg_t *reg, uint32_t mask) {
    mmio_write(reg, mmio_read(reg) & ~mask);
}

static void test_mmio_register(void) {
    mmio_reg_t ctrl = {.value = 0, .name = "UART_CTRL"};

    mmio_set_bits(&ctrl, 0x03);
    assert(mmio_read(&ctrl) == 0x03);

    mmio_clear_bits(&ctrl, 0x02);
    assert(mmio_read(&ctrl) == 0x01);
}

// ── Interrupt Descriptor Table Entry (x86_64) ─────────────────────────
// Real IDT entry is 16 bytes. We model the key fields.

typedef struct {
    uint16_t offset_low;     // bits 0-15 of handler address
    uint16_t selector;       // code segment selector
    uint8_t  ist;            // interrupt stack table index (0-7)
    uint8_t  type_attr;      // type and attributes
    uint16_t offset_mid;     // bits 16-31
    uint32_t offset_high;    // bits 32-63
    uint32_t reserved;
} __attribute__((packed)) idt_entry_t;

static idt_entry_t make_idt_entry(uint64_t handler_addr, uint16_t selector, uint8_t ist, uint8_t type_attr) {
    return (idt_entry_t){
        .offset_low  = (uint16_t)(handler_addr & 0xFFFF),
        .selector    = selector,
        .ist         = ist & 0x7,
        .type_attr   = type_attr,
        .offset_mid  = (uint16_t)((handler_addr >> 16) & 0xFFFF),
        .offset_high = (uint32_t)(handler_addr >> 32),
        .reserved    = 0,
    };
}

static uint64_t idt_handler_addr(const idt_entry_t *e) {
    return (uint64_t)e->offset_low
         | ((uint64_t)e->offset_mid << 16)
         | ((uint64_t)e->offset_high << 32);
}

static void test_idt_entry(void) {
    // Type 0x8E = present, DPL=0, 64-bit interrupt gate
    uint64_t handler = 0xFFFF800000001234ULL;
    idt_entry_t entry = make_idt_entry(handler, 0x08, 0, 0x8E);

    assert(idt_handler_addr(&entry) == handler);
    assert(entry.selector == 0x08);
    assert(entry.ist == 0);
    assert(entry.type_attr == 0x8E);

    // Double fault with IST=1
    idt_entry_t df = make_idt_entry(handler, 0x08, 1, 0x8E);
    assert(df.ist == 1);

    // Verify packed size
    assert(sizeof(idt_entry_t) == 16);
}

// ── GDT Entry ─────────────────────────────────────────────────────────
typedef uint64_t gdt_entry_t;

static int gdt_present(gdt_entry_t e)    { return (e >> 47) & 1; }
static int gdt_dpl(gdt_entry_t e)        { return (e >> 45) & 3; }
static int gdt_long_mode(gdt_entry_t e)  { return (e >> 53) & 1; }

static void test_gdt_entry(void) {
    gdt_entry_t null_seg = 0;
    assert(!gdt_present(null_seg));

    gdt_entry_t kernel_code = 0x00AF9A000000FFFFULL;
    assert(gdt_present(kernel_code));
    assert(gdt_dpl(kernel_code) == 0);
    assert(gdt_long_mode(kernel_code));

    gdt_entry_t kernel_data = 0x00CF92000000FFFFULL;
    assert(gdt_present(kernel_data));
}

// ── Struct packing and ABI layout ─────────────────────────────────────
// Kernel structures must match hardware layout exactly

typedef struct {
    uint8_t  type;
    uint8_t  code;
    uint16_t checksum;
    uint32_t data;
} __attribute__((packed)) icmp_header_t;

typedef struct {
    uint32_t eax, ebx, ecx, edx;
    uint32_t esi, edi, ebp, esp;
    uint64_t rip;
    uint64_t rflags;
} __attribute__((packed)) trap_frame_t;

static void test_struct_packing(void) {
    // ICMP header must be exactly 8 bytes (no padding)
    assert(sizeof(icmp_header_t) == 8);

    // Trap frame: 8 * 4 + 2 * 8 = 48 bytes
    assert(sizeof(trap_frame_t) == 48);

    // Verify no padding between fields
    icmp_header_t icmp = {.type = 8, .code = 0, .checksum = 0x1234, .data = 0xDEADBEEF};
    uint8_t *bytes = (uint8_t *)&icmp;
    assert(bytes[0] == 8);       // type
    assert(bytes[1] == 0);       // code
    assert(bytes[2] == 0x34 || bytes[2] == 0x12);  // checksum (endian-dependent)
}

int main(void) {
    test_page_table_entry();
    test_vaddr_decompose();
    test_mmio_register();
    test_idt_entry();
    test_gdt_entry();
    test_struct_packing();

    printf("All kernel topics examples passed.\n");
    return 0;
}
