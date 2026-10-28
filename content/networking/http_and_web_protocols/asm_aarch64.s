// Vidya — HTTP and Web Protocols in AArch64 Assembly
//
// Asm port focuses on the parsing primitives (find_byte / find_crlf scans
// + memeq) and the two small parsers built on them: parse_request_line
// (method, path, version) and parse_head / frame_body (header count, body
// offset, body length). Every assertion checks an offset or length the
// PARSER computed. Comparing the test data at hard-coded offsets would
// compare the data with itself and could never fail. Full lookup logic
// stays in the higher-level ports.
//
// The body is framed by Content-Length (RFC 9112 §6.3), never "whatever
// follows the headers": on a keep-alive connection the rest of the buffer
// is the next pipelined request, and treating it as body is the root of
// request smuggling. Chunked Transfer-Encoding is out of scope.

.global _start

.section .data
req1:         .ascii "GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n"
.equ req1_len, . - req1
req4:         .ascii "POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world"
.equ req4_len, . - req4
// Pipelined: the 5-byte body is followed by the next request. The
// lowercase name also checks that the name match ignores case.
req7:         .ascii "POST /x HTTP/1.1\r\ncontent-length: 5\r\n\r\nhelloGET / HTTP/1.1\r\n\r\n"
.equ req7_len, . - req7
req8:         .ascii "POST /x HTTP/1.1\r\nContent-Length: 20\r\n\r\nshort"
.equ req8_len, . - req8
// 128 body bytes follow, so only the digit check can reject "5x": read
// as 5 * 10 + ('x' - '0') = 122, it would pass the incomplete check.
req9:         .ascii "POST /x HTTP/1.1\r\nContent-Length: 5x\r\n\r\n"
              .fill 128, 1, 'h'
.equ req9_len, . - req9
req_nover:    .ascii "GET /x\r\n\r\n"          // request line without a version
.equ req_nover_len, . - req_nover
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
exp_body_hello:  .ascii "hello"
.equ exp_body_hello_len, . - exp_body_hello
cl_name:      .ascii "content-length:"
.equ cl_name_len, . - cl_name

.equ BODY_CAP, 1048576             // 413 Content Too Large above this

.section .rodata
msg_pass:     .ascii "http_and_web_protocols: 9/9 ok\n"
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

// find_crlf(x0=buf, x1=len, x2=start) -> x0 = offset of the CR or -1
find_crlf:
    mov     x3, x2
.fc_loop:
    add     x4, x3, #1
    cmp     x4, x1
    b.ge    .fc_neg
    ldrb    w5, [x0, x3]
    cmp     w5, #13
    b.ne    .fc_next
    ldrb    w5, [x0, x4]
    cmp     w5, #10
    b.ne    .fc_next
    mov     x0, x3
    ret
.fc_next:
    add     x3, x3, #1
    b       .fc_loop
.fc_neg:
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

// parse_request_line(x0=buf, x1=len) -> x0 = method length, x1 = path
// offset, x2 = path length, x3 = version offset, x4 = version length;
// x0 = -1 if the line is unterminated or a part is missing or empty.
// "METHOD SP PATH SP VERSION CRLF" (RFC 9112 §3).
parse_request_line:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0               // buf
    mov     x2, #0
    bl      find_crlf             // end of the request line
    cmn     x0, #1
    b.eq    .prl_bad
    mov     x20, x0               // line end
    mov     x0, x19
    mov     x1, #32               // ' '
    mov     x2, #0
    mov     x3, x20
    bl      find_byte             // end of the method
    cmp     x0, #0
    b.le    .prl_bad              // -1: no space; 0: empty method
    mov     x21, x0               // method length
    mov     x0, x19
    mov     x1, #32
    add     x2, x21, #1
    mov     x3, x20
    bl      find_byte             // end of the path
    cmn     x0, #1
    b.eq    .prl_bad              // no version
    mov     x22, x0
    add     x1, x21, #1           // path offset
    sub     x2, x22, x1           // path length
    cbz     x2, .prl_bad
    add     x3, x22, #1           // version offset
    sub     x4, x20, x3           // version length
    cbz     x4, .prl_bad
    mov     x0, x21
    b       .prl_ret
.prl_bad:
    mov     x0, #-1
.prl_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

// header_cl(x0=buf, x1=line start, x2=line end) -> x0 = the
// Content-Length value, -1 if that value is empty, not all digits, or
// over BODY_CAP, -2 if the line is some other header. The name match
// ignores case (RFC 9110 §5.1). Clobbers x3-x9.
header_cl:
    sub     x3, x2, x1            // line length
    cmp     x3, #cl_name_len
    b.lt    .hc_other
    adrp    x4, cl_name
    add     x4, x4, :lo12:cl_name
    mov     x5, #0                // i
.hc_name:
    cmp     x5, #cl_name_len
    b.eq    .hc_value
    add     x6, x1, x5
    ldrb    w6, [x0, x6]
    sub     w7, w6, #65           // 'A'
    cmp     w7, #25
    b.hi    .hc_cmp               // unsigned: not 'A'..'Z'
    add     w6, w6, #32           // to lowercase
.hc_cmp:
    ldrb    w7, [x4, x5]
    cmp     w6, w7
    b.ne    .hc_other
    add     x5, x5, #1
    b       .hc_name
.hc_value:
    add     x5, x1, #cl_name_len
.hc_ows:                          // skip optional whitespace (SP / HTAB)
    cmp     x5, x2
    b.ge    .hc_bad               // empty value
    ldrb    w6, [x0, x5]
    cmp     w6, #32
    b.eq    .hc_ows_next
    cmp     w6, #9
    b.ne    .hc_digits
.hc_ows_next:
    add     x5, x5, #1
    b       .hc_ows
.hc_digits:
    mov     x7, #0                // value
    mov     x8, #10
    mov     x9, #BODY_CAP
.hc_dloop:
    cmp     x5, x2
    b.ge    .hc_ret
    ldrb    w6, [x0, x5]
    sub     w6, w6, #48           // '0'
    cmp     w6, #9
    b.hi    .hc_bad               // unsigned: not '0'..'9' (400)
    madd    x7, x7, x8, x6        // value = value * 10 + digit
    cmp     x7, x9
    b.hi    .hc_bad               // 413; also keeps madd from overflowing
    add     x5, x5, #1
    b       .hc_dloop
.hc_ret:
    mov     x0, x7
    ret
.hc_bad:
    mov     x0, #-1
    ret
.hc_other:
    mov     x0, #-2
    ret

// parse_head(x0=buf, x1=len) -> x0 = header count (-1 if the head is
// unterminated or its Content-Length is malformed), x1 = body offset,
// x2 = Content-Length (0 when there is none: no Content-Length, no body).
// Walks CRLF-terminated lines with find_crlf: the request line, then
// headers until the empty line (a CRLF right at the start of a line).
parse_head:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    mov     x19, x0               // buf
    mov     x20, x1               // len
    mov     x23, #0               // Content-Length
    mov     x24, #0               // header count
    mov     x2, #0
    bl      find_crlf             // end of the request line
    cmn     x0, #1
    b.eq    .ph_bad
    add     x21, x0, #2           // start of the next line
.ph_loop:
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      find_crlf
    cmn     x0, #1
    b.eq    .ph_bad
    cmp     x0, x21               // CRLF at line start: the empty line
    b.eq    .ph_done
    add     x24, x24, #1
    mov     x22, x0               // line end
    mov     x0, x19
    mov     x1, x21
    mov     x2, x22
    bl      header_cl
    cmn     x0, #2
    b.eq    .ph_next              // some other header
    cmn     x0, #1
    b.eq    .ph_bad               // malformed Content-Length
    mov     x23, x0
.ph_next:
    add     x21, x22, #2
    b       .ph_loop
.ph_done:
    add     x1, x21, #2           // body starts after the empty line
    mov     x2, x23
    mov     x0, x24
    b       .ph_ret
.ph_bad:
    mov     x0, #-1
.ph_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

// frame_body(x0=buf, x1=len) -> x0 = body offset, x1 = body length
// (exactly Content-Length bytes), or x0 = -1 if the head is bad or fewer
// bytes are present than Content-Length declares (incomplete). Bytes
// past the body are left alone: they are the next request.
frame_body:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    mov     x19, x1               // len (parse_head clobbers x1)
    bl      parse_head
    cmn     x0, #1
    b.eq    .fr_bad
    add     x3, x1, x2            // body end
    cmp     x3, x19
    b.hi    .fr_bad               // body not fully received
    mov     x0, x1                // body offset
    mov     x1, x2                // body length = Content-Length
    b       .fr_ret
.fr_bad:
    mov     x0, #-1
.fr_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
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
    // 1. req1 method == "GET": parse_request_line's method length, then
    //    the bytes it spans
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    mov     x1, #req1_len
    bl      parse_request_line
    mov     x19, x0               // method length
    mov     x20, x1               // path offset
    mov     x21, x2               // path length
    mov     x22, x3               // version offset
    mov     x23, x4               // version length
    mov     x1, #exp_method_get_len
    bl      assert_eq
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    adrp    x1, exp_method_get
    add     x1, x1, :lo12:exp_method_get
    mov     x2, x19
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 2. path == "/index.html", at the offset and length the parser found
    mov     x0, x21
    mov     x1, #exp_path_idx_len
    bl      assert_eq
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    add     x0, x0, x20
    adrp    x1, exp_path_idx
    add     x1, x1, :lo12:exp_path_idx
    mov     x2, x21
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 3. version == "HTTP/1.1", likewise
    mov     x0, x23
    mov     x1, #exp_version_11_len
    bl      assert_eq
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    add     x0, x0, x22
    adrp    x1, exp_version_11
    add     x1, x1, :lo12:exp_version_11
    mov     x2, x23
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 4. req1 head: one header (Host), the body offset is the end of the
    //    request, and with no Content-Length there is no body
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    mov     x1, #req1_len
    bl      parse_head
    mov     x19, x1
    mov     x1, #1
    bl      assert_eq
    mov     x0, x19
    mov     x1, #req1_len
    bl      assert_eq
    adrp    x0, req1
    add     x0, x0, :lo12:req1
    mov     x1, #req1_len
    bl      frame_body
    mov     x0, x1                // body length
    mov     x1, #0
    bl      assert_eq

    // 5. req4 method == "POST"; body "hello world" at the offset
    //    frame_body found, framed by the Content-Length: 11 it parsed
    adrp    x0, req4
    add     x0, x0, :lo12:req4
    mov     x1, #req4_len
    bl      parse_request_line
    mov     x1, #exp_method_post_len
    bl      assert_eq
    adrp    x0, req4
    add     x0, x0, :lo12:req4
    adrp    x1, exp_method_post
    add     x1, x1, :lo12:exp_method_post
    mov     x2, #exp_method_post_len
    bl      memeq
    mov     x1, #1
    bl      assert_eq
    adrp    x0, req4
    add     x0, x0, :lo12:req4
    mov     x1, #req4_len
    bl      frame_body
    mov     x19, x0               // body offset (42)
    mov     x0, x1                // body length, from the header
    mov     x1, #exp_body_hw_len
    bl      assert_eq
    adrp    x0, req4
    add     x0, x0, :lo12:req4
    add     x0, x0, x19
    adrp    x1, exp_body_hw
    add     x1, x1, :lo12:exp_body_hw
    mov     x2, #exp_body_hw_len
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 6. Content-Length frames the body: the trailing pipelined request
    //    is not swallowed into it ("rest of the buffer" would be 23 bytes)
    adrp    x0, req7
    add     x0, x0, :lo12:req7
    mov     x1, #req7_len
    bl      frame_body
    mov     x19, x0
    mov     x0, x1
    mov     x1, #exp_body_hello_len
    bl      assert_eq
    adrp    x0, req7
    add     x0, x0, :lo12:req7
    add     x0, x0, x19
    adrp    x1, exp_body_hello
    add     x1, x1, :lo12:exp_body_hello
    mov     x2, #exp_body_hello_len
    bl      memeq
    mov     x1, #1
    bl      assert_eq

    // 7. a short body is incomplete, not accepted
    adrp    x0, req8
    add     x0, x0, :lo12:req8
    mov     x1, #req8_len
    bl      frame_body
    mov     x1, #-1
    bl      assert_eq

    // 8. a non-numeric Content-Length is rejected
    adrp    x0, req9
    add     x0, x0, :lo12:req9
    mov     x1, #req9_len
    bl      frame_body
    mov     x1, #-1
    bl      assert_eq

    // 9. a request line without a version is rejected
    adrp    x0, req_nover
    add     x0, x0, :lo12:req_nover
    mov     x1, #req_nover_len
    bl      parse_request_line
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
