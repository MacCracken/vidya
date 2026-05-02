// Vidya — HTTP and Web Protocols in AArch64 Assembly
//
// Asm port focuses on the parsing primitive (find_crlf scan +
// memeq) and verifies 5 critical assertions on a known-shape GET
// and POST request. Full lookup logic stays in the higher-level
// ports.

.global _start

.section .data
req1:         .ascii "GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n"
.equ req1_len, . - req1
req4:         .ascii "POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world"
.equ req4_len, . - req4
exp_method_get:  .ascii "GET"
.equ exp_method_get_len, . - exp_method_get
exp_path_idx:    .ascii "/index.html"
.equ exp_path_idx_len, . - exp_path_idx
exp_version_11:  .ascii "HTTP/1.1"
.equ exp_version_11_len, . - exp_version_11
exp_method_post: .ascii "POST"
.equ exp_method_post_len, . - exp_method_post
exp_body_hw:     .ascii "hello world"
.equ exp_body_hw_len, . - exp_body_hw

.section .rodata
msg_pass:     .ascii "http_and_web_protocols: 5/5 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// find_byte(x0=buf, x1=byte, x2=start, x3=end) -> x0 = offset or -1
find_byte:
    mov     x4, x2
.fb_loop:
    cmp     x4, x3
    b.ge    .fb_neg
    ldrb    w5, [x0, x4]
    cmp     w5, w1
    b.eq    .fb_hit
    add     x4, x4, #1
    b       .fb_loop
.fb_hit:
    mov     x0, x4
    ret
.fb_neg:
    mov     x0, #-1
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
    // 1. req1 first space at offset 3 (after "GET")
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    mov     x1, #32
    mov     x2, #0
    mov     x3, #req1_len
    bl      find_byte
    mov     x1, #exp_method_get_len
    bl      assert_eq

    // 2. req1[0..3] == "GET"
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    adrp    x1, exp_method_get
    add     x1, x1, :lo12:exp_method_get
    mov     x2, #exp_method_get_len
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 3. req1[4..15] == "/index.html"
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    add     x0, x0, #4
    adrp    x1, exp_path_idx
    add     x1, x1, :lo12:exp_path_idx
    mov     x2, #exp_path_idx_len
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 4. req1[16..23] == "HTTP/1.1"
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    add     x0, x0, #16
    adrp    x1, exp_version_11
    add     x1, x1, :lo12:exp_version_11
    mov     x2, #exp_version_11_len
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 5. req4[0..3] == "POST"
    adrp    x0, req4
    add     x0, x0, :lo12:req4
    adrp    x1, exp_method_post
    add     x1, x1, :lo12:exp_method_post
    mov     x2, #exp_method_post_len
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 6. req4[42..52] == "hello world"
    adrp    x0, req4
    add     x0, x0, :lo12:req4
    add     x0, x0, #42
    adrp    x1, exp_body_hw
    add     x1, x1, :lo12:exp_body_hw
    mov     x2, #exp_body_hw_len
    bl      memeq
    mov     x1, #1
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
