# Vidya — DNS in x86_64 Assembly
#
# Asm port focuses on the algorithmic primitives:
#   - zone_lookup with CNAME chain following + depth bound
#   - cache_lookup / cache_insert / advance_time
#   - resolve = cache_lookup → zone_lookup → cache_insert
# Tests cover the 6 critical assertions: A hit, CNAME chain, loop
# bounded, cache hit/miss across TTL expiry, and a CNAME answer cached for
# the shortest TTL on its chain (not a fallback).

.intel_syntax noprefix
.global _start

.equ RR_A, 1
.equ RR_CNAME, 3
.equ ZONE_CAP, 64
.equ CACHE_CAP, 32
.equ CNAME_MAX_DEPTH, 16
.equ NEGATIVE_TTL, 300

.section .bss
.align 8
z_name:       .skip 8 * ZONE_CAP
z_type:       .skip 8 * ZONE_CAP
z_ttl:        .skip 8 * ZONE_CAP
z_value:      .skip 8 * ZONE_CAP
c_name:       .skip 8 * CACHE_CAP
c_type:       .skip 8 * CACHE_CAP
c_value:      .skip 8 * CACHE_CAP
c_expires:    .skip 8 * CACHE_CAP

.section .data
z_count:      .quad 0
c_count:      .quad 0
now_clock:    .quad 0
last_status:  .quad 0
last_ttl:     .quad 0               # min TTL over the last lookup's chain

.section .rodata
msg_pass:     .ascii "dns: 6/6 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# zone_add(rdi=name, rsi=rtype, rdx=ttl, rcx=value)
zone_add:
    mov     rax, [rip + z_count]
    cmp     rax, ZONE_CAP
    jge     .za_done
    lea     r8, [rip + z_name]
    mov     [r8 + rax * 8], rdi
    lea     r8, [rip + z_type]
    mov     [r8 + rax * 8], rsi
    lea     r8, [rip + z_ttl]
    mov     [r8 + rax * 8], rdx
    lea     r8, [rip + z_value]
    mov     [r8 + rax * 8], rcx
    inc     qword ptr [rip + z_count]
.za_done:
    ret

# zone_lookup(rdi=name, rsi=rtype) -> rax
# r12=name (cur), r13=rtype, r14=depth
zone_lookup:
    push    r12
    push    r13
    push    r14
    mov     r12, rdi
    mov     r13, rsi
    xor     r14, r14
    mov     rax, 0x7FFFFFFFFFFFFFFF
    mov     [rip + last_ttl], rax
.zl_outer:
    cmp     r14, CNAME_MAX_DEPTH
    jg      .zl_neg
    # Search direct match
    mov     rax, [rip + z_count]
    xor     rcx, rcx
.zl_search:
    cmp     rcx, rax
    jge     .zl_search_done
    lea     r8, [rip + z_name]
    mov     r9, [r8 + rcx * 8]
    cmp     r9, r12
    jne     .zl_search_next
    lea     r8, [rip + z_type]
    mov     r9, [r8 + rcx * 8]
    cmp     r9, r13
    jne     .zl_search_next
    lea     r8, [rip + z_ttl]
    mov     r9, [r8 + rcx * 8]
    cmp     r9, [rip + last_ttl]
    jge     .zl_ttl_kept
    mov     [rip + last_ttl], r9    # the answer expires with its record...
.zl_ttl_kept:
    lea     r8, [rip + z_value]
    mov     rax, [r8 + rcx * 8]
    pop     r14
    pop     r13
    pop     r12
    ret
.zl_search_next:
    inc     rcx
    jmp     .zl_search
.zl_search_done:
    # Try CNAME if rtype == A
    cmp     r13, RR_A
    jne     .zl_neg
    mov     rax, [rip + z_count]
    xor     rcx, rcx
    xor     r10, r10                # cn = 0
.zl_cname:
    cmp     rcx, rax
    jge     .zl_cname_done
    lea     r8, [rip + z_name]
    mov     r9, [r8 + rcx * 8]
    cmp     r9, r12
    jne     .zl_cname_next
    lea     r8, [rip + z_type]
    mov     r9, [r8 + rcx * 8]
    cmp     r9, RR_CNAME
    jne     .zl_cname_next
    lea     r8, [rip + z_ttl]
    mov     r9, [r8 + rcx * 8]
    cmp     r9, [rip + last_ttl]
    jge     .zl_cn_ttl_kept
    mov     [rip + last_ttl], r9    # ...or with any CNAME on the way to it
.zl_cn_ttl_kept:
    lea     r8, [rip + z_value]
    mov     r10, [r8 + rcx * 8]
    jmp     .zl_cname_done
.zl_cname_next:
    inc     rcx
    jmp     .zl_cname
.zl_cname_done:
    test    r10, r10
    jz      .zl_neg
    mov     r12, r10
    inc     r14
    jmp     .zl_outer
.zl_neg:
    mov     rax, -1
    pop     r14
    pop     r13
    pop     r12
    ret

# cache_lookup(rdi=name, rsi=rtype) -> rax
cache_lookup:
    mov     r8, [rip + c_count]
    xor     rcx, rcx
.cl_loop:
    cmp     rcx, r8
    jge     .cl_miss
    lea     r9, [rip + c_name]
    mov     rax, [r9 + rcx * 8]
    cmp     rax, rdi
    jne     .cl_next
    lea     r9, [rip + c_type]
    mov     rax, [r9 + rcx * 8]
    cmp     rax, rsi
    jne     .cl_next
    lea     r9, [rip + c_expires]
    mov     rax, [r9 + rcx * 8]
    mov     r10, [rip + now_clock]
    cmp     rax, r10
    jle     .cl_next
    mov     qword ptr [rip + last_status], 1
    lea     r9, [rip + c_value]
    mov     rax, [r9 + rcx * 8]
    ret
.cl_next:
    inc     rcx
    jmp     .cl_loop
.cl_miss:
    mov     qword ptr [rip + last_status], 0
    mov     rax, -1
    ret

# cache_insert(rdi=name, rsi=rtype, rdx=value, rcx=ttl)
cache_insert:
    mov     r8, [rip + now_clock]
    add     r8, rcx                 # exp = now + ttl
    mov     r9, [rip + c_count]
    xor     rax, rax
.ci_loop:
    cmp     rax, r9
    jge     .ci_append
    lea     r10, [rip + c_name]
    mov     r11, [r10 + rax * 8]
    cmp     r11, rdi
    jne     .ci_next
    lea     r10, [rip + c_type]
    mov     r11, [r10 + rax * 8]
    cmp     r11, rsi
    jne     .ci_next
    lea     r10, [rip + c_value]
    mov     [r10 + rax * 8], rdx
    lea     r10, [rip + c_expires]
    mov     [r10 + rax * 8], r8
    ret
.ci_next:
    inc     rax
    jmp     .ci_loop
.ci_append:
    cmp     r9, CACHE_CAP
    jge     .ci_done
    lea     r10, [rip + c_name]
    mov     [r10 + r9 * 8], rdi
    lea     r10, [rip + c_type]
    mov     [r10 + r9 * 8], rsi
    lea     r10, [rip + c_value]
    mov     [r10 + r9 * 8], rdx
    lea     r10, [rip + c_expires]
    mov     [r10 + r9 * 8], r8
    inc     qword ptr [rip + c_count]
.ci_done:
    ret

# advance_time(rdi=s)
advance_time:
    add     [rip + now_clock], rdi
    ret

# resolve(rdi=name, rsi=rtype) -> rax
resolve:
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    call    cache_lookup
    mov     rcx, [rip + last_status]
    test    rcx, rcx
    jnz     .rs_done
    # zone_lookup
    mov     rdi, r12
    mov     rsi, r13
    call    zone_lookup
    cmp     rax, -1
    jne     .rs_pos
    # NXDOMAIN — cache negative
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, -1
    mov     rcx, NEGATIVE_TTL
    call    cache_insert
    mov     rax, -1
    jmp     .rs_done
.rs_pos:
    # Cache for the shortest TTL on the chain zone_lookup walked. Looking
    # up a record named (name, rtype) instead misses every CNAME answer —
    # there is no such record — and would fall back to NEGATIVE_TTL.
    mov     r8, rax                 # save value
    mov     r10, [rip + last_ttl]
.rs_insert:
    push    r8                      # cache_insert clobbers r8 (caller-saved)
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, r8
    mov     rcx, r10
    call    cache_insert
    pop     rax                     # the resolved value
.rs_done:
    pop     r13
    pop     r12
    ret

assert_eq:
    cmp     rdi, rsi
    jne     fail_exit
    ret

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
    # Build zone (subset; enough for the 5 asm-side asserts). The A
    # record's TTL (120) differs from NEGATIVE_TTL (300), so test 5 can
    # tell the record's own TTL from the fallback.
    mov     rdi, 1
    mov     rsi, RR_A
    mov     rdx, 120
    mov     rcx, 0x7F000001
    call    zone_add
    mov     rdi, 2
    mov     rsi, RR_CNAME
    mov     rdx, 600
    mov     rcx, 1
    call    zone_add
    mov     rdi, 10
    mov     rsi, RR_CNAME
    mov     rdx, 600
    mov     rcx, 11
    call    zone_add
    mov     rdi, 11
    mov     rsi, RR_CNAME
    mov     rdx, 600
    mov     rcx, 10
    call    zone_add

    # 1. A direct lookup
    mov     rdi, 1
    mov     rsi, RR_A
    call    zone_lookup
    mov     rdi, rax
    mov     rsi, 0x7F000001
    call    assert_eq

    # 2. CNAME chain follows to A
    mov     rdi, 2
    mov     rsi, RR_A
    call    zone_lookup
    mov     rdi, rax
    mov     rsi, 0x7F000001
    call    assert_eq

    # 3. CNAME loop bounded → -1
    mov     rdi, 10
    mov     rsi, RR_A
    call    zone_lookup
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq

    # 4. Cache miss → hit on second resolve (and both return the address)
    mov     rdi, 1
    mov     rsi, RR_A
    call    resolve
    mov     rdi, rax
    mov     rsi, 0x7F000001
    call    assert_eq
    mov     rdi, [rip + last_status]
    mov     rsi, 0
    call    assert_eq
    mov     rdi, 1
    mov     rsi, RR_A
    call    resolve
    mov     rdi, rax
    mov     rsi, 0x7F000001
    call    assert_eq
    mov     rdi, [rip + last_status]
    mov     rsi, 1
    call    assert_eq

    # 5. Advance time past the record's TTL (120) → cache miss
    mov     rdi, 121
    call    advance_time
    mov     rdi, 1
    mov     rsi, RR_A
    call    resolve
    mov     rdi, [rip + last_status]
    mov     rsi, 0
    call    assert_eq

    # 6. CNAME answer expires with the A record behind it (TTL 120), not
    # the CNAME's 600 or the 300 fallback
    mov     rdi, 2
    mov     rsi, RR_A
    call    resolve                 # miss: cached until now + 120
    mov     rdi, rax
    mov     rsi, 0x7F000001
    call    assert_eq
    mov     rdi, 121
    call    advance_time
    mov     rdi, 2
    mov     rsi, RR_A
    call    resolve
    mov     rdi, [rip + last_status]
    mov     rsi, 0                  # expired → miss
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
