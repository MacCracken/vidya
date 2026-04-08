/* Interrupt Handling — C Implementation
 *
 * Demonstrates x86_64 interrupt handling concepts:
 *   1. IDT entry (gate descriptor) bit layout and encoding
 *   2. Interrupt stack frame structure
 *   3. Exception table with error code tracking
 *   4. PIC 8259A cascade configuration
 *   5. Page fault error code decoding
 *
 * In a real kernel, the IDT is loaded via LIDT and entries point to
 * assembly stubs. Here we show the exact data structure layouts.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* ── IDT Entry (16 bytes on x86_64) ──────────────────────────────────── */

/* Hardware layout of an x86_64 IDT gate descriptor.
 * The handler address is split across three fields because of i386 legacy. */
typedef struct __attribute__((packed)) {
    uint16_t offset_low;    /* handler address bits 0-15  */
    uint16_t selector;      /* GDT code segment selector  */
    uint8_t  ist;           /* IST index (bits 0-2), rest reserved */
    uint8_t  type_attr;     /* P(1) DPL(2) 0(1) type(4)  */
    uint16_t offset_mid;    /* handler address bits 16-31 */
    uint32_t offset_high;   /* handler address bits 32-63 */
    uint32_t reserved;
} idt_entry_t;

/* Verify the struct is exactly 16 bytes — hardware requirement */
_Static_assert(sizeof(idt_entry_t) == 16, "IDT entry must be 16 bytes");

#define GATE_INTERRUPT  0x0E  /* 64-bit interrupt gate (clears IF) */
#define GATE_TRAP       0x0F  /* 64-bit trap gate (IF unchanged)   */
#define IDT_PRESENT     0x80

static idt_entry_t idt_interrupt_gate(uint64_t handler, uint16_t selector,
                                       uint8_t ist, uint8_t dpl) {
    idt_entry_t e;
    memset(&e, 0, sizeof(e));
    e.offset_low  = (uint16_t)(handler & 0xFFFF);
    e.selector    = selector;
    e.ist         = ist & 0x7;
    e.type_attr   = IDT_PRESENT | ((dpl & 0x3) << 5) | GATE_INTERRUPT;
    e.offset_mid  = (uint16_t)((handler >> 16) & 0xFFFF);
    e.offset_high = (uint32_t)((handler >> 32) & 0xFFFFFFFF);
    e.reserved    = 0;
    return e;
}

static uint64_t idt_handler_addr(const idt_entry_t *e) {
    return (uint64_t)e->offset_low
         | ((uint64_t)e->offset_mid << 16)
         | ((uint64_t)e->offset_high << 32);
}

static int idt_is_present(const idt_entry_t *e) {
    return (e->type_attr & IDT_PRESENT) != 0;
}

/* ── Interrupt Stack Frame ───────────────────────────────────────────── */

/* What the CPU pushes onto the stack when an interrupt fires.
 * On privilege change (ring 3 -> ring 0), SS and RSP are from TSS. */
typedef struct {
    uint64_t rip;
    uint64_t cs;
    uint64_t rflags;
    uint64_t rsp;
    uint64_t ss;
} interrupt_frame_t;

/* ── Exception Table ─────────────────────────────────────────────────── */

typedef enum {
    EXC_FAULT,
    EXC_TRAP,
    EXC_ABORT,
    EXC_INTERRUPT,
    EXC_FAULT_TRAP
} exception_type_t;

typedef struct {
    uint8_t         vector;
    const char     *name;
    int             has_error_code;
    exception_type_t type;
} exception_info_t;

static const char *exception_type_str(exception_type_t t) {
    switch (t) {
        case EXC_FAULT:      return "fault";
        case EXC_TRAP:       return "trap";
        case EXC_ABORT:      return "abort";
        case EXC_INTERRUPT:  return "interrupt";
        case EXC_FAULT_TRAP: return "fault/trap";
    }
    return "unknown";
}

static const exception_info_t EXCEPTIONS[] = {
    {  0, "Divide Error (#DE)",          0, EXC_FAULT      },
    {  1, "Debug (#DB)",                 0, EXC_FAULT_TRAP },
    {  2, "NMI",                         0, EXC_INTERRUPT  },
    {  3, "Breakpoint (#BP)",            0, EXC_TRAP       },
    {  4, "Overflow (#OF)",              0, EXC_TRAP       },
    {  5, "Bound Range (#BR)",           0, EXC_FAULT      },
    {  6, "Invalid Opcode (#UD)",        0, EXC_FAULT      },
    {  7, "Device Not Available (#NM)",  0, EXC_FAULT      },
    {  8, "Double Fault (#DF)",          1, EXC_ABORT      },
    { 10, "Invalid TSS (#TS)",           1, EXC_FAULT      },
    { 11, "Segment Not Present (#NP)",   1, EXC_FAULT      },
    { 12, "Stack Fault (#SS)",           1, EXC_FAULT      },
    { 13, "General Protection (#GP)",    1, EXC_FAULT      },
    { 14, "Page Fault (#PF)",            1, EXC_FAULT      },
    { 16, "x87 FP Exception (#MF)",      0, EXC_FAULT      },
    { 17, "Alignment Check (#AC)",       1, EXC_FAULT      },
    { 18, "Machine Check (#MC)",         0, EXC_ABORT      },
    { 19, "SIMD FP Exception (#XM)",     0, EXC_FAULT      },
};

#define NUM_EXCEPTIONS (sizeof(EXCEPTIONS) / sizeof(EXCEPTIONS[0]))

/* ── PIC 8259A ───────────────────────────────────────────────────────── */

/* The legacy PIC maps hardware IRQs to interrupt vectors.
 * Master: IRQ 0-7, Slave: IRQ 8-15 (cascade on master IRQ 2). */
typedef struct {
    uint8_t base_vector;  /* remapped base (0x20 master, 0x28 slave) */
    uint8_t mask;         /* IMR: bit set = IRQ masked               */
    uint8_t isr;          /* In-Service Register                     */
    uint8_t irr;          /* Interrupt Request Register               */
} pic_t;

static void pic_init(pic_t *pic, uint8_t base) {
    pic->base_vector = base;
    pic->mask = 0xFF;  /* all masked initially */
    pic->isr = 0;
    pic->irr = 0;
}

static void pic_unmask(pic_t *pic, int irq_line) {
    pic->mask &= ~(1 << irq_line);
}

static void pic_raise_irq(pic_t *pic, int irq_line) {
    pic->irr |= (1 << irq_line);
}

/* Acknowledge highest-priority pending unmasked IRQ. Returns vector or -1. */
static int pic_acknowledge(pic_t *pic) {
    uint8_t pending = pic->irr & ~pic->mask;
    if (pending == 0) return -1;
    for (int i = 0; i < 8; i++) {
        if (pending & (1 << i)) {
            pic->irr &= ~(1 << i);
            pic->isr |= (1 << i);
            return pic->base_vector + i;
        }
    }
    return -1;
}

static void pic_eoi(pic_t *pic, int irq_line) {
    pic->isr &= ~(1 << irq_line);
}

/* ── Page Fault Error Code ───────────────────────────────────────────── */

static void decode_pf_error(uint64_t code, char *buf, size_t buflen) {
    /* Bit 0: 0=not present, 1=protection violation
     * Bit 1: 0=read, 1=write
     * Bit 2: 0=kernel, 1=user
     * Bit 3: reserved bit set
     * Bit 4: instruction fetch (NX) */
    snprintf(buf, buflen, "%s, %s, %s%s%s",
             (code & 1) ? "protection violation" : "page not present",
             (code & 2) ? "write" : "read",
             (code & 4) ? "user mode" : "kernel mode",
             (code & 8) ? ", reserved bit" : "",
             (code & 16) ? ", instruction fetch" : "");
}

/* ── Main ────────────────────────────────────────────────────────────── */

int main(void) {
    printf("Interrupt Handling — x86_64 IDT and exception mechanics:\n\n");

    /* ── 1. Build the IDT ──────────────────────────────────────────── */
    printf("1. IDT entry layout (16 bytes per entry):\n");

    idt_entry_t idt[256];
    memset(idt, 0, sizeof(idt));

    /* Register exception handlers */
    unsigned handlers_set = 0;
    for (unsigned i = 0; i < NUM_EXCEPTIONS; i++) {
        uint64_t handler = 0xFFFF800000100000ULL + (EXCEPTIONS[i].vector * 0x100);
        uint8_t ist = (EXCEPTIONS[i].vector == 8) ? 1 : 0;
        idt[EXCEPTIONS[i].vector] = idt_interrupt_gate(handler, 0x08, ist, 0);
        handlers_set++;
    }

    /* Timer (IRQ 0 = vector 32) and keyboard (IRQ 1 = vector 33) */
    idt[32] = idt_interrupt_gate(0xFFFF800000200000ULL, 0x08, 0, 0);
    idt[33] = idt_interrupt_gate(0xFFFF800000200100ULL, 0x08, 0, 0);
    handlers_set += 2;

    printf("   Registered %u handlers (%zu exceptions + 2 IRQs)\n",
           handlers_set, NUM_EXCEPTIONS);

    /* Verify IDT entry encoding */
    assert(idt_is_present(&idt[14]));
    assert(idt_handler_addr(&idt[14]) == 0xFFFF800000100000ULL + 14 * 0x100);
    assert(idt[8].ist == 1);  /* Double fault uses IST[1] */
    assert(idt[14].type_attr == 0x8E);  /* P=1, DPL=0, type=0x0E */

    printf("   IDT[14] #PF: handler=0x%016llX type_attr=0x%02X ist=%d\n",
           (unsigned long long)idt_handler_addr(&idt[14]),
           idt[14].type_attr, idt[14].ist);
    printf("   IDT[8]  #DF: handler=0x%016llX type_attr=0x%02X ist=%d\n",
           (unsigned long long)idt_handler_addr(&idt[8]),
           idt[8].type_attr, idt[8].ist);
    printf("   IDT[32] timer: handler=0x%016llX\n",
           (unsigned long long)idt_handler_addr(&idt[32]));

    /* ── 2. Exception table ──────────────────────────────────────────── */
    printf("\n2. x86_64 exception table:\n");
    printf("   %3s  %-35s %5s %-10s\n", "#", "Name", "ErrC", "Type");
    printf("   ");
    for (int i = 0; i < 55; i++) printf("-");
    printf("\n");

    for (unsigned i = 0; i < NUM_EXCEPTIONS; i++) {
        printf("   %3d  %-35s %5s %-10s\n",
               EXCEPTIONS[i].vector,
               EXCEPTIONS[i].name,
               EXCEPTIONS[i].has_error_code ? "yes" : "no",
               exception_type_str(EXCEPTIONS[i].type));
    }

    /* ── 3. PIC 8259A cascade ────────────────────────────────────────── */
    printf("\n3. PIC 8259A cascade configuration:\n");

    pic_t master, slave;
    pic_init(&master, 0x20);
    pic_init(&slave, 0x28);

    pic_unmask(&master, 0);  /* timer */
    pic_unmask(&master, 1);  /* keyboard */
    pic_unmask(&master, 2);  /* cascade to slave */
    pic_unmask(&slave, 0);   /* IRQ 8 (RTC) */

    printf("   Master PIC: base=0x%02X mask=0x%02X\n", master.base_vector, master.mask);
    printf("     IRQ 0 (timer):    %s\n", (master.mask & 1) ? "masked" : "unmasked");
    printf("     IRQ 1 (keyboard): %s\n", (master.mask & 2) ? "masked" : "unmasked");
    printf("     IRQ 2 (cascade):  %s\n", (master.mask & 4) ? "masked" : "unmasked");
    printf("   Slave PIC:  base=0x%02X mask=0x%02X\n", slave.base_vector, slave.mask);
    printf("     IRQ 8 (RTC):      %s\n", (slave.mask & 1) ? "masked" : "unmasked");

    /* Simulate timer interrupt through PIC */
    pic_raise_irq(&master, 0);
    int vec = pic_acknowledge(&master);
    assert(vec == 0x20);
    printf("\n   Timer IRQ -> vector 0x%02X (IRQ %d)\n", vec, vec - master.base_vector);
    pic_eoi(&master, 0);
    assert(master.isr == 0);

    /* ── 4. Interrupt stack frame layout ─────────────────────────────── */
    printf("\n4. Interrupt stack frame layout (pushed by CPU):\n");
    printf("   Offset  Field     Size  Notes\n");
    printf("   ─────────────────────────────────────────────\n");
    printf("   +0x00   RIP       8     return address\n");
    printf("   +0x08   CS        8     code segment (padded to 8)\n");
    printf("   +0x10   RFLAGS    8     flags register\n");
    printf("   +0x18   RSP       8     user stack pointer\n");
    printf("   +0x20   SS        8     stack segment (padded to 8)\n");
    printf("   Total: 40 bytes (5 quadwords)\n");

    interrupt_frame_t frame = {
        .rip    = 0x0000000000401234ULL,
        .cs     = 0x2B,
        .rflags = 0x202,
        .rsp    = 0x00007FFFFFFEF000ULL,
        .ss     = 0x33,
    };
    printf("   Example: RIP=0x%016llX CS=0x%04llX RFLAGS=0x%08llX\n",
           (unsigned long long)frame.rip,
           (unsigned long long)frame.cs,
           (unsigned long long)frame.rflags);

    /* ── 5. Page fault error code decoding ───────────────────────────── */
    printf("\n5. Page fault error code decoding:\n");

    struct { uint64_t code; const char *desc; } pf_tests[] = {
        { 0x00, "kernel read, not present" },
        { 0x02, "kernel write, not present" },
        { 0x04, "user read, not present" },
        { 0x05, "user read, protection" },
        { 0x06, "user write, not present" },
        { 0x07, "user write, protection" },
        { 0x14, "user instruction fetch (NX)" },
    };

    char buf[256];
    for (unsigned i = 0; i < sizeof(pf_tests)/sizeof(pf_tests[0]); i++) {
        decode_pf_error(pf_tests[i].code, buf, sizeof(buf));
        printf("   0x%02llX -> %s\n",
               (unsigned long long)pf_tests[i].code, buf);
    }

    /* Verify error code decoding */
    decode_pf_error(0x06, buf, sizeof(buf));
    assert(strstr(buf, "not present") != NULL);
    assert(strstr(buf, "write") != NULL);
    assert(strstr(buf, "user") != NULL);

    printf("\n6. Key rules:\n");
    printf("   - #DF handler MUST use IST (needs guaranteed-good stack)\n");
    printf("   - Push dummy error code for exceptions without one (uniform frame)\n");
    printf("   - Send EOI to PIC/LAPIC after hardware interrupts\n");
    printf("   - IRETQ (not RET) to return from interrupt handlers\n");
    printf("   - Compile with -mno-red-zone (ISRs clobber red zone)\n");

    printf("\nAll assertions passed.\n");
    return 0;
}
