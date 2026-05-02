# Vidya — Serialization in x86_64 Assembly
#
# Asm port focuses on varint encode/decode + frame round-trip.
# 6 critical asserts cover the algorithmic core.

.intel_syntax noprefix
.global _start

.equ MAX_VARINT_BYTES, 10
.equ MAX_MSG_SIZE,     1024

.section .data
hello_payload: .ascii "hello, world"
.equ hello_len, 12

.section .bss
.align 8
enc_buf:      .skip 64
pl_out:       .skip 64
bomb_buf:     .skip 16

.section .data
dec_val:      .quad 0
dec_bytes:    .quad 0

.section .rodata
msg_pass:     .ascii "serialization: 6/6 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# encode_varint(rdi=value, rsi=out) -> rax = bytes written
encode_varint:
    xor     rax, rax              # n = 0
    mov     rcx, rdi              # remaining value
.ev_loop:
    cmp     rcx, 128
    jl      .ev_last
    mov     rdx, rcx
    and     rdx, 0x7F
    or      rdx, 0x80
    mov     [rsi + rax], dl
    shr     rcx, 7
    inc     rax
    jmp     .ev_loop
.ev_last:
    mov     rdx, rcx
    and     rdx, 0x7F
    mov     [rsi + rax], dl
    inc     rax
    ret

# decode_varint(rdi=buf, rsi=buf_len) -> rax = value or -1; sets dec_bytes/dec_val
decode_varint:
    mov     qword ptr [rip + dec_val], 0
    xor     rcx, rcx              # i
    xor     r8, r8                # shift
.dv_loop:
    cmp     rcx, MAX_VARINT_BYTES
    jge     .dv_overflow
    cmp     rcx, rsi
    jge     .dv_truncated
    movzx   r9, byte ptr [rdi + rcx]
    mov     r10, r9
    and     r10, 0x7F
    mov     r11, r10
    shl     r11, cl
    # Wait — we need to shift by `shift`, not by rcx. Use r8 and put it in cl.
    push    rcx
    mov     r11, r10
    mov     rcx, r8
    shl     r11, cl
    pop     rcx
    add     [rip + dec_val], r11
    test    r9, 0x80
    jz      .dv_done
    add     r8, 7
    inc     rcx
    jmp     .dv_loop
.dv_done:
    inc     rcx
    mov     [rip + dec_bytes], rcx
    mov     rax, [rip + dec_val]
    ret
.dv_overflow:
    mov     rax, -1
    mov     qword ptr [rip + dec_bytes], -1
    ret
.dv_truncated:
    mov     rax, -1
    mov     qword ptr [rip + dec_bytes], -1
    ret

# encode_frame(rdi=payload, rsi=payload_len, rdx=out) -> rax = total bytes
encode_frame:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi              # payload
    mov     r12, rsi              # payload_len
    mov     r13, rdx              # out
    mov     rdi, r12
    mov     rsi, r13
    call    encode_varint         # writes header at out[0..rax]
    mov     rcx, rax              # hdr_len
    xor     r9, r9                # i
.efr_copy:
    cmp     r9, r12
    jge     .efr_done
    movzx   r10, byte ptr [rbx + r9]
    # x86_64 addressing modes only allow base+index — fold rcx + r9
    # into a temp register first.
    mov     r11, rcx
    add     r11, r9
    mov     [r13 + r11], r10b
    inc     r9
    jmp     .efr_copy
.efr_done:
    add     rax, r12
    pop     r13
    pop     r12
    pop     rbx
    ret

# decode_frame(rdi=buf, rsi=buf_len, rdx=out, rcx=max_msg) -> rax = consumed or -1
decode_frame:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi              # buf
    mov     r12, rsi              # buf_len
    mov     r13, rdx              # out
    mov     r14, rcx              # max_msg
    mov     rdi, rbx
    mov     rsi, r12
    call    decode_varint
    cmp     rax, -1
    je      .dfr_neg
    cmp     rax, r14
    jg      .dfr_neg
    mov     r9, [rip + dec_bytes]
    mov     r10, r9
    add     r10, rax              # total
    cmp     r10, r12
    jg      .dfr_neg
    xor     rcx, rcx              # i
.dfr_copy:
    cmp     rcx, rax
    jge     .dfr_done
    # Fold r9 + rcx into a temp first (3-reg addressing not allowed).
    mov     r8, r9
    add     r8, rcx
    movzx   r11, byte ptr [rbx + r8]
    mov     [r13 + rcx], r11b
    inc     rcx
    jmp     .dfr_copy
.dfr_done:
    mov     rax, r10
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.dfr_neg:
    mov     rax, -1
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
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
    # 1. encode_varint(127) = 1 byte 0x7F
    mov     rdi, 127
    lea     rsi, [rip + enc_buf]
    call    encode_varint
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    movzx   rdi, byte ptr [rip + enc_buf]
    mov     rsi, 0x7F
    call    assert_eq

    # 2. encode_varint(128) = 2 bytes 0x80, 0x01
    mov     rdi, 128
    lea     rsi, [rip + enc_buf]
    call    encode_varint
    mov     rdi, rax
    mov     rsi, 2
    call    assert_eq

    # 3. round-trip 1234567890
    mov     rdi, 1234567890
    lea     rsi, [rip + enc_buf]
    call    encode_varint
    mov     r12, rax              # encoded length
    lea     rdi, [rip + enc_buf]
    mov     rsi, r12
    call    decode_varint
    mov     rdi, rax
    mov     rsi, 1234567890
    call    assert_eq

    # 4. overflow guard: 11 bytes of 0xFF → -1
    mov     rcx, 11
    xor     rax, rax
.fill_bomb:
    cmp     rax, rcx
    jge     .bomb_done
    lea     rdx, [rip + bomb_buf]
    mov     byte ptr [rdx + rax], 0xFF
    inc     rax
    jmp     .fill_bomb
.bomb_done:
    lea     rdi, [rip + bomb_buf]
    mov     rsi, 11
    call    decode_varint
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq

    # 5. frame round-trip: encode "hello, world", decode, check consumed = 13
    lea     rdi, [rip + hello_payload]
    mov     rsi, hello_len
    lea     rdx, [rip + enc_buf]
    call    encode_frame
    mov     r13, rax              # frame total
    lea     rdi, [rip + enc_buf]
    mov     rsi, r13
    lea     rdx, [rip + pl_out]
    mov     rcx, MAX_MSG_SIZE
    call    decode_frame
    mov     rdi, rax
    mov     rsi, 13
    call    assert_eq

    # 6. truncated frame: header says 100 but only 6 bytes total → -1
    lea     rdi, [rip + enc_buf]
    mov     byte ptr [rdi], 100
    mov     byte ptr [rdi + 1], 65
    mov     byte ptr [rdi + 2], 66
    mov     byte ptr [rdi + 3], 67
    mov     byte ptr [rdi + 4], 68
    mov     byte ptr [rdi + 5], 69
    mov     rsi, 6
    lea     rdx, [rip + pl_out]
    mov     rcx, MAX_MSG_SIZE
    call    decode_frame
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
