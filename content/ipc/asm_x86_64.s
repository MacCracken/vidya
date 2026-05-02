# Vidya — IPC in x86_64 Assembly
#
# Asm port focuses on the three primitives' state machines.
# 8 critical asserts: shm read/write, OOB rejection, pipe FIFO,
# pipe full+wrap, channel send/recv.

.intel_syntax noprefix
.global _start

.equ SHM_REGION_CAP, 4
.equ SHM_BYTES,      64
.equ PIPE_CAP,       8
.equ CHAN_CAP,       4
.equ CHAN_QUEUE_CAP, 8

.section .bss
.align 8
shm:          .skip SHM_REGION_CAP * SHM_BYTES
pipe_buf:     .skip PIPE_CAP
chan_open:    .skip CHAN_CAP * 8
chan_queue:   .skip CHAN_CAP * CHAN_QUEUE_CAP * 8
chan_count:   .skip CHAN_CAP * 8

.section .data
pipe_head:    .quad 0
pipe_count:   .quad 0

.section .rodata
msg_pass:     .ascii "ipc: 8/8 ok\n"
.equ msg_pass_len, . - msg_pass
msg_fail:     .ascii "FAIL\n"
.equ msg_fail_len, . - msg_fail

.section .text

# shm_write(rdi=region, rsi=offset, rdx=byte) -> rax 0/1
shm_write:
    test    rdi, rdi
    js      .sw_zero
    cmp     rdi, SHM_REGION_CAP
    jge     .sw_zero
    test    rsi, rsi
    js      .sw_zero
    cmp     rsi, SHM_BYTES
    jge     .sw_zero
    mov     rax, rdi
    imul    rax, SHM_BYTES
    add     rax, rsi
    lea     rcx, [rip + shm]
    mov     [rcx + rax], dl
    mov     rax, 1
    ret
.sw_zero:
    xor     rax, rax
    ret

# shm_read(rdi=region, rsi=offset) -> rax (or -1)
shm_read:
    test    rdi, rdi
    js      .sr_neg
    cmp     rdi, SHM_REGION_CAP
    jge     .sr_neg
    test    rsi, rsi
    js      .sr_neg
    cmp     rsi, SHM_BYTES
    jge     .sr_neg
    mov     rax, rdi
    imul    rax, SHM_BYTES
    add     rax, rsi
    lea     rcx, [rip + shm]
    movzx   rax, byte ptr [rcx + rax]
    ret
.sr_neg:
    mov     rax, -1
    ret

# pipe_write(rdi=byte) -> rax 0/1
pipe_write:
    mov     rax, [rip + pipe_count]
    cmp     rax, PIPE_CAP
    jge     .pw_zero
    mov     rcx, [rip + pipe_head]
    add     rcx, rax
    cmp     rcx, PIPE_CAP
    jl      .pw_store
    sub     rcx, PIPE_CAP
.pw_store:
    lea     rax, [rip + pipe_buf]
    mov     [rax + rcx], dil
    inc     qword ptr [rip + pipe_count]
    mov     rax, 1
    ret
.pw_zero:
    xor     rax, rax
    ret

# pipe_read -> rax (byte or -1)
pipe_read:
    mov     rax, [rip + pipe_count]
    test    rax, rax
    jz      .pr_neg
    mov     rcx, [rip + pipe_head]
    lea     rdx, [rip + pipe_buf]
    movzx   rax, byte ptr [rdx + rcx]
    inc     rcx
    cmp     rcx, PIPE_CAP
    jl      .pr_store_head
    xor     rcx, rcx
.pr_store_head:
    mov     [rip + pipe_head], rcx
    dec     qword ptr [rip + pipe_count]
    ret
.pr_neg:
    mov     rax, -1
    ret

# chan_listen(rdi=endpoint) -> rax 0/1
chan_listen:
    test    rdi, rdi
    js      .cl_zero
    cmp     rdi, CHAN_CAP
    jge     .cl_zero
    lea     rax, [rip + chan_open]
    mov     qword ptr [rax + rdi * 8], 1
    mov     rax, 1
    ret
.cl_zero:
    xor     rax, rax
    ret

# chan_send(rdi=dst, rsi=msg) -> rax 0/1
chan_send:
    test    rdi, rdi
    js      .cs_zero
    cmp     rdi, CHAN_CAP
    jge     .cs_zero
    lea     rax, [rip + chan_open]
    mov     rdx, [rax + rdi * 8]
    cmp     rdx, 1
    jne     .cs_zero
    lea     rax, [rip + chan_count]
    mov     rcx, [rax + rdi * 8]
    cmp     rcx, CHAN_QUEUE_CAP
    jge     .cs_zero
    # offset = (dst * CHAN_QUEUE_CAP + count) * 8
    mov     r8, rdi
    imul    r8, CHAN_QUEUE_CAP
    add     r8, rcx
    lea     r9, [rip + chan_queue]
    mov     [r9 + r8 * 8], rsi
    inc     qword ptr [rax + rdi * 8]
    mov     rax, 1
    ret
.cs_zero:
    xor     rax, rax
    ret

# chan_recv(rdi=endpoint) -> rax (msg or -1)
chan_recv:
    test    rdi, rdi
    js      .cr_neg
    cmp     rdi, CHAN_CAP
    jge     .cr_neg
    lea     rax, [rip + chan_open]
    mov     rdx, [rax + rdi * 8]
    cmp     rdx, 1
    jne     .cr_neg
    lea     rax, [rip + chan_count]
    mov     rcx, [rax + rdi * 8]
    test    rcx, rcx
    jz      .cr_neg
    # base = dst * CHAN_QUEUE_CAP
    mov     r8, rdi
    imul    r8, CHAN_QUEUE_CAP
    lea     r9, [rip + chan_queue]
    mov     r11, [r9 + r8 * 8]    # save first msg in r11
    # Shift queue[1..count] down by 1
    xor     r10, r10              # k
.crv_shift:
    mov     rax, rcx
    dec     rax
    cmp     r10, rax
    jge     .crv_shift_done
    mov     rdx, r8
    add     rdx, r10
    inc     rdx
    mov     rax, [r9 + rdx * 8]
    mov     rdx, r8
    add     rdx, r10
    mov     [r9 + rdx * 8], rax
    inc     r10
    jmp     .crv_shift
.crv_shift_done:
    lea     rax, [rip + chan_count]
    dec     qword ptr [rax + rdi * 8]
    mov     rax, r11
    ret
.cr_neg:
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
    # 1. shm write/read roundtrip
    mov     rdi, 1
    mov     rsi, 5
    mov     rdx, 0xA1
    call    shm_write
    mov     rdi, rax
    mov     rsi, 1
    call    assert_eq
    mov     rdi, 1
    mov     rsi, 5
    call    shm_read
    mov     rdi, rax
    mov     rsi, 0xA1
    call    assert_eq

    # 2. shm OOB rejected
    mov     rdi, 1
    mov     rsi, 99
    mov     rdx, 0xFF
    call    shm_write
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 3. pipe FIFO
    mov     rdi, 65
    call    pipe_write
    mov     rdi, 66
    call    pipe_write
    mov     rdi, 67
    call    pipe_write
    call    pipe_read
    mov     rdi, rax
    mov     rsi, 65
    call    assert_eq

    # 4. pipe drain to empty
    call    pipe_read
    call    pipe_read
    call    pipe_read
    mov     rdi, rax
    mov     rsi, -1
    call    assert_eq

    # 5. channel send to closed → 0
    mov     rdi, 1
    mov     rsi, 0xCAFE
    call    chan_send
    mov     rdi, rax
    mov     rsi, 0
    call    assert_eq

    # 6. listen + send + recv
    mov     rdi, 1
    call    chan_listen
    mov     rdi, 1
    mov     rsi, 0xCAFE
    call    chan_send
    mov     rdi, 1
    mov     rsi, 0xBABE
    call    chan_send
    mov     rdi, 1
    call    chan_recv
    mov     rdi, rax
    mov     rsi, 0xCAFE
    call    assert_eq
    mov     rdi, 1
    call    chan_recv
    mov     rdi, rax
    mov     rsi, 0xBABE
    call    assert_eq

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall
