// Vidya — Trait and Typeclass Systems in AArch64 Assembly
//
// At the machine level, trait dispatch is vtable lookup: load a
// function pointer from a table, then BLR (branch-link-register)
// for indirect call. A vtable is just an array of function pointers.
// The "trait object" is a pair: (data_ptr, vtable_ptr). Each type's
// vtable has the same layout — slot 0 is method A, slot 1 is method B.
// The caller doesn't know the concrete type, only the slot index.

.global _start

.section .rodata
msg_pass:   .ascii "All trait and typeclass systems examples passed.\n"
msg_len = . - msg_pass

// ── Vtable layout ───────────────────────────────────────────────────
// Trait "Shape":
//   slot 0: area(self) -> w0
//   slot 1: perimeter(self) -> w0
//
// Each concrete type provides its own vtable with function pointers.

.align 3
vtable_square:
    .xword  square_area             // slot 0: area
    .xword  square_perimeter        // slot 1: perimeter

.align 3
vtable_rect:
    .xword  rect_area               // slot 0: area
    .xword  rect_perimeter          // slot 1: perimeter

.section .data
.align 2
// Square with side=5
square_data:    .word 5

// Rectangle with width=4, height=6
rect_data:      .word 4, 6

.section .text

_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // ── Test 1: direct vtable dispatch — square area ────────────────
    // Load vtable, load function pointer from slot 0, call via BLR.
    adr     x0, square_data         // data pointer
    adr     x1, vtable_square       // vtable pointer
    ldr     x2, [x1, #0]           // slot 0 = area function
    blr     x2                      // indirect call
    cmp     w0, #25                 // 5 * 5 = 25
    b.ne    fail

    // ── Test 2: direct vtable dispatch — square perimeter ───────────
    adr     x0, square_data
    adr     x1, vtable_square
    ldr     x2, [x1, #8]           // slot 1 = perimeter function
    blr     x2
    cmp     w0, #20                 // 5 * 4 = 20
    b.ne    fail

    // ── Test 3: direct vtable dispatch — rect area ──────────────────
    adr     x0, rect_data
    adr     x1, vtable_rect
    ldr     x2, [x1, #0]           // slot 0 = area function
    blr     x2
    cmp     w0, #24                 // 4 * 6 = 24
    b.ne    fail

    // ── Test 4: direct vtable dispatch — rect perimeter ─────────────
    adr     x0, rect_data
    adr     x1, vtable_rect
    ldr     x2, [x1, #8]           // slot 1 = perimeter function
    blr     x2
    cmp     w0, #20                 // 2*(4+6) = 20
    b.ne    fail

    // ── Test 5: generic dispatch via trait_call helper ───────────────
    // This is what the compiler generates for `dyn Trait` calls.
    // trait_call(data_ptr, vtable_ptr, slot_index) -> w0
    adr     x0, square_data
    adr     x1, vtable_square
    mov     w2, #0                  // slot 0 = area
    bl      trait_call
    cmp     w0, #25
    b.ne    fail

    // ── Test 6: generic dispatch — different type, same slot ────────
    adr     x0, rect_data
    adr     x1, vtable_rect
    mov     w2, #0                  // slot 0 = area
    bl      trait_call
    cmp     w0, #24                 // same slot, different implementation
    b.ne    fail

    // ── Test 7: polymorphic iteration over "trait objects" ───────────
    // Process an array of (data_ptr, vtable_ptr) pairs.
    // Sum all areas regardless of concrete type.
    sub     sp, sp, #32

    // trait object 0: square
    adr     x0, square_data
    str     x0, [sp, #0]
    adr     x0, vtable_square
    str     x0, [sp, #8]

    // trait object 1: rect
    adr     x0, rect_data
    str     x0, [sp, #16]
    adr     x0, vtable_rect
    str     x0, [sp, #24]

    // Sum areas: iterate over trait objects
    mov     w4, #0                  // total = 0
    mov     w5, #0                  // i = 0
.Lpoly_loop:
    cmp     w5, #2
    b.ge    .Lpoly_done

    // Load trait object[i]
    lsl     w6, w5, #4             // i * 16 (size of pair)
    add     x7, sp, x6
    ldr     x0, [x7, #0]          // data_ptr
    ldr     x1, [x7, #8]          // vtable_ptr
    ldr     x2, [x1, #0]          // slot 0 = area
    blr     x2                      // call area()
    add     w4, w4, w0             // total += area

    add     w5, w5, #1
    b       .Lpoly_loop

.Lpoly_done:
    add     sp, sp, #32
    cmp     w4, #49                 // 25 + 24 = 49
    b.ne    fail

    // ── Test 8: vtable slot validation ──────────────────────────────
    // Verify that both vtables have non-null function pointers.
    adr     x0, vtable_square
    ldr     x1, [x0, #0]
    cbz     x1, fail
    ldr     x1, [x0, #8]
    cbz     x1, fail

    adr     x0, vtable_rect
    ldr     x1, [x0, #0]
    cbz     x1, fail
    ldr     x1, [x0, #8]
    cbz     x1, fail

    // ── Test 9: same interface, different perimeters ────────────────
    // Both shapes have perimeter 20 but different implementations.
    adr     x0, square_data
    adr     x1, vtable_square
    mov     w2, #1                  // slot 1 = perimeter
    bl      trait_call
    mov     w4, w0                  // save square perimeter

    adr     x0, rect_data
    adr     x1, vtable_rect
    mov     w2, #1
    bl      trait_call
    cmp     w0, w4                  // both are 20
    b.ne    fail

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

// ── trait_call(x0=data_ptr, x1=vtable_ptr, w2=slot) -> w0 ──────────
// Generic vtable dispatch: load function from vtable[slot] and call.
trait_call:
    stp     x29, x30, [sp, #-16]!
    ldr     x3, [x1, x2, lsl #3]  // vtable[slot]
    blr     x3                      // call with x0 = data_ptr
    ldp     x29, x30, [sp], #16
    ret

// ── Square methods ──────────────────────────────────────────────────
// x0 = pointer to square_data (word: side)

square_area:
    ldr     w1, [x0]               // side
    mul     w0, w1, w1             // side * side
    ret

square_perimeter:
    ldr     w1, [x0]               // side
    lsl     w0, w1, #2             // side * 4
    ret

// ── Rectangle methods ───────────────────────────────────────────────
// x0 = pointer to rect_data (word: width, word: height)

rect_area:
    ldr     w1, [x0, #0]          // width
    ldr     w2, [x0, #4]          // height
    mul     w0, w1, w2             // width * height
    ret

rect_perimeter:
    ldr     w1, [x0, #0]          // width
    ldr     w2, [x0, #4]          // height
    add     w0, w1, w2             // width + height
    lsl     w0, w0, #1             // * 2
    ret
