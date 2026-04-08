// Vidya — Boot and Startup in C
//
// Struct-packed GDT, IDT, and Multiboot data structures as they appear
// in real kernel code. C is the natural language for these — the structs
// map directly to hardware-defined memory layouts.
//
//   1. GDT entries (null, code64, data64) — packed 8-byte descriptors
//   2. IDT gate descriptor — 16-byte long-mode interrupt gate
//   3. Multiboot1 header — magic + flags + checksum
//   4. TSS (Task State Segment) — interrupt stack table layout
//   5. Layout verification with offsetof/sizeof
//
// Every field position is verified with static asserts and runtime checks.

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ── GDT Entry (Segment Descriptor) ──────────────────────────────────
//
// 8-byte descriptor with fragmented base/limit fields.
// In long mode, base and limit are ignored but the entry must exist.

typedef struct __attribute__((packed)) {
    uint16_t limit_lo;    // bits 0-15 of limit
    uint16_t base_lo;     // bits 0-15 of base
    uint8_t  base_mid;    // bits 16-23 of base
    uint8_t  access;      // access byte (P, DPL, S, type)
    uint8_t  flags_limit; // flags (high nibble) + limit bits 16-19 (low nibble)
    uint8_t  base_hi;     // bits 24-31 of base
} GdtEntry;

// Access byte bits
#define GDT_PRESENT   0x80  // P: segment is present
#define GDT_DPL_RING0 0x00  // DPL: ring 0
#define GDT_DPL_RING3 0x60  // DPL: ring 3
#define GDT_TYPE_CODE 0x1A  // S=1, E=1 (executable), R=1 (readable)
#define GDT_TYPE_DATA 0x12  // S=1, E=0 (data), W=1 (writable)

// Flags nibble (upper 4 bits of flags_limit byte)
#define GDT_FLAG_GRANULARITY 0x80  // G: limit in 4KB units
#define GDT_FLAG_SIZE_32     0x40  // DB: 32-bit operands
#define GDT_FLAG_LONG_MODE   0x20  // L: 64-bit code segment

static GdtEntry gdt_null(void) {
    GdtEntry e;
    memset(&e, 0, sizeof(e));
    return e;
}

static GdtEntry gdt_code64(uint8_t dpl) {
    GdtEntry e;
    e.limit_lo    = 0xFFFF;
    e.base_lo     = 0;
    e.base_mid    = 0;
    e.access      = GDT_PRESENT | dpl | GDT_TYPE_CODE;
    e.flags_limit = 0xAF;  // G=1, L=1, limit_hi=0xF
    e.base_hi     = 0;
    return e;
}

static GdtEntry gdt_data(uint8_t dpl) {
    GdtEntry e;
    e.limit_lo    = 0xFFFF;
    e.base_lo     = 0;
    e.base_mid    = 0;
    e.access      = GDT_PRESENT | dpl | GDT_TYPE_DATA;
    e.flags_limit = 0xCF;  // G=1, DB=1, limit_hi=0xF
    e.base_hi     = 0;
    return e;
}

static int gdt_is_present(const GdtEntry *e) {
    return (e->access & GDT_PRESENT) != 0;
}

static int gdt_dpl(const GdtEntry *e) {
    return (e->access >> 5) & 0x03;
}

static int gdt_is_code(const GdtEntry *e) {
    return (e->access & 0x08) != 0;
}

static int gdt_is_long_mode(const GdtEntry *e) {
    return (e->flags_limit & 0x20) != 0;
}

// ── IDT Gate Descriptor (Long Mode) ─────────────────────────────────
//
// 16 bytes in 64-bit mode. Routes interrupts/exceptions to handlers.

typedef struct __attribute__((packed)) {
    uint16_t offset_lo;    // bits 0-15 of handler address
    uint16_t selector;     // code segment selector (e.g., 0x08)
    uint8_t  ist;          // interrupt stack table index (bits 0-2)
    uint8_t  type_attr;    // P=1, DPL, gate type (0xE=interrupt, 0xF=trap)
    uint16_t offset_mid;   // bits 16-31 of handler address
    uint32_t offset_hi;    // bits 32-63 of handler address
    uint32_t reserved;     // must be zero
} IdtGateDescriptor;

#define IDT_INTERRUPT_GATE 0x8E  // P=1, DPL=0, type=0xE (interrupt gate)
#define IDT_TRAP_GATE      0x8F  // P=1, DPL=0, type=0xF (trap gate)

static IdtGateDescriptor idt_gate(uint64_t offset, uint16_t selector,
                                   uint8_t type_attr, uint8_t ist) {
    IdtGateDescriptor g;
    g.offset_lo  = (uint16_t)(offset & 0xFFFF);
    g.selector   = selector;
    g.ist        = ist & 0x07;
    g.type_attr  = type_attr;
    g.offset_mid = (uint16_t)((offset >> 16) & 0xFFFF);
    g.offset_hi  = (uint32_t)((offset >> 32) & 0xFFFFFFFF);
    g.reserved   = 0;
    return g;
}

static uint64_t idt_handler_addr(const IdtGateDescriptor *g) {
    return (uint64_t)g->offset_lo
         | ((uint64_t)g->offset_mid << 16)
         | ((uint64_t)g->offset_hi << 32);
}

// ── Multiboot1 Header ───────────────────────────────────────────────
//
// Must appear in the first 8KB of the kernel binary.
// Magic + flags + checksum must sum to zero (mod 2^32).

#define MULTIBOOT1_MAGIC_REQUEST  0x1BADB002
#define MULTIBOOT1_MAGIC_RESPONSE 0x2BADB002
#define MULTIBOOT1_FLAG_ALIGN     (1 << 0)  // align modules on page boundaries
#define MULTIBOOT1_FLAG_MEMINFO   (1 << 1)  // provide memory map

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint32_t flags;
    uint32_t checksum;
} MultibootHeader;

static MultibootHeader multiboot_header(uint32_t flags) {
    MultibootHeader h;
    h.magic    = MULTIBOOT1_MAGIC_REQUEST;
    h.flags    = flags;
    h.checksum = -(h.magic + h.flags);  // makes sum wrap to zero
    return h;
}

// ── TSS (Task State Segment) ────────────────────────────────────────
//
// In long mode, the TSS holds the Interrupt Stack Table (IST) —
// 7 stack pointers used for switching stacks on interrupts/exceptions.
// Also holds I/O permission bitmap base. The TSS is referenced by
// a GDT entry (selector 0x28 in typical AGNOS layout).

typedef struct __attribute__((packed)) {
    uint32_t reserved0;
    uint64_t rsp0;          // stack pointer for ring 0
    uint64_t rsp1;          // stack pointer for ring 1
    uint64_t rsp2;          // stack pointer for ring 2
    uint64_t reserved1;
    uint64_t ist1;          // interrupt stack table 1
    uint64_t ist2;
    uint64_t ist3;
    uint64_t ist4;
    uint64_t ist5;
    uint64_t ist6;
    uint64_t ist7;
    uint64_t reserved2;
    uint16_t reserved3;
    uint16_t iomap_base;    // offset to I/O permission bitmap
} Tss;

// ── Layout Verification ─────────────────────────────────────────────

static void verify_gdt_layout(void) {
    // GDT entry must be exactly 8 bytes
    assert(sizeof(GdtEntry) == 8);

    // Field offsets
    assert(offsetof(GdtEntry, limit_lo) == 0);
    assert(offsetof(GdtEntry, base_lo) == 2);
    assert(offsetof(GdtEntry, base_mid) == 4);
    assert(offsetof(GdtEntry, access) == 5);
    assert(offsetof(GdtEntry, flags_limit) == 6);
    assert(offsetof(GdtEntry, base_hi) == 7);
}

static void verify_idt_layout(void) {
    // IDT gate must be exactly 16 bytes in long mode
    assert(sizeof(IdtGateDescriptor) == 16);

    assert(offsetof(IdtGateDescriptor, offset_lo) == 0);
    assert(offsetof(IdtGateDescriptor, selector) == 2);
    assert(offsetof(IdtGateDescriptor, ist) == 4);
    assert(offsetof(IdtGateDescriptor, type_attr) == 5);
    assert(offsetof(IdtGateDescriptor, offset_mid) == 6);
    assert(offsetof(IdtGateDescriptor, offset_hi) == 8);
    assert(offsetof(IdtGateDescriptor, reserved) == 12);
}

static void verify_multiboot_layout(void) {
    assert(sizeof(MultibootHeader) == 12);

    assert(offsetof(MultibootHeader, magic) == 0);
    assert(offsetof(MultibootHeader, flags) == 4);
    assert(offsetof(MultibootHeader, checksum) == 8);
}

static void verify_tss_layout(void) {
    // TSS in long mode is 104 bytes
    assert(sizeof(Tss) == 104);

    assert(offsetof(Tss, reserved0) == 0);
    assert(offsetof(Tss, rsp0) == 4);
    assert(offsetof(Tss, rsp1) == 12);
    assert(offsetof(Tss, rsp2) == 20);
    assert(offsetof(Tss, ist1) == 36);
    assert(offsetof(Tss, ist7) == 84);
    assert(offsetof(Tss, iomap_base) == 102);
}

// ── Tests ────────────────────────────────────────────────────────────

static void test_gdt_entries(void) {
    // Build a minimal GDT: null + code64 + data64
    GdtEntry gdt[5];
    gdt[0] = gdt_null();       // 0x00: null
    gdt[1] = gdt_code64(GDT_DPL_RING0);  // 0x08: kernel code
    gdt[2] = gdt_data(GDT_DPL_RING0);    // 0x10: kernel data
    gdt[3] = gdt_code64(GDT_DPL_RING3);  // 0x18: user code
    gdt[4] = gdt_data(GDT_DPL_RING3);    // 0x20: user data

    // Null entry must be all zeros
    uint8_t zeros[8] = {0};
    assert(memcmp(&gdt[0], zeros, 8) == 0);
    assert(!gdt_is_present(&gdt[0]));

    // Kernel code: present, ring 0, code, long mode
    assert(gdt_is_present(&gdt[1]));
    assert(gdt_dpl(&gdt[1]) == 0);
    assert(gdt_is_code(&gdt[1]));
    assert(gdt_is_long_mode(&gdt[1]));

    // Kernel data: present, ring 0, data
    assert(gdt_is_present(&gdt[2]));
    assert(gdt_dpl(&gdt[2]) == 0);
    assert(!gdt_is_code(&gdt[2]));

    // User code: present, ring 3, code, long mode
    assert(gdt_is_present(&gdt[3]));
    assert(gdt_dpl(&gdt[3]) == 3);
    assert(gdt_is_code(&gdt[3]));
    assert(gdt_is_long_mode(&gdt[3]));

    // User data: present, ring 3, data
    assert(gdt_is_present(&gdt[4]));
    assert(gdt_dpl(&gdt[4]) == 3);
    assert(!gdt_is_code(&gdt[4]));

    // Selector values = index * 8
    assert(0 * 8 == 0x00);  // null
    assert(1 * 8 == 0x08);  // kernel code
    assert(2 * 8 == 0x10);  // kernel data
    assert(3 * 8 == 0x18);  // user code
    assert(4 * 8 == 0x20);  // user data

    printf("GDT: 5 entries, %zu bytes total\n", sizeof(gdt));
    for (int i = 0; i < 5; i++) {
        const char *label = (const char *[]){"null", "kernel_code64",
            "kernel_data", "user_code64", "user_data"}[i];
        printf("  [0x%02X] %s: present=%d dpl=%d code=%d long=%d\n",
            i * 8, label, gdt_is_present(&gdt[i]), gdt_dpl(&gdt[i]),
            gdt_is_code(&gdt[i]), gdt_is_long_mode(&gdt[i]));
    }
}

static void test_idt_gate(void) {
    // Create interrupt gate for divide-by-zero (vector 0)
    uint64_t handler = 0xFFFF800000001000ULL;
    IdtGateDescriptor gate = idt_gate(handler, 0x08, IDT_INTERRUPT_GATE, 1);

    // Verify handler address reconstruction
    uint64_t reconstructed = idt_handler_addr(&gate);
    assert(reconstructed == handler);

    // Verify individual fields
    assert(gate.offset_lo == 0x1000);
    assert(gate.selector == 0x08);
    assert(gate.ist == 1);
    assert((gate.type_attr & 0x0F) == 0x0E);  // interrupt gate
    assert((gate.type_attr & 0x80) == 0x80);   // present
    assert(gate.offset_mid == 0x0000);
    assert(gate.offset_hi == 0xFFFF8000);
    assert(gate.reserved == 0);

    printf("\nIDT gate: handler=0x%016lX selector=0x%02X ist=%d\n",
        (unsigned long)reconstructed, gate.selector, gate.ist);
}

static void test_multiboot(void) {
    uint32_t flags = MULTIBOOT1_FLAG_ALIGN | MULTIBOOT1_FLAG_MEMINFO;
    MultibootHeader hdr = multiboot_header(flags);

    assert(hdr.magic == 0x1BADB002);
    assert(hdr.flags == 0x03);  // ALIGN | MEMINFO

    // Checksum verification: sum must wrap to zero
    uint32_t sum = hdr.magic + hdr.flags + hdr.checksum;
    assert(sum == 0);

    // Response magic
    assert(MULTIBOOT1_MAGIC_RESPONSE == 0x2BADB002);

    printf("\nMultiboot header: magic=0x%08X flags=0x%08X checksum=0x%08X\n",
        hdr.magic, hdr.flags, hdr.checksum);
    printf("  Response magic: 0x%08X (GRUB puts this in EAX)\n",
        MULTIBOOT1_MAGIC_RESPONSE);
}

static void test_tss(void) {
    Tss tss;
    memset(&tss, 0, sizeof(tss));

    // Set up interrupt stacks
    tss.rsp0 = 0xFFFF800000010000ULL;  // kernel stack
    tss.ist1 = 0xFFFF800000020000ULL;  // double fault stack
    tss.ist2 = 0xFFFF800000030000ULL;  // NMI stack
    tss.iomap_base = sizeof(Tss);       // no I/O bitmap (base past TSS)

    assert(tss.rsp0 == 0xFFFF800000010000ULL);
    assert(tss.ist1 == 0xFFFF800000020000ULL);
    assert(tss.ist2 == 0xFFFF800000030000ULL);
    assert(tss.iomap_base == 104);

    printf("\nTSS: %zu bytes\n", sizeof(tss));
    printf("  RSP0 (kernel stack): 0x%016lX\n", (unsigned long)tss.rsp0);
    printf("  IST1 (double fault): 0x%016lX\n", (unsigned long)tss.ist1);
    printf("  IST2 (NMI):         0x%016lX\n", (unsigned long)tss.ist2);
    printf("  I/O map base:       %u\n", tss.iomap_base);
}

static void test_control_register_bits(void) {
    // CR0 bits
    uint32_t cr0_pe = 1 << 0;   // Protection Enable
    uint32_t cr0_pg = 1 << 31;  // Paging

    assert(cr0_pe == 0x00000001);
    assert(cr0_pg == 0x80000000);

    // CR4 bits
    uint32_t cr4_pae = 1 << 5;  // Physical Address Extension
    assert(cr4_pae == 0x00000020);

    // EFER MSR bits (0xC0000080)
    uint32_t efer_lme = 1 << 8;   // Long Mode Enable
    uint32_t efer_lma = 1 << 10;  // Long Mode Active
    assert(efer_lme == 0x00000100);
    assert(efer_lma == 0x00000400);

    printf("\nControl register bits verified:\n");
    printf("  CR0.PE = bit 0  (0x%08X)\n", cr0_pe);
    printf("  CR0.PG = bit 31 (0x%08X)\n", cr0_pg);
    printf("  CR4.PAE = bit 5 (0x%08X)\n", cr4_pae);
    printf("  EFER.LME = bit 8  (0x%08X)\n", efer_lme);
    printf("  EFER.LMA = bit 10 (0x%08X)\n", efer_lma);
}

int main(void) {
    verify_gdt_layout();
    verify_idt_layout();
    verify_multiboot_layout();
    verify_tss_layout();

    test_gdt_entries();
    test_idt_gate();
    test_multiboot();
    test_tss();
    test_control_register_bits();

    printf("\nAll boot and startup assertions passed.\n");
    return 0;
}
