// Vidya — Syscalls and ABI in AArch64 Assembly
//
// AArch64 Linux syscall convention:
//   x8  = syscall number
//   x0-x5 = arguments (arg1-arg6)
//   Return value in x0 (negative = -errno on error)
//   Clobbered: none (unlike x86_64 which clobbers rcx/r11)
//   Preserved: x1-x7, x9-x29, x30 (LR), sp
//
// AArch64 function calling convention (AAPCS64):
//   x0-x7  = arguments and return values (x0-x1 for 128-bit return)
//   x8     = indirect result location register
//   x9-x15 = temporary (caller-saved/volatile)
//   x16-x17 = intra-procedure call scratch (IP0/IP1)
//   x18    = platform register (reserved on Linux)
//   x19-x28 = callee-saved (must be preserved across calls)
//   x29    = frame pointer (FP)
//   x30    = link register (LR) — return address from BL
//   sp     = stack pointer (must be 16-byte aligned)
//
// Key AArch64 syscall numbers differ from x86_64:
//   write = 64 (vs 1), read = 63 (vs 0), exit = 93 (vs 60),
//   getpid = 172 (vs 39), getuid = 174 (vs 102), getgid = 176 (vs 104)

.global _start

.section .rodata
msg_pass:   .ascii "All syscalls and ABI examples passed.\n"
msg_len = . - msg_pass
msg_pid:    .ascii "getpid succeeded.\n"
pid_len = . - msg_pid

.section .data
.align 8
result_buf: .quad 0

.section .text

_start:
    // ── sys_getpid (syscall 172) — simplest syscall, no args ──────
    // AArch64 syscall: x8 = number, svc #0 to invoke
    mov     x8, #172            // sys_getpid
    svc     #0
    // x0 now contains our PID (always > 0)
    cmp     x0, #0
    b.le    fail                // PID must be positive

    // Save PID in callee-saved register for later verification
    mov     x19, x0

    // Call getpid again — must return same value
    mov     x8, #172
    svc     #0
    cmp     x0, x19
    b.ne    fail                // PID should be stable

    // ── sys_write (syscall 64) — demonstrates 3 argument syscall ──
    // write(fd=1, buf=msg_pid, count=pid_len)
    mov     x8, #64             // sys_write
    mov     x0, #1              // fd = stdout
    adr     x1, msg_pid         // buf = message pointer
    mov     x2, pid_len         // count = message length
    svc     #0
    // Returns bytes written in x0
    cmp     x0, pid_len
    b.ne    fail                // should write all bytes

    // ── sys_getuid (syscall 174) — another no-arg syscall ─────────
    mov     x8, #174            // sys_getuid
    svc     #0
    // x0 = uid (>= 0)
    mov     x20, x0             // save uid

    // ── sys_getgid (syscall 176) ──────────────────────────────────
    mov     x8, #176            // sys_getgid
    svc     #0
    mov     x21, x0             // save gid

    // ── Function calling convention (AAPCS64) ─────────────────────
    // Integer arguments: x0-x7
    // Return value: x0 (and x1 for 128-bit)
    // Caller-saved (volatile):  x0-x15, x16-x17
    // Callee-saved (preserved): x19-x28, x29 (FP), x30 (LR)
    // x18 is platform-reserved (do not use)
    // Stack must be 16-byte aligned at all times

    // Demonstrate function call with arguments
    mov     x0, #10             // arg1
    mov     x1, #32             // arg2
    bl      add_two_numbers
    cmp     x0, #42
    b.ne    fail

    // Demonstrate that callee-saved registers are preserved
    mov     x19, #0xAAAA
    mov     x20, #0xBBBB
    mov     x21, #0xCCCC
    mov     x0, #100
    mov     x1, #200
    bl      add_with_callee_saves
    cmp     x0, #300
    b.ne    fail
    mov     x2, #0xAAAA
    cmp     x19, x2             // must be preserved
    b.ne    fail
    mov     x2, #0xBBBB
    cmp     x20, x2             // must be preserved
    b.ne    fail
    mov     x2, #0xCCCC
    cmp     x21, x2             // must be preserved
    b.ne    fail

    // ── AArch64 vs x86_64: no register clobbering by svc ─────────
    // Unlike x86_64 where syscall clobbers rcx and r11,
    // AArch64's svc does NOT clobber any registers except x0 (return).
    // This means x1-x7 are preserved across syscalls.
    mov     x1, #0xDEAD
    mov     x8, #172            // sys_getpid
    svc     #0
    // x1 should still be 0xDEAD
    mov     x2, #0xDEAD
    cmp     x1, x2
    b.ne    fail                // x1 must be preserved across svc

    // ── Stack alignment for function calls ────────────────────────
    // AArch64 requires SP to be 16-byte aligned AT ALL TIMES,
    // not just before calls. This is enforced by hardware — an
    // unaligned SP causes a stack alignment fault (unlike x86_64
    // where misalignment is merely a convention violation).
    //
    // BL stores return address in x30 (LR), not on the stack,
    // so the callee sees the same SP alignment the caller had.
    mov     x0, #5
    mov     x1, #7
    bl      add_two_numbers
    cmp     x0, #12
    b.ne    fail

    // ── Print success ─────────────────────────────────────────────
    mov     x8, #64
    mov     x0, #1
    adr     x1, msg_pass
    mov     x2, msg_len
    svc     #0

    mov     x8, #93             // sys_exit
    mov     x0, #0              // status = 0
    svc     #0

fail:
    mov     x8, #93
    mov     x0, #1
    svc     #0

// ── add_two_numbers ────────────────────────────────────────────────
// Args: x0 = a, x1 = b
// Returns: x0 = a + b
// Leaf function — no frame needed, no callee-saved regs used
add_two_numbers:
    add     x0, x0, x1
    ret

// ── add_with_callee_saves ──────────────────────────────────────────
// Args: x0 = a, x1 = b
// Returns: x0 = a + b
// Demonstrates proper callee-saved register preservation
add_with_callee_saves:
    stp     x19, x20, [sp, #-16]!   // save callee-saved registers
    mov     x19, x0                  // use callee-saved for local work
    mov     x20, x1
    add     x0, x19, x20            // compute result
    ldp     x19, x20, [sp], #16     // restore in same order
    ret
