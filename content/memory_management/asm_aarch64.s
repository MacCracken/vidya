// Vidya — Memory Management in AArch64 Assembly
//
// AArch64 is a load/store architecture: all data manipulation happens
// in registers, memory is accessed only via LDR/STR. Stack grows down
// (SP must be 16-byte aligned). Heap is allocated via mmap syscall.
// The architecture enforces stricter alignment than x86_64.

.global _start

.section .data
static_val: .quad 42

.section .rodata
msg_pass:   .ascii "All memory management examples passed.\n"
msg_len = . - msg_pass

.section .bss
.align 4
bss_buf:    .skip 4096

.section .text

_start:
    // ── Register storage ───────────────────────────────────────────
    mov     x0, #42
    mov     x1, x0
    cmp     x1, #42
    b.ne    fail

    // ── Stack allocation ───────────────────────────────────────────
    // SP must be 16-byte aligned on AArch64
    sub     sp, sp, #32         // allocate 32 bytes
    mov     x0, #100
    str     x0, [sp]            // store at sp+0
    mov     x0, #200
    str     x0, [sp, #8]        // store at sp+8

    ldr     x0, [sp]
    cmp     x0, #100
    b.ne    fail
    ldr     x0, [sp, #8]
    cmp     x0, #200
    b.ne    fail
    add     sp, sp, #32         // deallocate

    // ── STP/LDP: store/load pair (efficient) ───────────────────────
    // Stores two registers in one instruction
    sub     sp, sp, #16
    stp     x19, x20, [sp]     // save callee-saved registers
    mov     x19, #111
    mov     x20, #222
    cmp     x19, #111
    b.ne    fail
    ldp     x19, x20, [sp]     // restore
    add     sp, sp, #16

    // ── Static data section ────────────────────────────────────────
    adr     x0, static_val
    ldr     x1, [x0]
    cmp     x1, #42
    b.ne    fail

    // Modify static data
    mov     x1, #100
    str     x1, [x0]
    ldr     x1, [x0]
    cmp     x1, #100
    b.ne    fail
    // Restore
    mov     x1, #42
    str     x1, [x0]

    // ── BSS: zero-initialized ──────────────────────────────────────
    adr     x0, bss_buf
    ldr     x1, [x0]
    cbnz    x1, fail            // should be zero

    mov     x1, #0xDEAD
    str     x1, [x0]
    ldr     x1, [x0]
    mov     x2, #0xDEAD
    cmp     x1, x2
    b.ne    fail

    // ── Heap via mmap ──────────────────────────────────────────────
    // mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    mov     x8, #222            // sys_mmap
    mov     x0, #0              // addr = NULL
    mov     x1, #4096           // length
    mov     x2, #3              // PROT_READ | PROT_WRITE
    mov     x3, #0x22           // MAP_PRIVATE | MAP_ANONYMOUS
    mov     x4, #-1             // fd = -1
    mov     x5, #0              // offset
    svc     #0

    // Check success (positive address)
    cmn     x0, #4096           // if x0 > -4096, it's an error
    b.hi    fail
    mov     x19, x0             // save heap pointer

    // Write and read heap
    mov     x1, #0xCAFE
    str     x1, [x19]
    ldr     x1, [x19]
    mov     x2, #0xCAFE
    cmp     x1, x2
    b.ne    fail

    // munmap
    mov     x8, #215            // sys_munmap
    mov     x0, x19
    mov     x1, #4096
    svc     #0
    cbnz    x0, fail

    // ── Addressing modes ───────────────────────────────────────────
    // AArch64 has rich addressing: base+offset, pre/post-index, register offset

    sub     sp, sp, #32
    mov     x0, #10
    mov     x1, #20
    mov     x2, #30
    mov     x3, #40

    // Base + immediate offset
    str     x0, [sp, #0]
    str     x1, [sp, #8]
    str     x2, [sp, #16]
    str     x3, [sp, #24]

    // Pre-index: update base before access
    mov     x4, sp
    ldr     x5, [x4, #8]!      // x4 = sp+8, then load from x4
    cmp     x5, #20
    b.ne    fail

    // Post-index: access then update base
    ldr     x5, [x4], #8       // load from x4, then x4 += 8
    cmp     x5, #20             // loaded value before increment
    b.ne    fail

    add     sp, sp, #32

    // ── DMB: data memory barrier ───────────────────────────────────
    // AArch64 has weaker memory ordering than x86_64
    // DMB ensures ordering of memory accesses
    adr     x0, bss_buf
    mov     x1, #99
    str     x1, [x0]
    dmb     ish                 // inner shareable barrier
    ldr     x1, [x0]
    cmp     x1, #99
    b.ne    fail

    // ── Print success ──────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0
