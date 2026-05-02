# Vidya — Write-Ahead Logging in x86_64 Assembly
#
# In-memory WAL: append a 24-byte log record (op, key, val) BEFORE
# mutating the data store, then replay the durable prefix on recovery.
# x86_64's flat memory + base+offset addressing is a perfect fit for the
# cyrius byte-buffer shape — each `mov [rip + log_buf + offset], rN`
# stores an i64 at a fixed offset and `imul rN, 24` produces the
# per-record stride. The 256-record cap and the OP_INVALID/SET/DEL
# constants match the cyrius reference. No real fsync — log_committed
# snapshots the durable prefix.

.intel_syntax noprefix
.global _start

.equ REC_SZ,        24
.equ LOG_CAP_BYTES, 6144
.equ OP_INVALID,    0
.equ OP_SET,        1
.equ OP_DEL,        2
.equ STORE_KEYS,    16

.section .data
log_offset:    .quad 0
log_committed: .quad 0

.section .bss
.align 8
log_buf:       .skip LOG_CAP_BYTES
data_vals:     .skip STORE_KEYS * 8
data_present:  .skip STORE_KEYS

.section .rodata
msg_pass:    .ascii "All write_ahead_logging examples passed.\n"
msg_pass_len = . - msg_pass
msg_fail:    .ascii "FAIL\n"
msg_fail_len = . - msg_fail

.section .text

# log_reset: clears offsets only (buffer wiped by reset_all).
log_reset:
    mov     qword ptr [rip + log_offset], 0
    mov     qword ptr [rip + log_committed], 0
    ret

# store_clear: zeroes data_vals and data_present.
store_clear:
    lea     rdi, [rip + data_vals]
    mov     rcx, STORE_KEYS * 8
    xor     al, al
    rep stosb
    lea     rdi, [rip + data_present]
    mov     rcx, STORE_KEYS
    xor     al, al
    rep stosb
    ret

# reset_all: wipe log buffer + offsets + store. A leftover record from
# a previous test would otherwise survive into the next replay.
reset_all:
    push    rbx
    call    log_reset
    call    store_clear
    lea     rdi, [rip + log_buf]
    mov     rcx, LOG_CAP_BYTES
    xor     al, al
    rep stosb
    pop     rbx
    ret

# log_append(rdi=op, rsi=key, rdx=val) -> rax = 1 ok / 0 full.
log_append:
    mov     rax, [rip + log_offset]
    mov     rcx, rax
    add     rcx, REC_SZ
    cmp     rcx, LOG_CAP_BYTES
    jg      .Lla_full
    lea     r8, [rip + log_buf]
    mov     [r8 + rax], rdi             # op
    mov     [r8 + rax + 8], rsi         # key
    mov     [r8 + rax + 16], rdx        # val
    add     rax, REC_SZ
    mov     [rip + log_offset], rax
    mov     rax, 1
    ret
.Lla_full:
    xor     rax, rax
    ret

# log_commit: snapshot offset as the durable prefix.
log_commit:
    mov     rax, [rip + log_offset]
    mov     [rip + log_committed], rax
    ret

# store_set(rdi=key, rsi=val) -> rax = 1 ok / 0 fail.
# WAL rule: log BEFORE data — log_append's failure short-circuits us.
store_set:
    push    rbx
    push    r12
    cmp     rdi, 0
    jl      .Lss_fail
    cmp     rdi, STORE_KEYS
    jge     .Lss_fail
    mov     rbx, rdi                    # save key
    mov     r12, rsi                    # save val
    mov     rdi, OP_SET
    mov     rsi, rbx
    mov     rdx, r12
    call    log_append
    test    rax, rax
    jz      .Lss_done                   # rax already 0
    lea     rcx, [rip + data_vals]
    mov     [rcx + rbx*8], r12
    lea     rcx, [rip + data_present]
    mov     byte ptr [rcx + rbx], 1
    mov     rax, 1
.Lss_done:
    pop     r12
    pop     rbx
    ret
.Lss_fail:
    xor     rax, rax
    pop     r12
    pop     rbx
    ret

# store_del(rdi=key) -> rax = 1 ok / 0 fail.
store_del:
    push    rbx
    cmp     rdi, 0
    jl      .Lsd_fail
    cmp     rdi, STORE_KEYS
    jge     .Lsd_fail
    mov     rbx, rdi
    mov     rdi, OP_DEL
    mov     rsi, rbx
    xor     rdx, rdx
    call    log_append
    test    rax, rax
    jz      .Lsd_done
    lea     rcx, [rip + data_vals]
    mov     qword ptr [rcx + rbx*8], 0
    lea     rcx, [rip + data_present]
    mov     byte ptr [rcx + rbx], 0
    mov     rax, 1
.Lsd_done:
    pop     rbx
    ret
.Lsd_fail:
    xor     rax, rax
    pop     rbx
    ret

# store_get(rdi=key) -> rax = value or -1.
store_get:
    cmp     rdi, 0
    jl      .Lsg_absent
    cmp     rdi, STORE_KEYS
    jge     .Lsg_absent
    lea     rcx, [rip + data_present]
    movzx   rax, byte ptr [rcx + rdi]
    test    rax, rax
    jz      .Lsg_absent
    lea     rcx, [rip + data_vals]
    mov     rax, [rcx + rdi*8]
    ret
.Lsg_absent:
    mov     rax, -1
    ret

# replay -> rax = applied count
replay:
    push    rbx
    call    store_clear
    xor     rcx, rcx                    # pos
    xor     rbx, rbx                    # applied
    lea     r8, [rip + log_buf]
    lea     r9, [rip + data_vals]
    lea     r10, [rip + data_present]
.Lrp_loop:
    cmp     rcx, [rip + log_committed]
    jge     .Lrp_done
    mov     rax, [r8 + rcx]             # op
    mov     rdi, [r8 + rcx + 8]         # key
    mov     rsi, [r8 + rcx + 16]        # val
    cmp     rax, OP_SET
    je      .Lrp_set
    cmp     rax, OP_DEL
    je      .Lrp_del
    jmp     .Lrp_next
.Lrp_set:
    mov     [r9 + rdi*8], rsi
    mov     byte ptr [r10 + rdi], 1
    inc     rbx
    jmp     .Lrp_next
.Lrp_del:
    mov     qword ptr [r9 + rdi*8], 0
    mov     byte ptr [r10 + rdi], 0
    inc     rbx
.Lrp_next:
    add     rcx, REC_SZ
    jmp     .Lrp_loop
.Lrp_done:
    mov     rax, rbx
    pop     rbx
    ret

# expect_eq(rdi, rsi): exits on mismatch.
expect_eq:
    cmp     rdi, rsi
    jne     fail
    ret

# load64_buf(rdi=offset) -> rax = log_buf[offset..]
load64_buf:
    lea     rcx, [rip + log_buf]
    mov     rax, [rcx + rdi]
    ret

_start:
    # --- test_append_and_replay ---
    call    reset_all
    mov     rdi, 0
    mov     rsi, 100
    call    store_set
    mov     rdi, 1
    mov     rsi, 200
    call    store_set
    mov     rdi, 2
    mov     rsi, 300
    call    store_set
    call    log_commit
    call    store_clear
    call    replay
    mov     rdi, rax
    mov     rsi, 3
    call    expect_eq
    mov     rdi, 0
    call    store_get
    mov     rdi, rax
    mov     rsi, 100
    call    expect_eq
    mov     rdi, 1
    call    store_get
    mov     rdi, rax
    mov     rsi, 200
    call    expect_eq
    mov     rdi, 2
    call    store_get
    mov     rdi, rax
    mov     rsi, 300
    call    expect_eq

    # --- test_log_before_data_invariant ---
    call    reset_all
    mov     rdi, 5
    mov     rsi, 42
    call    store_set
    mov     rdi, rax
    mov     rsi, 1
    call    expect_eq
    mov     rdi, 0
    call    load64_buf
    mov     rdi, rax
    mov     rsi, OP_SET
    call    expect_eq
    mov     rdi, 8
    call    load64_buf
    mov     rdi, rax
    mov     rsi, 5
    call    expect_eq
    mov     rdi, 16
    call    load64_buf
    mov     rdi, rax
    mov     rsi, 42
    call    expect_eq
    mov     rdi, 5
    call    store_get
    mov     rdi, rax
    mov     rsi, 42
    call    expect_eq

    # --- test_uncommitted_writes_lost_on_crash ---
    call    reset_all
    mov     rdi, 0
    mov     rsi, 1
    call    store_set
    mov     rdi, 1
    mov     rsi, 2
    call    store_set
    call    log_commit
    mov     rdi, 2
    mov     rsi, 3
    call    store_set
    mov     rdi, 3
    mov     rsi, 4
    call    store_set
    call    store_clear
    call    replay
    mov     rdi, rax
    mov     rsi, 2
    call    expect_eq
    mov     rdi, 0
    call    store_get
    mov     rdi, rax
    mov     rsi, 1
    call    expect_eq
    mov     rdi, 1
    call    store_get
    mov     rdi, rax
    mov     rsi, 2
    call    expect_eq
    mov     rdi, 2
    call    store_get
    mov     rdi, rax
    mov     rsi, -1
    call    expect_eq
    mov     rdi, 3
    call    store_get
    mov     rdi, rax
    mov     rsi, -1
    call    expect_eq

    # --- test_delete_replays_correctly ---
    call    reset_all
    mov     rdi, 0
    mov     rsi, 100
    call    store_set
    mov     rdi, 1
    mov     rsi, 200
    call    store_set
    mov     rdi, 0
    call    store_del
    call    log_commit
    call    store_clear
    call    replay
    mov     rdi, 0
    call    store_get
    mov     rdi, rax
    mov     rsi, -1
    call    expect_eq
    mov     rdi, 1
    call    store_get
    mov     rdi, rax
    mov     rsi, 200
    call    expect_eq

    # --- test_overwrite_uses_last_record ---
    call    reset_all
    mov     rdi, 7
    mov     rsi, 100
    call    store_set
    mov     rdi, 7
    mov     rsi, 200
    call    store_set
    mov     rdi, 7
    mov     rsi, 300
    call    store_set
    call    log_commit
    call    store_clear
    call    replay
    mov     rdi, 7
    call    store_get
    mov     rdi, rax
    mov     rsi, 300
    call    expect_eq

    # --- test_sequential_offsets_monotonic ---
    call    reset_all
    mov     r12, [rip + log_offset]     # prev
    xor     r13, r13                    # i
.Lmono_loop:
    cmp     r13, 5
    jge     .Lmono_done
    mov     rdi, r13
    mov     rsi, r13
    imul    rsi, rsi, 10
    call    store_set
    mov     rax, [rip + log_offset]
    cmp     rax, r12
    jle     fail
    mov     r12, rax
    inc     r13
    jmp     .Lmono_loop
.Lmono_done:

    # --- test_log_capacity_limit ---
    call    reset_all
    xor     r13, r13                    # i
    xor     r14, r14                    # failures
.Lcap_loop:
    cmp     r13, 300
    jge     .Lcap_done
    mov     rdi, 0
    mov     rsi, r13
    call    store_set
    test    rax, rax
    jnz     .Lcap_skip
    inc     r14
.Lcap_skip:
    inc     r13
    jmp     .Lcap_loop
.Lcap_done:
    test    r14, r14
    jz      fail

    # --- Done — write success and exit 0 ---
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [rip + msg_pass]
    mov     rdx, msg_pass_len
    syscall
    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 1
    mov     rdi, 2
    lea     rsi, [rip + msg_fail]
    mov     rdx, msg_fail_len
    syscall
    mov     rax, 60
    mov     rdi, 1
    syscall
