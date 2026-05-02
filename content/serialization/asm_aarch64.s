// Vidya — Serialization in AArch64 Assembly
//
// Varint encode/decode + frame round-trip + overflow + truncation.

.global _start

.equ MAX_VARINT_BYTES, 10
.equ MAX_MSG_SIZE,     1024

.section .data
hello_payload: .ascii "hello, world"
.equ hello_len, 12

.bss
.align 8
enc_buf:      .skip 64
pl_out:       .skip 64
bomb_buf:     .skip 16

.data
.align 8
dec_val:      .quad 0
dec_bytes:    .quad 0

.section .rodata
msg_pass:     .ascii "serialization: 6/6 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// encode_varint(x0=value, x1=out) -> x0
encode_varint:
    mov     x2, #0                // n
    mov     x3, x0                // remaining
.ev_loop:
    cmp     x3, #128
    b.lt    .ev_last
    and     x4, x3, #0x7F
    orr     x4, x4, #0x80
    strb    w4, [x1, x2]
    lsr     x3, x3, #7
    add     x2, x2, #1
    b       .ev_loop
.ev_last:
    and     x4, x3, #0x7F
    strb    w4, [x1, x2]
    add     x0, x2, #1
    ret

// decode_varint(x0=buf, x1=buf_len) -> x0 = value or -1; sets dec_bytes
decode_varint:
    adrp    x2, dec_val
    add     x2, x2, :lo12:dec_val
    str     xzr, [x2]
    mov     x3, #0                // i
    mov     x4, #0                // shift
.dv_loop:
    cmp     x3, #MAX_VARINT_BYTES
    b.ge    .dv_neg
    cmp     x3, x1
    b.ge    .dv_neg
    ldrb    w5, [x0, x3]
    and     x6, x5, #0x7F
    lsl     x6, x6, x4
    ldr     x7, [x2]
    add     x7, x7, x6
    str     x7, [x2]
    tbz     w5, #7, .dv_done
    add     x4, x4, #7
    add     x3, x3, #1
    b       .dv_loop
.dv_done:
    add     x3, x3, #1
    adrp    x6, dec_bytes
    add     x6, x6, :lo12:dec_bytes
    str     x3, [x6]
    mov     x0, x7
    ret
.dv_neg:
    mov     x0, #-1
    adrp    x6, dec_bytes
    add     x6, x6, :lo12:dec_bytes
    mov     x7, #-1
    str     x7, [x6]
    ret

// encode_frame(x0=payload, x1=payload_len, x2=out) -> x0 = total bytes
encode_frame:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    mov     x19, x0               // payload
    mov     x20, x1               // payload_len
    mov     x21, x2               // out
    mov     x0, x20
    mov     x1, x21
    bl      encode_varint
    mov     x22, x0               // hdr_len
    mov     x3, #0                // i
.efr_copy:
    cmp     x3, x20
    b.ge    .efr_done
    ldrb    w4, [x19, x3]
    add     x5, x22, x3
    strb    w4, [x21, x5]
    add     x3, x3, #1
    b       .efr_copy
.efr_done:
    add     x0, x22, x20
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// decode_frame(x0=buf, x1=buf_len, x2=out, x3=max_msg) -> x0 = consumed or -1
decode_frame:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    mov     x19, x0               // buf
    mov     x20, x1               // buf_len
    mov     x21, x2               // out
    mov     x22, x3               // max_msg
    mov     x0, x19
    mov     x1, x20
    bl      decode_varint
    cmn     x0, #1
    b.eq    .dfr_neg
    cmp     x0, x22
    b.gt    .dfr_neg
    mov     x23, x0               // length
    adrp    x4, dec_bytes
    add     x4, x4, :lo12:dec_bytes
    ldr     x4, [x4]              // hdr_len
    add     x24, x4, x23          // total
    cmp     x24, x20
    b.gt    .dfr_neg
    mov     x5, #0                // i
.dfr_copy:
    cmp     x5, x23
    b.ge    .dfr_done
    add     x6, x4, x5
    ldrb    w7, [x19, x6]
    strb    w7, [x21, x5]
    add     x5, x5, #1
    b       .dfr_copy
.dfr_done:
    mov     x0, x24
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret
.dfr_neg:
    mov     x0, #-1
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

assert_eq:
    cmp     x0, x1
    b.ne    fail_exit
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
    // 1. encode_varint(127) = 1, byte 0x7F
    mov     x0, #127
    adrp    x1, enc_buf
    add     x1, x1, :lo12:enc_buf
    bl      encode_varint
    mov     x1, #1
    bl      assert_eq
    adrp    x0, enc_buf
    add     x0, x0, :lo12:enc_buf
    ldrb    w0, [x0]
    mov     x1, #0x7F
    bl      assert_eq

    // 2. encode_varint(128) = 2 bytes
    mov     x0, #128
    adrp    x1, enc_buf
    add     x1, x1, :lo12:enc_buf
    bl      encode_varint
    mov     x1, #2
    bl      assert_eq

    // 3. round-trip 1234567890
    ldr     x0, =1234567890
    adrp    x1, enc_buf
    add     x1, x1, :lo12:enc_buf
    bl      encode_varint
    mov     x19, x0               // encoded length
    adrp    x0, enc_buf
    add     x0, x0, :lo12:enc_buf
    mov     x1, x19
    bl      decode_varint
    ldr     x1, =1234567890
    bl      assert_eq

    // 4. overflow guard: 11 bytes of 0xFF → -1
    adrp    x0, bomb_buf
    add     x0, x0, :lo12:bomb_buf
    mov     x1, #0xFF
    mov     x2, #0
.fill_bomb:
    cmp     x2, #11
    b.ge    .bomb_done
    strb    w1, [x0, x2]
    add     x2, x2, #1
    b       .fill_bomb
.bomb_done:
    adrp    x0, bomb_buf
    add     x0, x0, :lo12:bomb_buf
    mov     x1, #11
    bl      decode_varint
    mov     x1, #-1
    bl      assert_eq

    // 5. frame round-trip
    adrp    x0, hello_payload
    add     x0, x0, :lo12:hello_payload
    mov     x1, #hello_len
    adrp    x2, enc_buf
    add     x2, x2, :lo12:enc_buf
    bl      encode_frame
    mov     x19, x0               // frame total
    adrp    x0, enc_buf
    add     x0, x0, :lo12:enc_buf
    mov     x1, x19
    adrp    x2, pl_out
    add     x2, x2, :lo12:pl_out
    mov     x3, #MAX_MSG_SIZE
    bl      decode_frame
    mov     x1, #13
    bl      assert_eq

    // 6. truncated frame
    adrp    x0, enc_buf
    add     x0, x0, :lo12:enc_buf
    mov     x1, #100
    strb    w1, [x0]
    mov     x1, #65
    strb    w1, [x0, #1]
    mov     x1, #66
    strb    w1, [x0, #2]
    mov     x1, #67
    strb    w1, [x0, #3]
    mov     x1, #68
    strb    w1, [x0, #4]
    mov     x1, #69
    strb    w1, [x0, #5]
    adrp    x0, enc_buf
    add     x0, x0, :lo12:enc_buf
    mov     x1, #6
    adrp    x2, pl_out
    add     x2, x2, :lo12:pl_out
    mov     x3, #MAX_MSG_SIZE
    bl      decode_frame
    mov     x1, #-1
    bl      assert_eq

    mov     x0, #1
    adrp    x1, msg_pass
    add     x1, x1, :lo12:msg_pass
    mov     x2, #msg_pass_len
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
