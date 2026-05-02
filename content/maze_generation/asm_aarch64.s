// Vidya — Maze Generation in AArch64 Assembly
//
// Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell is a
// byte holding a wall bitmask (N=1, S=2, E=4, W=8). Generation carves
// passages by clearing the wall bit on both the current and the
// neighbour cell.
//
// AArch64 has no implicit overflow trap on `MUL`/`ADD` — multiplying
// two x-registers gives the low 64 bits, exactly the mod-2^64 wrap PCG
// requires. Constants larger than a 16-bit immediate (PCG_MULT,
// PCG_INC, GN-related literals beyond 4096) are loaded via the
// assembler literal pool: `ldr xN, =literal`. Functions calling `bl`
// MUST save x29 (FP) and x30 (LR) — the inner branch-link clobbers LR.

.global _start

.equ GW, 8
.equ GH, 8
.equ GN, 64

.equ WN, 1
.equ WS, 2
.equ WE, 4
.equ WW, 8
.equ WALLS_ALL, 15

.section .data
.align 3
rng_state:  .quad 12345

.section .bss
.align 3
maze_cells: .skip GN
visited:    .skip GN
dfs_stack:  .skip GN * 8
nbuf:       .skip 4 * 24
g_c0:       .skip 8
g_c27:      .skip 8
g_c63:      .skip 8
g_sum1:     .skip 8
g_sum2:     .skip 8

.section .rodata
msg_pass:    .ascii "All maze_generation examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// rng_seed: x0 = new state
rng_seed:
    adrp    x9, rng_state
    add     x9, x9, :lo12:rng_state
    str     x0, [x9]
    ret

// rng_next: x0 = next pseudo-random value (non-negative, 31 bits).
// MUL on x-regs gives low 64 bits — that *is* the modular step.
rng_next:
    adrp    x9, rng_state
    add     x9, x9, :lo12:rng_state
    ldr     x10, [x9]
    ldr     x11, =6364136223846793005
    mul     x10, x10, x11
    ldr     x11, =1442695040888963407
    add     x10, x10, x11
    str     x10, [x9]
    lsr     x10, x10, #33
    ldr     x11, =2147483647
    and     x0, x10, x11
    ret

// rng_range: x0 = max ; returns x0 in [0, max). Uses udiv+msub.
rng_range:
    cmp     x0, #0
    b.le    .Lrr_zero
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    bl      rng_next
    udiv    x10, x0, x19
    msub    x0, x10, x19, x0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lrr_zero:
    mov     x0, #0
    ret

// idx: x0=x, x1=y -> x0 = y*GW + x
idx:
    lsl     x9, x1, #3        // y << 3 = y * GW
    add     x0, x9, x0
    ret

// opposite_dir: x0=d -> x0 = opposite
opposite_dir:
    cmp     x0, #WN
    b.eq    .Lopp_s
    cmp     x0, #WS
    b.eq    .Lopp_n
    cmp     x0, #WE
    b.eq    .Lopp_w
    cmp     x0, #WW
    b.eq    .Lopp_e
    mov     x0, #0
    ret
.Lopp_s: mov x0, #WS; ret
.Lopp_n: mov x0, #WN; ret
.Lopp_w: mov x0, #WW; ret
.Lopp_e: mov x0, #WE; ret

// maze_init: fill cells with WALLS_ALL, visited with 0
maze_init:
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    adrp    x10, visited
    add     x10, x10, :lo12:visited
    mov     x11, #0
    mov     w12, #WALLS_ALL
.Lmi_loop:
    cmp     x11, #GN
    b.ge    .Lmi_done
    strb    w12, [x9, x11]
    strb    wzr, [x10, x11]
    add     x11, x11, #1
    b       .Lmi_loop
.Lmi_done:
    ret

// carve: x0=x, x1=y, x2=d, x3=nx, x4=ny
// Clears the wall bit on both cells. Without both edits the maze
// would have an asymmetric wall and fail the consistency check.
carve:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    str     x25, [sp, #64]

    mov     x19, x2           // d
    mov     x20, x3           // nx
    mov     x21, x4           // ny
    mov     x22, x0           // x
    mov     x23, x1           // y

    // ci = idx(x, y) — keep ci in a callee-saved reg across the
    // following bl idx / bl opposite_dir which both clobber x9.
    mov     x0, x22
    mov     x1, x23
    bl      idx
    mov     x24, x0           // ci

    // ni = idx(nx, ny)
    mov     x0, x20
    mov     x1, x21
    bl      idx
    mov     x25, x0           // ni

    // od = opposite(d)
    mov     x0, x19
    bl      opposite_dir      // x0 = od

    // cells[ci] &= ~d
    adrp    x11, maze_cells
    add     x11, x11, :lo12:maze_cells
    ldrb    w12, [x11, x24]
    mvn     w13, w19          // ~d (32-bit)
    and     w12, w12, w13
    strb    w12, [x11, x24]

    // cells[ni] &= ~od
    ldrb    w12, [x11, x25]
    mvn     w13, w0           // ~od
    and     w12, w12, w13
    strb    w12, [x11, x25]

    ldr     x25, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// collect_unvisited: x0=x, x1=y -> x0 = count
// Writes (dir, nx, ny) triples into nbuf, 24 bytes each.
collect_unvisited:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0           // x
    mov     x20, x1           // y
    mov     x21, #0           // n = 0
    adrp    x22, nbuf
    add     x22, x22, :lo12:nbuf
    adrp    x23, visited
    add     x23, x23, :lo12:visited

    // north: y > 0
    cmp     x20, #0
    b.le    .Lcu_no_n
    mov     x0, x19
    sub     x1, x20, #1
    bl      idx
    ldrb    w24, [x23, x0]
    cbnz    w24, .Lcu_no_n
    mov     x10, #24
    mul     x10, x21, x10
    mov     x11, #WN
    str     x11, [x22, x10]
    add     x12, x10, #8
    str     x19, [x22, x12]
    sub     x11, x20, #1
    add     x12, x10, #16
    str     x11, [x22, x12]
    add     x21, x21, #1
.Lcu_no_n:

    // south: y < GH-1
    cmp     x20, #GH-1
    b.ge    .Lcu_no_s
    mov     x0, x19
    add     x1, x20, #1
    bl      idx
    ldrb    w24, [x23, x0]
    cbnz    w24, .Lcu_no_s
    mov     x10, #24
    mul     x10, x21, x10
    mov     x11, #WS
    str     x11, [x22, x10]
    add     x12, x10, #8
    str     x19, [x22, x12]
    add     x11, x20, #1
    add     x12, x10, #16
    str     x11, [x22, x12]
    add     x21, x21, #1
.Lcu_no_s:

    // west: x > 0
    cmp     x19, #0
    b.le    .Lcu_no_w
    sub     x0, x19, #1
    mov     x1, x20
    bl      idx
    ldrb    w24, [x23, x0]
    cbnz    w24, .Lcu_no_w
    mov     x10, #24
    mul     x10, x21, x10
    mov     x11, #WW
    str     x11, [x22, x10]
    sub     x11, x19, #1
    add     x12, x10, #8
    str     x11, [x22, x12]
    add     x12, x10, #16
    str     x20, [x22, x12]
    add     x21, x21, #1
.Lcu_no_w:

    // east: x < GW-1
    cmp     x19, #GW-1
    b.ge    .Lcu_no_e
    add     x0, x19, #1
    mov     x1, x20
    bl      idx
    ldrb    w24, [x23, x0]
    cbnz    w24, .Lcu_no_e
    mov     x10, #24
    mul     x10, x21, x10
    mov     x11, #WE
    str     x11, [x22, x10]
    add     x11, x19, #1
    add     x12, x10, #8
    str     x11, [x22, x12]
    add     x12, x10, #16
    str     x20, [x22, x12]
    add     x21, x21, #1
.Lcu_no_e:

    mov     x0, x21
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// maze_generate: x0=sx, x1=sy
maze_generate:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0           // save sx
    mov     x20, x1           // save sy

    bl      maze_init

    // start = idx(sx, sy)
    mov     x0, x19
    mov     x1, x20
    bl      idx
    mov     x21, x0           // start

    // dfs_stack[0] = start
    adrp    x22, dfs_stack
    add     x22, x22, :lo12:dfs_stack
    str     x21, [x22]
    mov     x23, #1           // sp = 1

    // visited[start] = 1
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    mov     w10, #1
    strb    w10, [x9, x21]

.Lmg_loop:
    cbz     x23, .Lmg_done

    // top = dfs_stack[sp-1]; tx = top & 7; ty = top >> 3
    sub     x9, x23, #1
    ldr     x10, [x22, x9, lsl #3]
    and     x19, x10, #7        // tx (reuse x19 — sx no longer needed)
    lsr     x20, x10, #3        // ty (reuse x20 — sy no longer needed)

    // collect_unvisited(tx, ty)
    mov     x0, x19
    mov     x1, x20
    bl      collect_unvisited
    cbz     x0, .Lmg_back

    // pick = rng_range(k)
    bl      rng_range
    // pick = x0; load nbuf entry
    mov     x9, #24
    mul     x9, x0, x9
    adrp    x10, nbuf
    add     x10, x10, :lo12:nbuf
    ldr     x24, [x10, x9]                 // d (callee-saved)
    add     x11, x9, #8
    ldr     x12, [x10, x11]                // nx
    add     x11, x9, #16
    ldr     x13, [x10, x11]                // ny

    // x12 (nx) and x13 (ny) are caller-saved — push them in a fresh
    // 16-byte frame so `bl carve` and `bl idx` can't clobber them.
    stp     x12, x13, [sp, #-16]!
    // carve(tx, ty, d, nx, ny)
    mov     x0, x19            // tx
    mov     x1, x20            // ty
    mov     x2, x24            // d
    mov     x3, x12            // nx
    mov     x4, x13            // ny
    bl      carve
    ldp     x12, x13, [sp], #16

    // ni = idx(nx, ny)
    mov     x0, x12
    mov     x1, x13
    bl      idx
    mov     x10, x0            // ni

    // visited[ni] = 1
    adrp    x11, visited
    add     x11, x11, :lo12:visited
    mov     w12, #1
    strb    w12, [x11, x10]

    // dfs_stack[sp] = ni; sp++
    str     x10, [x22, x23, lsl #3]
    add     x23, x23, #1
    b       .Lmg_loop
.Lmg_back:
    sub     x23, x23, #1
    b       .Lmg_loop

.Lmg_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// count_visited: x0 = count
count_visited:
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    mov     x10, #0
    mov     x11, #0
.Lcv_loop:
    cmp     x11, #GN
    b.ge    .Lcv_done
    ldrb    w12, [x9, x11]
    cbz     w12, .Lcv_skip
    add     x10, x10, #1
.Lcv_skip:
    add     x11, x11, #1
    b       .Lcv_loop
.Lcv_done:
    mov     x0, x10
    ret

// count_removed_walls: x0 = count
count_removed_walls:
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    mov     x10, #0           // removed
    mov     x11, #0           // y
.Lcr_y:
    cmp     x11, #GH
    b.ge    .Lcr_done
    mov     x12, #0           // x
.Lcr_x:
    cmp     x12, #GW
    b.ge    .Lcr_yend
    lsl     x13, x11, #3
    add     x13, x13, x12
    ldrb    w14, [x9, x13]
    // y > 0 and !(w & WN): removed++
    cbz     x11, .Lcr_no_n
    tst     w14, #WN
    b.ne    .Lcr_no_n
    add     x10, x10, #1
.Lcr_no_n:
    // x > 0 and !(w & WW): removed++
    cbz     x12, .Lcr_no_w
    tst     w14, #WW
    b.ne    .Lcr_no_w
    add     x10, x10, #1
.Lcr_no_w:
    add     x12, x12, #1
    b       .Lcr_x
.Lcr_yend:
    add     x11, x11, #1
    b       .Lcr_y
.Lcr_done:
    mov     x0, x10
    ret

// walls_consistent: x0 = 1 if OK, 0 otherwise
walls_consistent:
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    mov     x11, #0           // y
.Lwc_y:
    cmp     x11, #GH
    b.ge    .Lwc_ok
    mov     x12, #0           // x
.Lwc_x:
    cmp     x12, #GW
    b.ge    .Lwc_yend
    lsl     x13, x11, #3
    add     x13, x13, x12
    ldrb    w14, [x9, x13]
    // east neighbour
    cmp     x12, #GW-1
    b.ge    .Lwc_skip_e
    add     x15, x13, #1
    ldrb    w16, [x9, x15]
    // east_open = (w & WE) == 0
    and     w17, w14, #WE
    cmp     w17, #0
    cset    w17, eq           // 1 if east open
    and     w0, w16, #WW
    cmp     w0, #0
    cset    w0, eq            // 1 if neighbour west open
    cmp     w17, w0
    b.ne    .Lwc_fail
.Lwc_skip_e:
    cmp     x11, #GH-1
    b.ge    .Lwc_skip_s
    add     x15, x13, #GW
    ldrb    w16, [x9, x15]
    and     w17, w14, #WS
    cmp     w17, #0
    cset    w17, eq
    and     w0, w16, #WN
    cmp     w0, #0
    cset    w0, eq
    cmp     w17, w0
    b.ne    .Lwc_fail
.Lwc_skip_s:
    add     x12, x12, #1
    b       .Lwc_x
.Lwc_yend:
    add     x11, x11, #1
    b       .Lwc_y
.Lwc_ok:
    mov     x0, #1
    ret
.Lwc_fail:
    mov     x0, #0
    ret

// expect_eq: x0=actual, x1=expected ; branches to fail on mismatch
expect_eq:
    cmp     x0, x1
    b.ne    fail
    ret

_start:
    // --- Test 1: init state ---
    bl      maze_init
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9]
    mov     x1, #WALLS_ALL
    bl      expect_eq
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9, #63]
    mov     x1, #WALLS_ALL
    bl      expect_eq
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    ldrb    w0, [x9]
    mov     x1, #0
    bl      expect_eq

    // --- Test 2: full coverage ---
    mov     x0, #42
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    bl      count_visited
    mov     x1, #GN
    bl      expect_eq

    // --- Test 3: perfect maze removes GN-1 walls ---
    mov     x0, #42
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    bl      count_removed_walls
    mov     x1, #GN-1
    bl      expect_eq

    // --- Test 4: wall consistency ---
    mov     x0, #42
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    bl      walls_consistent
    mov     x1, #1
    bl      expect_eq

    // --- Test 5: determinism ---
    mov     x0, #42
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w10, [x9]
    adrp    x11, g_c0
    add     x11, x11, :lo12:g_c0
    str     x10, [x11]
    ldrb    w10, [x9, #27]
    adrp    x11, g_c27
    add     x11, x11, :lo12:g_c27
    str     x10, [x11]
    ldrb    w10, [x9, #63]
    adrp    x11, g_c63
    add     x11, x11, :lo12:g_c63
    str     x10, [x11]

    mov     x0, #42
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9]
    adrp    x11, g_c0
    add     x11, x11, :lo12:g_c0
    ldr     x1, [x11]
    bl      expect_eq
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9, #27]
    adrp    x11, g_c27
    add     x11, x11, :lo12:g_c27
    ldr     x1, [x11]
    bl      expect_eq
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9, #63]
    adrp    x11, g_c63
    add     x11, x11, :lo12:g_c63
    ldr     x1, [x11]
    bl      expect_eq

    // --- Test 6: different seeds differ ---
    mov     x0, #1
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    mov     x10, #0
    mov     x11, #0
.Ls1:
    cmp     x11, #GN
    b.ge    .Ls1_done
    ldrb    w12, [x9, x11]
    add     x10, x10, x12
    add     x11, x11, #1
    b       .Ls1
.Ls1_done:
    adrp    x12, g_sum1
    add     x12, x12, :lo12:g_sum1
    str     x10, [x12]

    mov     x0, #2
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    mov     x10, #0
    mov     x11, #0
.Ls2:
    cmp     x11, #GN
    b.ge    .Ls2_done
    ldrb    w12, [x9, x11]
    add     x10, x10, x12
    add     x11, x11, #1
    b       .Ls2
.Ls2_done:
    adrp    x12, g_sum1
    add     x12, x12, :lo12:g_sum1
    ldr     x13, [x12]
    cmp     x10, x13
    b.eq    fail

    // --- Test 7: starting cell visited from (3,5) ---
    mov     x0, #42
    bl      rng_seed
    mov     x0, #3
    mov     x1, #5
    bl      maze_generate
    // idx(3,5) = 5*8+3 = 43
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    ldrb    w0, [x9, #43]
    mov     x1, #1
    bl      expect_eq
    bl      count_visited
    mov     x1, #GN
    bl      expect_eq

    // --- Cross-language byte parity ---
    mov     x0, #42
    bl      rng_seed
    mov     x0, #0
    mov     x1, #0
    bl      maze_generate
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9]
    mov     x1, #13
    bl      expect_eq
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9, #27]
    mov     x1, #12
    bl      expect_eq
    adrp    x9, maze_cells
    add     x9, x9, :lo12:maze_cells
    ldrb    w0, [x9, #63]
    mov     x1, #6
    bl      expect_eq

    // --- Done — write success and exit 0 ---
    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

fail:
    mov     x0, #2
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0
