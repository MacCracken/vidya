# Vidya — Page Management in x86_64 Assembly
#
# In-memory simulation matching the cyrius reference's six-assertion
# test surface. We don't do file I/O from asm — instead, .bss arenas
# back the page store: PAGES is one i64 per slot (the value at byte
# offset 0 of the page), FREE_NEXT is the next-page pointer for freed
# pages. HDR_PAGECOUNT and HDR_FREEHEAD are .data globals matching
# H_PGCOUNT/H_FREEHEAD in the cyrius layout.
#
# 64-bit constants use `mov rN, 0xLITERAL`; results returned in rax.
# Any failed assertion prints FAIL and exits 1 (it does not say which).

.intel_syntax noprefix
.global _start

.equ MAGIC,    0x50415452
.equ POOL_CAP, 64

.section .bss
.align 8
PAGES:        .skip 8 * POOL_CAP        # PAGES[i] = value stored at page i
FREE_NEXT:    .skip 8 * POOL_CAP        # FREE_NEXT[i] = next freed page id
FREED:        .skip POOL_CAP            # FREED[i] = 1 while page i is on the free list

.section .data
HDR_MAGIC:    .quad 0
HDR_PAGECOUNT: .quad 0
HDR_FREEHEAD: .quad 0

.section .rodata
msg_pass:     .ascii "page_management: 6/6 ok\n"
msg_pass_len = . - msg_pass
msg_fail:     .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# hdr_init — zero-init the header to MAGIC + page_count=1
hdr_init:
    mov     rax, MAGIC
    mov     [rip + HDR_MAGIC], rax
    mov     qword ptr [rip + HDR_PAGECOUNT], 1
    mov     qword ptr [rip + HDR_FREEHEAD], 0
    ret

# page_alloc -> rax = newly-allocated page id, or 0 when the pool is full
# (page 0 is the header, so 0 never names a data page).
# Free-list path first (FREEHEAD nonzero), else extend pagecount.
page_alloc:
    mov     rax, [rip + HDR_FREEHEAD]
    test    rax, rax
    jz      .pa_extend
    # rax = freehead; pop next from FREE_NEXT[rax]
    lea     rcx, [rip + FREE_NEXT]
    mov     rdx, [rcx + rax * 8]
    mov     [rip + HDR_FREEHEAD], rdx
    lea     rcx, [rip + FREED]
    mov     byte ptr [rcx + rax], 0
    ret
.pa_extend:
    mov     rax, [rip + HDR_PAGECOUNT]
    cmp     rax, POOL_CAP
    jae     .pa_full                # no slot past PAGES[POOL_CAP-1]
    inc     qword ptr [rip + HDR_PAGECOUNT]
    # Zero the slot
    lea     rcx, [rip + PAGES]
    mov     qword ptr [rcx + rax * 8], 0
    ret
.pa_full:
    xor     eax, eax
    ret

# page_free(rdi=num) -> rax = 1 freed / 0 refused — push num onto the
# free list. A page freed twice would sit on the list twice and be handed
# to two owners, so a second free (and page 0 / an unallocated id) is refused.
page_free:
    test    rdi, rdi
    jz      .pf_refuse
    cmp     rdi, [rip + HDR_PAGECOUNT]
    jae     .pf_refuse              # unsigned: also rejects negatives
    lea     rcx, [rip + FREED]
    cmp     byte ptr [rcx + rdi], 0
    jne     .pf_refuse              # already free: double free
    mov     byte ptr [rcx + rdi], 1
    lea     rcx, [rip + FREE_NEXT]
    mov     rax, [rip + HDR_FREEHEAD]
    mov     [rcx + rdi * 8], rax
    mov     [rip + HDR_FREEHEAD], rdi
    mov     eax, 1
    ret
.pf_refuse:
    xor     eax, eax
    ret

# page_write(rdi=num, rsi=val) -> rax = 1 / 0 if num is not an allocated id
page_write:
    xor     eax, eax
    cmp     rdi, [rip + HDR_PAGECOUNT]
    jae     .pw_done
    lea     rcx, [rip + PAGES]
    mov     [rcx + rdi * 8], rsi
    mov     eax, 1
.pw_done:
    ret

# page_read(rdi=num) -> rax (-1 if num is not an allocated id)
page_read:
    mov     rax, -1
    cmp     rdi, [rip + HDR_PAGECOUNT]
    jae     .pr_done
    lea     rcx, [rip + PAGES]
    mov     rax, [rcx + rdi * 8]
.pr_done:
    ret

# fail_exit — write FAIL\n + exit(1); reached by jne, no argument
fail_exit:
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall

_start:
    call    hdr_init

    # 1. magic ok
    mov     rax, [rip + HDR_MAGIC]
    mov     rcx, MAGIC
    cmp     rax, rcx
    jne     fail_exit

    # 2. pgcount starts at 1
    mov     rax, [rip + HDR_PAGECOUNT]
    cmp     rax, 1
    jne     fail_exit

    # 3. first alloc = 1
    call    page_alloc
    mov     r12, rax              # callee-saved cache for p1
    cmp     rax, 1
    jne     fail_exit

    # 4. second alloc = 2
    call    page_alloc
    mov     r13, rax              # callee-saved cache for p2
    cmp     rax, 2
    jne     fail_exit

    # 5. write 42 to p1, read back, verify == 42
    mov     rdi, r12
    mov     rsi, 42
    call    page_write
    mov     rdi, r12
    call    page_read
    cmp     rax, 42
    jne     fail_exit

    # 6. free p2, alloc returns 2 (free list reuse)
    mov     rdi, r13
    call    page_free
    call    page_alloc
    cmp     rax, 2
    jne     fail_exit

    # 7. double free is refused: page 2 must not be handed out twice
    mov     rdi, 2
    call    page_free
    mov     rdi, 2
    call    page_free               # second free of the same page
    test    rax, rax
    jnz     fail_exit
    call    page_alloc
    mov     r12, rax
    call    page_alloc
    cmp     rax, r12
    je      fail_exit

    # 8. the pool stops at POOL_CAP pages instead of writing past PAGES
    mov     rbx, 100
.pm_fill:
    call    page_alloc
    dec     rbx
    jnz     .pm_fill
    test    rax, rax
    jnz     fail_exit               # full → 0
    mov     rax, [rip + HDR_PAGECOUNT]
    cmp     rax, POOL_CAP
    jne     fail_exit
    mov     rdi, POOL_CAP           # one past the last page
    mov     rsi, 7
    call    page_write
    test    rax, rax
    jnz     fail_exit

    # success
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
