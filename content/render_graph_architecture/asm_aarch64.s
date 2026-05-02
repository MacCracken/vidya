// Vidya — Render Graph Architecture in AArch64 Assembly
//
// Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.

.global _start

.equ PASS_CAP, 16

.bss
.align 8
pass_id:      .skip 8 * PASS_CAP
reads_arr:    .skip 8 * PASS_CAP
writes_arr:   .skip 8 * PASS_CAP
topo_order:   .skip 8 * PASS_CAP
in_degree:    .skip 8 * PASS_CAP

.data
.align 8
pass_count:   .quad 0
topo_len:     .quad 0

.section .rodata
msg_pass:     .ascii "render_graph_architecture: 14/14 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

graph_init:
    mov     x0, #0
    adrp    x1, pass_id
    add     x1, x1, :lo12:pass_id
    mov     x2, #PASS_CAP
.gi1:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .gi1
    adrp    x1, reads_arr
    add     x1, x1, :lo12:reads_arr
    mov     x2, #PASS_CAP
.gi2:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .gi2
    adrp    x1, writes_arr
    add     x1, x1, :lo12:writes_arr
    mov     x2, #PASS_CAP
.gi3:
    str     x0, [x1], #8
    subs    x2, x2, #1
    b.ne    .gi3
    adrp    x1, pass_count
    add     x1, x1, :lo12:pass_count
    str     x0, [x1]
    adrp    x1, topo_len
    add     x1, x1, :lo12:topo_len
    str     x0, [x1]
    ret

// add_pass(x0=id, x1=r, x2=w) -> x0
add_pass:
    adrp    x3, pass_count
    add     x3, x3, :lo12:pass_count
    ldr     x4, [x3]
    cmp     x4, #PASS_CAP
    b.ge    .ap_full
    add     x5, x4, #1
    str     x5, [x3]
    adrp    x5, pass_id
    add     x5, x5, :lo12:pass_id
    str     x0, [x5, x4, lsl #3]
    adrp    x5, reads_arr
    add     x5, x5, :lo12:reads_arr
    str     x1, [x5, x4, lsl #3]
    adrp    x5, writes_arr
    add     x5, x5, :lo12:writes_arr
    str     x2, [x5, x4, lsl #3]
    mov     x0, x4
    ret
.ap_full:
    mov     x0, #-1
    ret

// has_edge(x0=p, x1=c) -> x0
has_edge:
    adrp    x2, writes_arr
    add     x2, x2, :lo12:writes_arr
    ldr     x2, [x2, x0, lsl #3]
    adrp    x3, reads_arr
    add     x3, x3, :lo12:reads_arr
    ldr     x3, [x3, x1, lsl #3]
    and     x0, x2, x3
    cbz     x0, .he_zero
    mov     x0, #1
    ret
.he_zero:
    mov     x0, #0
    ret

// topo_sort -> x0 = topo_len
topo_sort:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    // Zero in_degree
    adrp    x0, in_degree
    add     x0, x0, :lo12:in_degree
    mov     x1, #PASS_CAP
    mov     x2, #0
.ts_z:
    str     x2, [x0], #8
    subs    x1, x1, #1
    b.ne    .ts_z
    // Get count
    adrp    x0, pass_count
    add     x0, x0, :lo12:pass_count
    ldr     x19, [x0]                 // count (callee-saved)
    mov     x20, #0                   // i
.ts_i:
    cmp     x20, x19
    b.ge    .ts_kahn_init
    mov     x21, #0                   // j
.ts_j:
    cmp     x21, x19
    b.ge    .ts_i_next
    cmp     x20, x21
    b.eq    .ts_j_next
    mov     x0, x21
    mov     x1, x20
    bl      has_edge
    cbz     x0, .ts_j_next
    adrp    x2, in_degree
    add     x2, x2, :lo12:in_degree
    ldr     x3, [x2, x20, lsl #3]
    add     x3, x3, #1
    str     x3, [x2, x20, lsl #3]
.ts_j_next:
    add     x21, x21, #1
    b       .ts_j
.ts_i_next:
    add     x20, x20, #1
    b       .ts_i

.ts_kahn_init:
    adrp    x0, topo_len
    add     x0, x0, :lo12:topo_len
    mov     x1, #0
    str     x1, [x0]
    mov     x22, #0                   // emitted
.ts_kahn:
    cmp     x22, x19
    b.ge    .ts_done
    mov     x23, #-1                  // picked
    mov     x20, #0                   // k
.ts_pick:
    cmp     x20, x19
    b.ge    .ts_pick_done
    adrp    x2, in_degree
    add     x2, x2, :lo12:in_degree
    ldr     x3, [x2, x20, lsl #3]
    cbnz    x3, .ts_pick_next
    mov     x23, x20
    b       .ts_pick_done
.ts_pick_next:
    add     x20, x20, #1
    b       .ts_pick
.ts_pick_done:
    cmp     x23, #0
    b.lt    .ts_done
    // Emit picked
    adrp    x0, topo_len
    add     x0, x0, :lo12:topo_len
    ldr     x1, [x0]
    adrp    x2, topo_order
    add     x2, x2, :lo12:topo_order
    str     x23, [x2, x1, lsl #3]
    add     x1, x1, #1
    str     x1, [x0]
    // Mark emitted as -1
    adrp    x2, in_degree
    add     x2, x2, :lo12:in_degree
    mov     x3, #-1
    str     x3, [x2, x23, lsl #3]
    // Decrement consumers
    mov     x20, #0                   // c
.ts_dec:
    cmp     x20, x19
    b.ge    .ts_dec_done
    cmp     x20, x23
    b.eq    .ts_dec_next
    mov     x0, x23
    mov     x1, x20
    bl      has_edge
    cbz     x0, .ts_dec_next
    adrp    x2, in_degree
    add     x2, x2, :lo12:in_degree
    ldr     x3, [x2, x20, lsl #3]
    cmp     x3, #0
    b.le    .ts_dec_next
    sub     x3, x3, #1
    str     x3, [x2, x20, lsl #3]
.ts_dec_next:
    add     x20, x20, #1
    b       .ts_dec
.ts_dec_done:
    add     x22, x22, #1
    b       .ts_kahn
.ts_done:
    adrp    x0, topo_len
    add     x0, x0, :lo12:topo_len
    ldr     x0, [x0]
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// barrier_count -> x0
barrier_count:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    adrp    x0, topo_len
    add     x0, x0, :lo12:topo_len
    ldr     x19, [x0]                 // topo_len
    mov     x20, #0                   // count
    mov     x21, #0                   // i
.bc_i:
    cmp     x21, x19
    b.ge    .bc_done
    add     x22, x21, #1              // j
.bc_j:
    cmp     x22, x19
    b.ge    .bc_i_next
    adrp    x0, topo_order
    add     x0, x0, :lo12:topo_order
    ldr     x1, [x0, x22, lsl #3]
    ldr     x0, [x0, x21, lsl #3]
    bl      has_edge
    cbz     x0, .bc_j_next
    add     x20, x20, #1
.bc_j_next:
    add     x22, x22, #1
    b       .bc_j
.bc_i_next:
    add     x21, x21, #1
    b       .bc_i
.bc_done:
    mov     x0, x20
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// cull_dead -> x0
cull_dead:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    adrp    x0, pass_count
    add     x0, x0, :lo12:pass_count
    ldr     x19, [x0]                 // count
    mov     x20, #0                   // culled
    mov     x21, #0                   // i
.cd_i:
    cmp     x21, x19
    b.ge    .cd_done
    adrp    x0, writes_arr
    add     x0, x0, :lo12:writes_arr
    ldr     x22, [x0, x21, lsl #3]    // w
    cbz     x22, .cd_i_next
    mov     x23, #0                   // any_reader
    mov     x24, #0                   // j
.cd_j:
    cmp     x24, x19
    b.ge    .cd_j_done
    cmp     x24, x21
    b.eq    .cd_j_next
    adrp    x0, reads_arr
    add     x0, x0, :lo12:reads_arr
    ldr     x1, [x0, x24, lsl #3]
    and     x1, x1, x22
    cbz     x1, .cd_j_next
    mov     x23, #1
    b       .cd_j_done
.cd_j_next:
    add     x24, x24, #1
    b       .cd_j
.cd_j_done:
    cbnz    x23, .cd_i_next
    adrp    x0, writes_arr
    add     x0, x0, :lo12:writes_arr
    mov     x1, #0
    str     x1, [x0, x21, lsl #3]
    adrp    x0, reads_arr
    add     x0, x0, :lo12:reads_arr
    str     x1, [x0, x21, lsl #3]
    add     x20, x20, #1
.cd_i_next:
    add     x21, x21, #1
    b       .cd_i
.cd_done:
    mov     x0, x20
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

assert_eq:
    cmp     x0, x1
    b.ne    fail_exit
    ret

fail_exit:
    mov     x0, #1
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0

_start:
    bl      graph_init

    mov     x0, #100
    mov     x1, #0
    mov     x2, #1
    bl      add_pass
    mov     x1, #0
    bl      assert_eq

    mov     x0, #101
    mov     x1, #1
    mov     x2, #2
    bl      add_pass
    mov     x1, #1
    bl      assert_eq

    mov     x0, #102
    mov     x1, #2
    mov     x2, #0
    bl      add_pass
    mov     x1, #2
    bl      assert_eq

    bl      topo_sort
    mov     x1, #3
    bl      assert_eq
    adrp    x0, topo_order
    add     x0, x0, :lo12:topo_order
    ldr     x0, [x0]
    mov     x1, #0
    bl      assert_eq
    adrp    x0, topo_order
    add     x0, x0, :lo12:topo_order
    ldr     x0, [x0, #8]
    mov     x1, #1
    bl      assert_eq
    adrp    x0, topo_order
    add     x0, x0, :lo12:topo_order
    ldr     x0, [x0, #16]
    mov     x1, #2
    bl      assert_eq

    bl      barrier_count
    mov     x1, #2
    bl      assert_eq

    mov     x0, #103
    mov     x1, #0
    mov     x2, #4
    bl      add_pass
    mov     x1, #3
    bl      assert_eq
    bl      cull_dead
    mov     x1, #1
    bl      assert_eq
    adrp    x0, writes_arr
    add     x0, x0, :lo12:writes_arr
    ldr     x0, [x0, #24]
    mov     x1, #0
    bl      assert_eq

    bl      topo_sort
    mov     x1, #4
    bl      assert_eq
    bl      barrier_count
    mov     x1, #2
    bl      assert_eq

    bl      graph_init
    mov     x0, #200
    mov     x1, #1
    mov     x2, #2
    bl      add_pass
    mov     x0, #201
    mov     x1, #2
    mov     x2, #1
    bl      add_pass
    bl      topo_sort
    mov     x1, #0
    bl      assert_eq

    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
