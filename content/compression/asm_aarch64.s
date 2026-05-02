// Vidya — Compression (LZ77-shaped) in AArch64 Assembly
//
// Decoder-focused port — see the x86_64 sibling for the rationale on
// skipping the encoder. Token format matches cyrius.cyr: 2-byte tokens;
// b0=0 literal (b1 = value), b0!=0 match (b0 = offset, b1 = length).
// Byte-by-byte copy so offset=1 acts as RLE.
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// loop state cached in callee-saved x19–x24 across `bl decode`.

.global _start

.equ BUF_CAP, 512

.bss
.align 8
out_buf:      .skip BUF_CAP

.section .rodata
tok_abc:      .byte 0, 'A', 0, 'B', 0, 'C'
.equ tok_abc_len, . - tok_abc
exp_abc:      .ascii "ABC"
.equ exp_abc_len, . - exp_abc

tok_aaa:      .byte 0, 'A', 1, 7
.equ tok_aaa_len, . - tok_aaa
exp_aaa:      .ascii "AAAAAAAA"
.equ exp_aaa_len, . - exp_aaa

tok_abcabc:   .byte 0, 'A', 0, 'B', 0, 'C', 3, 6
.equ tok_abcabc_len, . - tok_abcabc
exp_abcabc:   .ascii "ABCABCABC"
.equ exp_abcabc_len, . - exp_abcabc

tok_bomb:     .byte 1, 200
.equ tok_bomb_len, . - tok_bomb

msg_pass:     .ascii "compression: 5/5 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// decode(x0=tok_ptr, x1=tok_len, x2=out_cap) -> x0 = output length, or -1 on bomb.
decode:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!

    mov     x19, x0               // tok ptr
    mov     x20, x1               // tok len
    mov     x21, x2               // out cap
    mov     x22, #0               // out pos
    mov     x23, #0               // ti

.dec_loop:
    add     x0, x23, #1
    cmp     x0, x20
    b.ge    .dec_done
    ldrb    w0, [x19, x23]        // b0
    add     x24, x23, #1
    ldrb    w1, [x19, x24]        // b1
    add     x23, x23, #2
    cbz     x0, .dec_lit
    // match: offset=x0, length=x1
    add     x4, x22, x1
    cmp     x4, x21
    b.gt    .dec_bomb
    adrp    x5, out_buf
    add     x5, x5, :lo12:out_buf
    mov     x6, #0                // k
.dm_copy:
    cmp     x6, x1
    b.ge    .dm_done
    sub     x7, x22, x0
    add     x7, x7, x6
    ldrb    w8, [x5, x7]
    add     x7, x22, x6
    strb    w8, [x5, x7]
    add     x6, x6, #1
    b       .dm_copy
.dm_done:
    add     x22, x22, x1
    b       .dec_loop
.dec_lit:
    add     x4, x22, #1
    cmp     x4, x21
    b.gt    .dec_bomb
    adrp    x5, out_buf
    add     x5, x5, :lo12:out_buf
    strb    w1, [x5, x22]
    add     x22, x22, #1
    b       .dec_loop

.dec_bomb:
    mov     x0, #-1
    b       .dec_ret
.dec_done:
    mov     x0, x22
.dec_ret:
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// memeq(x0=a, x1=b, x2=n) -> x0 = 1 if equal, 0 otherwise
memeq:
    mov     x3, #0
.me_loop:
    cmp     x3, x2
    b.eq    .me_eq
    ldrb    w4, [x0, x3]
    ldrb    w5, [x1, x3]
    cmp     w4, w5
    b.ne    .me_neq
    add     x3, x3, #1
    b       .me_loop
.me_eq:
    mov     x0, #1
    ret
.me_neq:
    mov     x0, #0
    ret

fail_exit:
    mov     x0, #1
    adrp    x1, msg_fail
    add     x1, x1, :lo12:msg_fail
    mov     x2, #msg_fail_len
    mov     x8, #64
    svc     #0
    mov     x0, #1
    mov     x8, #93
    svc     #0

_start:
    // Test 1: ABC literals
    adrp    x0, tok_abc
    add     x0, x0, :lo12:tok_abc
    mov     x1, #tok_abc_len
    mov     x2, #BUF_CAP
    bl      decode
    cmp     x0, #exp_abc_len
    b.ne    fail_exit
    adrp    x0, out_buf
    add     x0, x0, :lo12:out_buf
    adrp    x1, exp_abc
    add     x1, x1, :lo12:exp_abc
    mov     x2, #exp_abc_len
    bl      memeq
    cmp     x0, #1
    b.ne    fail_exit

    // Test 2: AAAAAAAA via RLE
    adrp    x0, tok_aaa
    add     x0, x0, :lo12:tok_aaa
    mov     x1, #tok_aaa_len
    mov     x2, #BUF_CAP
    bl      decode
    cmp     x0, #exp_aaa_len
    b.ne    fail_exit
    adrp    x0, out_buf
    add     x0, x0, :lo12:out_buf
    adrp    x1, exp_aaa
    add     x1, x1, :lo12:exp_aaa
    mov     x2, #exp_aaa_len
    bl      memeq
    cmp     x0, #1
    b.ne    fail_exit

    // Test 3: ABCABCABC via literals + substring
    adrp    x0, tok_abcabc
    add     x0, x0, :lo12:tok_abcabc
    mov     x1, #tok_abcabc_len
    mov     x2, #BUF_CAP
    bl      decode
    cmp     x0, #exp_abcabc_len
    b.ne    fail_exit
    adrp    x0, out_buf
    add     x0, x0, :lo12:out_buf
    adrp    x1, exp_abcabc
    add     x1, x1, :lo12:exp_abcabc
    mov     x2, #exp_abcabc_len
    bl      memeq
    cmp     x0, #1
    b.ne    fail_exit

    // Test 4: bomb guard returns -1 with cap=10
    adrp    x0, tok_bomb
    add     x0, x0, :lo12:tok_bomb
    mov     x1, #tok_bomb_len
    mov     x2, #10
    bl      decode
    cmn     x0, #1                // compare x0 to -1 via add (-(-1)=1)
    b.ne    fail_exit

    // Test 5: empty token stream
    adrp    x0, tok_abc
    add     x0, x0, :lo12:tok_abc
    mov     x1, #0
    mov     x2, #BUF_CAP
    bl      decode
    cmp     x0, #0
    b.ne    fail_exit

    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
