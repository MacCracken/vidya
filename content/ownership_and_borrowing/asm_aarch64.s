// Vidya — Ownership and Borrowing in AArch64 Assembly
//
// There is no ownership at the machine level. Registers and memory
// are freely aliased — any register can point to any address, and
// nothing prevents double-free or use-after-free. The programmer
// must manually track lifetimes. This file demonstrates the patterns
// that ownership systems automate: single-owner transfer, borrowing
// via pointer passing, and manual cleanup with BL/RET discipline.

.global _start

.section .rodata
msg_pass:   .ascii "All ownership and borrowing examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: ownership transfer (move semantics) ─────────────────
    // In Rust: let b = a; (a is moved, can't use a anymore)
    // In asm: we just copy the register. Nothing prevents using both.
    // The DISCIPLINE is: after "moving" w0 to w1, treat w0 as invalid.
    mov     w0, #42                 // "a" owns the value
    mov     w1, w0                  // "b" takes ownership (move)
    // Convention: w0 is now "dead" — we must not read it
    // w1 is the owner
    cmp     w1, #42
    b.ne    fail

    // ── Test 2: borrowing (shared reference) ────────────────────────
    // Borrow = pass a pointer without transferring ownership.
    // The callee reads but does not free/modify the pointee.
    sub     sp, sp, #16
    mov     w0, #100
    str     w0, [sp]               // "owner" stores value on stack

    mov     x0, sp                  // lend pointer (shared borrow)
    bl      borrow_read            // callee reads through pointer
    cmp     w0, #100                // value unchanged
    b.ne    fail

    // Owner can still use it after borrow returns
    ldr     w0, [sp]
    cmp     w0, #100
    b.ne    fail
    add     sp, sp, #16

    // ── Test 3: mutable borrow ──────────────────────────────────────
    // Mutable borrow = pass pointer, callee may write through it.
    // Only one mutable borrow at a time (by convention in asm).
    sub     sp, sp, #16
    mov     w0, #50
    str     w0, [sp]               // owner stores value

    mov     x0, sp                  // mutable borrow
    bl      borrow_mutate          // callee writes through pointer

    ldr     w0, [sp]               // owner reads back
    cmp     w0, #51                 // callee incremented it
    b.ne    fail
    add     sp, sp, #16

    // ── Test 4: aliasing — the problem ownership prevents ───────────
    // Two pointers to the same data. Both can write. Data race city.
    sub     sp, sp, #16
    mov     w0, #10
    str     w0, [sp]

    mov     x0, sp                  // alias 1
    mov     x1, sp                  // alias 2 (same address!)

    // Write through alias 1
    mov     w2, #20
    str     w2, [x0]

    // Read through alias 2 — sees the write (aliased!)
    ldr     w3, [x1]
    cmp     w3, #20                 // alias 2 sees alias 1's write
    b.ne    fail
    add     sp, sp, #16

    // ── Test 5: manual cleanup (RAII equivalent) ────────────────────
    // Allocate on stack, use, then clean up in reverse order.
    // This is the pattern that Drop/RAII automates.
    sub     sp, sp, #32            // allocate "resources"

    // Initialize resources
    mov     w0, #1
    str     w0, [sp, #0]           // resource A
    mov     w0, #2
    str     w0, [sp, #4]           // resource B
    mov     w0, #3
    str     w0, [sp, #8]           // resource C

    // Use resources
    ldr     w1, [sp, #0]
    ldr     w2, [sp, #4]
    ldr     w3, [sp, #8]
    add     w0, w1, w2
    add     w0, w0, w3             // 1 + 2 + 3 = 6
    cmp     w0, #6
    b.ne    fail

    // Cleanup in reverse order (LIFO — like destructors)
    str     wzr, [sp, #8]          // release C
    str     wzr, [sp, #4]          // release B
    str     wzr, [sp, #0]          // release A
    add     sp, sp, #32            // deallocate

    // ── Test 6: scope-based lifetime ────────────────────────────────
    // Inner scope borrows from outer scope. When inner returns,
    // the borrow ends and the outer scope still owns the data.
    sub     sp, sp, #16
    mov     w0, #77
    str     w0, [sp]               // outer scope owns

    mov     x0, sp
    bl      inner_scope            // inner scope borrows
    cmp     w0, #77                 // inner returned the value
    b.ne    fail

    // Outer scope still has the data
    ldr     w0, [sp]
    cmp     w0, #77
    b.ne    fail
    add     sp, sp, #16

    // ── Test 7: transfer and return (move out, move back) ───────────
    // Function takes ownership, transforms, returns new value.
    mov     w0, #10
    bl      take_and_transform     // takes w0, returns w0
    cmp     w0, #20                 // transformed: 10 * 2
    b.ne    fail

    // ── Test 8: double-free prevention (manual) ─────────────────────
    // Mark pointer as null after "free" to prevent double-free.
    sub     sp, sp, #16
    mov     w0, #42
    str     w0, [sp]

    // "Free" by zeroing and nulling the pointer
    str     wzr, [sp]              // clear data
    mov     x0, xzr                // null the pointer

    // Before "using", check for null (manual null check)
    cbz     x0, .Lnull_ok          // null -> skip use
    b       fail                    // should not reach here
.Lnull_ok:
    add     sp, sp, #16

    // ── Print success ────────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    ldp     x29, x30, [sp], #16
    mov     x8, #93
    mov     x0, #0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── borrow_read(x0=ptr) -> w0=value ────────────────────────────────
// Shared borrow: read only, do not modify.
borrow_read:
    ldr     w0, [x0]
    ret

// ── borrow_mutate(x0=ptr) ──────────────────────────────────────────
// Mutable borrow: read, modify, write back.
borrow_mutate:
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]
    ret

// ── inner_scope(x0=ptr) -> w0=value ────────────────────────────────
// Borrows pointer, reads value, returns it. Does not modify.
inner_scope:
    ldr     w0, [x0]
    ret

// ── take_and_transform(w0=value) -> w0=result ──────────────────────
// Takes "ownership" of the value, transforms it, returns new value.
take_and_transform:
    lsl     w0, w0, #1             // value * 2
    ret
