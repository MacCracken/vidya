// Vidya — Design Patterns in AArch64 Assembly
//
// Assembly patterns: function pointer dispatch (strategy), state
// transition table lookup (state machine), cleanup via structured
// bl/ret (RAII-like resource management). Same concepts as x86_64,
// adapted for AArch64's fixed-width instructions and register file.

.global _start

.section .rodata
msg_pass:   .ascii "All design patterns examples passed.\n"
msg_len = . - msg_pass

// ── Strategy: function pointer table ─────────────────────────────────
.align 8
strategy_table:
    .xword  strat_no_discount     // index 0
    .xword  strat_ten_percent     // index 1
    .xword  strat_flat_five       // index 2

// ── State machine: transition table ──────────────────────────────────
// States: 0=locked, 1=closed, 2=open
// Actions: 0=unlock, 1=open, 2=close, 3=lock
// Table[state][action] = next_state, 0xFF = invalid

transition_table:
    // locked: unlock→closed, open→invalid, close→invalid, lock→invalid
    .byte 1, 0xFF, 0xFF, 0xFF
    // closed: unlock→invalid, open→open, close→invalid, lock→locked
    .byte 0xFF, 2, 0xFF, 0
    // open: unlock→invalid, open→invalid, close→closed, lock→invalid
    .byte 0xFF, 0xFF, 1, 0xFF

.section .text

_start:
    // Save link register for nested calls
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: strategy — no discount on 100 → 100 ─────────────────
    adr     x0, strategy_table
    mov     w1, #100
    mov     w2, #0              // strategy index
    bl      apply_strategy
    cmp     w0, #100
    b.ne    fail

    // ── Test 2: strategy — 10% off 100 → 90 ─────────────────────────
    adr     x0, strategy_table
    mov     w1, #100
    mov     w2, #1
    bl      apply_strategy
    cmp     w0, #90
    b.ne    fail

    // ── Test 3: strategy — $5 off 100 → 95 ──────────────────────────
    adr     x0, strategy_table
    mov     w1, #100
    mov     w2, #2
    bl      apply_strategy
    cmp     w0, #95
    b.ne    fail

    // ── Test 4: strategy — $5 off 3 → 0 (floor) ────────────────────
    adr     x0, strategy_table
    mov     w1, #3
    mov     w2, #2
    bl      apply_strategy
    cmp     w0, #0
    b.ne    fail

    // ── Test 5: state machine — locked → unlock → closed ────────────
    mov     w0, #0              // state = locked
    mov     w1, #0              // action = unlock
    bl      state_transition
    cmp     w0, #1              // expect closed
    b.ne    fail

    // ── Test 6: state machine — closed → open → open ────────────────
    mov     w0, #1              // state = closed
    mov     w1, #1              // action = open
    bl      state_transition
    cmp     w0, #2              // expect open
    b.ne    fail

    // ── Test 7: state machine — open → close → closed ───────────────
    mov     w0, #2              // state = open
    mov     w1, #2              // action = close
    bl      state_transition
    cmp     w0, #1              // expect closed
    b.ne    fail

    // ── Test 8: state machine — closed → lock → locked ──────────────
    mov     w0, #1              // state = closed
    mov     w1, #3              // action = lock
    bl      state_transition
    cmp     w0, #0              // expect locked
    b.ne    fail

    // ── Test 9: state machine — invalid: locked → open ──────────────
    mov     w0, #0              // state = locked
    mov     w1, #1              // action = open
    bl      state_transition
    cmn     w0, #1              // compare with -1
    b.ne    fail

    // ── Test 10: cleanup pattern — resource counter ─────────────────
    bl      test_cleanup
    cmp     w0, #0              // should be back to 0
    b.ne    fail

    // ── Test 11: full state cycle ────────────────────────────────────
    // locked → unlock → open → close → lock → locked
    mov     w0, #0
    mov     w1, #0              // unlock
    bl      state_transition
    mov     w1, #1              // open
    bl      state_transition
    mov     w1, #2              // close
    bl      state_transition
    mov     w1, #3              // lock
    bl      state_transition
    cmp     w0, #0              // back to locked
    b.ne    fail

    // ── All passed ───────────────────────────────────────────────────
    mov     x8, #64             // sys_write
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93             // sys_exit
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── apply_strategy(x0=table, w1=price, w2=index) → w0 ───────────────
// Loads function pointer from table[index] and calls it with price.
apply_strategy:
    stp     x29, x30, [sp, #-16]!
    ldr     x3, [x0, x2, lsl #3]   // load function pointer
    mov     w0, w1                  // price as first arg
    blr     x3                      // call strategy
    ldp     x29, x30, [sp], #16
    ret

// ── Strategy implementations ─────────────────────────────────────────
// Each takes w0=price, returns w0=result.

strat_no_discount:
    // w0 already has price
    ret

strat_ten_percent:
    // price * 9 / 10
    mov     w1, #9
    mul     w0, w0, w1
    mov     w1, #10
    udiv    w0, w0, w1
    ret

strat_flat_five:
    subs    w0, w0, #5
    b.pl    .sf_done
    mov     w0, #0              // floor at 0
.sf_done:
    ret

// ── state_transition(w0=state, w1=action) → w0 (next or -1) ─────────
// Looks up transition_table[state * 4 + action].
state_transition:
    adr     x2, transition_table
    lsl     w3, w0, #2             // state * 4
    add     w3, w3, w1             // + action
    ldrb    w0, [x2, w3, uxtw]    // load byte
    cmp     w0, #0xFF
    b.eq    .st_invalid
    ret
.st_invalid:
    mov     w0, #-1
    ret

// ── test_cleanup() → w0 (resource counter, should be 0) ─────────────
// Structured acquire/release using stack discipline.
test_cleanup:
    mov     w0, #0              // counter = 0
    add     w0, w0, #1          // acquire resource 1 (counter = 1)
    add     w0, w0, #1          // acquire resource 2 (counter = 2)
    add     w0, w0, #1          // acquire resource 3 (counter = 3)
    // Release in reverse order (LIFO)
    sub     w0, w0, #1          // release resource 3 (counter = 2)
    sub     w0, w0, #1          // release resource 2 (counter = 1)
    sub     w0, w0, #1          // release resource 1 (counter = 0)
    ret
