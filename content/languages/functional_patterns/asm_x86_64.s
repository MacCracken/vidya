# Vidya — Functional Patterns in x86_64 Assembly
#
# Pure functions and memoization, compose and pipe, closures and partial
# application, what a closure captures, a persistent cons list that shares
# structure instead of copying, folds as its recursion scheme, and a tail
# call written by hand as a jmp. Mirrors all 47 checks of cyrius.cyr.
#
# A closure is a 16-byte pair [code, env] in memory. Calling one loads the
# env into rdi and makes an indirect `call [pair]`; the code takes its
# arguments in rsi, rdx, rcx. A closure that captures nothing is a static
# pair with env 0. Pairs, envs and cons cells come from a bump arena in
# .bss that never frees, and a list's identity is its node's address.

.intel_syntax noprefix
.global _start

.equ MEMO_CAP, 8
.equ HEAP_SIZE, 16384

# CHECK cc, "name": after a cmp or test, carry on if condition cc holds,
# else print "FAIL: name" and exit 1.
.macro CHECK cc, msg
    j\cc    .Lok\@
    .pushsection .rodata
.Lmsg\@: .ascii "\msg"
.Lend\@:
    .popsection
    lea     rsi, [rip + .Lmsg\@]
    mov     edx, .Lend\@ - .Lmsg\@
    jmp     fail
.Lok\@:
.endm

# CALLC reg: call the closure whose pair address is in reg (not rdi): env
# into rdi, then an indirect call through the code pointer.
.macro CALLC reg
    mov     rdi, [\reg + 8]
    call    qword ptr [\reg]
.endm

.section .bss
.align 8
heap:          .skip HEAP_SIZE
heap_top:      .skip 8
g_counter:     .skip 8          # hidden state impure_next reads and bumps
g_add_calls:   .skip 8          # counted_add's calls: the memo test's probe
g_cons_allocs: .skip 8          # nodes allocated, so checks can count copying
j_var:         .skip 8          # the one loop variable the by-address closures share
base_var:      .skip 8
by_value:      .skip 8 * 3      # section 4: closures by value
by_address:    .skip 8 * 3      # section 4: closures by address

.section .data
.align 8
# Closures that capture nothing: [code, env = 0], nothing allocated.
clo_counted_add: .quad counted_add_code, 0
clo_add_three:   .quad add_three_code, 0
clo_times_two:   .quad times_two_code, 0
clo_add3:        .quad add3_code, 0
clo_len_step:    .quad len_step_code, 0
clo_sum_step:    .quad sum_step_code, 0
clo_rev_step:    .quad rev_step_code, 0
clo_sub:         .quad sub_code, 0
clo_times_ten:   .quad times_ten_code, 0

.section .rodata
msg_pass:     .ascii "All functional pattern examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:     .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_oom:      .ascii "arena exhausted"
msg_oom_len = . - msg_oom
msg_nl:       .ascii "\n"

.section .text

# alloc(rdi = bytes, a multiple of 8) -> rax. A bump allocator: nothing is
# freed, so no version of a list can free a node another version shares.
# Clobbers rcx, rdx.
alloc:
    mov     rax, [rip + heap_top]
    lea     rdx, [rax + rdi]
    lea     rcx, [rip + heap + HEAP_SIZE]
    cmp     rdx, rcx
    ja      .alloc_full
    mov     [rip + heap_top], rdx
    ret
.alloc_full:
    lea     rsi, [rip + msg_oom]
    mov     edx, msg_oom_len
    jmp     fail

# closure(rdi = code, rsi = env) -> rax = a new pair [code, env].
closure:
    push    rdi
    push    rsi
    mov     edi, 16
    call    alloc
    pop     rsi
    pop     rdi
    mov     [rax], rdi
    mov     [rax + 8], rsi
    ret

# ---------------------------------------------------------------------------
# --- 1. Purity ---
# A pure function's result depends only on its arguments, and calling it
# changes nothing. Assembly has no word for that and nothing checks it:
# pure_add is pure because it reads only its argument registers and writes
# only rax, which the reader verifies, not the assembler. impure_next reads
# and writes memory that outlives the call.
pure_add:                       # (rdi = a, rsi = b) -> a + b
    lea     rax, [rdi + rsi]
    ret

impure_next:                    # () -> ++g_counter
    mov     rax, [rip + g_counter]
    inc     rax
    mov     [rip + g_counter], rax
    ret

# counted_add is pure_add plus a call counter. Its last act is a jmp into
# pure_add, a tail call: pure_add's ret returns straight to our caller.
counted_add_code:               # (rdi = env, rsi = a, rdx = b)
    inc     qword ptr [rip + g_add_calls]
    mov     rdi, rsi
    mov     rsi, rdx
    jmp     pure_add

# memoize2(rdi = f) -> rax = a closure with f's call shape that owns its
# table. Env: [f, n, then MEMO_CAP entries of (a, b, value)]. The key is
# BOTH arguments; a key of `a` alone would hand (2, 4) the result cached
# for (2, 3). Sound only for a pure f: a cached result must be what a
# fresh call would return.
memoize2:
    push    rbx
    mov     rbx, rdi
    mov     edi, 16 + MEMO_CAP * 24
    call    alloc
    mov     [rax], rbx                  # env.f
    mov     qword ptr [rax + 8], 0      # env.n
    lea     rdi, [rip + memo_code]
    mov     rsi, rax
    call    closure
    pop     rbx
    ret

memo_code:                      # (rdi = env, rsi = a, rdx = b)
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi                    # env
    mov     r12, rsi                    # a
    mov     r13, rdx                    # b
    mov     rcx, [rbx + 8]              # n
    lea     r8, [rbx + 16]              # entry 0
    xor     r9, r9                      # i
.memo_scan:
    cmp     r9, rcx
    jge     .memo_miss
    cmp     [r8], r12
    jne     .memo_next
    cmp     [r8 + 8], r13
    jne     .memo_next
    mov     rax, [r8 + 16]              # hit: the cached value
    jmp     .memo_ret
.memo_next:
    add     r8, 24
    inc     r9
    jmp     .memo_scan
.memo_miss:
    mov     r8, [rbx]                   # f
    mov     rsi, r12
    mov     rdx, r13
    CALLC   r8                          # rax = f(a, b)
    mov     rcx, [rbx + 8]
    cmp     rcx, MEMO_CAP
    jge     .memo_ret                   # table full: return it uncached
    imul    r8, rcx, 24
    lea     r8, [rbx + 16 + r8]
    mov     [r8], r12
    mov     [r8 + 8], r13
    mov     [r8 + 16], rax
    inc     rcx
    mov     [rbx + 8], rcx
.memo_ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

# ---------------------------------------------------------------------------
# --- 2. Higher-order functions and composition ---
# compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
# pipe(f, g)(x)    = g(f(x))   (left to right, reading order)
add_three_code:                 # (rsi = x) -> x + 3
    lea     rax, [rsi + 3]
    ret

times_two_code:                 # (rsi = x) -> x * 2
    lea     rax, [rsi + rsi]
    ret

# pair_env(rdi = code, rsi = f, rdx = g) -> rax = closure with env [f, g]
pair_env:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     edi, 16
    call    alloc
    mov     [rax], r12
    mov     [rax + 8], r13
    mov     rdi, rbx
    mov     rsi, rax
    call    closure
    pop     r13
    pop     r12
    pop     rbx
    ret

compose:                        # (rdi = f, rsi = g) -> closure
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + compose_code]
    jmp     pair_env

pipe:                           # (rdi = f, rsi = g) -> closure
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + pipe_code]
    jmp     pair_env

compose_code:                   # (rdi = env [f, g], rsi = x) -> f(g(x))
    push    rbx
    mov     rbx, rdi
    mov     r8, [rbx + 8]               # g
    CALLC   r8                          # rax = g(x)
    mov     rsi, rax
    mov     r8, [rbx]                   # f
    CALLC   r8
    pop     rbx
    ret

pipe_code:                      # (rdi = env [f, g], rsi = x) -> g(f(x))
    push    rbx
    mov     rbx, rdi
    mov     r8, [rbx]                   # f
    CALLC   r8                          # rax = f(x)
    mov     rsi, rax
    mov     r8, [rbx + 8]               # g
    CALLC   r8
    pop     rbx
    ret

# ---------------------------------------------------------------------------
# --- 3. Closures and partial application ---
# make_adder(n) copies n into a fresh env. A counter's private state is its
# env, written in place; each make_counter() allocates a new one, so two
# counters never share a count.
make_adder:                     # (rdi = n) -> closure with env [n]
    push    rbx
    mov     rbx, rdi
    mov     edi, 8
    call    alloc
    mov     [rax], rbx
    lea     rdi, [rip + adder_code]
    mov     rsi, rax
    call    closure
    pop     rbx
    ret

adder_code:                     # (rdi = env [n], rsi = x) -> x + n
    mov     rax, [rdi]
    add     rax, rsi
    ret

make_counter:                   # () -> closure with env [count = 0]
    mov     edi, 8
    call    alloc
    mov     qword ptr [rax], 0
    lea     rdi, [rip + counter_code]
    mov     rsi, rax
    jmp     closure

counter_code:                   # (rdi = env [count]) -> ++count
    mov     rax, [rdi]
    inc     rax
    mov     [rdi], rax
    ret

# partial(f, a, b) fixes the first two arguments of a 3-argument closure
# and returns a 1-argument one. partial_code ends in a jmp through f's code
# pointer: f returns straight to whoever called the partial.
add3_code:                      # (rsi = a, rdx = b, rcx = c) -> a + b + c
    lea     rax, [rsi + rdx]
    add     rax, rcx
    ret

partial:                        # (rdi = f, rsi = a, rdx = b) -> closure
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     edi, 24
    call    alloc
    mov     [rax], rbx                  # env [f, a, b]
    mov     [rax + 8], r12
    mov     [rax + 16], r13
    lea     rdi, [rip + partial_code]
    mov     rsi, rax
    call    closure
    pop     r13
    pop     r12
    pop     rbx
    ret

partial_code:                   # (rdi = env [f, a, b], rsi = c) -> f(a, b, c)
    mov     rcx, rsi
    mov     rsi, [rdi + 8]
    mov     rdx, [rdi + 16]
    mov     r8, [rdi]
    mov     rdi, [r8 + 8]
    jmp     qword ptr [r8]

# ---------------------------------------------------------------------------
# --- 4. The capture gotcha (what a closure sees of a loop variable) ---
# Python's `[lambda: i for i in range(3)]` gives [2, 2, 2] and a JS `var`
# loop [3, 3, 3]: those closures look the variable up when CALLED. Here
# both kinds of closure run the same one instruction, load_env_code, and
# differ only in what their env points at: a private copy made when the
# closure was built (early binding), or the variable itself (late binding).
load_env_code:                  # (rdi = env) -> [env]
    mov     rax, [rdi]
    ret

capture_value:                  # (rdi = v) -> closure over a copy of v
    push    rbx
    mov     rbx, rdi
    mov     edi, 8
    call    alloc
    mov     [rax], rbx
    lea     rdi, [rip + load_env_code]
    mov     rsi, rax
    call    closure
    pop     rbx
    ret

capture_address:                # (rdi = &var) -> closure whose env IS &var
    mov     rsi, rdi
    lea     rdi, [rip + load_env_code]
    jmp     closure

# ---------------------------------------------------------------------------
# --- 5. Persistent (immutable) list with structural sharing ---
# A cons cell is 16 bytes, [head, tail]; 0 is the empty list. cons never
# copies its tail, so prepending is O(1) and the old list is still a whole,
# unchanged list. No memory is read-only here: a list stays persistent only
# because no code writes a node once others can see it.
cons:                           # (rdi = h, rsi = t) -> rax = node
    push    rdi
    push    rsi
    mov     edi, 16
    call    alloc
    pop     rsi
    pop     rdi
    mov     [rax], rdi
    mov     [rax + 8], rsi
    inc     qword ptr [rip + g_cons_allocs]
    ret

list3:                          # (rdi = a, rsi = b, rdx = c) -> [a, b, c]
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rdx
    xor     esi, esi
    call    cons                        # [c]
    mov     rdi, r12
    mov     rsi, rax
    call    cons                        # [b, c]
    mov     rdi, rbx
    mov     rsi, rax
    pop     r12
    pop     rbx
    jmp     cons                        # [a, b, c]

nth:                            # (rdi = xs, rsi = i) -> head after i tails
    test    rsi, rsi
    jz      .nth_done
    mov     rdi, [rdi + 8]
    dec     rsi
    jmp     nth
.nth_done:
    mov     rax, [rdi]
    ret

# list_eq(rdi = a, rsi = b) -> 1 if the same values in the same order
# (structural equality: not the same nodes), else 0.
list_eq:
    test    rdi, rdi
    jz      .leq_a_end
    test    rsi, rsi
    jz      .leq_no
    mov     rax, [rdi]
    cmp     rax, [rsi]
    jne     .leq_no
    mov     rdi, [rdi + 8]
    mov     rsi, [rsi + 8]
    jmp     list_eq
.leq_a_end:
    test    rsi, rsi
    jnz     .leq_no
    mov     eax, 1
    ret
.leq_no:
    xor     eax, eax
    ret

# update_at(rdi = xs, rsi = i, rdx = v) -> a new list with element i
# replaced. It copies the i cells in front of i plus the replaced cell
# (i + 1 allocations) and shares everything after it.
update_at:
    test    rdi, rdi
    jz      .ua_nil
    test    rsi, rsi
    jnz     .ua_rec
    mov     rsi, [rdi + 8]              # cons(v, tail(xs))
    mov     rdi, rdx
    jmp     cons
.ua_rec:
    push    rbx
    mov     rbx, [rdi]                  # head(xs)
    mov     rdi, [rdi + 8]
    dec     rsi
    call    update_at                   # rest = update_at(tail(xs), i - 1, v)
    mov     rdi, rbx
    mov     rsi, rax
    pop     rbx
    jmp     cons                        # cons(head(xs), rest)
.ua_nil:
    xor     eax, eax
    ret

# ---------------------------------------------------------------------------
# --- 6. Fold as the recursion scheme ---
# foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
# foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
# Both call the combiner closure indirectly: foldl as f(acc, x), foldr as
# f(x, acc).
foldr:                          # (rdi = f, rsi = z, rdx = xs)
    test    rdx, rdx
    jnz     .fr_rec
    mov     rax, rsi
    ret
.fr_rec:
    push    rbx
    push    r12
    mov     rbx, rdi                    # f
    mov     r12, [rdx]                  # x = head(xs)
    mov     rdx, [rdx + 8]
    call    foldr                       # rax = foldr(f, z, tail(xs))
    mov     rsi, r12
    mov     rdx, rax
    CALLC   rbx                         # f(x, acc)
    pop     r12
    pop     rbx
    ret

foldl:                          # (rdi = f, rsi = z, rdx = xs)
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi                    # f
    mov     r12, rsi                    # acc
    mov     r13, rdx                    # p
.fl_loop:
    test    r13, r13
    jz      .fl_done
    mov     rsi, r12
    mov     rdx, [r13]
    CALLC   rbx                         # acc = f(acc, x)
    mov     r12, rax
    mov     r13, [r13 + 8]
    jmp     .fl_loop
.fl_done:
    mov     rax, r12
    pop     r13
    pop     r12
    pop     rbx
    ret

len_step_code:                  # (rsi = acc, rdx = x) -> acc + 1
    lea     rax, [rsi + 1]
    ret

sum_step_code:                  # (rsi = acc, rdx = x) -> acc + x
    lea     rax, [rsi + rdx]
    ret

rev_step_code:                  # (rsi = acc, rdx = x) -> cons(x, acc)
    mov     rdi, rdx
    jmp     cons

sub_code:                       # (rsi = a, rdx = b) -> a - b
    mov     rax, rsi
    sub     rax, rdx
    ret

times_ten_code:                 # (rsi = x) -> x * 10
    imul    rax, rsi, 10
    ret

map_step_code:                  # (rdi = env [g], rsi = x, rdx = acc) -> cons(g(x), acc)
    push    rbx
    mov     rbx, rdx
    mov     r8, [rdi]
    CALLC   r8                          # rax = g(x)
    mov     rdi, rax
    mov     rsi, rbx
    pop     rbx
    jmp     cons

list_length:                    # (rdi = xs)
    mov     rdx, rdi
    xor     esi, esi
    lea     rdi, [rip + clo_len_step]
    jmp     foldl

list_sum:                       # (rdi = xs)
    mov     rdx, rdi
    xor     esi, esi
    lea     rdi, [rip + clo_sum_step]
    jmp     foldl

list_reverse:                   # (rdi = xs)
    mov     rdx, rdi
    xor     esi, esi
    lea     rdi, [rip + clo_rev_step]
    jmp     foldl

list_map:                       # (rdi = g, rsi = xs); the step captures g
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    mov     edi, 8
    call    alloc
    mov     [rax], rbx
    lea     rdi, [rip + map_step_code]
    mov     rsi, rax
    call    closure
    mov     rdi, rax
    xor     esi, esi
    mov     rdx, r12
    pop     r12
    pop     rbx
    jmp     foldr

# ---------------------------------------------------------------------------
# --- 7. Tail recursion and stack depth ---
# sum_to_tail is the recursion `return sum_to_tail(n - 1, acc + n)` with
# the call made by hand the way tail-call elimination compiles it: rewrite
# the argument registers in place and jmp to the function's entry. No
# return address is pushed, so the stack never grows; at the machine level
# a self tail call and a loop are the same jump. Written with `call`, each
# level would push 8 bytes of return address: 800 KB at 100,000 levels,
# and 80 MB at 10,000,000, about ten times the default 8 MiB stack.
sum_to_loop:                    # (rdi = n) -> 1 + 2 + ... + n
    xor     eax, eax
    mov     ecx, 1
.stl_loop:
    cmp     rcx, rdi
    jg      .stl_done
    add     rax, rcx
    inc     rcx
    jmp     .stl_loop
.stl_done:
    ret

sum_to_tail:                    # (rdi = n, rsi = acc) -> acc + 1 + ... + n
    test    rdi, rdi
    jnz     .stt_step
    mov     rax, rsi
    ret
.stt_step:
    add     rsi, rdi                    # acc + n
    dec     rdi                         # n - 1
    jmp     sum_to_tail                 # the tail call

# ===========================================================================
# === Tests ===

test_purity:
    push    rbx
    mov     edi, 2
    mov     esi, 3
    call    pure_add
    mov     rbx, rax                    # r1
    mov     edi, 2
    mov     esi, 3
    call    pure_add                    # r2
    cmp     rbx, rax
    CHECK   e, "pure_add: same arguments, same result"
    cmp     rbx, 5
    CHECK   e, "pure_add(2, 3) = 5"

    mov     qword ptr [rip + g_counter], 0
    call    impure_next
    mov     rbx, rax                    # n1
    call    impure_next                 # n2
    cmp     rbx, rax
    CHECK   ne, "impure_next: same call, different results (1, then 2)"
    cmp     qword ptr [rip + g_counter], 2
    CHECK   e, "impure_next left a trace: hidden state bumped twice"
    pop     rbx
    ret

test_memoize:
    push    rbx
    mov     qword ptr [rip + g_add_calls], 0
    lea     rdi, [rip + clo_counted_add]
    call    memoize2
    mov     rbx, rax                    # madd
    mov     esi, 2
    mov     edx, 3
    CALLC   rbx
    cmp     rax, 5
    CHECK   e, "memo: first call computes 2 + 3 = 5"
    mov     esi, 2
    mov     edx, 3
    CALLC   rbx
    cmp     rax, 5
    CHECK   e, "memo: second call returns the cached 5"
    cmp     qword ptr [rip + g_add_calls], 1
    CHECK   e, "memo: second call is a cache hit (1 call, not 2)"
    mov     esi, 2
    mov     edx, 4
    CALLC   rbx
    cmp     rax, 6
    CHECK   e, "memo: (2, 4) is a miss, the key is both arguments"
    cmp     qword ptr [rip + g_add_calls], 2
    CHECK   e, "memo: the miss ran the underlying fn once more"
    pop     rbx
    ret

test_composition:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    lea     rdi, [rip + clo_add_three]
    lea     rsi, [rip + clo_times_two]
    call    compose
    mov     rbx, rax                    # c = compose(f, g)
    lea     rdi, [rip + clo_add_three]
    lea     rsi, [rip + clo_times_two]
    call    pipe
    mov     r12, rax                    # p = pipe(f, g)

    mov     esi, 1
    CALLC   rbx
    mov     r13, rax                    # c(1)
    cmp     rax, 5
    CHECK   e, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5"
    mov     esi, 1
    CALLC   r12                         # p(1)
    cmp     rax, 8
    CHECK   e, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8"
    cmp     r13, rax
    CHECK   ne, "order matters: compose != pipe at x = 1"

    # The laws, over a range of x: compose applies g first, and pipe is
    # compose with its arguments swapped. Each law is one check for the
    # whole range, as in the reference.
    lea     rdi, [rip + clo_times_two]
    lea     rsi, [rip + clo_add_three]
    call    compose
    mov     r13, rax                    # cgf = compose(g, f)
    mov     r14, -2                     # x
    xor     r15d, r15d                  # failures: bit 0 compose law, bit 1 pipe law
.law_loop:
    cmp     r14, 2
    jg      .law_done
    mov     rsi, r14
    call    times_two_code
    mov     rsi, rax
    call    add_three_code
    mov     rbp, rax                    # f(g(x)), the two called directly
    mov     rsi, r14
    CALLC   rbx                         # compose(f, g)(x)
    cmp     rax, rbp
    je      .law_c_ok
    or      r15, 1
.law_c_ok:
    mov     rsi, r14
    CALLC   r13
    mov     rbp, rax                    # compose(g, f)(x)
    mov     rsi, r14
    CALLC   r12                         # pipe(f, g)(x)
    cmp     rax, rbp
    je      .law_p_ok
    or      r15, 2
.law_p_ok:
    inc     r14
    jmp     .law_loop
.law_done:
    test    r15, 1
    CHECK   z, "compose(f, g)(x) == f(g(x)) for x in -2..2"
    test    r15, 2
    CHECK   z, "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2"
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

test_closures:
    push    rbx
    push    r12
    mov     edi, 5
    call    make_adder
    mov     rbx, rax                    # add5
    mov     edi, 10
    call    make_adder
    mov     r12, rax                    # add10
    mov     esi, 1
    CALLC   rbx
    cmp     rax, 6
    CHECK   e, "make_adder(5)(1) = 6"
    mov     esi, 1
    CALLC   r12
    cmp     rax, 11
    CHECK   e, "make_adder(10)(1) = 11: each adder keeps its own n"

    call    make_counter
    mov     rbx, rax                    # c1
    call    make_counter
    mov     r12, rax                    # c2
    CALLC   rbx
    CALLC   rbx
    CALLC   rbx
    cmp     rax, 3
    CHECK   e, "counter 1 counted 1, 2, 3"
    CALLC   r12
    cmp     rax, 1
    CHECK   e, "counter 2 starts at 1: its state is its own"
    CALLC   rbx
    cmp     rax, 4
    CHECK   e, "counter 1 carries on at 4, untouched by counter 2"

    lea     rdi, [rip + clo_add3]
    mov     esi, 1
    mov     edx, 2
    call    partial
    mov     rbx, rax
    mov     esi, 3
    CALLC   rbx
    cmp     rax, 6
    CHECK   e, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6"
    pop     r12
    pop     rbx
    ret

test_capture:
    push    rbx
    push    r12
    # By value: each closure copies i as it was when the closure was built.
    xor     ebx, ebx                    # i
.cv_loop:
    cmp     rbx, 3
    jge     .cv_done
    mov     rdi, rbx
    call    capture_value
    lea     rcx, [rip + by_value]
    mov     [rcx + rbx * 8], rax
    inc     rbx
    jmp     .cv_loop
.cv_done:
    mov     rbx, [rip + by_value + 0]
    CALLC   rbx
    cmp     rax, 0
    CHECK   e, "by value: closure 0 returns 0"
    mov     rbx, [rip + by_value + 8]
    CALLC   rbx
    cmp     rax, 1
    CHECK   e, "by value: closure 1 returns 1"
    mov     rbx, [rip + by_value + 16]
    CALLC   rbx
    cmp     rax, 2
    CHECK   e, "by value: closure 2 returns 2"

    # Early binding: a later assignment is not seen.
    mov     qword ptr [rip + base_var], 1
    mov     rdi, [rip + base_var]
    call    capture_value
    mov     rbx, rax                    # g
    mov     qword ptr [rip + base_var], 99
    CALLC   rbx
    cmp     rax, 1
    CHECK   e, "by value: captured 1, the later base = 99 is not seen"

    # Late binding on purpose: every env is the address of the one j, read
    # when called, after the loop left it at 3: the JS `var` result. The
    # fix is to capture the value.
    mov     qword ptr [rip + j_var], 0
.cr_loop:
    mov     rbx, [rip + j_var]
    cmp     rbx, 3
    jge     .cr_done
    lea     rdi, [rip + j_var]
    call    capture_address
    lea     rcx, [rip + by_address]
    mov     [rcx + rbx * 8], rax
    inc     qword ptr [rip + j_var]
    jmp     .cr_loop
.cr_done:
    mov     rbx, [rip + by_address + 0]
    CALLC   rbx
    cmp     rax, 3
    CHECK   e, "by address: closure 0 sees j's final 3"
    mov     rbx, [rip + by_address + 8]
    CALLC   rbx
    cmp     rax, 3
    CHECK   e, "by address: closure 1 sees j's final 3"
    mov     rbx, [rip + by_address + 16]
    CALLC   rbx
    cmp     rax, 3
    CHECK   e, "by address: closure 2 sees j's final 3"
    pop     r12
    pop     rbx
    ret

# expect_list3(rdi = list, rsi = a, rdx = b, rcx = c) -> rax = list_eq(list, [a, b, c])
expect_list3:
    push    rbx
    mov     rbx, rdi
    mov     rdi, rsi
    mov     rsi, rdx
    mov     rdx, rcx
    call    list3
    mov     rdi, rbx
    mov     rsi, rax
    pop     rbx
    jmp     list_eq

test_persistent_list:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    call    list3
    mov     rbx, rax                    # xs = [1, 2, 3]
    xor     edi, edi
    mov     rsi, rbx
    call    cons
    mov     r12, rax                    # ys = cons(0, xs)
    cmp     [r12 + 8], rbx
    CHECK   e, "cons shares: tail(ys) IS xs, the same node"
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    call    list3
    xor     edi, edi
    mov     rsi, rax
    call    cons                        # a fresh [0, 1, 2, 3]
    mov     rdi, r12
    mov     rsi, rax
    call    list_eq
    cmp     rax, 1
    CHECK   e, "ys reads [0, 1, 2, 3]"
    mov     rdi, rbx
    mov     esi, 1
    mov     edx, 2
    mov     ecx, 3
    call    expect_list3
    cmp     rax, 1
    CHECK   e, "xs still reads [1, 2, 3] after the cons"

    mov     r14, [rip + g_cons_allocs]  # before
    mov     rdi, rbx
    mov     esi, 1
    mov     edx, 20
    call    update_at
    mov     r13, rax                    # zs = update_at(xs, 1, 20)
    mov     rax, [rip + g_cons_allocs]
    sub     rax, r14
    cmp     rax, 2
    CHECK   e, "update at index 1 allocates i + 1 = 2 nodes, not 3"
    mov     rdi, r13
    mov     esi, 1
    mov     edx, 20
    mov     ecx, 3
    call    expect_list3
    cmp     rax, 1
    CHECK   e, "zs reads [1, 20, 3]"
    mov     rax, [r13 + 8]
    mov     rax, [rax + 8]              # tail(tail(zs))
    mov     rcx, [rbx + 8]
    mov     rcx, [rcx + 8]              # tail(tail(xs))
    cmp     rax, rcx
    CHECK   e, "the suffix after the updated cell is shared"
    mov     rax, [r13 + 8]
    cmp     rax, [rbx + 8]
    CHECK   ne, "the updated cell is new, not xs's"
    mov     rdi, rbx
    mov     esi, 1
    mov     edx, 2
    mov     ecx, 3
    call    expect_list3
    cmp     rax, 1
    CHECK   e, "xs still reads [1, 2, 3] after the update"

    # The gotcha: write through a node two versions share and both change.
    # Nothing stops this mov; persistence is a rule the code keeps.
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    call    list3
    mov     r14, rax                    # vs = [1, 2, 3]
    mov     rdi, r14
    xor     esi, esi
    mov     edx, 7
    call    update_at
    mov     r15, rax                    # ws = [7, 2, 3], shares vs's [2, 3]
    mov     rax, [r14 + 8]
    mov     qword ptr [rax], 99         # in-place write to the shared cell
    mov     rdi, r15
    mov     esi, 1
    call    nth
    cmp     rax, 99
    CHECK   e, "a write through a shared node changes the other version too"
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

test_folds:
    push    rbx
    push    r12
    mov     edi, 1
    mov     esi, 2
    mov     edx, 3
    call    list3
    mov     rbx, rax                    # xs = [1, 2, 3]
    mov     rdi, rbx
    call    list_length
    cmp     rax, 3
    CHECK   e, "length via foldl = 3"
    xor     edi, edi
    call    list_length
    cmp     rax, 0
    CHECK   e, "length of the empty list = 0"
    mov     rdi, rbx
    call    list_sum
    cmp     rax, 6
    CHECK   e, "sum via foldl = 1 + 2 + 3 = 6"
    mov     rdi, rbx
    call    list_reverse
    mov     rdi, rax
    mov     esi, 3
    mov     edx, 2
    mov     ecx, 1
    call    expect_list3
    cmp     rax, 1
    CHECK   e, "reverse via foldl = [3, 2, 1]"
    lea     rdi, [rip + clo_times_ten]
    mov     rsi, rbx
    call    list_map
    mov     rdi, rax
    mov     esi, 10
    mov     edx, 20
    mov     ecx, 30
    call    expect_list3
    cmp     rax, 1
    CHECK   e, "map via foldr keeps order: [10, 20, 30]"
    mov     rdi, rbx
    mov     esi, 1
    mov     edx, 2
    mov     ecx, 3
    call    expect_list3
    cmp     rax, 1
    CHECK   e, "the folds left xs as [1, 2, 3]"

    # Subtraction is not associative, so the fold's direction shows.
    lea     rdi, [rip + clo_sub]
    xor     esi, esi
    mov     rdx, rbx
    call    foldl
    cmp     rax, -6
    CHECK   e, "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6"
    lea     rdi, [rip + clo_sub]
    xor     esi, esi
    mov     rdx, rbx
    call    foldr
    cmp     rax, 2
    CHECK   e, "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2"
    pop     r12
    pop     rbx
    ret

test_tail_calls:
    mov     edi, 100000
    call    sum_to_loop
    mov     rcx, 5000050000
    cmp     rax, rcx
    CHECK   e, "accumulator loop: sum 1..100000 = 5000050000"
    mov     edi, 100000
    xor     esi, esi
    call    sum_to_tail
    mov     rcx, 5000050000
    cmp     rax, rcx
    CHECK   e, "tail call: sum 1..100000 = 5000050000"
    # 10,000,000 levels as real calls would need 80 MB of stack, so
    # finishing at all shows each level was a jump. n(n + 1) / 2.
    mov     edi, 10000000
    xor     esi, esi
    call    sum_to_tail
    mov     rcx, 50000005000000
    cmp     rax, rcx
    CHECK   e, "tail call 10,000,000 deep runs in constant stack"
    ret

_start:
    lea     rax, [rip + heap]
    mov     [rip + heap_top], rax
    call    test_purity
    call    test_memoize
    call    test_composition
    call    test_closures
    call    test_capture
    call    test_persistent_list
    call    test_folds
    call    test_tail_calls

    mov     eax, 1
    mov     edi, 1
    lea     rsi, [rip + msg_pass]
    mov     edx, msg_pass_len
    syscall
    mov     eax, 60
    xor     edi, edi
    syscall

# fail(rsi = name, rdx = length): "FAIL: name\n" on stderr, exit 1.
fail:
    mov     r12, rsi
    mov     r13, rdx
    mov     eax, 1
    mov     edi, 2
    lea     rsi, [rip + msg_fail]
    mov     edx, msg_fail_len
    syscall
    mov     eax, 1
    mov     edi, 2
    mov     rsi, r12
    mov     rdx, r13
    syscall
    mov     eax, 1
    mov     edi, 2
    lea     rsi, [rip + msg_nl]
    mov     edx, 1
    syscall
    mov     eax, 60
    mov     edi, 1
    syscall
