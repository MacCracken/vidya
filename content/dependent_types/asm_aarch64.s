// Vidya — Dependent Types in AArch64 Assembly
//
// A dependent type depends on a VALUE: Vec n a is a vector whose length n
// is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
// v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
// values computed at run time; none of vidya's 11 languages can.
//
// Assembly is at the bottom of the list, with Shell: there are no types.
// The "type" is an invariant a checked constructor establishes (a length
// word in front of the elements, an index range-checked once) and code
// after that boundary relies on without checking again. The assembler can
// check sizes of static data (.if/.error); an address in a register has none.

.global _start

.equ ARENA_WORDS, 16

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

// --- 1. Length-indexed vector ---
// A vector is a length word followed by its elements. For static data the
// assembler computes the length word from the elements themselves, so the
// word cannot disagree with the data it describes.
.section .data
.align 3
vec0:   .quad (vec0_end - vec0 - 8) / 8
vec0_end:
vec2:   .quad (vec2_end - vec2 - 8) / 8
        .quad 1, 2
vec2_end:
vec3:   .quad (vec3_end - vec3 - 8) / 8
        .quad 3, 4, 5
vec3_end:
seven:  .quad (seven_end - seven - 8) / 8
        .quad 7
seven_end:
two:    .quad (two_end - two - 8) / 8
        .quad 1, 2
two_end:
three:  .quad (three_end - three - 8) / 8
        .quad 1, 2, 3
three_end:

.equ VEC2_LEN, (vec2_end - vec2 - 8) / 8
.equ VEC3_LEN, (vec3_end - vec3 - 8) / 8

.section .bss
.align 3
vec5:   .skip 8 + 8 * 5         // a length word and room for 5 elements
vec5_end:
arena:  .skip 8 * ARENA_WORDS   // Percent cells and Σ pairs; never freed
arena_used:       .skip 8       // words handed out so far
g_percent_checks: .skip 8       // counts validations, so a check can see them

// append writes 2 + 3 elements into vec5 without checking its room. The
// proof is here, at assembly time; with room for 4 the build stops:
//   Error: append(vec2, vec3) needs room for 2 + 3
.if (vec5_end - vec5 - 8) / 8 != VEC2_LEN + VEC3_LEN
.error "append(vec2, vec3) needs room for 2 + 3"
.endif

// HEAD vec: x0 = the first element of a STATIC vector. The assembler
// knows its size, so an empty one stops the build:
//   HEAD vec0
//   Error: head of an empty vector
.macro HEAD vec
.if \vec\()_end - \vec == 8
.error "head of an empty vector"
.endif
    LDADDR  x0, \vec
    ldr     x0, [x0, #8]
.endm

.section .rodata
msg_pass:     .ascii "All dependent type examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:     .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_nl:       .ascii "\n"

.section .text

// vlen(x0 = vec) -> x0 = its length word.
vlen:
    ldr     x0, [x0]
    ret

// vec_head(x0 = vec) -> x0 = 1 and x1 = the first element, or x0 = 0 for
// an empty vector. The address arrives at run time and the assembler
// cannot see what it points to, so the length is checked when it runs.
vec_head:
    ldr     x2, [x0]
    cbz     x2, .Lvh_empty
    ldr     x1, [x0, #8]
    mov     x0, #1
    ret
.Lvh_empty:
    mov     x0, #0
    ret

// append(x0 = a, x1 = b, x2 = out): out = a ++ b and out's length word =
// a's + b's. It trusts that out has room (proved above for vec5).
append:
    ldr     x3, [x0]                    // n
    ldr     x4, [x1]                    // m
    add     x5, x3, x4
    str     x5, [x2]                    // out's length word = n + m
    add     x6, x0, #8                  // a's elements
    add     x7, x2, #8                  // out's elements
    mov     x8, #0
.Lapp_a:
    cmp     x8, x3
    b.ge    .Lapp_b_start
    ldr     x9, [x6, x8, lsl #3]
    str     x9, [x7, x8, lsl #3]
    add     x8, x8, #1
    b       .Lapp_a
.Lapp_b_start:
    add     x7, x7, x3, lsl #3          // out's element n
    add     x6, x1, #8                  // b's elements
    mov     x8, #0
.Lapp_b:
    cmp     x8, x4
    b.ge    .Lapp_done
    ldr     x9, [x6, x8, lsl #3]
    str     x9, [x7, x8, lsl #3]
    add     x8, x8, #1
    b       .Lapp_b
.Lapp_done:
    ret

// --- 2. Fin n: an index proven in range ---
// fin3(x0 = i) -> x0 = 1 if 0 <= i < VEC3_LEN, else 0; x1 = i. One
// unsigned compare makes both tests: a negative i is a huge unsigned
// number. The bound is VEC3_LEN, vec3's own length, not a second literal.
fin3:
    mov     x1, x0
    cmp     x0, #VEC3_LEN
    cset    x0, lo
    ret

fin2:
    mov     x1, x0
    cmp     x0, #VEC2_LEN
    cset    x0, lo
    ret

// index(x0 = vec, x1 = k) -> x0 = element k, with no bounds check: k came
// from fin2 or fin3. It is one routine for both, because a Fin2 and a
// Fin3 are the same register; only the constructor that made k differs,
// and nothing here can tell which one did.
index:
    add     x0, x0, #8
    ldr     x0, [x0, x1, lsl #3]
    ret

// --- 3. Refinement at the boundary (parse, don't validate) ---
// alloc_words(x0 = n) -> x0 = the address of n fresh words, or 0 when the
// arena is full.
alloc_words:
    LDADDR  x2, arena_used
    ldr     x3, [x2]
    add     x4, x3, x0
    cmp     x4, #ARENA_WORDS
    b.hi    .Lalloc_full
    str     x4, [x2]
    LDADDR  x5, arena
    add     x0, x5, x3, lsl #3
    ret
.Lalloc_full:
    mov     x0, #0
    ret

// percent(x0 = x) -> x0 = the address of a Percent word holding x, or 0
// when x is outside 0..100. The one place the range is checked.
percent:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    LDADDR  x2, g_percent_checks
    ldr     x3, [x2]
    add     x3, x3, #1
    str     x3, [x2]
    cmp     x0, #100
    b.hi    .Lpct_refuse                // unsigned: x > 100, and every x < 0
    mov     x19, x0
    mov     x0, #1
    bl      alloc_words
    cbz     x0, .Lpct_done
    str     x19, [x0]
    b       .Lpct_done
.Lpct_refuse:
    mov     x0, #0
.Lpct_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// discount(x0 = price, x1 = Percent address) -> x0 = price - price * p
// / 100. It reads the word and trusts it: no range check here.
discount:
    ldr     x2, [x1]
    mul     x2, x0, x2
    mov     x3, #100
    sdiv    x2, x2, x3                  // truncates toward zero, as in C
    sub     x0, x0, x2
    ret

// --- 4. Σ type (dependent pair) ---
// Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
// the first. Here a pair is two words [n, data]; sized checks the
// dependency once, building the pair only when data's length word is n,
// and sized_sum then takes its loop bound from n alone.
// sized(x0 = n, x1 = data) -> x0 = the pair's address, or 0.
sized:
    ldr     x2, [x1]
    cmp     x2, x0
    b.ne    .Lsized_refuse
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    mov     x0, #2
    bl      alloc_words
    cbz     x0, .Lsized_done
    stp     x19, x20, [x0]
.Lsized_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.Lsized_refuse:
    mov     x0, #0
    ret

// sized_sum(x0 = pair) -> x0 = the sum of its n elements.
sized_sum:
    ldp     x2, x3, [x0]                // n (the loop bound), data
    add     x3, x3, #8
    mov     x0, #0
    mov     x4, #0
.Lss_loop:
    cmp     x4, x2
    b.ge    .Lss_done
    ldr     x5, [x3, x4, lsl #3]
    add     x0, x0, x5
    add     x4, x4, #1
    b       .Lss_loop
.Lss_done:
    ret

// --- 5. The escape hatch ---
// Nothing marks a word as a Percent. Storing 150 into a fresh word makes
// one that percent() never saw, a str rewrites a checked one in place,
// and index with a 7 that no fin3 made reads past vec3 without a fault.
// What keeps the invariant is only the convention that every Percent comes
// from percent(), every k from a fin constructor: review is the checker.

_start:
    // ---- 1. Length-indexed vector ----
    LDADDR  x0, vec0
    bl      vlen
    cmp     x0, #0
    CHECK   eq, "vec0's length word says 0"
    LDADDR  x0, vec2
    bl      vlen
    cmp     x0, #2
    CHECK   eq, "vec2's length word says 2"
    LDADDR  x0, vec3
    bl      vlen
    cmp     x0, #3
    CHECK   eq, "vec3's length word says 3"
    HEAD    vec2
    cmp     x0, #1
    CHECK   eq, "head of [1, 2] = 1"
    HEAD    vec3
    cmp     x0, #3
    CHECK   eq, "head of [3, 4, 5] = 3"

    LDADDR  x0, vec2
    LDADDR  x1, vec3
    LDADDR  x2, vec5
    bl      append
    LDADDR  x0, vec5
    bl      vlen
    cmp     x0, #5
    CHECK   eq, "append(vec2, vec3) has length 2 + 3 = 5"
    LDADDR  x19, vec5
    ldr     x21, [x19]                  // its length word
    add     x19, x19, #8
    mov     x20, #0
.Lt_app:
    cmp     x20, x21
    b.ge    .Lt_app_done
    ldr     x0, [x19, x20, lsl #3]
    add     x1, x20, #1
    cmp     x0, x1
    CHECK   eq, "append(vec2, vec3) reads [1, 2, 3, 4, 5]"
    add     x20, x20, #1
    b       .Lt_app
.Lt_app_done:

    // The run-time head: the empty case is refused when it happens.
    LDADDR  x0, vec0
    bl      vec_head
    cmp     x0, #0
    CHECK   eq, "run-time head of an empty vector is refused"
    LDADDR  x0, seven
    bl      vec_head
    cmp     x0, #1
    CHECK   eq, "run-time head of [7] is allowed"
    cmp     x1, #7
    CHECK   eq, "run-time head of [7] = 7"

    // ---- 2. Fin n ----
    mov     x0, #-1
    bl      fin3
    cmp     x0, #0
    CHECK   eq, "fin3(-1) is refused"
    mov     x0, #3
    bl      fin3
    cmp     x0, #0
    CHECK   eq, "fin3(3) is refused: 3 is not < 3"

    mov     x20, #0                     // accepted
    mov     x19, #-1                    // i, over -1..3
.Lt_fin:
    cmp     x19, #3
    b.gt    .Lt_fin_done
    mov     x0, x19
    bl      fin3                        // x1 = k when x0 = 1
    cbz     x0, .Lt_fin_next
    add     x20, x20, #1
    LDADDR  x0, vec3
    bl      index
    add     x1, x19, #3
    cmp     x0, x1
    CHECK   eq, "index with each Fin3 reads [3, 4, 5] in order"
.Lt_fin_next:
    add     x19, x19, #1
    b       .Lt_fin
.Lt_fin_done:
    cmp     x20, #3
    CHECK   eq, "fin3 accepts exactly 0, 1, 2 out of -1..3"

    mov     x0, #2
    bl      fin2
    cmp     x0, #0
    CHECK   eq, "fin2(2) is refused: 2 is not < 2"
    mov     x0, #1
    bl      fin2
    cmp     x0, #1
    CHECK   eq, "fin2(1) is accepted"
    LDADDR  x0, vec2
    bl      index
    cmp     x0, #2
    CHECK   eq, "index([1, 2], fin2(1)) = 2"

    // ---- 3. Refinement at the boundary ----
    LDADDR  x24, g_percent_checks
    str     xzr, [x24]
    mov     x0, #-1
    bl      percent
    cmp     x0, #0
    CHECK   eq, "percent(-1) is refused"
    mov     x0, #101
    bl      percent
    cmp     x0, #0
    CHECK   eq, "percent(101) is refused"
    mov     x0, #0
    bl      percent
    mov     x19, x0                     // p0
    mov     x0, #100
    bl      percent
    mov     x20, x0                     // p100
    mov     x0, #25
    bl      percent
    mov     x21, x0                     // p25
    cmp     x19, #0
    CHECK   ne, "percent accepts 0"
    cmp     x20, #0
    CHECK   ne, "percent accepts 100"
    cmp     x21, #0
    CHECK   ne, "percent accepts 25"
    ldr     x0, [x24]
    cmp     x0, #5
    CHECK   eq, "5 constructions, 5 validations"

    mov     x0, #200
    mov     x1, x21
    bl      discount
    cmp     x0, #150
    CHECK   eq, "discount(200, 25%) = 150"
    mov     x0, #200
    mov     x1, x19
    bl      discount
    cmp     x0, #200
    CHECK   eq, "discount(200, 0%) = 200"
    mov     x0, #200
    mov     x1, x20
    bl      discount
    cmp     x0, #0
    CHECK   eq, "discount(200, 100%) = 0"
    ldr     x0, [x24]
    cmp     x0, #5
    CHECK   eq, "discount never re-validated: still 5 checks after 3 calls"

    // ---- 4. Σ type ----
    mov     x0, #3
    LDADDR  x1, two
    bl      sized
    cmp     x0, #0
    CHECK   eq, "(3, [1, 2]) is refused: the length is 2"
    mov     x0, #2
    LDADDR  x1, three
    bl      sized
    cmp     x0, #0
    CHECK   eq, "(2, [1, 2, 3]) is refused: the length is 3"
    mov     x0, #3
    LDADDR  x1, three
    bl      sized
    cmp     x0, #0
    CHECK   ne, "(3, [1, 2, 3]) is built"
    mov     x19, x0
    ldr     x0, [x19]
    cmp     x0, #3
    CHECK   eq, "the pair's n is 3"
    mov     x0, x19
    bl      sized_sum
    cmp     x0, #6
    CHECK   eq, "sized_sum reads n = 3 elements: 1 + 2 + 3 = 6"

    // ---- 5. The escape hatch ----
    mov     x0, #150
    bl      percent
    cmp     x0, #0
    CHECK   eq, "the API refuses 150"
    mov     x0, #1
    bl      alloc_words                 // a word percent() never saw
    cmp     x0, #0
    CHECK   ne, "the arena has a word for the forgery"
    mov     x19, x0
    mov     x0, #150
    str     x0, [x19]                   // skips the constructor
    mov     x0, #200
    mov     x1, x19
    bl      discount
    cmp     x0, #-100
    CHECK   eq, "and discount trusts it: 200 - 300 = -100"

    mov     x0, #30
    bl      percent
    cmp     x0, #0
    CHECK   ne, "percent(30) is accepted"
    mov     x19, x0
    mov     x0, #250
    str     x0, [x19]                   // rewrites a checked Percent in place
    mov     x0, #100
    mov     x1, x19
    bl      discount
    cmp     x0, #-150
    CHECK   eq, "a str into a checked Percent breaks it too: -150"

    // ---- All passed ----
    mov     x0, #1
    LDADDR  x1, msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
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
