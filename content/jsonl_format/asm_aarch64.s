// Vidya — JSON Lines (JSONL) in AArch64 Assembly
//
// Asm port focuses on JSON string escape/unescape with bounds check
// — the algorithmically meaningful piece. 4 assertions:
//   1. escape produces 18 bytes from 12-byte input
//   2. bounds check returns -1
//   3. unescape recovers 12 bytes
//   4. round-trip bytes match
//
// AArch64 ABI notes (see field-note aarch64_callee_saved_and_imm_limits):
// loop state cached in callee-saved x19+ across `bl`.

.global _start

.section .data
src:          .byte 's', 'a', 'y', ' ', '"', 'h', 'i', '"', 9, 10, 13, 92
.equ src_len, . - src

.bss
.align 8
esc_buf:      .skip 256
unesc_buf:    .skip 256

.section .rodata
msg_pass:     .ascii "jsonl_format: 4/4 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// json_escape(x0=dst, x1=dst_cap, x2=src, x3=src_len) -> x0 = w or -1
json_escape:
    lsl     x4, x3, #1            // x4 = src_len * 2
    cmp     x4, x1
    b.gt    .je_bomb
    mov     x4, #0                // w
    mov     x5, #0                // i
.je_loop:
    cmp     x5, x3
    b.ge    .je_done
    ldrb    w6, [x2, x5]
    cmp     w6, #34
    b.eq    .je_quote
    cmp     w6, #92
    b.eq    .je_back
    cmp     w6, #10
    b.eq    .je_nl
    cmp     w6, #9
    b.eq    .je_tab
    cmp     w6, #13
    b.eq    .je_cr
    strb    w6, [x0, x4]
    add     x4, x4, #1
    b       .je_next
.je_quote:
    mov     w7, #92
    strb    w7, [x0, x4]
    add     x8, x4, #1
    mov     w7, #34
    strb    w7, [x0, x8]
    add     x4, x4, #2
    b       .je_next
.je_back:
    mov     w7, #92
    strb    w7, [x0, x4]
    add     x8, x4, #1
    strb    w7, [x0, x8]
    add     x4, x4, #2
    b       .je_next
.je_nl:
    mov     w7, #92
    strb    w7, [x0, x4]
    add     x8, x4, #1
    mov     w7, #110
    strb    w7, [x0, x8]
    add     x4, x4, #2
    b       .je_next
.je_tab:
    mov     w7, #92
    strb    w7, [x0, x4]
    add     x8, x4, #1
    mov     w7, #116
    strb    w7, [x0, x8]
    add     x4, x4, #2
    b       .je_next
.je_cr:
    mov     w7, #92
    strb    w7, [x0, x4]
    add     x8, x4, #1
    mov     w7, #114
    strb    w7, [x0, x8]
    add     x4, x4, #2
.je_next:
    add     x5, x5, #1
    b       .je_loop
.je_done:
    mov     x0, x4
    ret
.je_bomb:
    mov     x0, #-1
    ret

// json_unescape(x0=dst, x1=src, x2=src_len) -> x0 = w
json_unescape:
    mov     x3, #0                // w
    mov     x4, #0                // i
.ju_loop:
    cmp     x4, x2
    b.ge    .ju_done
    ldrb    w5, [x1, x4]
    cmp     w5, #92
    b.ne    .ju_plain
    add     x6, x4, #1
    cmp     x6, x2
    b.ge    .ju_plain
    ldrb    w7, [x1, x6]
    cmp     w7, #34
    b.eq    .ju_q
    cmp     w7, #92
    b.eq    .ju_b
    cmp     w7, #110
    b.eq    .ju_nl
    cmp     w7, #116
    b.eq    .ju_tab
    cmp     w7, #114
    b.eq    .ju_cr
.ju_plain:
    strb    w5, [x0, x3]
    add     x3, x3, #1
    add     x4, x4, #1
    b       .ju_loop
.ju_q:
    mov     w8, #34
    strb    w8, [x0, x3]
    add     x3, x3, #1
    add     x4, x4, #2
    b       .ju_loop
.ju_b:
    mov     w8, #92
    strb    w8, [x0, x3]
    add     x3, x3, #1
    add     x4, x4, #2
    b       .ju_loop
.ju_nl:
    mov     w8, #10
    strb    w8, [x0, x3]
    add     x3, x3, #1
    add     x4, x4, #2
    b       .ju_loop
.ju_tab:
    mov     w8, #9
    strb    w8, [x0, x3]
    add     x3, x3, #1
    add     x4, x4, #2
    b       .ju_loop
.ju_cr:
    mov     w8, #13
    strb    w8, [x0, x3]
    add     x3, x3, #1
    add     x4, x4, #2
    b       .ju_loop
.ju_done:
    mov     x0, x3
    ret

// memeq(x0=a, x1=b, x2=n) -> x0
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
    // 1. escape produces 18 bytes
    adrp    x0, esc_buf
    add     x0, x0, :lo12:esc_buf
    mov     x1, #256
    adrp    x2, src
    add     x2, x2, :lo12:src
    mov     x3, #src_len
    bl      json_escape
    cmp     x0, #18
    b.ne    fail_exit
    mov     x19, x0               // cache escaped len in callee-saved

    // 2. bounds check returns -1
    adrp    x0, esc_buf
    add     x0, x0, :lo12:esc_buf
    mov     x1, #4
    adrp    x2, src
    add     x2, x2, :lo12:src
    mov     x3, #4
    bl      json_escape
    cmn     x0, #1                // compare to -1
    b.ne    fail_exit

    // Re-escape into esc_buf for unescape
    adrp    x0, esc_buf
    add     x0, x0, :lo12:esc_buf
    mov     x1, #256
    adrp    x2, src
    add     x2, x2, :lo12:src
    mov     x3, #src_len
    bl      json_escape

    // 3. unescape recovers 12 bytes
    adrp    x0, unesc_buf
    add     x0, x0, :lo12:unesc_buf
    adrp    x1, esc_buf
    add     x1, x1, :lo12:esc_buf
    mov     x2, x19               // = 18
    bl      json_unescape
    cmp     x0, #src_len
    b.ne    fail_exit

    // 4. round-trip bytes match
    adrp    x0, unesc_buf
    add     x0, x0, :lo12:unesc_buf
    adrp    x1, src
    add     x1, x1, :lo12:src
    mov     x2, #src_len
    bl      memeq
    cmp     x0, #1
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
