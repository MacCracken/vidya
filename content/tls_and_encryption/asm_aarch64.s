// Vidya — TLS and Encryption in AArch64 Assembly
//
// Asm port focuses on pick_cipher + verify_chain + AEAD primitives.
// Handshake driver is in higher-level ports.

.global _start

.equ TLS_AES_128_GCM_SHA256, 0x1301
.equ TLS_AES_256_GCM_SHA384, 0x1302
.equ TLS_CHACHA20_POLY1305_SHA256, 0x1303
.equ TLS_RSA_AES_128_CBC_SHA, 0x002F

.data
.align 8
srv_ciphers:  .quad TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384
cli_ciphers:  .quad TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256
srv_legacy:   .quad TLS_RSA_AES_128_CBC_SHA

leaf_cert:    .quad 100, 200
inter_cert:   .quad 200, 300
root_cert:    .quad 300, 300
chain_arr:    .quad 0, 0, 0
trust_arr:    .quad 0
bad_root:     .quad 999, 999
bad_trust:    .quad 0

pt_text:      .ascii "secret message"
.equ pt_len, 14

.bss
.align 8
ct_buf:       .skip 64
pt_buf:       .skip 64

.section .rodata
msg_pass:     .ascii "tls_and_encryption: 5/5 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.text

// is_tls13(x0=c) -> x0
is_tls13:
    ldr     x1, =0x1301
    cmp     x0, x1
    b.eq    .it_one
    ldr     x1, =0x1302
    cmp     x0, x1
    b.eq    .it_one
    ldr     x1, =0x1303
    cmp     x0, x1
    b.eq    .it_one
    mov     x0, #0
    ret
.it_one:
    mov     x0, #1
    ret

// pick_cipher(x0=srv, x1=sn, x2=cli, x3=cn) -> x0
// Caches all args + index in callee-saveds across `bl is_tls13`.
pick_cipher:
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    mov     x19, x0               // srv
    mov     x20, x1               // sn
    mov     x21, x2               // cli
    mov     x22, x3               // cn
    mov     x23, #0               // i
.pc_outer:
    cmp     x23, x20
    b.ge    .pc_zero
    ldr     x0, [x19, x23, lsl #3]
    mov     x24, x0               // cache cipher to compare
    bl      is_tls13
    cbz     x0, .pc_outer_next
    mov     x0, #0                // j (use x0 since we're done with is_tls13's return)
    mov     x1, #0
.pc_inner:
    cmp     x1, x22
    b.ge    .pc_outer_next
    ldr     x2, [x21, x1, lsl #3]
    cmp     x2, x24
    b.ne    .pc_inner_next
    mov     x0, x24
    b       .pc_done
.pc_inner_next:
    add     x1, x1, #1
    b       .pc_inner
.pc_outer_next:
    add     x23, x23, #1
    b       .pc_outer
.pc_zero:
    mov     x0, #0
.pc_done:
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

// verify_chain(x0=chain, x1=n_certs, x2=trust, x3=n_roots) -> x0
verify_chain:
    cbz     x1, .vc_zero
    mov     x4, #0                // i
.vc_link:
    sub     x5, x1, #1
    cmp     x4, x5
    b.ge    .vc_root
    ldr     x6, [x0, x4, lsl #3]  // chain[i] ptr
    add     x7, x4, #1
    ldr     x7, [x0, x7, lsl #3]  // chain[i+1] ptr
    ldr     x8, [x6, #8]          // chain[i].issuer
    ldr     x9, [x7]              // chain[i+1].subject
    cmp     x8, x9
    b.ne    .vc_zero
    add     x4, x4, #1
    b       .vc_link
.vc_root:
    sub     x4, x1, #1            // last index
    ldr     x5, [x0, x4, lsl #3]  // last cert ptr
    ldr     x5, [x5]              // last subject
    mov     x4, #0                // k
.vc_trust:
    cmp     x4, x3
    b.ge    .vc_zero
    ldr     x6, [x2, x4, lsl #3]
    ldr     x6, [x6]
    cmp     x6, x5
    b.eq    .vc_one
    add     x4, x4, #1
    b       .vc_trust
.vc_one:
    mov     x0, #1
    ret
.vc_zero:
    mov     x0, #0
    ret

// xor_stream(x0=out, x1=src, x2=len, x3=key)
xor_stream:
    mov     x4, #0
.xs_loop:
    cmp     x4, x2
    b.ge    .xs_done
    ldrb    w5, [x1, x4]
    eor     w5, w5, w3
    strb    w5, [x0, x4]
    add     x4, x4, #1
    b       .xs_loop
.xs_done:
    ret

// compute_tag(x0=buf, x1=len, x2=key, x3=nonce) -> x0
compute_tag:
    mov     x4, #0                // sum
    mov     x5, #0                // i
.ct_loop:
    cmp     x5, x1
    b.ge    .ct_done
    ldrb    w6, [x0, x5]
    add     x4, x4, x6
    add     x5, x5, #1
    b       .ct_loop
.ct_done:
    eor     x4, x4, x2
    eor     x0, x4, x3
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
    // Init chain_arr / trust_arr with cert pointers
    adrp    x0, leaf_cert
    add     x0, x0, :lo12:leaf_cert
    adrp    x1, chain_arr
    add     x1, x1, :lo12:chain_arr
    str     x0, [x1]
    adrp    x0, inter_cert
    add     x0, x0, :lo12:inter_cert
    str     x0, [x1, #8]
    adrp    x0, root_cert
    add     x0, x0, :lo12:root_cert
    str     x0, [x1, #16]
    adrp    x0, root_cert
    add     x0, x0, :lo12:root_cert
    adrp    x1, trust_arr
    add     x1, x1, :lo12:trust_arr
    str     x0, [x1]
    adrp    x0, bad_root
    add     x0, x0, :lo12:bad_root
    adrp    x1, bad_trust
    add     x1, x1, :lo12:bad_trust
    str     x0, [x1]

    // 1. pick_cipher → AES_128_GCM
    adrp    x0, srv_ciphers
    add     x0, x0, :lo12:srv_ciphers
    mov     x1, #2
    adrp    x2, cli_ciphers
    add     x2, x2, :lo12:cli_ciphers
    mov     x3, #2
    bl      pick_cipher
    ldr     x1, =0x1301
    bl      assert_eq

    // 2. legacy-only → 0
    adrp    x0, srv_legacy
    add     x0, x0, :lo12:srv_legacy
    mov     x1, #1
    adrp    x2, cli_ciphers
    add     x2, x2, :lo12:cli_ciphers
    mov     x3, #2
    bl      pick_cipher
    mov     x1, #0
    bl      assert_eq

    // 3. valid chain → 1
    adrp    x0, chain_arr
    add     x0, x0, :lo12:chain_arr
    mov     x1, #3
    adrp    x2, trust_arr
    add     x2, x2, :lo12:trust_arr
    mov     x3, #1
    bl      verify_chain
    mov     x1, #1
    bl      assert_eq

    // 4. untrusted root → 0
    adrp    x0, chain_arr
    add     x0, x0, :lo12:chain_arr
    mov     x1, #3
    adrp    x2, bad_trust
    add     x2, x2, :lo12:bad_trust
    mov     x3, #1
    bl      verify_chain
    mov     x1, #0
    bl      assert_eq

    // 5. AEAD round-trip
    adrp    x0, ct_buf
    add     x0, x0, :lo12:ct_buf
    adrp    x1, pt_text
    add     x1, x1, :lo12:pt_text
    mov     x2, #pt_len
    mov     x3, #42
    bl      xor_stream
    adrp    x0, pt_text
    add     x0, x0, :lo12:pt_text
    mov     x1, #pt_len
    mov     x2, #42
    mov     x3, #7
    bl      compute_tag
    mov     x19, x0               // tag (callee-saved)
    adrp    x0, pt_buf
    add     x0, x0, :lo12:pt_buf
    adrp    x1, ct_buf
    add     x1, x1, :lo12:ct_buf
    mov     x2, #pt_len
    mov     x3, #42
    bl      xor_stream
    adrp    x0, pt_buf
    add     x0, x0, :lo12:pt_buf
    mov     x1, #pt_len
    mov     x2, #42
    mov     x3, #7
    bl      compute_tag
    mov     x1, x19
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
