# Vidya — Package Resolution in x86_64 Assembly
#
# Semantic versioning, caret constraint matching, range intersection for
# diamond dependencies, highest-version selection, bounded backtracking, and
# dependency-cycle detection — the core of a dependency resolver (npm, cargo,
# cyrius.cyml's own). Mirrors content/package_resolution/cyrius.cyr.
#
# A semver major.minor.patch is encoded as one integer
#   enc = major*1_000_000 + minor*1_000 + patch
# so version comparison IS integer comparison. A constraint is a half-open
# range [lo, hi). A caret ^X.Y.Z = [X.Y.Z, (X+1).0.0). Resolving a shared
# ("diamond") dependency means intersecting the ranges every requirer imposes
# and picking the highest version that survives — and backtracking on an
# earlier choice when the highest pick paints a later dependency into a
# corner. All encoded values are small non-negatives; idiv sign handling is
# fine. Static parallel arrays in .bss back the package graph (Kahn scan).

.intel_syntax noprefix
.global _start

.equ VMAJ, 1000000          # major weight
.equ VMIN, 1000             # minor weight
.equ MAXD, 8                # max deps per package

.section .data
.align 8
# Available versions of the shared dependency C: 1.0.0, 1.5.0, 2.0.0
c_vers:     .quad 1000000, 1005000, 2000000
c_n:        .quad 3

.section .bss
.align 8
p_depcnt:   .skip 8 * 128       # number of dependencies per package
p_deps:     .skip 8 * 1024      # flat deps: p_deps[p*MAXD + k]
p_placed:   .skip 8 * 128       # Kahn scratch: placed flag
p_n:        .skip 8             # number of live packages
g_chosen_c: .skip 8             # out-param: C chosen by resolve_backtrack

.section .rodata
msg_pass:    .ascii "All package_resolution examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# sv(rdi=maj, rsi=min, rdx=pat) -> rax = maj*VMAJ + min*VMIN + pat
sv:
    mov     rax, rdi
    imul    rax, VMAJ
    mov     rcx, rsi
    imul    rcx, VMIN
    add     rax, rcx
    add     rax, rdx
    ret

# sv_major(rdi=v) -> rax = v / VMAJ  (cqo + idiv)
sv_major:
    mov     rax, rdi
    cqo
    mov     rcx, VMAJ
    idiv    rcx                         # rax = v / VMAJ
    ret

# caret_hi(rdi=v) -> rax = (sv_major(v) + 1) * VMAJ
caret_hi:
    call    sv_major
    inc     rax
    imul    rax, VMAJ
    ret

# satisfies(rdi=v, rsi=lo, rdx=hi) -> rax = 1 if lo<=v<hi else 0
satisfies:
    xor     rax, rax
    cmp     rdi, rsi
    jl      .sat_done                   # v < lo
    cmp     rdi, rdx
    jge     .sat_done                   # v >= hi
    mov     rax, 1
.sat_done:
    ret

# range_lo_max(rdi=a, rsi=b) -> rax = max(a, b)
range_lo_max:
    mov     rax, rdi
    cmp     rsi, rax
    cmovg   rax, rsi
    ret

# range_hi_min(rdi=a, rsi=b) -> rax = min(a, b)
range_hi_min:
    mov     rax, rdi
    cmp     rsi, rax
    cmovl   rax, rsi
    ret

# best_match(rdi=lo, rsi=hi) -> rax = highest c_vers in [lo,hi), else -1.
# Scans the global c_vers array (c_n entries).
best_match:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r14, rdi                    # lo
    mov     r15, rsi                    # hi
    mov     r12, -1                     # best = -1
    lea     rax, [rip + c_n]
    mov     r13, [rax]                  # n
    xor     rbx, rbx                    # i = 0
.bm_loop:
    cmp     rbx, r13
    jge     .bm_done
    lea     rax, [rip + c_vers]
    mov     rdi, [rax + rbx * 8]        # v
    cmp     rdi, r14
    jl      .bm_next                    # v < lo
    cmp     rdi, r15
    jge     .bm_next                    # v >= hi
    cmp     rdi, r12
    jle     .bm_next                    # v <= best
    mov     r12, rdi                    # best = v
.bm_next:
    inc     rbx
    jmp     .bm_loop
.bm_done:
    mov     rax, r12
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# intersect(rdi=a_base, rsi=b_base) -> rax = lo, rdx = hi of
#   ^a_base ∩ ^b_base.  lo = max(a_base, b_base); hi = min(caret_hi).
# Empty iff lo >= hi (caller checks).  Clobbers rcx; preserves nothing else.
intersect:
    push    rbx                         # a_base
    push    r12                         # b_base
    push    r13                         # lo
    mov     rbx, rdi
    mov     r12, rsi
    # lo = max(a_base, b_base)
    mov     rdi, rbx
    mov     rsi, r12
    call    range_lo_max
    mov     r13, rax                    # lo
    # hi = min(caret_hi(a), caret_hi(b))
    mov     rdi, rbx
    call    caret_hi
    mov     rsi, rax                    # caret_hi(a)
    mov     rdi, r12
    push    rsi
    call    caret_hi                    # rax = caret_hi(b)
    pop     rsi                         # caret_hi(a)
    mov     rdi, rsi
    mov     rsi, rax
    call    range_hi_min                # rax = hi
    mov     rdx, rax                    # hi
    mov     rax, r13                    # lo
    pop     r13
    pop     r12
    pop     rbx
    ret

# resolve_shared(rdi=a_base, rsi=b_base) -> rax = chosen C, or -1.
# Intersect ^a_base and ^b_base, then best_match over C.
resolve_shared:
    call    intersect                   # rax = lo, rdx = hi
    cmp     rax, rdx
    jge     .rs_empty                   # lo >= hi ⇒ empty ⇒ -1
    mov     rdi, rax                    # lo
    mov     rsi, rdx                    # hi
    call    best_match
    ret
.rs_empty:
    mov     rax, -1
    ret

# resolve_backtrack(rdi=&a_vers, rsi=&a_creq, rdx=an, rcx=b_base) -> rax=bestA,
# and stores chosen C in g_chosen_c.  For each A candidate i: intersect its
# C-requirement caret with B's caret; if non-empty and best_match succeeds,
# keep the candidate with the highest A version.  -1 if none.
resolve_backtrack:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 8                      # 16-byte align
    mov     rbx, rdi                    # &a_vers
    mov     r12, rsi                    # &a_creq
    mov     r13, rdx                    # an
    mov     r14, rcx                    # b_base
    mov     r15, -1                     # bestA = -1
    mov     rbp, -1                     # bestC = -1
    xor     rcx, rcx                    # i = 0  (kept on stack via reload)
    mov     [rsp], rcx                  # i
.rb_loop:
    mov     rcx, [rsp]                  # i
    cmp     rcx, r13
    jge     .rb_done
    # aver = a_vers[i]; creq = a_creq[i]
    mov     rax, [rbx + rcx * 8]        # aver
    mov     rdx, [r12 + rcx * 8]        # creq
    # intersect(creq, b_base)
    push    rax                         # save aver
    mov     rdi, rdx
    mov     rsi, r14
    call    intersect                   # rax = lo, rdx = hi
    cmp     rax, rdx
    jge     .rb_next_pop                # empty ⇒ skip
    mov     rdi, rax
    mov     rsi, rdx
    call    best_match                  # rax = c, or -1
    cmp     rax, -1
    je      .rb_next_pop                # no C satisfies ⇒ skip
    mov     rdx, rax                    # c
    pop     rax                         # aver
    cmp     rax, r15
    jle     .rb_next                    # aver <= bestA ⇒ skip
    mov     r15, rax                    # bestA = aver
    mov     rbp, rdx                    # bestC = c
    jmp     .rb_next
.rb_next_pop:
    pop     rax                         # discard saved aver
.rb_next:
    mov     rcx, [rsp]
    inc     rcx
    mov     [rsp], rcx
    jmp     .rb_loop
.rb_done:
    lea     rax, [rip + g_chosen_c]
    mov     [rax], rbp                  # g_chosen_c = bestC
    mov     rax, r15                    # bestA
    add     rsp, 8
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# pkg_reset(rdi=n): p_n = n; depcnt[0..n) = 0
pkg_reset:
    lea     rax, [rip + p_n]
    mov     [rax], rdi
    xor     rcx, rcx
.pr_loop:
    cmp     rcx, rdi
    jge     .pr_done
    lea     rax, [rip + p_depcnt]
    mov     qword ptr [rax + rcx * 8], 0
    inc     rcx
    jmp     .pr_loop
.pr_done:
    ret

# pkg_add_dep(rdi=p, rsi=d): append d to p's dep list, bump depcnt
pkg_add_dep:
    lea     rax, [rip + p_depcnt]
    mov     rcx, [rax + rdi * 8]        # c = current dep count
    mov     rdx, rdi
    imul    rdx, MAXD
    add     rdx, rcx                    # slot = p*MAXD + c
    lea     rax, [rip + p_deps]
    mov     [rax + rdx * 8], rsi
    lea     rax, [rip + p_depcnt]
    inc     rcx
    mov     [rax + rdi * 8], rcx
    ret

# pkg_has_cycle() -> rax = 1 if a cycle exists, else 0.
# Kahn ready-scan: place any package whose deps are all placed; a full scan
# placing nothing leaves the remainder stuck ⇒ cycle.
pkg_has_cycle:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    lea     r15, [rip + p_n]
    mov     r15, [r15]                  # n

    # clear p_placed[0..n)
    xor     rcx, rcx
    lea     rax, [rip + p_placed]
.hc_clear:
    cmp     rcx, r15
    jge     .hc_clear_done
    mov     qword ptr [rax + rcx * 8], 0
    inc     rcx
    jmp     .hc_clear
.hc_clear_done:

    xor     r12, r12                    # placed = 0
.hc_outer:
    cmp     r12, r15
    jge     .hc_acyclic                 # placed == n ⇒ no cycle
    xor     r13, r13                    # progress = 0
    xor     rbx, rbx                    # p = 0
.hc_scan:
    cmp     rbx, r15
    jge     .hc_scan_done

    lea     rax, [rip + p_placed]
    mov     rax, [rax + rbx * 8]
    test    rax, rax
    jnz     .hc_next_p                  # already placed

    mov     r14, 1                      # ready = 1
    lea     rax, [rip + p_depcnt]
    mov     r8, [rax + rbx * 8]         # dc
    xor     r9, r9                      # k = 0
.hc_dep:
    cmp     r9, r8
    jge     .hc_dep_done
    mov     r10, rbx
    imul    r10, MAXD
    add     r10, r9
    lea     rax, [rip + p_deps]
    mov     r10, [rax + r10 * 8]        # d
    lea     rax, [rip + p_placed]
    mov     rax, [rax + r10 * 8]
    test    rax, rax
    jnz     .hc_dep_next
    xor     r14, r14                    # ready = 0
.hc_dep_next:
    inc     r9
    jmp     .hc_dep
.hc_dep_done:

    test    r14, r14
    jz      .hc_next_p
    # place p
    lea     rax, [rip + p_placed]
    mov     qword ptr [rax + rbx * 8], 1
    inc     r12
    mov     r13, 1
.hc_next_p:
    inc     rbx
    jmp     .hc_scan
.hc_scan_done:
    test    r13, r13
    jz      .hc_cycle                   # no progress ⇒ stuck ⇒ cycle
    jmp     .hc_outer
.hc_cycle:
    mov     rax, 1
    jmp     .hc_ret
.hc_acyclic:
    xor     rax, rax
.hc_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# ---- Test sequence (hardcoded, like build_systems/asm_x86_64.s) ----
# Backtrack candidate tables live in .data so we can pass their addresses.
.section .data
.align 8
a_vers:     .quad 1100000, 1000000      # A 1.1.0, A 1.0.0
a_creq:     .quad 2000000, 1000000      # A 1.1.0 -> C^2.0.0, A 1.0.0 -> C^1.0.0

.section .text
_start:
    # ---- Semver ordering: sv(1,2,3) > sv(1,2,0) ----
    mov     rdi, 1
    mov     rsi, 2
    mov     rdx, 3
    call    sv
    mov     rbx, rax                    # sv(1,2,3)
    mov     rdi, 1
    mov     rsi, 2
    mov     rdx, 0
    call    sv                          # sv(1,2,0)
    cmp     rbx, rax
    jle     fail

    # sv(2,0,0) > sv(1,9,9)
    mov     rdi, 2
    xor     rsi, rsi
    xor     rdx, rdx
    call    sv
    mov     rbx, rax
    mov     rdi, 1
    mov     rsi, 9
    mov     rdx, 9
    call    sv
    cmp     rbx, rax
    jle     fail

    # sv_major(sv(1,5,2)) == 1
    mov     rdi, 1
    mov     rsi, 5
    mov     rdx, 2
    call    sv
    mov     rdi, rax
    call    sv_major
    cmp     rax, 1
    jne     fail

    # ---- Caret: caret_hi(1.2.0) == 2000000 ----
    mov     rdi, 1200000
    call    caret_hi
    cmp     rax, 2000000
    jne     fail

    # satisfies(1.4.0, ^1.2.0) == 1   [lo=1200000, hi=2000000]
    mov     rdi, 1400000
    mov     rsi, 1200000
    mov     rdx, 2000000
    call    satisfies
    cmp     rax, 1
    jne     fail

    # satisfies(2.0.0, ^1.2.0) == 0
    mov     rdi, 2000000
    mov     rsi, 1200000
    mov     rdx, 2000000
    call    satisfies
    test    rax, rax
    jnz     fail

    # satisfies(1.1.0, ^1.2.0) == 0
    mov     rdi, 1100000
    mov     rsi, 1200000
    mov     rdx, 2000000
    call    satisfies
    test    rax, rax
    jnz     fail

    # ---- Intersect: lo of (1.0.0, 1.3.0) == 1.3.0 ----
    mov     rdi, 1000000
    mov     rsi, 1003000
    call    range_lo_max
    cmp     rax, 1003000
    jne     fail

    # hi of (2.0.0, 3.0.0) == 2.0.0
    mov     rdi, 2000000
    mov     rsi, 3000000
    call    range_hi_min
    cmp     rax, 2000000
    jne     fail

    # ^1.0.0 ∩ ^2.0.0 empty (lo >= hi)
    mov     rdi, 1000000
    mov     rsi, 2000000
    call    intersect                   # rax = lo, rdx = hi
    cmp     rax, rdx
    jl      fail                        # must be empty (lo >= hi)

    # ---- best_match(C, ^1.0.0) == 1005000  [lo=1000000, hi=2000000] ----
    mov     rdi, 1000000
    mov     rsi, 2000000
    call    best_match
    cmp     rax, 1005000
    jne     fail

    # best_match(C, ^3.0.0) == -1  [lo=3000000, hi=4000000]
    mov     rdi, 3000000
    mov     rsi, 4000000
    call    best_match
    cmp     rax, -1
    jne     fail

    # ---- resolve_shared(^1.0.0, ^1.0.0) == 1005000 ----
    mov     rdi, 1000000
    mov     rsi, 1000000
    call    resolve_shared
    cmp     rax, 1005000
    jne     fail

    # resolve_shared(^1.0.0, ^2.0.0) == -1
    mov     rdi, 1000000
    mov     rsi, 2000000
    call    resolve_shared
    cmp     rax, -1
    jne     fail

    # ---- resolve_backtrack: chosen A == 1000000, chosen C == 1005000 ----
    lea     rdi, [rip + a_vers]
    lea     rsi, [rip + a_creq]
    mov     rdx, 2                       # an
    mov     rcx, 1000000                 # B requires C ^1.0.0
    call    resolve_backtrack            # rax = bestA
    cmp     rax, 1000000
    jne     fail
    lea     rax, [rip + g_chosen_c]
    mov     rax, [rax]
    cmp     rax, 1005000
    jne     fail

    # ---- Cycle: A->B, B->A ⇒ cycle ----
    mov     rdi, 2
    call    pkg_reset
    mov     rdi, 0
    mov     rsi, 1
    call    pkg_add_dep
    mov     rdi, 1
    mov     rsi, 0
    call    pkg_add_dep
    call    pkg_has_cycle
    cmp     rax, 1
    jne     fail

    # app->A, app->B (2=app deps [0,1]) ⇒ no cycle
    mov     rdi, 3
    call    pkg_reset
    mov     rdi, 2
    mov     rsi, 0
    call    pkg_add_dep
    mov     rdi, 2
    mov     rsi, 1
    call    pkg_add_dep
    call    pkg_has_cycle
    test    rax, rax
    jnz     fail

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
