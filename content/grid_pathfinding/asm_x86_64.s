# Vidya — Grid Pathfinding in x86_64 Assembly
#
# BFS + A* on an 8x8 4-connected grid (0=walkable, 1=blocked). Static
# buffers in .bss back grid/visited/came_from/queue/open_set/g_score/
# f_score — exactly the layout cyrius.cyr declares. The A* open set is
# a flat array; we linear-scan for the lowest f-score rather than
# building a heap (correct for 64 cells; a real heap is the right
# answer ~512 cells and up). Manhattan distance is the heuristic.
# 64-bit g_score sentinels use the `mov rN, 0xLITERAL` form because
# x86_64 `mov` with a 32-bit operand sign-extends — INT64_MAX needs
# the 64-bit-immediate form.

.intel_syntax noprefix
.global _start

.equ GW, 8
.equ GH, 8
.equ GN, 64

.section .bss
.align 8
grid:       .skip 64           # u8 per cell
visited:    .skip 64           # u8 per cell
dist:       .skip 8 * 64       # i64 per cell (BFS)
came_from:  .skip 8 * 64       # i64 per cell
queue:      .skip 8 * 64       # i64 per cell (BFS FIFO)
open_set:   .skip 8 * 64       # i64 per cell (A* open list)
g_score:    .skip 8 * 64       # i64 per cell
f_score:    .skip 8 * 64       # i64 per cell

.section .rodata
msg_pass:    .ascii "All grid_pathfinding examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# idx(rdi=x, rsi=y) -> rax  (rax = y*GW + x)
idx:
    mov     rax, rsi
    shl     rax, 3              # *8 = *GW
    add     rax, rdi
    ret

# manhattan(rdi=ax, rsi=ay, rdx=bx, rcx=by) -> rax = |ax-bx| + |ay-by|
manhattan:
    sub     rdi, rdx
    mov     rax, rdi
    neg     rax
    cmovs   rax, rdi            # rax = abs(ax-bx); cmovs picks rdi if rax<0
    sub     rsi, rcx
    mov     r8, rsi
    neg     r8
    cmovs   r8, rsi
    add     rax, r8
    ret

# grid_clear: zero grid + visited (visited touched per-call elsewhere too)
grid_clear:
    lea     rdi, [rip + grid]
    mov     rcx, GN
    xor     rax, rax
.gc_loop:
    mov     byte ptr [rdi], al
    inc     rdi
    dec     rcx
    jnz     .gc_loop
    ret

# grid_block(rdi=x, rsi=y): grid[y*GW+x] = 1
grid_block:
    push    rdi
    push    rsi
    call    idx
    pop     rsi
    pop     rdi
    lea     rdi, [rip + grid]
    mov     byte ptr [rdi + rax], 1
    ret

# init_visited: zero the visited[] array
init_visited:
    lea     rdi, [rip + visited]
    mov     rcx, GN
    xor     rax, rax
.iv_loop:
    mov     byte ptr [rdi], al
    inc     rdi
    dec     rcx
    jnz     .iv_loop
    ret

# init_dist_neg1: set dist[i] = -1 for i in 0..GN
init_dist_neg1:
    lea     rdi, [rip + dist]
    mov     rcx, GN
    mov     rax, -1
.id_loop:
    mov     [rdi], rax
    add     rdi, 8
    dec     rcx
    jnz     .id_loop
    ret

# init_g_f_inf: set g_score[i] = f_score[i] = INT64_MAX
init_g_f_inf:
    mov     r9, 0x7FFFFFFFFFFFFFFF
    lea     rdi, [rip + g_score]
    lea     rsi, [rip + f_score]
    mov     rcx, GN
.if_loop:
    mov     [rdi], r9
    mov     [rsi], r9
    add     rdi, 8
    add     rsi, 8
    dec     rcx
    jnz     .if_loop
    ret

# bfs(rdi=start, rsi=goal) -> rax = path length, or -1
# Uses callee-saved r12/r13/r14/r15 to avoid clobber on internal calls.
bfs:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi            # start
    mov     r13, rsi            # goal

    # if start == goal return 0
    cmp     r12, r13
    jne     .bfs_init
    xor     rax, rax
    jmp     .bfs_done

.bfs_init:
    call    init_visited
    call    init_dist_neg1

    # queue[0] = start; head=0; tail=1
    lea     rax, [rip + queue]
    mov     [rax], r12
    xor     r14, r14            # head
    mov     r15, 1              # tail

    # visited[start] = 1
    lea     rax, [rip + visited]
    mov     byte ptr [rax + r12], 1

    # dist[start] = 0
    lea     rax, [rip + dist]
    mov     qword ptr [rax + r12 * 8], 0

.bfs_loop:
    cmp     r14, r15
    jge     .bfs_unreach

    # curr = queue[head++]
    lea     rax, [rip + queue]
    mov     rbx, [rax + r14 * 8]
    inc     r14

    # goal check
    cmp     rbx, r13
    jne     .bfs_expand
    lea     rax, [rip + dist]
    mov     rax, [rax + rbx * 8]
    jmp     .bfs_done

.bfs_expand:
    # cx = curr % GW (= curr & 7); cy = curr / GW (= curr >> 3)
    mov     r8, rbx
    and     r8, 7               # cx
    mov     r9, rbx
    shr     r9, 3               # cy

    # up: cy > 0 ⇒ n = curr - GW
    test    r9, r9
    jz      .bfs_skip_up
    mov     r10, rbx
    sub     r10, GW
    call    bfs_relax
.bfs_skip_up:

    # down: cy < GH-1 ⇒ n = curr + GW
    cmp     r9, GH - 1
    jge     .bfs_skip_down
    mov     r10, rbx
    add     r10, GW
    call    bfs_relax
.bfs_skip_down:

    # left: cx > 0 ⇒ n = curr - 1
    test    r8, r8
    jz      .bfs_skip_left
    mov     r10, rbx
    dec     r10
    call    bfs_relax
.bfs_skip_left:

    # right: cx < GW-1 ⇒ n = curr + 1
    cmp     r8, GW - 1
    jge     .bfs_skip_right
    mov     r10, rbx
    inc     r10
    call    bfs_relax
.bfs_skip_right:

    jmp     .bfs_loop

.bfs_unreach:
    mov     rax, -1

.bfs_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# bfs_relax: r10=neighbor, rbx=curr; if !visited[n] && grid[n]==0:
#   visited[n] = 1; dist[n] = dist[curr]+1; queue[tail++] = n.
# Uses r11 / rax as scratch.
bfs_relax:
    lea     r11, [rip + visited]
    cmp     byte ptr [r11 + r10], 0
    jne     .bxr_done
    lea     r11, [rip + grid]
    cmp     byte ptr [r11 + r10], 0
    jne     .bxr_done
    # mark visited
    lea     r11, [rip + visited]
    mov     byte ptr [r11 + r10], 1
    # dist[n] = dist[curr] + 1
    lea     r11, [rip + dist]
    mov     rax, [r11 + rbx * 8]
    inc     rax
    mov     [r11 + r10 * 8], rax
    # queue[tail++] = n
    lea     r11, [rip + queue]
    mov     [r11 + r15 * 8], r10
    inc     r15
.bxr_done:
    ret

# astar(rdi=sx, rsi=sy, rdx=gx, rcx=gy) -> rax = g_score[goal] or -1
# Saves goal coords in r12/r13, goal-cell idx in r14, open_n in r15.
astar:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 32             # spill area: [rsp]=sx, [rsp+8]=sy, [rsp+16]=gx, [rsp+24]=gy

    mov     [rsp], rdi
    mov     [rsp + 8], rsi
    mov     [rsp + 16], rdx
    mov     [rsp + 24], rcx
    mov     r12, rdx            # gx
    mov     r13, rcx            # gy

    call    init_visited
    call    init_g_f_inf

    # start = idx(sx, sy)
    mov     rdi, [rsp]
    mov     rsi, [rsp + 8]
    call    idx
    mov     rbx, rax            # start

    # goal = idx(gx, gy)
    mov     rdi, [rsp + 16]
    mov     rsi, [rsp + 24]
    call    idx
    mov     r14, rax            # goal

    # g_score[start] = 0
    lea     rax, [rip + g_score]
    mov     qword ptr [rax + rbx * 8], 0
    # f_score[start] = manhattan(sx, sy, gx, gy)
    mov     rdi, [rsp]
    mov     rsi, [rsp + 8]
    mov     rdx, [rsp + 16]
    mov     rcx, [rsp + 24]
    call    manhattan
    lea     rdi, [rip + f_score]
    mov     [rdi + rbx * 8], rax

    # open_set[0] = start; open_n = 1 (r15)
    lea     rax, [rip + open_set]
    mov     [rax], rbx
    mov     r15, 1

.astar_loop:
    test    r15, r15
    jz      .astar_unreach

    # Linear scan for min-f. best_i = 0; best_f = f_score[open_set[0]].
    xor     r8, r8              # best_i
    lea     r9, [rip + open_set]
    mov     r10, [r9]            # cell at index 0
    lea     r11, [rip + f_score]
    mov     rcx, [r11 + r10 * 8]    # best_f

    mov     rdi, 1              # k = 1
.scan_loop:
    cmp     rdi, r15
    jge     .scan_done
    mov     r10, [r9 + rdi * 8]      # node = open_set[k]
    mov     rdx, [r11 + r10 * 8]     # fv
    cmp     rdx, rcx
    jge     .scan_skip
    mov     rcx, rdx
    mov     r8, rdi
.scan_skip:
    inc     rdi
    jmp     .scan_loop
.scan_done:
    # curr = open_set[best_i]
    mov     rbx, [r9 + r8 * 8]

    # if curr == goal: return g_score[goal]
    cmp     rbx, r14
    jne     .astar_pop
    lea     rax, [rip + g_score]
    mov     rax, [rax + r14 * 8]
    jmp     .astar_done

.astar_pop:
    # Remove best_i: open_set[best_i] = open_set[--open_n] (unless equal).
    dec     r15
    cmp     r8, r15
    je      .astar_after_pop
    mov     rdx, [r9 + r15 * 8]
    mov     [r9 + r8 * 8], rdx
.astar_after_pop:
    # closed[curr] = 1 (using `visited` as the closed set)
    lea     rdx, [rip + visited]
    mov     byte ptr [rdx + rbx], 1

    # tg = g_score[curr] + 1  (kept in rdi across relax calls;
    # astar_relax preserves rdi via push/pop)
    lea     rdx, [rip + g_score]
    mov     rdi, [rdx + rbx * 8]
    inc     rdi                  # rdi = tg

    # cx = rbx & 7; cy = rbx >> 3 — recomputed before each direction
    # because manhattan (called inside astar_relax) clobbers r8/r9.

    # up: cy > 0
    mov     r9, rbx
    shr     r9, 3
    test    r9, r9
    jz      .a_no_up
    mov     r10, rbx
    sub     r10, GW
    call    astar_relax
.a_no_up:
    # down: cy < GH-1
    mov     r9, rbx
    shr     r9, 3
    cmp     r9, GH - 1
    jge     .a_no_down
    mov     r10, rbx
    add     r10, GW
    call    astar_relax
.a_no_down:
    # left: cx > 0
    mov     r8, rbx
    and     r8, 7
    test    r8, r8
    jz      .a_no_left
    mov     r10, rbx
    dec     r10
    call    astar_relax
.a_no_left:
    # right: cx < GW-1
    mov     r8, rbx
    and     r8, 7
    cmp     r8, GW - 1
    jge     .a_no_right
    mov     r10, rbx
    inc     r10
    call    astar_relax
.a_no_right:

    jmp     .astar_loop

.astar_unreach:
    mov     rax, -1

.astar_done:
    add     rsp, 32
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# astar_relax: r10=n, rbx=curr, rdi=tg, r12=gx, r13=gy, r14=goal, r15=open_n
# If !closed[n] && grid[n]==0 && tg < g_score[n]:
#   g_score[n] = tg
#   f_score[n] = tg + manhattan(n%GW, n/GW, gx, gy)
#   open_set[open_n++] = n
astar_relax:
    lea     r11, [rip + visited]
    cmp     byte ptr [r11 + r10], 0
    jne     .ar_done
    lea     r11, [rip + grid]
    cmp     byte ptr [r11 + r10], 0
    jne     .ar_done
    lea     r11, [rip + g_score]
    cmp     rdi, [r11 + r10 * 8]
    jge     .ar_done

    # Save callee-clobbered scratch around the manhattan call:
    # rdi = tg, r10 = n, rbx = curr (caller-saved across us)
    push    rdi
    push    r10
    push    rbx

    # g_score[n] = tg
    mov     [r11 + r10 * 8], rdi

    # nx = n & 7 ; ny = n >> 3
    mov     rcx, r10
    and     rcx, 7
    mov     rdx, r10
    shr     rdx, 3
    # manhattan(rdi=nx, rsi=ny, rdx=gx, rcx=gy)
    mov     rdi, rcx           # nx
    mov     rsi, rdx           # ny
    mov     rdx, r12
    mov     rcx, r13
    call    manhattan          # rax = h
    # f_score[n] = tg + h ; tg sits on the stack at [rsp+16]
    mov     rdx, [rsp + 16]    # tg
    add     rax, rdx
    pop     rbx
    pop     r10
    pop     rdi
    lea     r11, [rip + f_score]
    mov     [r11 + r10 * 8], rax

    # open_set[open_n++] = n
    lea     r11, [rip + open_set]
    mov     [r11 + r15 * 8], r10
    inc     r15
.ar_done:
    ret

# block_wall: block (4, 0..6) — cells x=4 for y in 0..6
block_wall:
    push    r12
    xor     r12, r12            # y
.bw_loop:
    cmp     r12, 7
    jge     .bw_done
    mov     rdi, 4
    mov     rsi, r12
    call    grid_block
    inc     r12
    jmp     .bw_loop
.bw_done:
    pop     r12
    ret

# block_pocket: block (6,7) and (7,6) — isolates (7,7)
block_pocket:
    mov     rdi, 6
    mov     rsi, 7
    call    grid_block
    mov     rdi, 7
    mov     rsi, 6
    call    grid_block
    ret

# Macro: assert rax == imm; on mismatch, jump to fail.
# (No m4; emitted inline at each call site.)

_start:
    # ---- Test 1: manhattan ----
    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 0
    mov     rcx, 0
    call    manhattan
    test    rax, rax
    jnz     fail

    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 3
    mov     rcx, 4
    call    manhattan
    cmp     rax, 7
    jne     fail

    mov     rdi, 7
    mov     rsi, 7
    mov     rdx, 0
    mov     rcx, 0
    call    manhattan
    cmp     rax, 14
    jne     fail

    mov     rdi, 2
    mov     rsi, 5
    mov     rdx, 5
    mov     rcx, 2
    call    manhattan
    cmp     rax, 6
    jne     fail

    # ---- Test 2: BFS empty grid (0,0)→(7,7) = 14 ----
    call    grid_clear
    mov     rdi, 0
    mov     rsi, 0
    call    idx
    mov     r12, rax              # start
    mov     rdi, 7
    mov     rsi, 7
    call    idx
    mov     r13, rax              # goal
    mov     rdi, r12
    mov     rsi, r13
    call    bfs
    cmp     rax, 14
    jne     fail

    # ---- Test 3: BFS same start/goal = 0 ----
    call    grid_clear
    mov     rdi, 3
    mov     rsi, 3
    call    idx
    mov     r12, rax
    mov     rdi, r12
    mov     rsi, r12
    call    bfs
    test    rax, rax
    jnz     fail

    # ---- Test 4: BFS around vertical wall = 21 ----
    call    grid_clear
    call    block_wall
    mov     rdi, 0
    mov     rsi, 0
    call    idx
    mov     r12, rax
    mov     rdi, 7
    mov     rsi, 0
    call    idx
    mov     r13, rax
    mov     rdi, r12
    mov     rsi, r13
    call    bfs
    cmp     rax, 21
    jne     fail

    # ---- Test 5: BFS unreachable ----
    call    grid_clear
    call    block_pocket
    mov     rdi, 0
    mov     rsi, 0
    call    idx
    mov     r12, rax
    mov     rdi, 7
    mov     rsi, 7
    call    idx
    mov     r13, rax
    mov     rdi, r12
    mov     rsi, r13
    call    bfs
    cmp     rax, -1
    jne     fail

    # ---- Test 6: A* empty grid = 14 ----
    call    grid_clear
    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 7
    mov     rcx, 7
    call    astar
    cmp     rax, 14
    jne     fail

    # ---- Test 7: A* matches BFS around wall = 21 ----
    call    grid_clear
    call    block_wall
    mov     rdi, 0
    mov     rsi, 0
    call    idx
    mov     r12, rax
    mov     rdi, 7
    mov     rsi, 0
    call    idx
    mov     r13, rax
    mov     rdi, r12
    mov     rsi, r13
    call    bfs
    mov     r12, rax              # save bfs_len
    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 7
    mov     rcx, 0
    call    astar
    cmp     rax, r12
    jne     fail
    cmp     rax, 21
    jne     fail

    # ---- Test 8: A* unreachable = -1 ----
    call    grid_clear
    call    block_pocket
    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 7
    mov     rcx, 7
    call    astar
    cmp     rax, -1
    jne     fail

    # ---- All passed ----
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall
