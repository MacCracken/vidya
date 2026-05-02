// Vidya — 2D Collision Detection in AArch64 Assembly
//
// All coordinates in 16.16 fixed-point on x-registers (64-bit). The
// Cyrius reference pre-shifts deltas by 4 (ASR #4) so a squared
// distance fits in i64; for full 128-bit precision the AArch64 trick
// is `MUL` (low 64) + `SMULH` (high 64), but this test set keeps
// coordinates small and uses the >>4 form.
//
// Any subroutine that calls `bl` must save x29 (FP) + x30 (LR) in
// the prologue or the inner call clobbers our return address.
// Constants > 16 bits use the assembler's `ldr xN, =literal` form
// which materialises any 64-bit value via the literal pool.

.global _start

.section .rodata
msg_pass:    .ascii "All collision_detection_2d examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// dist_sq: x0=x1, x1=y1, x2=x2, x3=y2 -> x0 = (dx>>4)^2 + (dy>>4)^2
dist_sq:
    sub     x4, x2, x0          // dx
    asr     x4, x4, #4
    sub     x5, x3, x1          // dy
    asr     x5, x5, #4
    mul     x4, x4, x4          // dx*dx
    mul     x5, x5, x5          // dy*dy
    add     x0, x4, x5
    ret

// circle_circle: x0=x1, x1=y1, x2=r1, x3=x2, x4=y2, x5=r2 -> x0 = bool
circle_circle:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x2, [sp, #16]       // save r1
    str     x5, [sp, #24]       // save r2
    // Reorder for dist_sq(x1,y1, x2,y2): need x0,x1,x2,x3
    mov     x6, x3              // x2
    mov     x7, x4              // y2
    mov     x2, x6
    mov     x3, x7
    bl      dist_sq             // x0 = d2
    ldr     x6, [sp, #16]       // r1
    ldr     x7, [sp, #24]       // r2
    add     x6, x6, x7
    asr     x6, x6, #4          // sum_r >> 4
    mul     x6, x6, x6
    cmp     x0, x6
    cset    x0, le              // d2 <= sum_r^2 -> 1
    ldp     x29, x30, [sp], #32
    ret

// aabb_overlap: x0=l1, x1=t1, x2=r1, x3=b1, x4=l2, x5=t2, x6=r2, x7=b2
aabb_overlap:
    cmp     x0, x6              // l1 >= r2 -> no
    b.ge    .Laabb_no
    cmp     x2, x4              // r1 <= l2 -> no
    b.le    .Laabb_no
    cmp     x1, x7              // t1 >= b2 -> no
    b.ge    .Laabb_no
    cmp     x3, x5              // b1 <= t2 -> no
    b.le    .Laabb_no
    mov     x0, #1
    ret
.Laabb_no:
    mov     x0, #0
    ret

// point_in_rect: x0=px, x1=py, x2=left, x3=top, x4=right, x5=bottom -> x0
point_in_rect:
    cmp     x0, x2              // px < left -> out
    b.lt    .Lpir_no
    cmp     x0, x4              // px >= right -> out
    b.ge    .Lpir_no
    cmp     x1, x3              // py < top -> out
    b.lt    .Lpir_no
    cmp     x1, x5              // py >= bottom -> out
    b.ge    .Lpir_no
    mov     x0, #1
    ret
.Lpir_no:
    mov     x0, #0
    ret

// _start: run all tests
_start:
    // -------- Test 1: circle_circle overlapping ---------
    // (10,10) r=5 vs (13,10) r=5  -> 1
    ldr     x0, =655360         // 10.0
    ldr     x1, =655360         // 10.0
    ldr     x2, =327680         // r=5.0
    ldr     x3, =851968         // 13.0
    ldr     x4, =655360         // 10.0
    ldr     x5, =327680         // r=5.0
    bl      circle_circle
    cmp     x0, #1
    b.ne    fail

    // -------- Test 2: distant circles ---------
    // (0,0) r=1 vs (100,100) r=1  -> 0
    mov     x0, #0
    mov     x1, #0
    ldr     x2, =65536          // r=1.0
    ldr     x3, =6553600        // 100.0
    ldr     x4, =6553600        // 100.0
    ldr     x5, =65536
    bl      circle_circle
    cmp     x0, #0
    b.ne    fail

    // -------- Test 3: touching circles ---------
    // (0,0) r=5 vs (10,0) r=5  -> 1
    mov     x0, #0
    mov     x1, #0
    ldr     x2, =327680         // r=5.0
    ldr     x3, =655360         // 10.0
    mov     x4, #0
    ldr     x5, =327680
    bl      circle_circle
    cmp     x0, #1
    b.ne    fail

    // -------- Test 4: AABB overlap ---------
    // A(0,0)-(10,10) vs B(5,5)-(15,15) -> 1
    mov     x0, #0
    mov     x1, #0
    ldr     x2, =655360         // r1=10
    ldr     x3, =655360         // b1=10
    ldr     x4, =327680         // l2=5
    ldr     x5, =327680         // t2=5
    ldr     x6, =983040         // r2=15
    ldr     x7, =983040         // b2=15
    bl      aabb_overlap
    cmp     x0, #1
    b.ne    fail

    // -------- Test 5: AABB no overlap ---------
    // A(0,0)-(5,5) vs B(10,10)-(20,20) -> 0
    mov     x0, #0
    mov     x1, #0
    ldr     x2, =327680         // r1=5
    ldr     x3, =327680         // b1=5
    ldr     x4, =655360         // l2=10
    ldr     x5, =655360         // t2=10
    ldr     x6, =1310720        // r2=20
    ldr     x7, =1310720        // b2=20
    bl      aabb_overlap
    cmp     x0, #0
    b.ne    fail

    // -------- Test 6: AABB edge-adjacent (Cyrius: 0) ---------
    // A(0,0)-(10,10) vs B(10,0)-(20,10) -> 0 (touching, not overlapping)
    mov     x0, #0
    mov     x1, #0
    ldr     x2, =655360         // r1=10
    ldr     x3, =655360         // b1=10
    ldr     x4, =655360         // l2=10
    mov     x5, #0              // t2=0
    ldr     x6, =1310720        // r2=20
    ldr     x7, =655360         // b2=10
    bl      aabb_overlap
    cmp     x0, #0
    b.ne    fail

    // -------- Test 7: point inside rect ---------
    ldr     x0, =327680         // px=5
    ldr     x1, =327680         // py=5
    mov     x2, #0              // left
    mov     x3, #0              // top
    ldr     x4, =655360         // right=10
    ldr     x5, =655360         // bottom=10
    bl      point_in_rect
    cmp     x0, #1
    b.ne    fail

    // -------- Test 8: point outside rect ---------
    ldr     x0, =983040         // px=15
    ldr     x1, =327680         // py=5
    mov     x2, #0
    mov     x3, #0
    ldr     x4, =655360
    ldr     x5, =655360
    bl      point_in_rect
    cmp     x0, #0
    b.ne    fail

    // -------- Test 9: left edge inclusive ---------
    mov     x0, #0              // px=0 (left edge)
    ldr     x1, =327680         // py=5
    mov     x2, #0
    mov     x3, #0
    ldr     x4, =655360
    ldr     x5, =655360
    bl      point_in_rect
    cmp     x0, #1
    b.ne    fail

    // -------- Test 10: right edge exclusive ---------
    ldr     x0, =655360         // px=10 (right edge)
    ldr     x1, =327680         // py=5
    mov     x2, #0
    mov     x3, #0
    ldr     x4, =655360
    ldr     x5, =655360
    bl      point_in_rect
    cmp     x0, #0
    b.ne    fail

    // -------- Test 11: dist_sq positive for 3-4-5 ---------
    mov     x0, #0
    mov     x1, #0
    ldr     x2, =196608         // 3.0
    ldr     x3, =262144         // 4.0
    bl      dist_sq
    cmp     x0, #0
    b.le    fail

    // -------- All passed --------
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #2
    adr     x1, msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
