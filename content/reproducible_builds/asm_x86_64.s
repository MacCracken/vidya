# Vidya — Reproducible Builds in x86_64 Assembly
#
# A reproducible build is a pure function of its inputs: identical sources
# yield a byte-identical artifact, on any machine, at any time. This mirrors
# content/reproducible_builds/cyrius.cyr exactly. Three classic sources of
# non-determinism and their fixes are modeled over an in-memory file set:
#
#   1. Wall-clock timestamps  → clamp "now" to SOURCE_DATE_EPOCH (normalize_ts)
#      so a future clock never leaks in.
#   2. Filesystem iteration order → sort filenames before folding them, so
#      output never depends on directory layout (files_sort).
#   3. Artifact names → name by HASH of content (cas_path), making identical
#      inputs map to identical paths (idempotent).
#
# The build digest folds the normalized timestamp and every file's
# (name, content) with a polynomial hash. A correct pipeline (sort+normalize)
# stays identical across runs differing in BOTH input order and clock; a naive
# one drifts. Parallel .bss arrays back the file set (8 bytes/i64 slot, 128
# capacity); f_n lives in .bss. All values are small non-negative ints, so the
# imul/cqo/idiv sign handling is fine.

.intel_syntax noprefix
.global _start

.equ HB, 131                # hash polynomial base
.equ HM, 1000003            # hash modulus (prime; keeps values < 2^53)
.equ HSEED, 7               # digest seed

.section .bss
.align 8
f_name:     .skip 8 * 128    # file name sort-keys
f_content:  .skip 8 * 128    # file content signatures (paired with f_name)
f_n:        .skip 8          # number of live files

.section .rodata
msg_pass:    .ascii "All reproducible_builds examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# fold(rdi=h, rsi=v) -> rax = (h*HB + v) % HM
fold:
    mov     rax, rdi
    imul    rax, HB                     # h*HB
    add     rax, rsi                    # + v
    cqo
    mov     rcx, HM
    idiv    rcx                         # rdx = (h*HB + v) % HM
    mov     rax, rdx
    ret

# normalize_ts(rdi=now, rsi=sde) -> rax = (now > sde) ? sde : now
normalize_ts:
    mov     rax, rdi                    # now
    cmp     rdi, rsi
    jle     .nts_done                   # now <= sde → keep now
    mov     rax, rsi                    # now > sde → clamp to sde
.nts_done:
    ret

# cas_path(rdi=content) -> rax = (content*HB + 7) % HM
cas_path:
    mov     rax, rdi
    imul    rax, HB                     # content*HB
    add     rax, 7                      # + 7
    cqo
    mov     rcx, HM
    idiv    rcx
    mov     rax, rdx
    ret

# files_reset(rdi=n): f_n = n
files_reset:
    lea     rax, [rip + f_n]
    mov     [rax], rdi
    ret

# file_set(rdi=i, rsi=name, rdx=content): f_name[i]=name; f_content[i]=content
file_set:
    lea     rax, [rip + f_name]
    mov     [rax + rdi * 8], rsi
    lea     rax, [rip + f_content]
    mov     [rax + rdi * 8], rdx
    ret

# files_sort(): insertion sort by f_name ascending, moving f_content alongside.
files_sort:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    lea     r15, [rip + f_n]
    mov     r15, [r15]                  # f_n
    mov     rbx, 1                      # i = 1
.sort_outer:
    cmp     rbx, r15
    jge     .sort_done
    lea     rax, [rip + f_name]
    mov     r12, [rax + rbx * 8]        # kn = f_name[i]
    lea     rax, [rip + f_content]
    mov     r13, [rax + rbx * 8]        # kc = f_content[i]
    mov     r14, rbx
    dec     r14                         # j = i - 1
.sort_inner:
    cmp     r14, 0
    jl      .sort_place                 # j < 0 → place
    lea     rax, [rip + f_name]
    mov     rcx, [rax + r14 * 8]        # f_name[j]
    cmp     rcx, r12
    jle     .sort_place                 # f_name[j] <= kn → place
    # shift element j up to j+1 (name and content together)
    lea     rax, [rip + f_name]
    mov     [rax + r14 * 8 + 8], rcx
    lea     rax, [rip + f_content]
    mov     rdx, [rax + r14 * 8]
    mov     [rax + r14 * 8 + 8], rdx
    dec     r14
    jmp     .sort_inner
.sort_place:
    # f_name[j+1] = kn; f_content[j+1] = kc
    lea     rax, [rip + f_name]
    mov     [rax + r14 * 8 + 8], r12
    lea     rax, [rip + f_content]
    mov     [rax + r14 * 8 + 8], r13
    inc     rbx
    jmp     .sort_outer
.sort_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# build_digest(rdi=do_sort, rsi=do_norm, rdx=now, rcx=sde) -> rax = digest
build_digest:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rsi                    # do_norm
    mov     r13, rdx                    # now
    mov     r14, rcx                    # sde

    # if do_sort: files_sort()
    test    rdi, rdi
    jz      .bd_ts
    call    files_sort
.bd_ts:
    # ts = now; if do_norm: ts = normalize_ts(now, sde)
    mov     r15, r13                    # ts = now
    test    r12, r12
    jz      .bd_seed
    mov     rdi, r13
    mov     rsi, r14
    call    normalize_ts
    mov     r15, rax                    # ts = normalize_ts(now, sde)
.bd_seed:
    # h = fold(HSEED, ts)
    mov     rdi, HSEED
    mov     rsi, r15
    call    fold
    mov     rbx, rax                    # h

    # for i in 0..f_n: h = fold(h, name); h = fold(h, content)
    lea     rax, [rip + f_n]
    mov     r12, [rax]                  # f_n
    xor     r13, r13                    # i = 0
.bd_loop:
    cmp     r13, r12
    jge     .bd_done
    lea     rax, [rip + f_name]
    mov     rdi, rbx
    mov     rsi, [rax + r13 * 8]
    call    fold
    mov     rbx, rax
    lea     rax, [rip + f_content]
    mov     rdi, rbx
    mov     rsi, [rax + r13 * 8]
    call    fold
    mov     rbx, rax
    inc     r13
    jmp     .bd_loop
.bd_done:
    mov     rax, rbx
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# setup_order_a(): same SET of 3 files, input order A
setup_order_a:
    push    rbx
    mov     rdi, 3
    call    files_reset
    mov     rdi, 0
    mov     rsi, 30
    mov     rdx, 111
    call    file_set
    mov     rdi, 1
    mov     rsi, 10
    mov     rdx, 222
    call    file_set
    mov     rdi, 2
    mov     rsi, 20
    mov     rdx, 333
    call    file_set
    pop     rbx
    ret

# setup_order_b(): same SET of 3 files, input order B
setup_order_b:
    push    rbx
    mov     rdi, 3
    call    files_reset
    mov     rdi, 0
    mov     rsi, 20
    mov     rdx, 333
    call    file_set
    mov     rdi, 1
    mov     rsi, 30
    mov     rdx, 111
    call    file_set
    mov     rdi, 2
    mov     rsi, 10
    mov     rdx, 222
    call    file_set
    pop     rbx
    ret

_start:
    # ---- Test 1: normalize_ts clamps a future clock, keeps a past one ----
    mov     rdi, 9999
    mov     rsi, 5000
    call    normalize_ts
    cmp     rax, 5000
    jne     fail
    mov     rdi, 3000
    mov     rsi, 5000
    call    normalize_ts
    cmp     rax, 3000
    jne     fail

    # ---- Test 2: sorted iteration — names ascending, content stays paired ----
    call    setup_order_a
    call    files_sort
    lea     rax, [rip + f_name]
    cmp     qword ptr [rax + 0 * 8], 10
    jne     fail
    lea     rax, [rip + f_name]
    cmp     qword ptr [rax + 1 * 8], 20
    jne     fail
    lea     rax, [rip + f_name]
    cmp     qword ptr [rax + 2 * 8], 30
    jne     fail
    lea     rax, [rip + f_content]
    cmp     qword ptr [rax + 0 * 8], 222    # content followed name 10
    jne     fail

    # ---- Test 3: content-addressed paths ----
    mov     rdi, 111
    call    cas_path
    mov     rbx, rax                        # cas_path(111)
    mov     rdi, 111
    call    cas_path
    cmp     rax, rbx                        # same content → same path
    jne     fail
    mov     rdi, 222
    call    cas_path
    cmp     rax, rbx                        # different content → different path
    je      fail

    # ---- Test 4: deterministic build is byte-identical across runs that
    #      differ in BOTH input order and wall-clock now ----
    call    setup_order_a
    mov     rdi, 1
    mov     rsi, 1
    mov     rdx, 9999
    mov     rcx, 5000
    call    build_digest
    mov     rbx, rax                        # d1
    call    setup_order_b
    mov     rdi, 1
    mov     rsi, 1
    mov     rdx, 8888
    mov     rcx, 5000
    call    build_digest
    cmp     rax, rbx
    jne     fail

    # ---- Test 5: naive build (no sort, raw now) drifts ----
    call    setup_order_a
    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 9999
    mov     rcx, 5000
    call    build_digest
    mov     rbx, rax                        # d1
    call    setup_order_b
    mov     rdi, 0
    mov     rsi, 0
    mov     rdx, 8888
    mov     rcx, 5000
    call    build_digest
    cmp     rax, rbx
    je      fail                            # must differ

    # ---- Test 6: normalization alone kills clock drift ----
    call    setup_order_a
    mov     rdi, 1
    mov     rsi, 1
    mov     rdx, 9999
    mov     rcx, 5000
    call    build_digest
    mov     rbx, rax                        # norm1 (clamps 9999 → 5000)
    call    setup_order_a
    mov     rdi, 1
    mov     rsi, 1
    mov     rdx, 7777
    mov     rcx, 5000
    call    build_digest
    cmp     rax, rbx                        # norm2 (clamps 7777 → 5000)
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
