# Vidya — Tracing in x86_64 Assembly
#
# At the assembly level, tracing is write() syscalls with context:
# function name, timing, and data values. The rdtsc instruction reads
# the CPU timestamp counter — hardware-level profiling with cycle
# accuracy. A trace line is built by writing strings and converting
# numbers to decimal ASCII, then emitting everything via sys_write.

.intel_syntax noprefix
.global _start

.section .rodata
trace_enter:    .ascii "[TRACE] enter "
trace_enter_len = . - trace_enter

trace_exit:     .ascii "[TRACE] exit  "
trace_exit_len = . - trace_exit

trace_cycles:   .ascii " cycles="
trace_cycles_len = . - trace_cycles

trace_nl:       .ascii "\n"

fn_start:       .ascii "_start"
fn_start_len = . - fn_start

fn_work:        .ascii "do_work"
fn_work_len = . - fn_work

msg_pass:       .ascii "All tracing examples passed.\n"
msg_len = . - msg_pass

.section .bss
# Buffer for number-to-string conversion
numbuf:     .skip 24
# Buffer for storing timestamps
ts_start:   .skip 8
ts_end:     .skip 8

.section .text

_start:
    # ── Trace entry to _start ──────────────────────────────────────
    lea     rdi, [fn_start]
    mov     esi, fn_start_len
    call    trace_fn_enter

    # ── Read rdtsc: timestamp counter ──────────────────────────────
    # rdtsc puts low 32 bits in eax, high 32 bits in edx.
    # Combine into a single 64-bit value.
    call    read_tsc
    mov     qword ptr [ts_start], rax

    # ── Do some measurable work ────────────────────────────────────
    lea     rdi, [fn_work]
    mov     esi, fn_work_len
    call    trace_fn_enter

    call    do_work
    mov     rbx, rax            # save work result

    lea     rdi, [fn_work]
    mov     esi, fn_work_len
    call    trace_fn_exit

    # Verify work result
    cmp     ebx, 5050           # sum of 1..100 = 5050
    jne     fail

    # ── Read rdtsc again and compute delta ─────────────────────────
    call    read_tsc
    mov     qword ptr [ts_end], rax

    # Compute elapsed cycles
    mov     rax, qword ptr [ts_end]
    sub     rax, qword ptr [ts_start]
    # rax = elapsed cycles (will vary per run)

    # Verify elapsed > 0 (rdtsc should advance)
    test    rax, rax
    jz      fail

    # ── Print elapsed cycles as a trace line ───────────────────────
    push    rax
    # Print: "[TRACE] exit  _start cycles=NNNN\n"
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [trace_exit]
    mov     rdx, trace_exit_len
    syscall

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [fn_start]
    mov     rdx, fn_start_len
    syscall

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [trace_cycles]
    mov     rdx, trace_cycles_len
    syscall

    pop     rdi                 # elapsed cycles
    call    print_u64

    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [trace_nl]
    mov     rdx, 1
    syscall

    # ── Test u64_to_str conversion ─────────────────────────────────
    # Convert known number, verify string
    mov     rdi, 12345
    lea     rsi, [numbuf]
    call    u64_to_str
    # rax = length, rsi = start of digits in numbuf
    cmp     eax, 5              # "12345" = 5 chars
    jne     fail

    # Verify first digit is '1'
    cmp     byte ptr [rsi], '1'
    jne     fail
    cmp     byte ptr [rsi + 4], '5'
    jne     fail

    # Test zero
    mov     rdi, 0
    lea     rsi, [numbuf]
    call    u64_to_str
    cmp     eax, 1              # "0" = 1 char
    jne     fail
    cmp     byte ptr [rsi], '0'
    jne     fail

    # ── Test rdtsc monotonicity ────────────────────────────────────
    # Two reads should be monotonically increasing
    call    read_tsc
    mov     rbx, rax
    call    read_tsc
    cmp     rax, rbx
    jb      fail               # second reading should be >= first

    # ── Print success ──────────────────────────────────────────────
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [msg_pass]
    mov     rdx, msg_len
    syscall

    mov     rax, 60
    xor     rdi, rdi
    syscall

fail:
    mov     rax, 60
    mov     rdi, 1
    syscall

# ── read_tsc() → rax: 64-bit timestamp counter ────────────────────
# rdtsc returns edx:eax. We combine into rax.
read_tsc:
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    ret

# ── u64_to_str(rdi=value, rsi=buf) → rax=len, rsi=start ───────────
# Converts a 64-bit unsigned integer to decimal ASCII.
# Writes digits into buf from the end, returns pointer to first digit.
u64_to_str:
    push    rbx
    lea     rbx, [rsi + 23]     # point to end of buffer
    mov     byte ptr [rbx], 0   # null terminate (not used, but safe)
    mov     rax, rdi            # value to convert
    mov     rcx, 10

    # Special case: zero
    test    rax, rax
    jnz     .u2s_loop
    dec     rbx
    mov     byte ptr [rbx], '0'
    mov     rsi, rbx
    mov     eax, 1
    pop     rbx
    ret

.u2s_loop:
    test    rax, rax
    jz      .u2s_done
    xor     edx, edx
    div     rcx                 # rax = quotient, rdx = remainder
    dec     rbx
    add     dl, '0'
    mov     byte ptr [rbx], dl
    jmp     .u2s_loop

.u2s_done:
    mov     rsi, rbx            # pointer to first digit
    lea     rax, [rsi + 23]
    sub     rax, rbx            # length = (buf+23) - start
    # rax was rsi+23 before sub, recalculate properly
    mov     rax, rsi
    push    rdi
    lea     rdi, [numbuf + 23]
    sub     rdi, rax            # length
    mov     rax, rdi
    pop     rdi
    pop     rbx
    ret

# ── print_u64(rdi=value) — print decimal number to stdout ──────────
print_u64:
    push    rdi
    lea     rsi, [numbuf]
    call    u64_to_str
    # rax = length, rsi = start
    mov     rdx, rax            # length
    mov     rax, 1              # sys_write
    mov     rdi, 1              # stdout
    syscall
    pop     rdi
    ret

# ── trace_fn_enter(rdi=name, esi=name_len) — print entry trace ─────
trace_fn_enter:
    push    rdi
    push    rsi
    # Print "[TRACE] enter "
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [trace_enter]
    mov     rdx, trace_enter_len
    syscall
    pop     rsi
    pop     rdi
    # Print function name
    push    rdi
    push    rsi
    mov     rdx, rsi            # length
    mov     rsi, rdi            # name pointer — but rdi is about to be fd
    mov     rdi, 1              # fd = stdout
    mov     rax, 1
    # rsi was set to name pointer above... but we need to fix order
    # rdi=name, rsi=name_len on stack; we popped into rsi,rdi reversed
    # Let's redo:
    pop     rdx                 # name_len (was pushed as rsi)
    pop     rsi                 # name (was pushed as rdi)
    mov     rax, 1
    mov     rdi, 1
    syscall
    # Print newline
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [trace_nl]
    mov     rdx, 1
    syscall
    ret

# ── trace_fn_exit(rdi=name, esi=name_len) — print exit trace ───────
trace_fn_exit:
    push    rdi
    push    rsi
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [trace_exit]
    mov     rdx, trace_exit_len
    syscall
    pop     rdx                 # name_len
    pop     rsi                 # name
    mov     rax, 1
    mov     rdi, 1
    syscall
    mov     rax, 1
    mov     rdi, 1
    lea     rsi, [trace_nl]
    mov     rdx, 1
    syscall
    ret

# ── do_work() → eax: sum of 1..100 ────────────────────────────────
# Gives rdtsc something to measure.
do_work:
    xor     eax, eax
    mov     ecx, 1
.dw_loop:
    add     eax, ecx
    inc     ecx
    cmp     ecx, 101
    jl      .dw_loop
    ret
