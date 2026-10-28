// Vidya — Quantum Computing in AArch64 Assembly
//
// Quantum concepts at the instruction level: state space sizing,
// Grover iteration counting, resource estimation, gate budget
// calculations. AArch64's multiply-accumulate instructions (madd)
// map well to complex arithmetic.

.global _start

.section .rodata
msg_pass:   .ascii "All quantum computing examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    // ── Test 1: State space size = 2^n ────────────────────────────────
    // 1 qubit → 2
    mov     w0, #1
    mov     w1, #1
    lsl     w1, w1, w0
    cmp     w1, #2
    b.ne    fail

    // 10 qubits → 1024
    mov     w0, #10
    mov     w1, #1
    lsl     w1, w1, w0
    cmp     w1, #1024
    b.ne    fail

    // 20 qubits → 1048576
    mov     w0, #20
    mov     w1, #1
    lsl     w1, w1, w0
    mov     w2, #0x100000       // 1048576
    cmp     w1, w2
    b.ne    fail

    // ── Test 2: Simulation memory = 2^n × 16 bytes ───────────────────
    // 20 qubits: 1048576 × 16 = 16777216 (16MB)
    mov     x0, #20
    mov     x1, #1
    lsl     x1, x1, x0
    lsl     x1, x1, #4         // × 16
    mov     x2, #16777216
    cmp     x1, x2
    b.ne    fail

    // ── Test 3: Grover iterations N=4 ─────────────────────────────────
    // floor(785 × 2 / 1000) = 1
    mov     w0, #785
    mov     w1, #2
    mul     w0, w0, w1         // 1570
    mov     w1, #1000
    udiv    w0, w0, w1         // 1
    cmp     w0, #1
    b.ne    fail

    // ── Test 4: Grover iterations N=1M ────────────────────────────────
    // floor(785 × 1000 / 1000) = 785
    mov     w0, #785
    mov     w1, #1000
    mul     w0, w0, w1         // 785000
    mov     w1, #1000
    udiv    w0, w0, w1         // 785
    mov     w2, #785
    cmp     w0, w2
    b.ne    fail

    // ── Test 5: Physical qubits needed ────────────────────────────────
    // 4000 × 1000 = 4000000
    mov     x0, #4000
    mov     x1, #1000
    mul     x0, x0, x1
    movz    x2, #0x0900         // 4000000 = 0x3D0900
    movk    x2, #0x003D, lsl #16
    cmp     x0, x2
    b.ne    fail

    // ── Test 6: Gate budget ───────────────────────────────────────────
    // 100000ns / 20ns = 5000
    movz    w0, #0x86A0         // 100000 = 0x186A0
    movk    w0, #0x0001, lsl #16
    mov     w1, #20
    udiv    w0, w0, w1
    mov     w2, #5000
    cmp     w0, w2
    b.ne    fail

    // ── Test 7: Quantum volume ────────────────────────────────────────
    mov     w0, #1
    lsl     w0, w0, #5         // 2^5 = 32
    cmp     w0, #32
    b.ne    fail

    mov     w0, #1
    lsl     w0, w0, #10        // 2^10 = 1024
    cmp     w0, #1024
    b.ne    fail

    // ── Test 8: FLOPs per gate ────────────────────────────────────────
    // 6 × 2^20 = 6291456
    mov     x0, #1
    lsl     x0, x0, #20
    mov     x1, #6
    mul     x0, x0, x1
    movz    x2, #0x0000         // 6291456 = 0x600000
    movk    x2, #0x0060, lsl #16
    cmp     x0, x2
    b.ne    fail

    // ── All passed ───────────────────────────────────────────────────
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
