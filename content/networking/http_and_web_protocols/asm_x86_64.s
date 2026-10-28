# Vidya — HTTP and Web Protocols in x86_64 Assembly
#
# Asm port focuses on the parsing primitive: find_crlf scan + the
# critical assertions (method == "GET", path == "/index.html",
# version == "HTTP/1.1", header count, body roundtrip from a
# Content-Length request). Full lookup is in higher-level ports;
# the asm port verifies the byte-level scan correctness on a
# simple GET and a POST.
#
# The body is framed by Content-Length (RFC 9112 §6.3), never "whatever
# follows the headers": on a keep-alive connection the rest of the buffer
# is the next pipelined request, and treating it as body is the root of
# request smuggling. Chunked Transfer-Encoding is out of scope.

.intel_syntax noprefix
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
# Pipelined: the 5-byte body is followed by the next request. The
# lowercase name also checks that the name match ignores case.
req7:         .ascii "POST /x HTTP/1.1\r\ncontent-length: 5\r\n\r\nhelloGET / HTTP/1.1\r\n\r\n"
.equ req7_len, . - req7
req8:         .ascii "POST /x HTTP/1.1\r\nContent-Length: 20\r\n\r\nshort"
.equ req8_len, . - req8
# 128 body bytes follow, so only the digit check can reject "5x": read
# as 5 * 10 + ('x' - '0') = 122, it would pass the incomplete check.
req9:         .ascii "POST /x HTTP/1.1\r\nContent-Length: 5x\r\n\r\n"
              .fill 128, 1, 'h'
.equ req9_len, . - req9
exp_body_hello:  .ascii "hello"
.equ exp_body_hello_len, . - exp_body_hello
cl_name:      .ascii "content-length:"
.equ cl_name_len, . - cl_name

.equ BODY_CAP, 1048576             # 413 Content Too Large above this

.section .rodata
msg_pass:     .ascii "http_and_web_protocols: 8/8 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# find_crlf(rdi=buf, rsi=len, rdx=start) -> rax = offset or -1
find_crlf:
    mov     rcx, rdx
.fc_loop:
    mov     r8, rcx
    add     r8, 1
    cmp     r8, rsi
    jge     .fc_neg
    movzx   r9, byte ptr [rdi + rcx]
    cmp     r9, 13
    jne     .fc_next
    movzx   r9, byte ptr [rdi + rcx + 1]
    cmp     r9, 10
    jne     .fc_next
    mov     rax, rcx
    ret
.fc_next:
    inc     rcx
    jmp     .fc_loop
.fc_neg:
    mov     rax, -1
    ret

# find_byte(rdi=buf, rsi=byte, rdx=start, rcx=end) -> rax = offset or -1
find_byte:
    mov     r8, rdx
.fb_loop:
    cmp     r8, rcx
    jge     .fb_neg
    movzx   r9, byte ptr [rdi + r8]
    cmp     r9, rsi
    je      .fb_hit
    inc     r8
    jmp     .fb_loop
.fb_hit:
    mov     rax, r8
    ret
.fb_neg:
    mov     rax, -1
    ret

# memeq(rdi=a, rsi=b, rdx=n) -> rax = 1 if equal, 0 otherwise
memeq:
    xor     rax, rax
.me_loop:
    cmp     rax, rdx
    je      .me_eq
    movzx   rcx, byte ptr [rdi + rax]
    movzx   r8, byte ptr [rsi + rax]
    cmp     rcx, r8
    jne     .me_neq
    inc     rax
    jmp     .me_loop
.me_eq:
    mov     rax, 1
    ret
.me_neq:
    xor     rax, rax
    ret

# header_cl(rdi=buf, rsi=line start, rdx=line end) -> rax = the
# Content-Length value, -1 if that value is empty, not all digits, or
# over BODY_CAP, -2 if the line is some other header. The name match
# ignores case (RFC 9110 §5.1). Clobbers rcx, r8-r11.
header_cl:
    mov     rcx, rdx
    sub     rcx, rsi               # line length
    cmp     rcx, cl_name_len
    jl      .hc_other
    xor     r8, r8                 # i
    lea     r10, [rip + cl_name]
.hc_name:
    cmp     r8, cl_name_len
    je      .hc_value
    lea     r11, [rsi + r8]
    movzx   r9d, byte ptr [rdi + r11]
    lea     r11d, [r9 - 'A']
    cmp     r11d, 25
    ja      .hc_cmp                # unsigned: not 'A'..'Z'
    add     r9d, 32                # to lowercase
.hc_cmp:
    movzx   r11d, byte ptr [r10 + r8]
    cmp     r9d, r11d
    jne     .hc_other
    inc     r8
    jmp     .hc_name
.hc_value:
    lea     r8, [rsi + cl_name_len]
.hc_ows:                           # skip optional whitespace (SP / HTAB)
    cmp     r8, rdx
    jge     .hc_bad                # empty value
    movzx   r9d, byte ptr [rdi + r8]
    cmp     r9d, ' '
    je      .hc_ows_next
    cmp     r9d, 9
    jne     .hc_digits
.hc_ows_next:
    inc     r8
    jmp     .hc_ows
.hc_digits:
    xor     eax, eax
.hc_dloop:
    cmp     r8, rdx
    jge     .hc_ret
    movzx   r9d, byte ptr [rdi + r8]
    sub     r9d, '0'
    cmp     r9d, 9
    ja      .hc_bad                # unsigned: not '0'..'9' (400)
    imul    rax, rax, 10
    add     rax, r9
    cmp     rax, BODY_CAP
    ja      .hc_bad                # 413; also keeps imul from overflowing
    inc     r8
    jmp     .hc_dloop
.hc_ret:
    ret
.hc_bad:
    mov     rax, -1
    ret
.hc_other:
    mov     rax, -2
    ret

# parse_head(rdi=buf, rsi=len) -> rax = header count (-1 if the head is
# unterminated or its Content-Length is malformed), rdx = body offset,
# rcx = Content-Length (0 when there is none: no Content-Length, no
# body). Walks CRLF-terminated lines with find_crlf: the request line,
# then headers until the empty line (a CRLF right at the start of a line).
parse_head:
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                 # keep rsp 16-byte aligned at the calls
    mov     r12, rdi               # buf
    mov     r13, rsi               # len
    xor     r15, r15               # Content-Length
    xor     rdx, rdx
    call    find_crlf              # end of the request line
    cmp     rax, -1
    je      .ph_bad
    lea     rbx, [rax + 2]         # start of the next line
    xor     r14, r14               # header count
.ph_loop:
    mov     rdi, r12
    mov     rsi, r13
    mov     rdx, rbx
    call    find_crlf
    cmp     rax, -1
    je      .ph_bad
    cmp     rax, rbx               # CRLF at line start: the empty line
    je      .ph_done
    inc     r14
    mov     rbp, rax               # line end
    mov     rdi, r12
    mov     rsi, rbx
    mov     rdx, rbp
    call    header_cl
    cmp     rax, -2
    je      .ph_next               # some other header
    cmp     rax, -1
    je      .ph_bad                # malformed Content-Length
    mov     r15, rax
.ph_next:
    lea     rbx, [rbp + 2]
    jmp     .ph_loop
.ph_done:
    lea     rdx, [rbx + 2]         # body starts after the empty line
    mov     rcx, r15
    mov     rax, r14
    jmp     .ph_ret
.ph_bad:
    mov     rax, -1
.ph_ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
    ret

# frame_body(rdi=buf, rsi=len) -> rax = body offset, rdx = body length
# (exactly Content-Length bytes), or rax = -1 if the head is bad or
# fewer bytes are present than Content-Length declares (incomplete).
# Bytes past the body are left alone: they are the next request.
frame_body:
    push    rsi                    # parse_head clobbers rsi; also aligns rsp
    call    parse_head
    pop     rsi
    cmp     rax, -1
    je      .fr_bad
    mov     rax, rdx               # body offset
    mov     rdx, rcx               # body length = Content-Length
    lea     r8, [rax + rdx]
    cmp     r8, rsi
    ja      .fr_bad                # body not fully received
    ret
.fr_bad:
    mov     rax, -1
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
    # Test 1: req1 method == "GET" — the first space ends it
    lea     rdi, [rip + req1]
    mov     rsi, ' '
    mov     rdx, 0
    mov     rcx, req1_len
    call    find_byte
    mov     r12, rax               # end of method (3 for "GET")
    mov     rdi, rax
    mov     rsi, exp_method_get_len
    call    assert_eq
    lea     rdi, [rip + req1]
    lea     rsi, [rip + exp_method_get]
    mov     rdx, exp_method_get_len
    call    memeq
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # Test 2: path == "/index.html" — between the first and second space
    lea     rdi, [rip + req1]
    mov     rsi, ' '
    lea     rdx, [r12 + 1]
    mov     rcx, req1_len
    call    find_byte
    mov     r13, rax               # end of path
    sub     rax, r12
    dec     rax                    # path length
    mov     rdi, rax
    mov     rsi, exp_path_idx_len
    call    assert_eq
    lea     rdi, [rip + req1 + 1]
    add     rdi, r12
    lea     rsi, [rip + exp_path_idx]
    mov     rdx, exp_path_idx_len
    call    memeq
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # Test 3: version == "HTTP/1.1" — second space to the first CRLF
    lea     rdi, [rip + req1]
    mov     rsi, req1_len
    mov     rdx, 0
    call    find_crlf
    sub     rax, r13
    dec     rax                    # version length
    mov     rdi, rax
    mov     rsi, exp_version_11_len
    call    assert_eq
    lea     rdi, [rip + req1 + 1]
    add     rdi, r13
    lea     rsi, [rip + exp_version_11]
    mov     rdx, exp_version_11_len
    call    memeq
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # Test 4: header count — req1 has one header (Host) and no body
    lea     rdi, [rip + req1]
    mov     rsi, req1_len
    call    parse_head
    push    rdx
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    pop     rdi                    # body offset: the end of the request
    mov     rsi, req1_len
    call    assert_eq
    lea     rdi, [rip + req1]
    mov     rsi, req1_len
    call    frame_body
    mov     rdi, rdx               # no Content-Length, no body
    xor     esi, esi
    call    assert_eq

    # Test 5: req4 method == "POST", body "hello world" found by scanning
    # for the empty line — not a hard-coded offset — and framed by the
    # Content-Length: 11 header, which frame_body parses
    lea     rdi, [rip + req4]
    lea     rsi, [rip + exp_method_post]
    mov     rdx, exp_method_post_len
    call    memeq
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    lea     rdi, [rip + req4]
    mov     rsi, req4_len
    call    parse_head
    mov     rdi, rax
    mov     rsi, 1                 # one header: Content-Length
    call    assert_eq
    lea     rdi, [rip + req4]
    mov     rsi, req4_len
    call    frame_body
    mov     r12, rax               # body offset (42)
    mov     rdi, rdx               # body length, from the header
    mov     rsi, exp_body_hw_len
    call    assert_eq
    lea     rdi, [rip + req4]
    add     rdi, r12
    lea     rsi, [rip + exp_body_hw]
    mov     rdx, exp_body_hw_len
    call    memeq
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # Test 6: Content-Length frames the body — the trailing pipelined
    # request is not swallowed into it (the old "rest of the buffer"
    # body was 23 bytes here)
    lea     rdi, [rip + req7]
    mov     rsi, req7_len
    call    frame_body
    mov     r12, rax
    mov     rdi, rdx
    mov     rsi, exp_body_hello_len
    call    assert_eq
    lea     rdi, [rip + req7]
    add     rdi, r12
    lea     rsi, [rip + exp_body_hello]
    mov     rdx, exp_body_hello_len
    call    memeq
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # Test 7: a short body is incomplete, not accepted
    lea     rdi, [rip + req8]
    mov     rsi, req8_len
    call    frame_body
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq

    # Test 8: a non-numeric Content-Length is rejected
    lea     rdi, [rip + req9]
    mov     rsi, req9_len
    call    frame_body
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
