# Vidya — Dependent Types in x86_64 Assembly
#
# A dependent type depends on a VALUE: Vec n a is a vector whose length n
# is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
# v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
# values computed at run time; none of vidya's 11 languages can.
#
# Assembly is at the bottom of the list, with Shell: there are no types.
# The "type" is an invariant a checked constructor establishes (a length
# word in front of the elements, an index range-checked once) and code
# after that boundary relies on without checking again. The assembler can
# check sizes of static data (.if/.error); an address in a register has none.

.intel_syntax noprefix
.global _start

.equ ARENA_WORDS, 16

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

# --- 1. Length-indexed vector ---
# A vector is a length word followed by its elements. For static data the
# assembler computes the length word from the elements themselves, so the
# word cannot disagree with the data it describes.
.section .data
.align 8
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
.align 8
vec5:   .skip 8 + 8 * 5         # a length word and room for 5 elements
vec5_end:
arena:  .skip 8 * ARENA_WORDS   # Percent cells and Σ pairs; never freed
arena_used:       .skip 8       # words handed out so far
g_percent_checks: .skip 8       # counts validations, so a check can see them

# append writes 2 + 3 elements into vec5 without checking its room. The
# proof is here, at assembly time; with room for 4 the build stops:
#   Error: append(vec2, vec3) needs room for 2 + 3
.if (vec5_end - vec5 - 8) / 8 != VEC2_LEN + VEC3_LEN
.error "append(vec2, vec3) needs room for 2 + 3"
.endif

# HEAD vec: rax = the first element of a STATIC vector. The assembler
# knows its size, so an empty one stops the build:
#   HEAD vec0
#   Error: head of an empty vector
.macro HEAD vec
.if \vec\()_end - \vec == 8
.error "head of an empty vector"
.endif
    mov     rax, [rip + \vec + 8]
.endm

.section .rodata
msg_pass:     .ascii "All dependent type examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:     .ascii "FAIL: "
msg_fail_len = . - msg_fail
msg_nl:       .ascii "\n"

.section .text

# vlen(rdi = vec) -> rax = its length word.
vlen:
    mov     rax, [rdi]
    ret

# vec_head(rdi = vec) -> rax = 1 and rdx = the first element, or rax = 0
# for an empty vector. The address arrives at run time and the assembler
# cannot see what it points to, so the length is checked when it runs.
vec_head:
    xor     eax, eax
    cmp     qword ptr [rdi], 0
    je      .Lvh_done
    mov     rdx, [rdi + 8]
    mov     eax, 1
.Lvh_done:
    ret

# append(rdi = a, rsi = b, rdx = out): out = a ++ b and out's length word
# = a's + b's. It trusts that out has room (proved above for vec5).
append:
    mov     r8, [rdi]                   # n
    mov     r9, [rsi]                   # m
    lea     rax, [r8 + r9]
    mov     [rdx], rax                  # out's length word = n + m
    xor     ecx, ecx
.Lapp_a:
    cmp     rcx, r8
    jge     .Lapp_b_start
    mov     rax, [rdi + 8 + rcx * 8]
    mov     [rdx + 8 + rcx * 8], rax
    inc     rcx
    jmp     .Lapp_a
.Lapp_b_start:
    lea     r10, [rdx + 8 + r8 * 8]     # out's element n
    xor     ecx, ecx
.Lapp_b:
    cmp     rcx, r9
    jge     .Lapp_done
    mov     rax, [rsi + 8 + rcx * 8]
    mov     [r10 + rcx * 8], rax
    inc     rcx
    jmp     .Lapp_b
.Lapp_done:
    ret

# --- 2. Fin n: an index proven in range ---
# fin3(rdi = i) -> rax = 1 and rdx = i if 0 <= i < VEC3_LEN, else rax = 0.
# One unsigned compare makes both tests: a negative i is a huge unsigned
# number. The bound is VEC3_LEN, vec3's own length, not a second literal.
fin3:
    xor     eax, eax
    cmp     rdi, VEC3_LEN
    jae     .Lfin3_done
    mov     rdx, rdi
    mov     eax, 1
.Lfin3_done:
    ret

fin2:
    xor     eax, eax
    cmp     rdi, VEC2_LEN
    jae     .Lfin2_done
    mov     rdx, rdi
    mov     eax, 1
.Lfin2_done:
    ret

# index(rdi = vec, rsi = k) -> rax = element k, with no bounds check: k
# came from fin2 or fin3. It is one routine for both, because a Fin2 and
# a Fin3 are the same register; only the constructor that made k differs,
# and nothing here can tell which one did.
index:
    mov     rax, [rdi + 8 + rsi * 8]
    ret

# --- 3. Refinement at the boundary (parse, don't validate) ---
# alloc_words(rdi = n) -> rax = the address of n fresh words, or 0 when
# the arena is full.
alloc_words:
    mov     rax, [rip + arena_used]
    lea     rcx, [rax + rdi]
    cmp     rcx, ARENA_WORDS
    ja      .Lalloc_full
    mov     [rip + arena_used], rcx
    lea     rdx, [rip + arena]
    lea     rax, [rdx + rax * 8]
    ret
.Lalloc_full:
    xor     eax, eax
    ret

# percent(rdi = x) -> rax = the address of a Percent word holding x, or 0
# when x is outside 0..100. The one place the range is checked.
percent:
    inc     qword ptr [rip + g_percent_checks]
    cmp     rdi, 100
    ja      .Lpct_refuse                # unsigned: x > 100, and every x < 0
    push    rdi
    mov     edi, 1
    call    alloc_words
    pop     rdi
    test    rax, rax
    jz      .Lpct_done
    mov     [rax], rdi
.Lpct_done:
    ret
.Lpct_refuse:
    xor     eax, eax
    ret

# discount(rdi = price, rsi = Percent address) -> rax = price - price * p
# / 100. It reads the word and trusts it: no range check here.
discount:
    mov     rax, rdi
    imul    rax, [rsi]
    cqo
    mov     rcx, 100
    idiv    rcx                         # truncates toward zero, as in C
    mov     rdx, rdi
    sub     rdx, rax
    mov     rax, rdx
    ret

# --- 4. Σ type (dependent pair) ---
# Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
# the first. Here a pair is two words [n, data]; sized checks the
# dependency once, building the pair only when data's length word is n,
# and sized_sum then takes its loop bound from n alone.
# sized(rdi = n, rsi = data) -> rax = the pair's address, or 0.
sized:
    cmp     [rsi], rdi
    jne     .Lsized_refuse
    push    rdi
    push    rsi
    mov     edi, 2
    call    alloc_words
    pop     rsi
    pop     rdi
    test    rax, rax
    jz      .Lsized_done
    mov     [rax], rdi
    mov     [rax + 8], rsi
.Lsized_done:
    ret
.Lsized_refuse:
    xor     eax, eax
    ret

# sized_sum(rdi = pair) -> rax = the sum of its n elements.
sized_sum:
    mov     rcx, [rdi]                  # n, the loop bound
    mov     rsi, [rdi + 8]              # data
    xor     eax, eax
    xor     edx, edx
.Lss_loop:
    cmp     rdx, rcx
    jge     .Lss_done
    add     rax, [rsi + 8 + rdx * 8]
    inc     rdx
    jmp     .Lss_loop
.Lss_done:
    ret

# --- 5. The escape hatch ---
# Nothing marks a word as a Percent. Storing 150 into a fresh word makes
# one that percent() never saw, a mov rewrites a checked one in place,
# and index with a 7 that no fin3 made reads past vec3 without a fault.
# What keeps the invariant is only the convention that every Percent comes
# from percent(), every k from a fin constructor: review is the checker.

_start:
    # ---- 1. Length-indexed vector ----
    lea     rdi, [rip + vec0]
    call    vlen
    cmp     rax, 0
    CHECK   e, "vec0's length word says 0"
    lea     rdi, [rip + vec2]
    call    vlen
    cmp     rax, 2
    CHECK   e, "vec2's length word says 2"
    lea     rdi, [rip + vec3]
    call    vlen
    cmp     rax, 3
    CHECK   e, "vec3's length word says 3"
    HEAD    vec2
    cmp     rax, 1
    CHECK   e, "head of [1, 2] = 1"
    HEAD    vec3
    cmp     rax, 3
    CHECK   e, "head of [3, 4, 5] = 3"

    lea     rdi, [rip + vec2]
    lea     rsi, [rip + vec3]
    lea     rdx, [rip + vec5]
    call    append
    lea     rdi, [rip + vec5]
    call    vlen
    cmp     rax, 5
    CHECK   e, "append(vec2, vec3) has length 2 + 3 = 5"
    lea     rbx, [rip + vec5]
    xor     r12d, r12d
.Lt_app:
    cmp     r12, [rbx]
    jge     .Lt_app_done
    mov     rax, [rbx + 8 + r12 * 8]
    lea     rcx, [r12 + 1]
    cmp     rax, rcx
    CHECK   e, "append(vec2, vec3) reads [1, 2, 3, 4, 5]"
    inc     r12
    jmp     .Lt_app
.Lt_app_done:

    # The run-time head: the empty case is refused when it happens.
    lea     rdi, [rip + vec0]
    call    vec_head
    test    rax, rax
    CHECK   z, "run-time head of an empty vector is refused"
    lea     rdi, [rip + seven]
    call    vec_head
    test    rax, rax
    CHECK   nz, "run-time head of [7] is allowed"
    cmp     rdx, 7
    CHECK   e, "run-time head of [7] = 7"

    # ---- 2. Fin n ----
    mov     rdi, -1
    call    fin3
    test    rax, rax
    CHECK   z, "fin3(-1) is refused"
    mov     rdi, 3
    call    fin3
    test    rax, rax
    CHECK   z, "fin3(3) is refused: 3 is not < 3"

    xor     r13d, r13d                  # accepted
    mov     r12, -1                     # i, over -1..3
.Lt_fin:
    cmp     r12, 3
    jg      .Lt_fin_done
    mov     rdi, r12
    call    fin3
    test    rax, rax
    jz      .Lt_fin_next
    inc     r13
    lea     rdi, [rip + vec3]
    mov     rsi, rdx
    call    index
    lea     rcx, [r12 + 3]
    cmp     rax, rcx
    CHECK   e, "index with each Fin3 reads [3, 4, 5] in order"
.Lt_fin_next:
    inc     r12
    jmp     .Lt_fin
.Lt_fin_done:
    cmp     r13, 3
    CHECK   e, "fin3 accepts exactly 0, 1, 2 out of -1..3"

    mov     rdi, 2
    call    fin2
    test    rax, rax
    CHECK   z, "fin2(2) is refused: 2 is not < 2"
    mov     rdi, 1
    call    fin2
    test    rax, rax
    CHECK   nz, "fin2(1) is accepted"
    lea     rdi, [rip + vec2]
    mov     rsi, rdx
    call    index
    cmp     rax, 2
    CHECK   e, "index([1, 2], fin2(1)) = 2"

    # ---- 3. Refinement at the boundary ----
    mov     qword ptr [rip + g_percent_checks], 0
    mov     rdi, -1
    call    percent
    test    rax, rax
    CHECK   z, "percent(-1) is refused"
    mov     rdi, 101
    call    percent
    test    rax, rax
    CHECK   z, "percent(101) is refused"
    mov     rdi, 0
    call    percent
    mov     r12, rax                    # p0
    mov     rdi, 100
    call    percent
    mov     r13, rax                    # p100
    mov     rdi, 25
    call    percent
    mov     r14, rax                    # p25
    test    r12, r12
    CHECK   nz, "percent accepts 0"
    test    r13, r13
    CHECK   nz, "percent accepts 100"
    test    r14, r14
    CHECK   nz, "percent accepts 25"
    cmp     qword ptr [rip + g_percent_checks], 5
    CHECK   e, "5 constructions, 5 validations"

    mov     rdi, 200
    mov     rsi, r14
    call    discount
    cmp     rax, 150
    CHECK   e, "discount(200, 25%) = 150"
    mov     rdi, 200
    mov     rsi, r12
    call    discount
    cmp     rax, 200
    CHECK   e, "discount(200, 0%) = 200"
    mov     rdi, 200
    mov     rsi, r13
    call    discount
    cmp     rax, 0
    CHECK   e, "discount(200, 100%) = 0"
    cmp     qword ptr [rip + g_percent_checks], 5
    CHECK   e, "discount never re-validated: still 5 checks after 3 calls"

    # ---- 4. Σ type ----
    mov     rdi, 3
    lea     rsi, [rip + two]
    call    sized
    test    rax, rax
    CHECK   z, "(3, [1, 2]) is refused: the length is 2"
    mov     rdi, 2
    lea     rsi, [rip + three]
    call    sized
    test    rax, rax
    CHECK   z, "(2, [1, 2, 3]) is refused: the length is 3"
    mov     rdi, 3
    lea     rsi, [rip + three]
    call    sized
    test    rax, rax
    CHECK   nz, "(3, [1, 2, 3]) is built"
    mov     rbx, rax
    cmp     qword ptr [rbx], 3
    CHECK   e, "the pair's n is 3"
    mov     rdi, rbx
    call    sized_sum
    cmp     rax, 6
    CHECK   e, "sized_sum reads n = 3 elements: 1 + 2 + 3 = 6"

    # ---- 5. The escape hatch ----
    mov     rdi, 150
    call    percent
    test    rax, rax
    CHECK   z, "the API refuses 150"
    mov     edi, 1
    call    alloc_words                 # a word percent() never saw
    test    rax, rax
    CHECK   nz, "the arena has a word for the forgery"
    mov     rbx, rax
    mov     qword ptr [rbx], 150        # skips the constructor
    mov     rdi, 200
    mov     rsi, rbx
    call    discount
    cmp     rax, -100
    CHECK   e, "and discount trusts it: 200 - 300 = -100"

    mov     rdi, 30
    call    percent
    test    rax, rax
    CHECK   nz, "percent(30) is accepted"
    mov     rbx, rax
    mov     qword ptr [rbx], 250        # rewrites a checked Percent in place
    mov     rdi, 100
    mov     rsi, rbx
    call    discount
    cmp     rax, -150
    CHECK   e, "a mov into a checked Percent breaks it too: -150"

    # ---- All passed ----
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
