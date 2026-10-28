# Vidya — Error Handling in x86_64 Assembly
#
# At the assembly level, errors are communicated through return values
# in registers (rax), condition flags (CF, ZF), and errno. System calls
# return negative values on error. There are no exceptions — you branch
# on every potentially failing operation.

.intel_syntax noprefix
.global _start

.section .rodata
msg_pass:   .ascii "All error handling examples passed.\n"
msg_len = . - msg_pass

.section .text

_start:
    # ── Syscall error checking ──────────────────────────────────────
    # sys_write returns bytes written, or negative errno on error
    # Write to stdout (should succeed)
    mov     rax, 1              # sys_write
    mov     rdi, 1              # fd = stdout
    lea     rsi, [msg_pass]
    mov     rdx, 1              # write 1 byte
    syscall
    test    rax, rax
    js      fail                # jump if negative (error)
    cmp     rax, 1              # should have written 1 byte
    jne     fail

    # ── Invalid fd: syscall returns -EBADF ──────────────────────────
    mov     rax, 1              # sys_write
    mov     rdi, 999            # invalid fd
    lea     rsi, [msg_pass]
    mov     rdx, 1
    syscall
    test    rax, rax
    jns     fail                # should be negative (error)
    # rax = -9 (EBADF)
    cmp     rax, -9
    jne     fail

    # ── Function return codes ───────────────────────────────────────
    # Convention: rax = 0 success, nonzero = error code
    mov     rdi, 42
    mov     rsi, 2
    call    safe_divide
    test    edx, edx            # edx = error flag
    jnz     fail
    cmp     eax, 21             # 42 / 2 = 21
    jne     fail

    # Division by zero: returns error
    mov     rdi, 42
    xor     rsi, rsi            # divisor = 0
    call    safe_divide
    test    edx, edx
    jz      fail                # should have error flag set

    # ── Flags-based error signaling ─────────────────────────────────
    # Carry flag (CF) as error indicator
    mov     rdi, 100
    mov     rsi, 50
    call    safe_subtract       # 100 - 50 = 50, no underflow
    jc      fail                # CF set = error
    cmp     rax, 50
    jne     fail

    # Underflow case
    mov     rdi, 50
    mov     rsi, 100
    call    safe_subtract       # 50 - 100 = underflow
    jnc     fail                # CF should be set

    # ── Bounds checking ─────────────────────────────────────────────
    # Check array index is in bounds before access
    mov     rdi, 3              # index
    mov     rsi, 10             # array length
    call    check_bounds
    test    eax, eax
    jnz     fail                # should be in bounds (0)

    mov     rdi, 15             # out of bounds index
    mov     rsi, 10
    call    check_bounds
    test    eax, eax
    jz      fail                # should be out of bounds (nonzero)

    # ── Print success ───────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    # ── Exit success ────────────────────────────────────────────────
    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── safe_divide: rdi / rsi ──────────────────────────────────────────
# Returns: eax = quotient, edx = 0 (ok) or 1 (error)
safe_divide:
    test    rsi, rsi
    jz      .div_error
    mov     rax, rdi
    xor     edx, edx
    div     rsi                 # rax = quotient, rdx = remainder
    xor     edx, edx            # edx = 0 = success
    ret
.div_error:
    xor     eax, eax
    mov     edx, 1              # edx = 1 = error
    ret

# ── safe_subtract: rdi - rsi (unsigned) ─────────────────────────────
# Returns: rax = result, CF = set on underflow
safe_subtract:
    mov     rax, rdi
    sub     rax, rsi            # CF set if rsi > rdi
    ret

# ── check_bounds: is rdi < rsi? ────────────────────────────────────
# Returns: eax = 0 (in bounds) or 1 (out of bounds)
check_bounds:
    xor     eax, eax
    cmp     rdi, rsi
    jb      .bounds_ok
    mov     eax, 1
.bounds_ok:
    ret
