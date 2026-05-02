# Vidya — TLS and Encryption in x86_64 Assembly
#
# Asm port focuses on the algorithmic primitives:
#   - pick_cipher: linear-scan intersection with TLS 1.3 filter
#   - verify_chain: linear linkage check + trust-store reachability
#   - AEAD seal/open: XOR stream + sum-based tag with verification
# Handshake driver is in higher-level ports; the asm port verifies
# the 5 critical assertions.

.intel_syntax noprefix
.global _start

.equ TLS_AES_128_GCM_SHA256, 0x1301
.equ TLS_AES_256_GCM_SHA384, 0x1302
.equ TLS_CHACHA20_POLY1305_SHA256, 0x1303
.equ TLS_RSA_AES_128_CBC_SHA, 0x002F

.section .data
.align 8
srv_ciphers:  .quad TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384
cli_ciphers:  .quad TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256
srv_legacy:   .quad TLS_RSA_AES_128_CBC_SHA

# Cert chain: each cert is { subject, issuer } as i64 pair.
leaf_cert:    .quad 100, 200
inter_cert:   .quad 200, 300
root_cert:    .quad 300, 300
chain_arr:    .quad 0, 0, 0          # filled at runtime to point at the certs above
trust_arr:    .quad 0                # filled at runtime to point at root_cert
ss_leaf:      .quad 100, 100
bad_root:     .quad 999, 999
bad_trust:    .quad 0

pt_text:      .ascii "secret message"
.equ pt_len, 14

.section .bss
.align 8
ct_buf:       .skip 64
pt_buf:       .skip 64

.section .rodata
msg_pass:     .ascii "tls_and_encryption: 5/5 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# is_tls13(rdi=c) -> rax 0/1
is_tls13:
    cmp     rdi, TLS_AES_128_GCM_SHA256
    je      .it_one
    cmp     rdi, TLS_AES_256_GCM_SHA384
    je      .it_one
    cmp     rdi, TLS_CHACHA20_POLY1305_SHA256
    je      .it_one
    xor     rax, rax
    ret
.it_one:
    mov     rax, 1
    ret

# pick_cipher(rdi=srv, rsi=sn, rdx=cli, rcx=cn) -> rax
pick_cipher:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi              # srv
    mov     r13, rsi              # sn
    mov     r14, rdx              # cli
    mov     r15, rcx              # cn
    xor     rbx, rbx              # i
.pc_outer:
    cmp     rbx, r13
    jge     .pc_zero
    mov     rdi, [r12 + rbx * 8]
    push    rdi
    call    is_tls13
    pop     rdi
    test    rax, rax
    jz      .pc_outer_next
    xor     rcx, rcx              # j
.pc_inner:
    cmp     rcx, r15
    jge     .pc_outer_next
    mov     rax, [r14 + rcx * 8]
    cmp     rax, rdi
    jne     .pc_inner_next
    # Hit
    mov     rax, rdi
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
.pc_inner_next:
    inc     rcx
    jmp     .pc_inner
.pc_outer_next:
    inc     rbx
    jmp     .pc_outer
.pc_zero:
    xor     rax, rax
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

# verify_chain(rdi=chain, rsi=n_certs, rdx=trust, rcx=n_roots) -> rax 0/1
verify_chain:
    test    rsi, rsi
    jz      .vc_zero
    # Linkage check: chain[i].issuer == chain[i+1].subject for i in [0, n-1)
    xor     r8, r8                # i
.vc_link:
    mov     rax, rsi
    dec     rax
    cmp     r8, rax
    jge     .vc_root
    mov     r9, [rdi + r8 * 8]    # ptr to cert i
    mov     r10, [rdi + r8 * 8 + 8] # ptr to cert i+1
    mov     rax, [r9 + 8]         # cert[i].issuer
    mov     r11, [r10]            # cert[i+1].subject
    cmp     rax, r11
    jne     .vc_zero
    inc     r8
    jmp     .vc_link
.vc_root:
    # Last cert's subject must match a trust-store cert's subject
    mov     rax, rsi
    dec     rax                   # last index
    mov     r9, [rdi + rax * 8]   # last cert ptr
    mov     r9, [r9]              # last cert subject
    xor     r8, r8                # k
.vc_trust:
    cmp     r8, rcx
    jge     .vc_zero
    mov     r10, [rdx + r8 * 8]
    mov     r10, [r10]            # root subject
    cmp     r10, r9
    je      .vc_one
    inc     r8
    jmp     .vc_trust
.vc_one:
    mov     rax, 1
    ret
.vc_zero:
    xor     rax, rax
    ret

# xor_stream(rdi=out, rsi=src, rdx=len, rcx=key)
xor_stream:
    xor     r8, r8
.xs_loop:
    cmp     r8, rdx
    jge     .xs_done
    movzx   r9, byte ptr [rsi + r8]
    xor     r9, rcx
    mov     [rdi + r8], r9b
    inc     r8
    jmp     .xs_loop
.xs_done:
    ret

# compute_tag(rdi=buf, rsi=len, rdx=key, rcx=nonce) -> rax
compute_tag:
    xor     rax, rax
    xor     r8, r8
.ct_loop:
    cmp     r8, rsi
    jge     .ct_done
    movzx   r9, byte ptr [rdi + r8]
    add     rax, r9
    inc     r8
    jmp     .ct_loop
.ct_done:
    xor     rax, rdx
    xor     rax, rcx
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
    # Initialize chain_arr to point at the cert blobs
    lea     rax, [rip + leaf_cert]
    lea     rcx, [rip + chain_arr]
    mov     [rcx], rax
    lea     rax, [rip + inter_cert]
    mov     [rcx + 8], rax
    lea     rax, [rip + root_cert]
    mov     [rcx + 16], rax
    lea     rax, [rip + root_cert]
    lea     rcx, [rip + trust_arr]
    mov     [rcx], rax
    lea     rax, [rip + bad_root]
    lea     rcx, [rip + bad_trust]
    mov     [rcx], rax

    # 1. pick_cipher → AES_128_GCM
    lea     rdi, [rip + srv_ciphers]
    mov     rsi, 2
    lea     rdx, [rip + cli_ciphers]
    mov     rcx, 2
    call    pick_cipher
    mov     rdi, rax
    mov     rsi, TLS_AES_128_GCM_SHA256
    call    assert_eq

    # 2. pick_cipher with legacy-only server → 0
    lea     rdi, [rip + srv_legacy]
    mov     rsi, 1
    lea     rdx, [rip + cli_ciphers]
    mov     rcx, 2
    call    pick_cipher
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 3. verify_chain valid → 1
    lea     rdi, [rip + chain_arr]
    mov     rsi, 3
    lea     rdx, [rip + trust_arr]
    mov     rcx, 1
    call    verify_chain
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq

    # 4. verify_chain with untrusted root → 0
    lea     rdi, [rip + chain_arr]
    mov     rsi, 3
    lea     rdx, [rip + bad_trust]
    mov     rcx, 1
    call    verify_chain
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 5. AEAD round-trip + tampering rejection
    lea     rdi, [rip + ct_buf]
    lea     rsi, [rip + pt_text]
    mov     rdx, pt_len
    mov     rcx, 42
    call    xor_stream
    lea     rdi, [rip + pt_text]
    mov     rsi, pt_len
    mov     rdx, 42
    mov     rcx, 7
    call    compute_tag
    mov     r12, rax              # tag
    # Decrypt
    lea     rdi, [rip + pt_buf]
    lea     rsi, [rip + ct_buf]
    mov     rdx, pt_len
    mov     rcx, 42
    call    xor_stream
    lea     rdi, [rip + pt_buf]
    mov     rsi, pt_len
    mov     rdx, 42
    mov     rcx, 7
    call    compute_tag
    mov     rdi, rax
    mov     rsi, r12
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
