// Vidya — Grid Pathfinding in AArch64 Assembly
//
// BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked). Static
// buffers in .bss back grid/visited/dist/queue/open_set/g_score/
// f_score — same layout as cyrius.cyr. The A* open set is a flat
// array; we linear-scan for the lowest f-score (a real heap is the
// right answer above ~512 cells; for 64 the scan is instant).
//
// Every function that calls `bl` saves x29/x30 in its prologue.
// Constants > 16 bits use `ldr xN, =literal` to handle any 64-bit
// immediate in one form. Manhattan distance is the heuristic.

.global _start

.equ GW, 8
.equ GH, 8
.equ GN, 64

.section .bss
.align 3
grid:       .skip 64
visited:    .skip 64
dist:       .skip 8 * 64
came_from:  .skip 8 * 64
queue:      .skip 8 * 64
open_set:   .skip 8 * 64
g_score:    .skip 8 * 64
f_score:    .skip 8 * 64

.section .rodata
msg_pass:    .ascii "All grid_pathfinding examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

// idx_real(x0=x, x1=y) -> x0 = y*GW + x  (GW=8 ⇒ y<<3)
idx_real:
    lsl     x2, x1, #3
    add     x0, x2, x0
    ret

// abs_i(x0) -> x0 = |x0|
abs_i:
    cmp     x0, #0
    b.ge    .Labs_done
    neg     x0, x0
.Labs_done:
    ret

// manhattan(x0=ax, x1=ay, x2=bx, x3=by) -> x0
// Uses x9..x12 as scratch; preserves no callee-saved registers.
manhattan:
    sub     x9, x0, x2          // dx
    cmp     x9, #0
    b.ge    .Lm_dx_pos
    neg     x9, x9
.Lm_dx_pos:
    sub     x10, x1, x3         // dy
    cmp     x10, #0
    b.ge    .Lm_dy_pos
    neg     x10, x10
.Lm_dy_pos:
    add     x0, x9, x10
    ret

// grid_clear: zero out grid + visited
grid_clear:
    adrp    x9, grid
    add     x9, x9, :lo12:grid
    mov     x10, #GN
.Lgc_loop:
    strb    wzr, [x9], #1
    sub     x10, x10, #1
    cbnz    x10, .Lgc_loop
    ret

// grid_block(x0=x, x1=y) — set grid[y*GW+x]=1
grid_block:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    bl      idx_real            // x0 = idx
    adrp    x9, grid
    add     x9, x9, :lo12:grid
    mov     w10, #1
    strb    w10, [x9, x0]
    ldp     x29, x30, [sp], #16
    ret

// init_visited: zero out visited[]
init_visited:
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    mov     x10, #GN
.Liv_loop:
    strb    wzr, [x9], #1
    sub     x10, x10, #1
    cbnz    x10, .Liv_loop
    ret

// init_dist_neg1: set dist[i] = -1 for i in 0..GN
init_dist_neg1:
    adrp    x9, dist
    add     x9, x9, :lo12:dist
    mov     x10, #GN
    mov     x11, #-1
.Lid_loop:
    str     x11, [x9], #8
    sub     x10, x10, #1
    cbnz    x10, .Lid_loop
    ret

// init_g_f_inf: set g_score[i] = f_score[i] = +INT64_MAX
init_g_f_inf:
    ldr     x11, =0x7FFFFFFFFFFFFFFF
    adrp    x9, g_score
    add     x9, x9, :lo12:g_score
    adrp    x10, f_score
    add     x10, x10, :lo12:f_score
    mov     x12, #GN
.Lif_loop:
    str     x11, [x9], #8
    str     x11, [x10], #8
    sub     x12, x12, #1
    cbnz    x12, .Lif_loop
    ret

// bfs(x0=start, x1=goal) -> x0 = path length, or -1
// Callee-saved usage: x19=start, x20=goal, x21=head, x22=tail, x23=curr.
bfs:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // start
    mov     x20, x1             // goal

    cmp     x19, x20
    b.ne    .Lbfs_init
    mov     x0, #0
    b       .Lbfs_done

.Lbfs_init:
    bl      init_visited
    bl      init_dist_neg1

    // queue[0] = start; head=0; tail=1
    adrp    x9, queue
    add     x9, x9, :lo12:queue
    str     x19, [x9]
    mov     x21, #0             // head
    mov     x22, #1             // tail

    // visited[start] = 1
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    mov     w10, #1
    strb    w10, [x9, x19]

    // dist[start] = 0
    adrp    x9, dist
    add     x9, x9, :lo12:dist
    str     xzr, [x9, x19, lsl #3]

.Lbfs_loop:
    cmp     x21, x22
    b.ge    .Lbfs_unreach

    // curr = queue[head++]
    adrp    x9, queue
    add     x9, x9, :lo12:queue
    ldr     x23, [x9, x21, lsl #3]
    add     x21, x21, #1

    cmp     x23, x20
    b.ne    .Lbfs_expand
    adrp    x9, dist
    add     x9, x9, :lo12:dist
    ldr     x0, [x9, x23, lsl #3]
    b       .Lbfs_done

.Lbfs_expand:
    // cx = curr & 7, cy = curr >> 3 — kept in callee-saved x24 for
    // re-use across bfs_relax calls (bfs_relax doesn't clobber x24).
    and     x24, x23, #7        // cx (kept)

    // up: cy > 0 ⇒ n = curr - GW
    lsr     x9, x23, #3         // cy
    cbz     x9, .Lbfs_no_up
    sub     x10, x23, #GW
    bl      bfs_relax
.Lbfs_no_up:
    // down: cy < GH-1 ⇒ n = curr + GW
    lsr     x9, x23, #3
    cmp     x9, #GH - 1
    b.ge    .Lbfs_no_down
    add     x10, x23, #GW
    bl      bfs_relax
.Lbfs_no_down:
    // left: cx > 0 ⇒ n = curr - 1
    cbz     x24, .Lbfs_no_left
    sub     x10, x23, #1
    bl      bfs_relax
.Lbfs_no_left:
    // right: cx < GW-1 ⇒ n = curr + 1
    cmp     x24, #GW - 1
    b.ge    .Lbfs_no_right
    add     x10, x23, #1
    bl      bfs_relax
.Lbfs_no_right:
    b       .Lbfs_loop

.Lbfs_unreach:
    mov     x0, #-1

.Lbfs_done:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// bfs_relax: x10=neighbor, x23=curr, x22=tail.
// If !visited[n] && grid[n]==0: visited[n]=1; dist[n]=dist[curr]+1;
// queue[tail++]=n. Uses x9,x11,x12 as scratch only.
bfs_relax:
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    ldrb    w11, [x9, x10]
    cbnz    w11, .Lbxr_done
    adrp    x9, grid
    add     x9, x9, :lo12:grid
    ldrb    w11, [x9, x10]
    cbnz    w11, .Lbxr_done
    // visited[n] = 1
    adrp    x9, visited
    add     x9, x9, :lo12:visited
    mov     w11, #1
    strb    w11, [x9, x10]
    // dist[n] = dist[curr] + 1
    adrp    x9, dist
    add     x9, x9, :lo12:dist
    ldr     x11, [x9, x23, lsl #3]
    add     x11, x11, #1
    str     x11, [x9, x10, lsl #3]
    // queue[tail++] = n
    adrp    x9, queue
    add     x9, x9, :lo12:queue
    str     x10, [x9, x22, lsl #3]
    add     x22, x22, #1
.Lbxr_done:
    ret

// astar(x0=sx, x1=sy, x2=gx, x3=gy) -> x0 = g_score[goal] or -1
// Callee-saved layout:
//   x19 = goal index
//   x20 = gx
//   x21 = gy
//   x22 = open_n
//   x23 = curr
//   x24 = tg (g_score[curr] + 1)
astar:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    // spill sx/sy into x25/x26 for re-use
    mov     x25, x0             // sx
    mov     x26, x1             // sy
    mov     x20, x2             // gx
    mov     x21, x3             // gy

    bl      init_visited
    bl      init_g_f_inf

    // start = idx(sx, sy)
    mov     x0, x25
    mov     x1, x26
    bl      idx_real
    mov     x4, x0              // x4 = start (caller-saved; we save it on the
                                // stack before the manhattan call below)

    // goal = idx(gx, gy)
    mov     x0, x20
    mov     x1, x21
    bl      idx_real
    mov     x19, x0             // goal

    // g_score[start] = 0
    adrp    x9, g_score
    add     x9, x9, :lo12:g_score
    str     xzr, [x9, x4, lsl #3]

    // f_score[start] = manhattan(sx, sy, gx, gy)
    // Save x4 (start) on the stack — manhattan will clobber x4 (caller-saved).
    str     x4, [sp, #-16]!     // push start
    mov     x0, x25
    mov     x1, x26
    mov     x2, x20
    mov     x3, x21
    bl      manhattan
    ldr     x4, [sp], #16       // pop start
    adrp    x9, f_score
    add     x9, x9, :lo12:f_score
    str     x0, [x9, x4, lsl #3]

    // open_set[0] = start; open_n = 1
    adrp    x9, open_set
    add     x9, x9, :lo12:open_set
    str     x4, [x9]
    mov     x22, #1             // open_n

.Lastar_loop:
    cbz     x22, .Lastar_unreach

    // Linear-scan for min-f. best_i in x9; best_f in x10.
    adrp    x11, open_set
    add     x11, x11, :lo12:open_set
    adrp    x12, f_score
    add     x12, x12, :lo12:f_score

    mov     x9, #0              // best_i
    ldr     x13, [x11]          // node = open_set[0]
    ldr     x10, [x12, x13, lsl #3]   // best_f

    mov     x14, #1             // k = 1
.Lscan_loop:
    cmp     x14, x22
    b.ge    .Lscan_done
    ldr     x13, [x11, x14, lsl #3]
    ldr     x15, [x12, x13, lsl #3]
    cmp     x15, x10
    b.ge    .Lscan_skip
    mov     x10, x15
    mov     x9, x14
.Lscan_skip:
    add     x14, x14, #1
    b       .Lscan_loop
.Lscan_done:
    // curr = open_set[best_i]
    ldr     x23, [x11, x9, lsl #3]

    // if curr == goal: return g_score[goal]
    cmp     x23, x19
    b.ne    .Lastar_pop
    adrp    x12, g_score
    add     x12, x12, :lo12:g_score
    ldr     x0, [x12, x19, lsl #3]
    b       .Lastar_done

.Lastar_pop:
    // open_set[best_i] = open_set[--open_n] (unless they're equal)
    sub     x22, x22, #1
    cmp     x9, x22
    b.eq    .Lastar_after_pop
    ldr     x15, [x11, x22, lsl #3]
    str     x15, [x11, x9, lsl #3]
.Lastar_after_pop:
    // closed[curr] = 1 (we use `visited` as the closed set)
    adrp    x12, visited
    add     x12, x12, :lo12:visited
    mov     w15, #1
    strb    w15, [x12, x23]

    // tg = g_score[curr] + 1
    adrp    x12, g_score
    add     x12, x12, :lo12:g_score
    ldr     x24, [x12, x23, lsl #3]
    add     x24, x24, #1

    // up: cy > 0
    lsr     x9, x23, #3
    cbz     x9, .La_no_up
    sub     x10, x23, #GW
    bl      astar_relax
.La_no_up:
    // down: cy < GH-1
    lsr     x9, x23, #3
    cmp     x9, #GH - 1
    b.ge    .La_no_down
    add     x10, x23, #GW
    bl      astar_relax
.La_no_down:
    // left: cx > 0
    and     x9, x23, #7
    cbz     x9, .La_no_left
    sub     x10, x23, #1
    bl      astar_relax
.La_no_left:
    // right: cx < GW-1
    and     x9, x23, #7
    cmp     x9, #GW - 1
    b.ge    .La_no_right
    add     x10, x23, #1
    bl      astar_relax
.La_no_right:
    b       .Lastar_loop

.Lastar_unreach:
    mov     x0, #-1

.Lastar_done:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret

// astar_relax: x10=n, x23=curr, x24=tg, x19=goal, x20=gx, x21=gy, x22=open_n.
// If !closed[n] && grid[n]==0 && tg < g_score[n]:
//   g_score[n] = tg
//   f_score[n] = tg + manhattan(n%GW, n/GW, gx, gy)
//   open_set[open_n++] = n
// Saves x29/x30 because it calls manhattan via `bl`.
astar_relax:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    adrp    x9, visited
    add     x9, x9, :lo12:visited
    ldrb    w11, [x9, x10]
    cbnz    w11, .Lar_done
    adrp    x9, grid
    add     x9, x9, :lo12:grid
    ldrb    w11, [x9, x10]
    cbnz    w11, .Lar_done
    adrp    x9, g_score
    add     x9, x9, :lo12:g_score
    ldr     x11, [x9, x10, lsl #3]
    cmp     x24, x11
    b.ge    .Lar_done

    // g_score[n] = tg
    str     x24, [x9, x10, lsl #3]

    // Save x10 (n) across manhattan call (manhattan only clobbers
    // x9..x12, plus x0..x3 — x10 is in that scratch range).
    str     x10, [sp, #16]

    // manhattan(nx, ny, gx, gy)  with nx = n & 7, ny = n >> 3
    and     x0, x10, #7         // nx
    lsr     x1, x10, #3         // ny
    mov     x2, x20             // gx
    mov     x3, x21             // gy
    bl      manhattan           // x0 = h

    ldr     x10, [sp, #16]      // restore n

    // f_score[n] = tg + h
    adrp    x9, f_score
    add     x9, x9, :lo12:f_score
    add     x11, x24, x0
    str     x11, [x9, x10, lsl #3]

    // open_set[open_n++] = n
    adrp    x9, open_set
    add     x9, x9, :lo12:open_set
    str     x10, [x9, x22, lsl #3]
    add     x22, x22, #1

.Lar_done:
    ldp     x29, x30, [sp], #32
    ret

// block_wall: block (4, 0..6)
block_wall:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, #0
.Lbw_loop:
    cmp     x19, #7
    b.ge    .Lbw_done
    mov     x0, #4
    mov     x1, x19
    bl      grid_block
    add     x19, x19, #1
    b       .Lbw_loop
.Lbw_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// block_pocket: block (6,7) and (7,6) — isolates (7,7)
block_pocket:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, #6
    mov     x1, #7
    bl      grid_block
    mov     x0, #7
    mov     x1, #6
    bl      grid_block
    ldp     x29, x30, [sp], #16
    ret

// _start: run all tests; sp is 16-byte aligned at entry.
_start:
    // ---- Test 1: manhattan ----
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    bl      manhattan
    cbnz    x0, fail

    mov     x0, #0
    mov     x1, #0
    mov     x2, #3
    mov     x3, #4
    bl      manhattan
    cmp     x0, #7
    b.ne    fail

    mov     x0, #7
    mov     x1, #7
    mov     x2, #0
    mov     x3, #0
    bl      manhattan
    cmp     x0, #14
    b.ne    fail

    mov     x0, #2
    mov     x1, #5
    mov     x2, #5
    mov     x3, #2
    bl      manhattan
    cmp     x0, #6
    b.ne    fail

    // ---- Test 2: BFS empty grid (0,0)→(7,7) = 14 ----
    bl      grid_clear
    mov     x0, #0
    mov     x1, #0
    bl      idx_real
    mov     x19, x0             // start
    mov     x0, #7
    mov     x1, #7
    bl      idx_real
    mov     x20, x0             // goal
    mov     x0, x19
    mov     x1, x20
    bl      bfs
    cmp     x0, #14
    b.ne    fail

    // ---- Test 3: BFS same start/goal = 0 ----
    bl      grid_clear
    mov     x0, #3
    mov     x1, #3
    bl      idx_real
    mov     x19, x0
    mov     x0, x19
    mov     x1, x19
    bl      bfs
    cbnz    x0, fail

    // ---- Test 4: BFS around vertical wall = 21 ----
    bl      grid_clear
    bl      block_wall
    mov     x0, #0
    mov     x1, #0
    bl      idx_real
    mov     x19, x0
    mov     x0, #7
    mov     x1, #0
    bl      idx_real
    mov     x20, x0
    mov     x0, x19
    mov     x1, x20
    bl      bfs
    cmp     x0, #21
    b.ne    fail

    // ---- Test 5: BFS unreachable = -1 ----
    bl      grid_clear
    bl      block_pocket
    mov     x0, #0
    mov     x1, #0
    bl      idx_real
    mov     x19, x0
    mov     x0, #7
    mov     x1, #7
    bl      idx_real
    mov     x20, x0
    mov     x0, x19
    mov     x1, x20
    bl      bfs
    cmn     x0, #1              // compare with -1
    b.ne    fail

    // ---- Test 6: A* empty grid = 14 ----
    bl      grid_clear
    mov     x0, #0
    mov     x1, #0
    mov     x2, #7
    mov     x3, #7
    bl      astar
    cmp     x0, #14
    b.ne    fail

    // ---- Test 7: A* matches BFS around wall = 21 ----
    bl      grid_clear
    bl      block_wall
    mov     x0, #0
    mov     x1, #0
    bl      idx_real
    mov     x19, x0
    mov     x0, #7
    mov     x1, #0
    bl      idx_real
    mov     x20, x0
    mov     x0, x19
    mov     x1, x20
    bl      bfs
    mov     x19, x0             // bfs_len
    mov     x0, #0
    mov     x1, #0
    mov     x2, #7
    mov     x3, #0
    bl      astar
    cmp     x0, x19
    b.ne    fail
    cmp     x0, #21
    b.ne    fail

    // ---- Test 8: A* unreachable = -1 ----
    bl      grid_clear
    bl      block_pocket
    mov     x0, #0
    mov     x1, #0
    mov     x2, #7
    mov     x3, #7
    bl      astar
    cmn     x0, #1
    b.ne    fail

    // ---- All passed ----
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
