# Vidya — Pattern Matching in x86_64 Assembly
#
# Assembly has no pattern matching syntax. "Matching" is done with
# compare-and-branch (cmp/jcc), jump tables for switch-like dispatch,
# and computed jumps. The CPU does one comparison at a time.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All pattern matching examples passed.\n"
msg_len = . - msg_pass

# Jump table for dispatch (4 entries, 8 bytes each)
.align 8
jump_table:
    .quad .case_0
    .quad .case_1
    .quad .case_2
    .quad .case_3
jump_table_size = 4

.section .text

_start:
    # ── Compare and branch (if-else chain) ──────────────────────────
    mov     edi, -5
    call    classify_number
    cmp     eax, 1              # 1 = negative
    jne     fail

    mov     edi, 0
    call    classify_number
    cmp     eax, 2              # 2 = zero
    jne     fail

    mov     edi, 7
    call    classify_number
    cmp     eax, 3              # 3 = small (1-10)
    jne     fail

    mov     edi, 100
    call    classify_number
    cmp     eax, 4              # 4 = large
    jne     fail

    # ── Jump table dispatch (switch-like) ───────────────────────────
    # Dispatch on values 0-3 via computed jump
    mov     edi, 0
    call    dispatch_jump_table
    cmp     eax, 10
    jne     fail

    mov     edi, 2
    call    dispatch_jump_table
    cmp     eax, 30
    jne     fail

    mov     edi, 3
    call    dispatch_jump_table
    cmp     eax, 40
    jne     fail

    # Out of range: default case
    mov     edi, 99
    call    dispatch_jump_table
    cmp     eax, -1
    jne     fail

    # ── Byte-level pattern matching ─────────────────────────────────
    # Classify ASCII character
    mov     dil, '5'
    call    classify_char
    cmp     eax, 1              # 1 = digit
    jne     fail

    mov     dil, 'a'
    call    classify_char
    cmp     eax, 2              # 2 = lowercase
    jne     fail

    mov     dil, 'Z'
    call    classify_char
    cmp     eax, 3              # 3 = uppercase
    jne     fail

    mov     dil, ' '
    call    classify_char
    cmp     eax, 4              # 4 = space
    jne     fail

    mov     dil, '@'
    call    classify_char
    cmp     eax, 0              # 0 = other
    jne     fail

    # ── Bit pattern matching ────────────────────────────────────────
    # Test specific bits with AND/TEST
    mov     eax, 0b10110100
    test    eax, 0b00000100     # test bit 2
    jz      fail                # bit 2 is set

    test    eax, 0b00001000     # test bit 3
    jnz     fail                # bit 3 is clear

    # ── CMOV: conditional move (branchless matching) ────────────────
    # Select between two values without branching
    mov     eax, 42
    mov     ecx, 99
    cmp     eax, 50
    cmovl   eax, ecx            # if eax < 50, eax = ecx
    cmp     eax, 99
    jne     fail

    mov     eax, 100
    mov     ecx, 0
    cmp     eax, 50
    cmovl   eax, ecx            # if eax < 50, eax = ecx (not taken)
    cmp     eax, 100
    jne     fail

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── classify_number: range matching via compare chain ───────────────
# edi = number, returns eax: 1=negative, 2=zero, 3=small, 4=large
classify_number:
    test    edi, edi
    js      .cn_negative
    jz      .cn_zero
    cmp     edi, 10
    jle     .cn_small
    mov     eax, 4
    ret
.cn_negative:
    mov     eax, 1
    ret
.cn_zero:
    mov     eax, 2
    ret
.cn_small:
    mov     eax, 3
    ret

# ── dispatch_jump_table: computed jump for 0-3 ──────────────────────
# edi = case value, returns eax = result
dispatch_jump_table:
    cmp     edi, jump_table_size
    jge     .jt_default
    lea     rax, [jump_table]
    movsxd  rcx, edi
    jmp     [rax + rcx * 8]
.case_0:
    mov     eax, 10
    ret
.case_1:
    mov     eax, 20
    ret
.case_2:
    mov     eax, 30
    ret
.case_3:
    mov     eax, 40
    ret
.jt_default:
    mov     eax, -1
    ret

# ── classify_char: ASCII character classification ───────────────────
# dil = character, returns eax: 0=other, 1=digit, 2=lower, 3=upper, 4=space
classify_char:
    movzx   eax, dil
    cmp     al, '0'
    jb      .cc_check_upper
    cmp     al, '9'
    jbe     .cc_digit
.cc_check_upper:
    cmp     al, 'A'
    jb      .cc_check_lower
    cmp     al, 'Z'
    jbe     .cc_upper
.cc_check_lower:
    cmp     al, 'a'
    jb      .cc_check_space
    cmp     al, 'z'
    jbe     .cc_lower
.cc_check_space:
    cmp     al, ' '
    je      .cc_space
    cmp     al, '\t'
    je      .cc_space
    xor     eax, eax
    ret
.cc_digit:
    mov     eax, 1
    ret
.cc_lower:
    mov     eax, 2
    ret
.cc_upper:
    mov     eax, 3
    ret
.cc_space:
    mov     eax, 4
    ret
