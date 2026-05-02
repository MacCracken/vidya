# Vidya — Maze Generation in x86_64 Assembly
#
# Recursive backtracker (iterative DFS) on an 8x8 grid. Each cell is a
# byte holding a wall bitmask (N=1, S=2, E=4, W=8). Generation carves
# passages by clearing the wall bit on both the current and the
# neighbour cell.
#
# x86_64's `add r64, imm` form sign-extends a 32-bit immediate, so the
# 64-bit PCG_INC and PCG_MULT must be loaded via `mov r64, imm64` into
# a register before use. `imul` provides the natural mod-2^64 wrap on
# the low 64 bits — the same multiplicative behaviour as cyrius.

.intel_syntax noprefix
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

# PCG state, seeded to 12345 (overwritten by rng_seed)
rng_state:  .quad 12345

.section .bss
.align 8
maze_cells: .skip GN          # u8 per cell
visited:    .skip GN          # u8 per cell (0 / 1)
dfs_stack:  .skip GN * 8      # i64 cell index per slot
nbuf:       .skip 4 * 24      # 4 neighbours * (dir,nx,ny) * 8 bytes
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

# rng_seed: rdi = new state
rng_seed:
    mov     [rip + rng_state], rdi
    ret

# rng_next: returns next pseudo-random value in rax (non-negative,
# 31-bit). `imul` wraps to the low 64 bits — the PCG modular step.
rng_next:
    mov     rax, [rip + rng_state]
    mov     rcx, 6364136223846793005
    imul    rax, rcx
    mov     rcx, 1442695040888963407
    add     rax, rcx
    mov     [rip + rng_state], rax
    shr     rax, 33
    mov     rcx, 0x7fffffff
    and     rax, rcx
    ret

# rng_range: rdi = max ; returns rax in [0, max). max > 0 assumed.
rng_range:
    test    rdi, rdi
    jg      .Lrr_go
    xor     rax, rax
    ret
.Lrr_go:
    push    rdi
    call    rng_next
    pop     rcx
    xor     rdx, rdx
    div     rcx
    mov     rax, rdx          # remainder
    ret

# idx: rdi=x, rsi=y -> rax = y*GW+x
idx:
    mov     rax, rsi
    shl     rax, 3            # *8 (GW=8)
    add     rax, rdi
    ret

# opposite_dir: rdi=d -> rax = opposite
opposite_dir:
    cmp     rdi, WN
    je      .Lopp_s
    cmp     rdi, WS
    je      .Lopp_n
    cmp     rdi, WE
    je      .Lopp_w
    cmp     rdi, WW
    je      .Lopp_e
    xor     rax, rax
    ret
.Lopp_s:
    mov     rax, WS
    ret
.Lopp_n:
    mov     rax, WN
    ret
.Lopp_w:
    mov     rax, WW
    ret
.Lopp_e:
    mov     rax, WE
    ret

# maze_init: fill cells with WALLS_ALL, visited with 0
maze_init:
    lea     rdi, [rip + maze_cells]
    mov     rcx, GN
    mov     al, WALLS_ALL
    rep stosb
    lea     rdi, [rip + visited]
    mov     rcx, GN
    xor     al, al
    rep stosb
    ret

# carve: rdi=x, rsi=y, rdx=d, rcx=nx, r8=ny
carve:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdx          # d
    mov     r13, rcx          # nx
    mov     r14, r8           # ny
    mov     r15, rsi          # y
    mov     rbx, rdi          # x

    # ci = idx(x, y)
    mov     rdi, rbx
    mov     rsi, r15
    call    idx               # rax = ci
    mov     r9, rax           # save ci

    # ni = idx(nx, ny)
    mov     rdi, r13
    mov     rsi, r14
    call    idx               # rax = ni
    mov     r10, rax          # save ni

    # od = opposite(d)
    mov     rdi, r12
    call    opposite_dir      # rax = od

    # cells[ci] &= ~d
    lea     r11, [rip + maze_cells]
    mov     dl, byte ptr [r11 + r9]
    mov     ecx, r12d
    not     ecx
    and     dl, cl
    mov     byte ptr [r11 + r9], dl

    # cells[ni] &= ~od
    mov     dl, byte ptr [r11 + r10]
    mov     ecx, eax
    not     ecx
    and     dl, cl
    mov     byte ptr [r11 + r10], dl

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# collect_unvisited: rdi=x, rsi=y -> rax = count, fills nbuf with
# 24-byte records {dir(8), nx(8), ny(8)}
collect_unvisited:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi          # x
    mov     r12, rsi          # y
    xor     r13, r13          # n = 0
    lea     r14, [rip + nbuf]
    lea     r15, [rip + visited]

    # north: y > 0
    test    r12, r12
    jle     .Lcu_skip_n
    mov     rdi, rbx
    mov     rsi, r12
    dec     rsi
    call    idx
    cmp     byte ptr [r15 + rax], 0
    jne     .Lcu_skip_n
    mov     rax, r13
    imul    rax, rax, 24
    mov     qword ptr [r14 + rax], WN
    mov     qword ptr [r14 + rax + 8], rbx
    mov     rcx, r12
    dec     rcx
    mov     qword ptr [r14 + rax + 16], rcx
    inc     r13
.Lcu_skip_n:

    # south: y < GH-1
    cmp     r12, GH-1
    jge     .Lcu_skip_s
    mov     rdi, rbx
    mov     rsi, r12
    inc     rsi
    call    idx
    cmp     byte ptr [r15 + rax], 0
    jne     .Lcu_skip_s
    mov     rax, r13
    imul    rax, rax, 24
    mov     qword ptr [r14 + rax], WS
    mov     qword ptr [r14 + rax + 8], rbx
    mov     rcx, r12
    inc     rcx
    mov     qword ptr [r14 + rax + 16], rcx
    inc     r13
.Lcu_skip_s:

    # west: x > 0
    test    rbx, rbx
    jle     .Lcu_skip_w
    mov     rdi, rbx
    dec     rdi
    mov     rsi, r12
    call    idx
    cmp     byte ptr [r15 + rax], 0
    jne     .Lcu_skip_w
    mov     rax, r13
    imul    rax, rax, 24
    mov     qword ptr [r14 + rax], WW
    mov     rcx, rbx
    dec     rcx
    mov     qword ptr [r14 + rax + 8], rcx
    mov     qword ptr [r14 + rax + 16], r12
    inc     r13
.Lcu_skip_w:

    # east: x < GW-1
    cmp     rbx, GW-1
    jge     .Lcu_skip_e
    mov     rdi, rbx
    inc     rdi
    mov     rsi, r12
    call    idx
    cmp     byte ptr [r15 + rax], 0
    jne     .Lcu_skip_e
    mov     rax, r13
    imul    rax, rax, 24
    mov     qword ptr [r14 + rax], WE
    mov     rcx, rbx
    inc     rcx
    mov     qword ptr [r14 + rax + 8], rcx
    mov     qword ptr [r14 + rax + 16], r12
    inc     r13
.Lcu_skip_e:

    mov     rax, r13
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# maze_generate: rdi=sx, rsi=sy
maze_generate:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi          # save sx BEFORE clobbering callees
    mov     r12, rsi          # save sy

    call    maze_init

    # start = idx(sx, sy)
    mov     rdi, rbx
    mov     rsi, r12
    call    idx               # rax = start
    mov     r13, rax

    # dfs_stack[0] = start, sp = 1, visited[start] = 1
    lea     r14, [rip + dfs_stack]
    mov     qword ptr [r14], r13
    mov     r15, 1            # sp = 1
    lea     rax, [rip + visited]
    mov     byte ptr [rax + r13], 1

.Lmg_loop:
    test    r15, r15
    jz      .Lmg_done
    # top = dfs_stack[sp-1]
    mov     rcx, r15
    dec     rcx
    mov     rax, qword ptr [r14 + rcx*8]
    # tx = top % GW, ty = top / GW
    mov     rdx, rax
    and     rdx, GW-1         # tx = top & 7
    mov     rcx, rax
    shr     rcx, 3            # ty = top >> 3
    push    rcx               # save ty
    push    rdx               # save tx
    # collect_unvisited(tx, ty)
    mov     rdi, rdx
    mov     rsi, rcx
    call    collect_unvisited
    pop     rdx               # tx
    pop     rcx               # ty
    test    rax, rax
    jnz     .Lmg_pick
    # k == 0: backtrack
    dec     r15
    jmp     .Lmg_loop
.Lmg_pick:
    # rax = k. Save tx, ty before rng_range clobbers regs.
    push    rdx               # tx
    push    rcx               # ty
    mov     rdi, rax
    call    rng_range         # rax = pick
    pop     rcx               # ty
    pop     rdx               # tx
    # nbuf[pick] is at base + pick*24
    imul    rax, rax, 24
    lea     r9, [rip + nbuf]
    mov     r8, qword ptr [r9 + rax]              # d
    mov     r10, qword ptr [r9 + rax + 8]         # nx
    mov     r11, qword ptr [r9 + rax + 16]        # ny
    # carve(tx, ty, d, nx, ny)
    push    r10
    push    r11
    push    rcx
    push    rdx
    mov     rdi, rdx          # x
    mov     rsi, rcx          # y
    mov     rdx, r8           # d
    mov     rcx, r10          # nx
    mov     r8, r11           # ny
    call    carve
    pop     rdx
    pop     rcx
    pop     r11
    pop     r10
    # ni = idx(nx, ny); visited[ni] = 1; dfs_stack[sp] = ni; sp++
    push    rdx
    push    rcx
    mov     rdi, r10
    mov     rsi, r11
    call    idx               # rax = ni
    pop     rcx
    pop     rdx
    lea     r9, [rip + visited]
    mov     byte ptr [r9 + rax], 1
    mov     qword ptr [r14 + r15*8], rax
    inc     r15
    jmp     .Lmg_loop

.Lmg_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# count_visited: rax = count
count_visited:
    xor     rax, rax
    xor     rcx, rcx
    lea     r8, [rip + visited]
.Lcv_loop:
    cmp     rcx, GN
    jge     .Lcv_done
    movzx   rdx, byte ptr [r8 + rcx]
    test    rdx, rdx
    jz      .Lcv_skip
    inc     rax
.Lcv_skip:
    inc     rcx
    jmp     .Lcv_loop
.Lcv_done:
    ret

# count_removed_walls: rax = removed count
count_removed_walls:
    xor     rax, rax          # removed
    xor     rcx, rcx          # y
    lea     r8, [rip + maze_cells]
.Lcr_y:
    cmp     rcx, GH
    jge     .Lcr_done
    xor     rdx, rdx          # x
.Lcr_x:
    cmp     rdx, GW
    jge     .Lcr_yend
    # i = y*GW + x
    mov     r9, rcx
    shl     r9, 3
    add     r9, rdx
    movzx   r10, byte ptr [r8 + r9]
    # if y > 0 and !(w & WN): removed++
    test    rcx, rcx
    jle     .Lcr_no_n
    test    r10, WN
    jnz     .Lcr_no_n
    inc     rax
.Lcr_no_n:
    # if x > 0 and !(w & WW): removed++
    test    rdx, rdx
    jle     .Lcr_no_w
    test    r10, WW
    jnz     .Lcr_no_w
    inc     rax
.Lcr_no_w:
    inc     rdx
    jmp     .Lcr_x
.Lcr_yend:
    inc     rcx
    jmp     .Lcr_y
.Lcr_done:
    ret

# walls_consistent: rax = 1 if consistent, 0 otherwise
walls_consistent:
    xor     rcx, rcx          # y
    lea     r8, [rip + maze_cells]
.Lwc_y:
    cmp     rcx, GH
    jge     .Lwc_ok
    xor     rdx, rdx          # x
.Lwc_x:
    cmp     rdx, GW
    jge     .Lwc_yend
    # i = y*GW + x
    mov     r9, rcx
    shl     r9, 3
    add     r9, rdx
    movzx   r10, byte ptr [r8 + r9]
    # east neighbour: x < GW-1
    cmp     rdx, GW-1
    jge     .Lwc_skip_e
    movzx   r11, byte ptr [r8 + r9 + 1]
    # east_open = (w & WE == 0) ? 1 : 0
    mov     rax, r10
    and     rax, WE
    cmp     rax, 0
    sete    al
    movzx   rdi, al
    mov     rax, r11
    and     rax, WW
    cmp     rax, 0
    sete    al
    movzx   rsi, al
    cmp     rdi, rsi
    jne     .Lwc_fail
.Lwc_skip_e:
    # south neighbour: y < GH-1
    cmp     rcx, GH-1
    jge     .Lwc_skip_s
    movzx   r11, byte ptr [r8 + r9 + GW]
    mov     rax, r10
    and     rax, WS
    cmp     rax, 0
    sete    al
    movzx   rdi, al
    mov     rax, r11
    and     rax, WN
    cmp     rax, 0
    sete    al
    movzx   rsi, al
    cmp     rdi, rsi
    jne     .Lwc_fail
.Lwc_skip_s:
    inc     rdx
    jmp     .Lwc_x
.Lwc_yend:
    inc     rcx
    jmp     .Lwc_y
.Lwc_ok:
    mov     rax, 1
    ret
.Lwc_fail:
    xor     rax, rax
    ret

# expect_eq: rdi=actual, rsi=expected -> exits on mismatch
expect_eq:
    cmp     rdi, rsi
    jne     fail
    ret

_start:
    # --- Test 1: init state ---
    call    maze_init
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax]
    mov     rsi, WALLS_ALL
    call    expect_eq
    movzx   rdi, byte ptr [rax + 63]
    mov     rsi, WALLS_ALL
    call    expect_eq
    lea     rax, [rip + visited]
    movzx   rdi, byte ptr [rax]
    xor     rsi, rsi
    call    expect_eq

    # --- Test 2: full coverage from (0,0) with seed 42 ---
    mov     rdi, 42
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    call    count_visited
    mov     rdi, rax
    mov     rsi, GN
    call    expect_eq

    # --- Test 3: perfect maze removes GN-1 walls ---
    mov     rdi, 42
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    call    count_removed_walls
    mov     rdi, rax
    mov     rsi, GN-1
    call    expect_eq

    # --- Test 4: wall consistency ---
    mov     rdi, 42
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    call    walls_consistent
    mov     rdi, rax
    mov     rsi, 1
    call    expect_eq

    # --- Test 5: determinism (cells 0/27/63) ---
    mov     rdi, 42
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax]
    mov     [rip + g_c0], rdi
    movzx   rdi, byte ptr [rax + 27]
    mov     [rip + g_c27], rdi
    movzx   rdi, byte ptr [rax + 63]
    mov     [rip + g_c63], rdi

    mov     rdi, 42
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax]
    mov     rsi, [rip + g_c0]
    call    expect_eq
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax + 27]
    mov     rsi, [rip + g_c27]
    call    expect_eq
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax + 63]
    mov     rsi, [rip + g_c63]
    call    expect_eq

    # --- Test 6: different seeds differ (sum) ---
    mov     rdi, 1
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    lea     r12, [rip + maze_cells]
    xor     rax, rax
    xor     rcx, rcx
.Ls1:
    cmp     rcx, GN
    jge     .Ls1_done
    movzx   rdx, byte ptr [r12 + rcx]
    add     rax, rdx
    inc     rcx
    jmp     .Ls1
.Ls1_done:
    mov     [rip + g_sum1], rax

    mov     rdi, 2
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    lea     r12, [rip + maze_cells]
    xor     rax, rax
    xor     rcx, rcx
.Ls2:
    cmp     rcx, GN
    jge     .Ls2_done
    movzx   rdx, byte ptr [r12 + rcx]
    add     rax, rdx
    inc     rcx
    jmp     .Ls2
.Ls2_done:
    mov     [rip + g_sum2], rax
    mov     rdi, [rip + g_sum1]
    cmp     rdi, [rip + g_sum2]
    je      fail

    # --- Test 7: starting cell (3,5) visited; full coverage ---
    mov     rdi, 42
    call    rng_seed
    mov     rdi, 3
    mov     rsi, 5
    call    maze_generate
    # idx(3,5) = 5*8+3 = 43
    lea     rax, [rip + visited]
    movzx   rdi, byte ptr [rax + 43]
    mov     rsi, 1
    call    expect_eq
    call    count_visited
    mov     rdi, rax
    mov     rsi, GN
    call    expect_eq

    # --- Cross-language byte parity (matches cyrius reference) ---
    mov     rdi, 42
    call    rng_seed
    xor     rdi, rdi
    xor     rsi, rsi
    call    maze_generate
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax]
    mov     rsi, 13
    call    expect_eq
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax + 27]
    mov     rsi, 12
    call    expect_eq
    lea     rax, [rip + maze_cells]
    movzx   rdi, byte ptr [rax + 63]
    mov     rsi, 6
    call    expect_eq

    # --- Done — write success and exit 0 ---
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
