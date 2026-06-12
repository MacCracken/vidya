# Vidya — Build Systems in x86_64 Assembly
#
# A minimal build-system core: a DAG of targets, topological build order,
# content-signature dirty-tracking, ninja-style incremental rebuild (only
# dirty targets run), and cycle detection. Mirrors content/build_systems/
# cyrius.cyr exactly. Static parallel arrays in .bss back every table
# (8 bytes per i64 slot, 16 targets capacity); n_targets lives in .bss too.
#
# No real files or compilers: each target carries a source "content
# signature" (an integer). A target's INPUT signature mixes its own source
# with the OUTPUT signatures of its deps via a polynomial hash
# (sig = src % HM, then sig = (sig*HB + out[dep]) % HM). If that differs
# from the signature it was last built against, the target rebuilds —
# exactly how mtime/hash tools (make, ninja, bazel) decide what to redo.
# All signature values are non-negative, so idiv/imul sign handling is fine.

.intel_syntax noprefix
.global _start

.equ MAXD, 8                # max deps per target
.equ HB, 131                # signature polynomial base
.equ HM, 1000003            # signature modulus (prime; keeps values < 2^53)

.section .bss
.align 8
t_src:      .skip 8 * 16     # source content signature
t_depcnt:   .skip 8 * 16     # number of dependencies
t_deps:     .skip 8 * 128    # flat deps: t_deps[t*MAXD + k] (16*8 slots)
t_built:    .skip 8 * 16     # signature last built against (-1 = never)
t_out:      .skip 8 * 16     # current output signature
t_order:    .skip 8 * 16     # topological order (target ids)
t_placed:   .skip 8 * 16     # topo scratch: placed flag
n_targets:  .skip 8          # number of live targets

.section .rodata
msg_pass:    .ascii "All build_systems examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# bs_reset(rdi=n): n_targets=n; for i in 0..n: src=0, depcnt=0,
#   built=-1 (never), out=0.
bs_reset:
    lea     rax, [rip + n_targets]
    mov     [rax], rdi
    xor     rcx, rcx                # i
.reset_loop:
    cmp     rcx, rdi
    jge     .reset_done
    lea     rax, [rip + t_src]
    mov     qword ptr [rax + rcx * 8], 0
    lea     rax, [rip + t_depcnt]
    mov     qword ptr [rax + rcx * 8], 0
    lea     rax, [rip + t_built]
    mov     qword ptr [rax + rcx * 8], -1
    lea     rax, [rip + t_out]
    mov     qword ptr [rax + rcx * 8], 0
    inc     rcx
    jmp     .reset_loop
.reset_done:
    ret

# bs_set_src(rdi=t, rsi=sig): t_src[t] = sig
bs_set_src:
    lea     rax, [rip + t_src]
    mov     [rax + rdi * 8], rsi
    ret

# bs_add_dep(rdi=t, rsi=d): append d to t's dep list, bump depcnt
bs_add_dep:
    lea     rax, [rip + t_depcnt]
    mov     rcx, [rax + rdi * 8]        # c = current dep count
    # slot = t*MAXD + c
    mov     rdx, rdi
    imul    rdx, MAXD
    add     rdx, rcx
    lea     rax, [rip + t_deps]
    mov     [rax + rdx * 8], rsi
    # depcnt[t] = c + 1
    lea     rax, [rip + t_depcnt]
    inc     rcx
    mov     [rax + rdi * 8], rcx
    ret

# bs_topo() -> rax = number of targets ordered (< n_targets ⇒ cycle).
# Kahn-style ready-scan: repeatedly place any unplaced target whose deps
# are all placed; a full scan that places nothing ⇒ cycle. Uses callee-
# saved registers so internal structure stays simple (no internal calls).
bs_topo:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    lea     r15, [rip + n_targets]
    mov     r15, [r15]                  # n_targets

    # clear t_placed[0..n]
    xor     rcx, rcx
    lea     rax, [rip + t_placed]
.topo_clear:
    cmp     rcx, r15
    jge     .topo_clear_done
    mov     qword ptr [rax + rcx * 8], 0
    inc     rcx
    jmp     .topo_clear
.topo_clear_done:

    xor     r12, r12                    # placed = 0
.topo_outer:
    cmp     r12, r15
    jge     .topo_full                  # placed == n_targets
    xor     r13, r13                    # progress = 0
    xor     rbx, rbx                    # t = 0
.topo_scan:
    cmp     rbx, r15
    jge     .topo_scan_done

    # if t_placed[t] != 0 skip
    lea     rax, [rip + t_placed]
    mov     rax, [rax + rbx * 8]
    test    rax, rax
    jnz     .topo_next_t

    # ready iff every dep is already placed
    mov     r14, 1                      # ready = 1
    lea     rax, [rip + t_depcnt]
    mov     r8, [rax + rbx * 8]         # dc
    xor     r9, r9                      # k = 0
.topo_dep:
    cmp     r9, r8
    jge     .topo_dep_done
    # d = t_deps[t*MAXD + k]
    mov     r10, rbx
    imul    r10, MAXD
    add     r10, r9
    lea     rax, [rip + t_deps]
    mov     r10, [rax + r10 * 8]        # d
    lea     rax, [rip + t_placed]
    mov     rax, [rax + r10 * 8]
    test    rax, rax
    jnz     .topo_dep_next
    xor     r14, r14                    # ready = 0
.topo_dep_next:
    inc     r9
    jmp     .topo_dep
.topo_dep_done:

    test    r14, r14
    jz      .topo_next_t
    # place t: t_order[placed] = t; t_placed[t] = 1; placed++; progress=1
    lea     rax, [rip + t_order]
    mov     [rax + r12 * 8], rbx
    lea     rax, [rip + t_placed]
    mov     qword ptr [rax + rbx * 8], 1
    inc     r12
    mov     r13, 1

.topo_next_t:
    inc     rbx
    jmp     .topo_scan
.topo_scan_done:
    test    r13, r13
    jz      .topo_full                  # progress == 0 ⇒ stuck ⇒ cycle
    jmp     .topo_outer

.topo_full:
    mov     rax, r12
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# bs_sig(rdi=t) -> rax = input signature.
# sig = src % HM; per dep: sig = (sig*HB + out[dep]) % HM.
# Uses idiv (rdx:rax / divisor) for %; rbx holds running sig.
bs_sig:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r14, rdi                    # t

    # sig = src % HM
    lea     rax, [rip + t_src]
    mov     rax, [rax + r14 * 8]
    cqo
    mov     r10, HM
    idiv    r10                         # rdx = src % HM
    mov     rbx, rdx                    # sig

    lea     rax, [rip + t_depcnt]
    mov     r12, [rax + r14 * 8]        # dc
    xor     r13, r13                    # k = 0
.sig_loop:
    cmp     r13, r12
    jge     .sig_done
    # d = t_deps[t*MAXD + k]
    mov     r10, r14
    imul    r10, MAXD
    add     r10, r13
    lea     rax, [rip + t_deps]
    mov     r10, [rax + r10 * 8]        # d
    # sig = (sig*HB + out[d]) % HM
    mov     rax, rbx
    imul    rax, HB                     # sig*HB
    lea     r11, [rip + t_out]
    add     rax, [r11 + r10 * 8]        # + out[d]
    cqo
    mov     r10, HM
    idiv    r10
    mov     rbx, rdx                    # sig = ... % HM
    inc     r13
    jmp     .sig_loop
.sig_done:
    mov     rax, rbx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# bs_build() -> rax = number of targets rebuilt.
# Walk topo order; if input sig != t_built[t] → t_out=sig, t_built=sig,
# count a rebuild.
bs_build:
    push    rbx
    push    r12
    push    r13

    call    bs_topo
    mov     r12, rax                    # ordered
    xor     r13, r13                    # rebuilt = 0
    xor     rbx, rbx                    # i = 0
.build_loop:
    cmp     rbx, r12
    jge     .build_done
    # t = t_order[i]
    lea     rax, [rip + t_order]
    mov     rdi, [rax + rbx * 8]        # t
    push    rdi
    call    bs_sig                      # rax = sig
    pop     rdi                         # t
    # if sig != t_built[t]: produce output + remember + count
    lea     rcx, [rip + t_built]
    cmp     rax, [rcx + rdi * 8]
    je      .build_next
    lea     rcx, [rip + t_out]
    mov     [rcx + rdi * 8], rax
    lea     rcx, [rip + t_built]
    mov     [rcx + rdi * 8], rax
    inc     r13
.build_next:
    inc     rbx
    jmp     .build_loop
.build_done:
    mov     rax, r13
    pop     r13
    pop     r12
    pop     rbx
    ret

# build_graph(): classic C build graph
#   0=util.o(src 1001), 1=main.o(src 2002), 2=app(src 3003); app deps [0,1]
build_graph:
    push    rbx
    mov     rdi, 3
    call    bs_reset
    mov     rdi, 0
    mov     rsi, 1001
    call    bs_set_src
    mov     rdi, 1
    mov     rsi, 2002
    call    bs_set_src
    mov     rdi, 2
    mov     rsi, 3003
    call    bs_set_src
    mov     rdi, 2
    mov     rsi, 0
    call    bs_add_dep
    mov     rdi, 2
    mov     rsi, 1
    call    bs_add_dep
    pop     rbx
    ret

# order_pos(rdi=target) -> rax = index in t_order, or -1 if absent
order_pos:
    lea     r8, [rip + n_targets]
    mov     r8, [r8]
    lea     r9, [rip + t_order]
    xor     rcx, rcx
.op_loop:
    cmp     rcx, r8
    jge     .op_miss
    cmp     [r9 + rcx * 8], rdi
    je      .op_hit
    inc     rcx
    jmp     .op_loop
.op_hit:
    mov     rax, rcx
    ret
.op_miss:
    mov     rax, -1
    ret

_start:
    # ---- Test 1: topo orders all 3; app(2) after util.o(0) and main.o(1) ----
    call    build_graph
    call    bs_topo
    cmp     rax, 3
    jne     fail

    mov     rdi, 2
    call    order_pos
    mov     rbx, rax                    # pos(app)
    mov     rdi, 0
    call    order_pos                   # pos(util.o)
    cmp     rbx, rax
    jle     fail                        # app must be AFTER util.o
    mov     rdi, 1
    call    order_pos                   # pos(main.o)
    cmp     rbx, rax
    jle     fail                        # app must be AFTER main.o

    # ---- Test 2: cold build rebuilds all 3 ----
    call    build_graph
    call    bs_build
    cmp     rax, 3
    jne     fail

    # ---- Test 3: second build (no edits) rebuilds 0 ----
    call    build_graph
    call    bs_build                    # cold
    call    bs_build                    # no-op
    test    rax, rax
    jnz     fail

    # ---- Test 4: edit main.c (t_src[1]=2999) → rebuilds 2 ----
    call    build_graph
    call    bs_build                    # cold
    mov     rdi, 1
    mov     rsi, 2999
    call    bs_set_src
    call    bs_build
    cmp     rax, 2
    jne     fail

    # ---- Test 5: edit util.c (t_src[0]=1999) → rebuilds 2; main.o built unchanged ----
    call    build_graph
    call    bs_build                    # cold
    lea     rax, [rip + t_built]
    mov     rbx, [rax + 1 * 8]          # main.o built signature before edit
    mov     rdi, 0
    mov     rsi, 1999
    call    bs_set_src
    call    bs_build
    cmp     rax, 2
    jne     fail
    lea     rax, [rip + t_built]
    mov     rax, [rax + 1 * 8]
    cmp     rax, rbx                    # main.o left untouched
    jne     fail

    # ---- Test 6: 2-node cycle (0→1, 1→0) → topo places < 2 ----
    mov     rdi, 2
    call    bs_reset
    mov     rdi, 0
    mov     rsi, 1
    call    bs_add_dep
    mov     rdi, 1
    mov     rsi, 0
    call    bs_add_dep
    call    bs_topo
    cmp     rax, 2
    jge     fail                        # must be < 2 (cycle)

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
