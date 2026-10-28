// Vidya — Functional Patterns in AArch64 Assembly
//
// Pure functions and memoization, compose and pipe, closures and partial
// application, what a closure captures, a persistent cons list that shares
// structure instead of copying, folds as its recursion scheme, and a tail
// call written by hand as a branch. Mirrors all 47 checks of cyrius.cyr.
//
// A closure is a 16-byte pair [code, env] in memory. Calling one loads the
// env into x0 and the code pointer into x16, then `blr x16`; the code takes
// its arguments in x1, x2, x3. A closure that captures nothing is a static
// pair with env 0. Pairs, envs and cons cells come from a bump arena in
// .bss that never frees, and a list's identity is its node's address.

.global _start

.equ MEMO_CAP, 8
.equ HEAP_SIZE, 16384

.macro LDADDR reg, sym
    adrp    \reg, \sym
    add     \reg, \reg, :lo12:\sym
.endm

// CHECK cc, "name": after a cmp or tst, carry on if condition cc holds,
// else print "FAIL: name" and exit 1.
.macro CHECK cc, msg
    b.\cc   .Lok\@
    .pushsection .rodata
.Lmsg\@: .ascii "\msg"
.Lend\@:
    .popsection
    LDADDR  x1, .Lmsg\@
    mov     x2, #(.Lend\@ - .Lmsg\@)
    b       fail
.Lok\@:
.endm

// CALLC reg: call the closure whose pair address is in reg (not x0 or
// x16): env into x0, code into x16, then an indirect branch-and-link.
.macro CALLC reg
    ldr     x0, [\reg, #8]
    ldr     x16, [\reg]
    blr     x16
.endm

.section .bss
.align 3
heap:          .skip HEAP_SIZE
heap_end:
heap_top:      .skip 8
g_counter:     .skip 8          // hidden state impure_next reads and bumps
g_add_calls:   .skip 8          // counted_add's calls: the memo test's probe
g_cons_allocs: .skip 8          // nodes allocated, so checks can count copying
j_var:         .skip 8          // the one loop variable the by-address closures share
base_var:      .skip 8
by_value:      .skip 8 * 3      // section 4: closures by value
by_address:    .skip 8 * 3      // section 4: closures by address

.section .data
.align 3
// Closures that capture nothing: [code, env = 0], nothing allocated.
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

// alloc(x0 = bytes, a multiple of 8) -> x0. A bump allocator: nothing is
// freed, so no version of a list can free a node another version shares.
// Clobbers x9-x12.
alloc:
    LDADDR  x9, heap_top
    ldr     x10, [x9]
    add     x11, x10, x0
    LDADDR  x12, heap_end
    cmp     x11, x12
    b.hi    .Lalloc_full
    str     x11, [x9]
    mov     x0, x10
    ret
.Lalloc_full:
    LDADDR  x1, msg_oom
    mov     x2, #msg_oom_len
    b       fail

// closure(x0 = code, x1 = env) -> x0 = a new pair [code, env].
closure:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x0, x1, [sp, #16]
    mov     x0, #16
    bl      alloc
    ldp     x9, x10, [sp, #16]
    stp     x9, x10, [x0]
    ldp     x29, x30, [sp], #32
    ret

// ---------------------------------------------------------------------------
// --- 1. Purity ---
// A pure function's result depends only on its arguments, and calling it
// changes nothing. Assembly has no word for that and nothing checks it:
// pure_add is pure because it reads only its argument registers and writes
// only x0, which the reader verifies, not the assembler. impure_next reads
// and writes memory that outlives the call.
pure_add:                       // (x0 = a, x1 = b) -> a + b
    add     x0, x0, x1
    ret

impure_next:                    // () -> ++g_counter
    LDADDR  x9, g_counter
    ldr     x0, [x9]
    add     x0, x0, #1
    str     x0, [x9]
    ret

// counted_add is pure_add plus a call counter. Its last act is a plain
// branch into pure_add, a tail call: x30 still holds our caller's return
// address, so pure_add's ret goes straight back there.
counted_add_code:               // (x0 = env, x1 = a, x2 = b)
    LDADDR  x9, g_add_calls
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    mov     x0, x1
    mov     x1, x2
    b       pure_add

// memoize2(x0 = f) -> x0 = a closure with f's call shape that owns its
// table. Env: [f, n, then MEMO_CAP entries of (a, b, value)]. The key is
// BOTH arguments; a key of `a` alone would hand (2, 4) the result cached
// for (2, 3). Sound only for a pure f: a cached result must be what a
// fresh call would return.
memoize2:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    mov     x0, #(16 + MEMO_CAP * 24)
    bl      alloc
    str     x19, [x0]                   // env.f
    str     xzr, [x0, #8]               // env.n
    mov     x1, x0
    LDADDR  x0, memo_code
    bl      closure
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

memo_code:                      // (x0 = env, x1 = a, x2 = b)
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x19, x0                     // env
    mov     x20, x1                     // a
    mov     x21, x2                     // b
    ldr     x9, [x19, #8]               // n
    add     x10, x19, #16               // entry 0
    mov     x11, #0                     // i
.Lmemo_scan:
    cmp     x11, x9
    b.ge    .Lmemo_miss
    ldr     x12, [x10]
    cmp     x12, x20
    b.ne    .Lmemo_next
    ldr     x12, [x10, #8]
    cmp     x12, x21
    b.ne    .Lmemo_next
    ldr     x0, [x10, #16]              // hit: the cached value
    b       .Lmemo_ret
.Lmemo_next:
    add     x10, x10, #24
    add     x11, x11, #1
    b       .Lmemo_scan
.Lmemo_miss:
    ldr     x8, [x19]                   // f
    mov     x1, x20
    mov     x2, x21
    CALLC   x8                          // x0 = f(a, b)
    ldr     x9, [x19, #8]
    cmp     x9, #MEMO_CAP
    b.ge    .Lmemo_ret                  // table full: return it uncached
    mov     x10, #24
    madd    x10, x9, x10, x19
    add     x10, x10, #16               // entry n
    stp     x20, x21, [x10]
    str     x0, [x10, #16]
    add     x9, x9, #1
    str     x9, [x19, #8]
.Lmemo_ret:
    ldp     x19, x20, [sp, #16]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// ---------------------------------------------------------------------------
// --- 2. Higher-order functions and composition ---
// compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
// pipe(f, g)(x)    = g(f(x))   (left to right, reading order)
add_three_code:                 // (x1 = x) -> x + 3
    add     x0, x1, #3
    ret

times_two_code:                 // (x1 = x) -> x * 2
    add     x0, x1, x1
    ret

// pair_env(x0 = code, x1 = f, x2 = g) -> x0 = closure with env [f, g]
pair_env:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, #16
    bl      alloc
    stp     x20, x21, [x0]
    mov     x1, x0
    mov     x0, x19
    bl      closure
    ldp     x19, x20, [sp, #16]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

compose:                        // (x0 = f, x1 = g) -> closure
    mov     x2, x1
    mov     x1, x0
    LDADDR  x0, compose_code
    b       pair_env

pipe:                           // (x0 = f, x1 = g) -> closure
    mov     x2, x1
    mov     x1, x0
    LDADDR  x0, pipe_code
    b       pair_env

compose_code:                   // (x0 = env [f, g], x1 = x) -> f(g(x))
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    ldr     x8, [x19, #8]               // g
    CALLC   x8                          // x0 = g(x)
    mov     x1, x0
    ldr     x8, [x19]                   // f
    CALLC   x8
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

pipe_code:                      // (x0 = env [f, g], x1 = x) -> g(f(x))
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    ldr     x8, [x19]                   // f
    CALLC   x8                          // x0 = f(x)
    mov     x1, x0
    ldr     x8, [x19, #8]               // g
    CALLC   x8
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// ---------------------------------------------------------------------------
// --- 3. Closures and partial application ---
// make_adder(n) copies n into a fresh env. A counter's private state is its
// env, written in place; each make_counter() allocates a new one, so two
// counters never share a count.
make_adder:                     // (x0 = n) -> closure with env [n]
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    mov     x0, #8
    bl      alloc
    str     x19, [x0]
    mov     x1, x0
    LDADDR  x0, adder_code
    bl      closure
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

adder_code:                     // (x0 = env [n], x1 = x) -> x + n
    ldr     x9, [x0]
    add     x0, x1, x9
    ret

make_counter:                   // () -> closure with env [count = 0]
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     x0, #8
    bl      alloc
    str     xzr, [x0]
    mov     x1, x0
    LDADDR  x0, counter_code
    ldp     x29, x30, [sp], #16
    b       closure

counter_code:                   // (x0 = env [count]) -> ++count
    ldr     x9, [x0]
    add     x9, x9, #1
    str     x9, [x0]
    mov     x0, x9
    ret

// partial(f, a, b) fixes the first two arguments of a 3-argument closure
// and returns a 1-argument one. partial_code ends in `br` through f's code
// pointer: f returns straight to whoever called the partial.
add3_code:                      // (x1 = a, x2 = b, x3 = c) -> a + b + c
    add     x0, x1, x2
    add     x0, x0, x3
    ret

partial:                        // (x0 = f, x1 = a, x2 = b) -> closure
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x0, #24
    bl      alloc
    str     x19, [x0]                   // env [f, a, b]
    stp     x20, x21, [x0, #8]
    mov     x1, x0
    LDADDR  x0, partial_code
    bl      closure
    ldp     x19, x20, [sp, #16]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

partial_code:                   // (x0 = env [f, a, b], x1 = c) -> f(a, b, c)
    mov     x3, x1
    ldr     x1, [x0, #8]
    ldr     x2, [x0, #16]
    ldr     x8, [x0]
    ldr     x0, [x8, #8]
    ldr     x16, [x8]
    br      x16

// ---------------------------------------------------------------------------
// --- 4. The capture gotcha (what a closure sees of a loop variable) ---
// Python's `[lambda: i for i in range(3)]` gives [2, 2, 2] and a JS `var`
// loop [3, 3, 3]: those closures look the variable up when CALLED. Here
// both kinds of closure run the same code, load_env_code, and differ only
// in what their env points at: a private copy made when the closure was
// built (early binding), or the variable itself (late binding).
load_env_code:                  // (x0 = env) -> [env]
    ldr     x0, [x0]
    ret

capture_value:                  // (x0 = v) -> closure over a copy of v
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    mov     x0, #8
    bl      alloc
    str     x19, [x0]
    mov     x1, x0
    LDADDR  x0, load_env_code
    bl      closure
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

capture_address:                // (x0 = &var) -> closure whose env IS &var
    mov     x1, x0
    LDADDR  x0, load_env_code
    b       closure

// ---------------------------------------------------------------------------
// --- 5. Persistent (immutable) list with structural sharing ---
// A cons cell is 16 bytes, [head, tail]; 0 is the empty list. cons never
// copies its tail, so prepending is O(1) and the old list is still a whole,
// unchanged list. No memory is read-only here: a list stays persistent only
// because no code writes a node once others can see it.
cons:                           // (x0 = h, x1 = t) -> x0 = node
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x0, x1, [sp, #16]
    mov     x0, #16
    bl      alloc
    ldp     x9, x10, [sp, #16]
    stp     x9, x10, [x0]
    LDADDR  x9, g_cons_allocs
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    ldp     x29, x30, [sp], #32
    ret

list3:                          // (x0 = a, x1 = b, x2 = c) -> [a, b, c]
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    mov     x0, x2
    mov     x1, #0
    bl      cons                        // [c]
    mov     x1, x0
    mov     x0, x20
    bl      cons                        // [b, c]
    mov     x1, x0
    mov     x0, x19
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    b       cons                        // [a, b, c]

nth:                            // (x0 = xs, x1 = i) -> head after i tails
    cbz     x1, .Lnth_done
    ldr     x0, [x0, #8]
    sub     x1, x1, #1
    b       nth
.Lnth_done:
    ldr     x0, [x0]
    ret

// list_eq(x0 = a, x1 = b) -> 1 if the same values in the same order
// (structural equality: not the same nodes), else 0.
list_eq:
    cbz     x0, .Lleq_a_end
    cbz     x1, .Lleq_no
    ldr     x9, [x0]
    ldr     x10, [x1]
    cmp     x9, x10
    b.ne    .Lleq_no
    ldr     x0, [x0, #8]
    ldr     x1, [x1, #8]
    b       list_eq
.Lleq_a_end:
    cbnz    x1, .Lleq_no
    mov     x0, #1
    ret
.Lleq_no:
    mov     x0, #0
    ret

// update_at(x0 = xs, x1 = i, x2 = v) -> a new list with element i
// replaced. It copies the i cells in front of i plus the replaced cell
// (i + 1 allocations) and shares everything after it.
update_at:
    cbz     x0, .Lua_nil
    cbnz    x1, .Lua_rec
    ldr     x1, [x0, #8]                // cons(v, tail(xs))
    mov     x0, x2
    b       cons
.Lua_rec:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    ldr     x19, [x0]                   // head(xs)
    ldr     x0, [x0, #8]
    sub     x1, x1, #1
    bl      update_at                   // rest = update_at(tail(xs), i - 1, v)
    mov     x1, x0
    mov     x0, x19
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    b       cons                        // cons(head(xs), rest)
.Lua_nil:
    mov     x0, #0
    ret

// ---------------------------------------------------------------------------
// --- 6. Fold as the recursion scheme ---
// foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
// foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
// Both call the combiner closure indirectly: foldl as f(acc, x), foldr as
// f(x, acc).
foldr:                          // (x0 = f, x1 = z, x2 = xs)
    cbnz    x2, .Lfr_rec
    mov     x0, x1
    ret
.Lfr_rec:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0                     // f
    ldr     x20, [x2]                   // x = head(xs)
    ldr     x2, [x2, #8]
    bl      foldr                       // x0 = foldr(f, z, tail(xs))
    mov     x2, x0
    mov     x1, x20
    CALLC   x19                         // f(x, acc)
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

foldl:                          // (x0 = f, x1 = z, x2 = xs)
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x19, x0                     // f
    mov     x20, x1                     // acc
    mov     x21, x2                     // p
.Lfl_loop:
    cbz     x21, .Lfl_done
    mov     x1, x20
    ldr     x2, [x21]
    CALLC   x19                         // acc = f(acc, x)
    mov     x20, x0
    ldr     x21, [x21, #8]
    b       .Lfl_loop
.Lfl_done:
    mov     x0, x20
    ldp     x19, x20, [sp, #16]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

len_step_code:                  // (x1 = acc, x2 = x) -> acc + 1
    add     x0, x1, #1
    ret

sum_step_code:                  // (x1 = acc, x2 = x) -> acc + x
    add     x0, x1, x2
    ret

rev_step_code:                  // (x1 = acc, x2 = x) -> cons(x, acc)
    mov     x0, x2
    b       cons

sub_code:                       // (x1 = a, x2 = b) -> a - b
    sub     x0, x1, x2
    ret

times_ten_code:                 // (x1 = x) -> x * 10
    mov     x9, #10
    mul     x0, x1, x9
    ret

map_step_code:                  // (x0 = env [g], x1 = x, x2 = acc) -> cons(g(x), acc)
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x2
    ldr     x8, [x0]
    CALLC   x8                          // x0 = g(x)
    mov     x1, x19
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    b       cons

list_length:                    // (x0 = xs)
    mov     x2, x0
    mov     x1, #0
    LDADDR  x0, clo_len_step
    b       foldl

list_sum:                       // (x0 = xs)
    mov     x2, x0
    mov     x1, #0
    LDADDR  x0, clo_sum_step
    b       foldl

list_reverse:                   // (x0 = xs)
    mov     x2, x0
    mov     x1, #0
    LDADDR  x0, clo_rev_step
    b       foldl

list_map:                       // (x0 = g, x1 = xs); the step captures g
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    mov     x0, #8
    bl      alloc
    str     x19, [x0]
    mov     x1, x0
    LDADDR  x0, map_step_code
    bl      closure
    mov     x1, #0
    mov     x2, x20
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    b       foldr

// ---------------------------------------------------------------------------
// --- 7. Tail recursion and stack depth ---
// sum_to_tail is the recursion `return sum_to_tail(n - 1, acc + n)` with
// the call made by hand the way tail-call elimination compiles it: rewrite
// the argument registers in place and branch to the function's entry with
// `b`, not `bl`. x30 is left alone and nothing is saved, so the stack never
// grows; at the machine level a self tail call and a loop are the same
// branch. Written with `bl`, each level would have to save its return
// address x30 (with x29, 16 bytes): 1.6 MB at 100,000 levels, and 160 MB
// at 10,000,000, about twenty times the default 8 MiB stack.
sum_to_loop:                    // (x0 = n) -> 1 + 2 + ... + n
    mov     x9, #0                      // acc
    mov     x10, #1                     // i
.Lstl_loop:
    cmp     x10, x0
    b.gt    .Lstl_done
    add     x9, x9, x10
    add     x10, x10, #1
    b       .Lstl_loop
.Lstl_done:
    mov     x0, x9
    ret

sum_to_tail:                    // (x0 = n, x1 = acc) -> acc + 1 + ... + n
    cbnz    x0, .Lstt_step
    mov     x0, x1
    ret
.Lstt_step:
    add     x1, x1, x0                  // acc + n
    sub     x0, x0, #1                  // n - 1
    b       sum_to_tail                 // the tail call

// ===========================================================================
// === Tests ===

test_purity:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x0, #2
    mov     x1, #3
    bl      pure_add
    mov     x19, x0                     // r1
    mov     x0, #2
    mov     x1, #3
    bl      pure_add                    // r2
    cmp     x19, x0
    CHECK   eq, "pure_add: same arguments, same result"
    cmp     x19, #5
    CHECK   eq, "pure_add(2, 3) = 5"

    LDADDR  x9, g_counter
    str     xzr, [x9]
    bl      impure_next
    mov     x19, x0                     // n1
    bl      impure_next                 // n2
    cmp     x19, x0
    CHECK   ne, "impure_next: same call, different results (1, then 2)"
    LDADDR  x9, g_counter
    ldr     x9, [x9]
    cmp     x9, #2
    CHECK   eq, "impure_next left a trace: hidden state bumped twice"
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

test_memoize:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    LDADDR  x20, g_add_calls
    str     xzr, [x20]
    LDADDR  x0, clo_counted_add
    bl      memoize2
    mov     x19, x0                     // madd
    mov     x1, #2
    mov     x2, #3
    CALLC   x19
    cmp     x0, #5
    CHECK   eq, "memo: first call computes 2 + 3 = 5"
    mov     x1, #2
    mov     x2, #3
    CALLC   x19
    cmp     x0, #5
    CHECK   eq, "memo: second call returns the cached 5"
    ldr     x9, [x20]
    cmp     x9, #1
    CHECK   eq, "memo: second call is a cache hit (1 call, not 2)"
    mov     x1, #2
    mov     x2, #4
    CALLC   x19
    cmp     x0, #6
    CHECK   eq, "memo: (2, 4) is a miss, the key is both arguments"
    ldr     x9, [x20]
    cmp     x9, #2
    CHECK   eq, "memo: the miss ran the underlying fn once more"
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

test_composition:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    LDADDR  x0, clo_add_three
    LDADDR  x1, clo_times_two
    bl      compose
    mov     x19, x0                     // c = compose(f, g)
    LDADDR  x0, clo_add_three
    LDADDR  x1, clo_times_two
    bl      pipe
    mov     x20, x0                     // p = pipe(f, g)

    mov     x1, #1
    CALLC   x19
    mov     x21, x0                     // c(1)
    cmp     x0, #5
    CHECK   eq, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5"
    mov     x1, #1
    CALLC   x20                         // p(1)
    cmp     x0, #8
    CHECK   eq, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8"
    cmp     x21, x0
    CHECK   ne, "order matters: compose != pipe at x = 1"

    // The laws, over a range of x: compose applies g first, and pipe is
    // compose with its arguments swapped. Each law is one check for the
    // whole range, as in the reference.
    LDADDR  x0, clo_times_two
    LDADDR  x1, clo_add_three
    bl      compose
    mov     x21, x0                     // cgf = compose(g, f)
    mov     x22, #-2                    // x
    mov     x23, #0                     // failures: bit 0 compose law, bit 1 pipe law
.Llaw_loop:
    cmp     x22, #2
    b.gt    .Llaw_done
    mov     x1, x22
    bl      times_two_code
    mov     x1, x0
    bl      add_three_code
    mov     x24, x0                     // f(g(x)), the two called directly
    mov     x1, x22
    CALLC   x19                         // compose(f, g)(x)
    cmp     x0, x24
    b.eq    .Llaw_c_ok
    orr     x23, x23, #1
.Llaw_c_ok:
    mov     x1, x22
    CALLC   x21
    mov     x24, x0                     // compose(g, f)(x)
    mov     x1, x22
    CALLC   x20                         // pipe(f, g)(x)
    cmp     x0, x24
    b.eq    .Llaw_p_ok
    orr     x23, x23, #2
.Llaw_p_ok:
    add     x22, x22, #1
    b       .Llaw_loop
.Llaw_done:
    tst     x23, #1
    CHECK   eq, "compose(f, g)(x) == f(g(x)) for x in -2..2"
    tst     x23, #2
    CHECK   eq, "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2"
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

test_closures:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x0, #5
    bl      make_adder
    mov     x19, x0                     // add5
    mov     x0, #10
    bl      make_adder
    mov     x20, x0                     // add10
    mov     x1, #1
    CALLC   x19
    cmp     x0, #6
    CHECK   eq, "make_adder(5)(1) = 6"
    mov     x1, #1
    CALLC   x20
    cmp     x0, #11
    CHECK   eq, "make_adder(10)(1) = 11: each adder keeps its own n"

    bl      make_counter
    mov     x19, x0                     // c1
    bl      make_counter
    mov     x20, x0                     // c2
    CALLC   x19
    CALLC   x19
    CALLC   x19
    cmp     x0, #3
    CHECK   eq, "counter 1 counted 1, 2, 3"
    CALLC   x20
    cmp     x0, #1
    CHECK   eq, "counter 2 starts at 1: its state is its own"
    CALLC   x19
    cmp     x0, #4
    CHECK   eq, "counter 1 carries on at 4, untouched by counter 2"

    LDADDR  x0, clo_add3
    mov     x1, #1
    mov     x2, #2
    bl      partial
    mov     x19, x0
    mov     x1, #3
    CALLC   x19
    cmp     x0, #6
    CHECK   eq, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6"
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

test_capture:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    // By value: each closure copies i as it was when the closure was built.
    LDADDR  x20, by_value
    mov     x19, #0                     // i
.Lcv_loop:
    cmp     x19, #3
    b.ge    .Lcv_done
    mov     x0, x19
    bl      capture_value
    str     x0, [x20, x19, lsl #3]
    add     x19, x19, #1
    b       .Lcv_loop
.Lcv_done:
    ldr     x21, [x20, #0]
    CALLC   x21
    cmp     x0, #0
    CHECK   eq, "by value: closure 0 returns 0"
    ldr     x21, [x20, #8]
    CALLC   x21
    cmp     x0, #1
    CHECK   eq, "by value: closure 1 returns 1"
    ldr     x21, [x20, #16]
    CALLC   x21
    cmp     x0, #2
    CHECK   eq, "by value: closure 2 returns 2"

    // Early binding: a later assignment is not seen.
    LDADDR  x20, base_var
    mov     x9, #1
    str     x9, [x20]
    ldr     x0, [x20]
    bl      capture_value
    mov     x21, x0                     // g
    mov     x9, #99
    str     x9, [x20]
    CALLC   x21
    cmp     x0, #1
    CHECK   eq, "by value: captured 1, the later base = 99 is not seen"

    // Late binding on purpose: every env is the address of the one j, read
    // when called, after the loop left it at 3: the JS `var` result. The
    // fix is to capture the value.
    LDADDR  x19, j_var
    LDADDR  x20, by_address
    str     xzr, [x19]
.Lcr_loop:
    ldr     x21, [x19]
    cmp     x21, #3
    b.ge    .Lcr_done
    mov     x0, x19
    bl      capture_address
    ldr     x21, [x19]
    str     x0, [x20, x21, lsl #3]
    add     x21, x21, #1
    str     x21, [x19]
    b       .Lcr_loop
.Lcr_done:
    ldr     x21, [x20, #0]
    CALLC   x21
    cmp     x0, #3
    CHECK   eq, "by address: closure 0 sees j's final 3"
    ldr     x21, [x20, #8]
    CALLC   x21
    cmp     x0, #3
    CHECK   eq, "by address: closure 1 sees j's final 3"
    ldr     x21, [x20, #16]
    CALLC   x21
    cmp     x0, #3
    CHECK   eq, "by address: closure 2 sees j's final 3"
    ldp     x19, x20, [sp, #16]
    ldr     x21, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

// expect_list3(x0 = list, x1 = a, x2 = b, x3 = c) -> x0 = list_eq(list, [a, b, c])
expect_list3:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x0
    mov     x0, x1
    mov     x1, x2
    mov     x2, x3
    bl      list3
    mov     x1, x0
    mov     x0, x19
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    b       list_eq

test_persistent_list:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x0, #1
    mov     x1, #2
    mov     x2, #3
    bl      list3
    mov     x19, x0                     // xs = [1, 2, 3]
    mov     x0, #0
    mov     x1, x19
    bl      cons
    mov     x20, x0                     // ys = cons(0, xs)
    ldr     x9, [x20, #8]
    cmp     x9, x19
    CHECK   eq, "cons shares: tail(ys) IS xs, the same node"
    mov     x0, #1
    mov     x1, #2
    mov     x2, #3
    bl      list3
    mov     x1, x0
    mov     x0, #0
    bl      cons                        // a fresh [0, 1, 2, 3]
    mov     x1, x0
    mov     x0, x20
    bl      list_eq
    cmp     x0, #1
    CHECK   eq, "ys reads [0, 1, 2, 3]"
    mov     x0, x19
    mov     x1, #1
    mov     x2, #2
    mov     x3, #3
    bl      expect_list3
    cmp     x0, #1
    CHECK   eq, "xs still reads [1, 2, 3] after the cons"

    LDADDR  x22, g_cons_allocs
    ldr     x23, [x22]                  // before
    mov     x0, x19
    mov     x1, #1
    mov     x2, #20
    bl      update_at
    mov     x21, x0                     // zs = update_at(xs, 1, 20)
    ldr     x9, [x22]
    sub     x9, x9, x23
    cmp     x9, #2
    CHECK   eq, "update at index 1 allocates i + 1 = 2 nodes, not 3"
    mov     x0, x21
    mov     x1, #1
    mov     x2, #20
    mov     x3, #3
    bl      expect_list3
    cmp     x0, #1
    CHECK   eq, "zs reads [1, 20, 3]"
    ldr     x9, [x21, #8]
    ldr     x9, [x9, #8]                // tail(tail(zs))
    ldr     x10, [x19, #8]
    ldr     x10, [x10, #8]              // tail(tail(xs))
    cmp     x9, x10
    CHECK   eq, "the suffix after the updated cell is shared"
    ldr     x9, [x21, #8]
    ldr     x10, [x19, #8]
    cmp     x9, x10
    CHECK   ne, "the updated cell is new, not xs's"
    mov     x0, x19
    mov     x1, #1
    mov     x2, #2
    mov     x3, #3
    bl      expect_list3
    cmp     x0, #1
    CHECK   eq, "xs still reads [1, 2, 3] after the update"

    // The gotcha: write through a node two versions share and both change.
    // Nothing stops this str; persistence is a rule the code keeps.
    mov     x0, #1
    mov     x1, #2
    mov     x2, #3
    bl      list3
    mov     x23, x0                     // vs = [1, 2, 3]
    mov     x1, #0
    mov     x2, #7
    bl      update_at
    mov     x24, x0                     // ws = [7, 2, 3], shares vs's [2, 3]
    ldr     x9, [x23, #8]
    mov     x10, #99
    str     x10, [x9]                   // in-place write to the shared cell
    mov     x0, x24
    mov     x1, #1
    bl      nth
    cmp     x0, #99
    CHECK   eq, "a write through a shared node changes the other version too"
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

test_folds:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x0, #1
    mov     x1, #2
    mov     x2, #3
    bl      list3
    mov     x19, x0                     // xs = [1, 2, 3]
    bl      list_length
    cmp     x0, #3
    CHECK   eq, "length via foldl = 3"
    mov     x0, #0
    bl      list_length
    cmp     x0, #0
    CHECK   eq, "length of the empty list = 0"
    mov     x0, x19
    bl      list_sum
    cmp     x0, #6
    CHECK   eq, "sum via foldl = 1 + 2 + 3 = 6"
    mov     x0, x19
    bl      list_reverse
    mov     x1, #3
    mov     x2, #2
    mov     x3, #1
    bl      expect_list3
    cmp     x0, #1
    CHECK   eq, "reverse via foldl = [3, 2, 1]"
    LDADDR  x0, clo_times_ten
    mov     x1, x19
    bl      list_map
    mov     x1, #10
    mov     x2, #20
    mov     x3, #30
    bl      expect_list3
    cmp     x0, #1
    CHECK   eq, "map via foldr keeps order: [10, 20, 30]"
    mov     x0, x19
    mov     x1, #1
    mov     x2, #2
    mov     x3, #3
    bl      expect_list3
    cmp     x0, #1
    CHECK   eq, "the folds left xs as [1, 2, 3]"

    // Subtraction is not associative, so the fold's direction shows.
    LDADDR  x0, clo_sub
    mov     x1, #0
    mov     x2, x19
    bl      foldl
    mov     x9, #-6
    cmp     x0, x9
    CHECK   eq, "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6"
    LDADDR  x0, clo_sub
    mov     x1, #0
    mov     x2, x19
    bl      foldr
    cmp     x0, #2
    CHECK   eq, "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2"
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

test_tail_calls:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    ldr     x0, =100000
    bl      sum_to_loop
    ldr     x9, =5000050000
    cmp     x0, x9
    CHECK   eq, "accumulator loop: sum 1..100000 = 5000050000"
    ldr     x0, =100000
    mov     x1, #0
    bl      sum_to_tail
    ldr     x9, =5000050000
    cmp     x0, x9
    CHECK   eq, "tail call: sum 1..100000 = 5000050000"
    // 10,000,000 levels as real calls would need 160 MB of stack, so
    // finishing at all shows each level was a branch. n(n + 1) / 2.
    ldr     x0, =10000000
    mov     x1, #0
    bl      sum_to_tail
    ldr     x9, =50000005000000
    cmp     x0, x9
    CHECK   eq, "tail call 10,000,000 deep runs in constant stack"
    ldp     x29, x30, [sp], #16
    ret

_start:
    LDADDR  x9, heap
    LDADDR  x10, heap_top
    str     x9, [x10]
    bl      test_purity
    bl      test_memoize
    bl      test_composition
    bl      test_closures
    bl      test_capture
    bl      test_persistent_list
    bl      test_folds
    bl      test_tail_calls

    mov     x0, #1
    LDADDR  x1, msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64                     // write
    svc     #0
    mov     x0, #0
    mov     x8, #93                     // exit
    svc     #0

// fail(x1 = name, x2 = length): "FAIL: name\n" on stderr, exit 1.
fail:
    mov     x19, x1
    mov     x20, x2
    mov     x0, #2
    LDADDR  x1, msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #2
    mov     x1, x19
    mov     x2, x20
    mov     x8, #64
    svc     #0
    mov     x0, #2
    LDADDR  x1, msg_nl
    mov     x2, #1
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0

.ltorg
