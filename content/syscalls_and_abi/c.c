// Vidya — Syscalls and ABI in C
//
// Demonstrates Linux x86_64 syscalls and System V AMD64 ABI:
//   - Direct syscall via inline assembly (no libc wrapper)
//   - syscall() wrapper from unistd.h
//   - System V AMD64 calling convention register assignments
//   - Syscall error handling (negative return = errno)
//   - SYSCALL clobbers RCX and R11
//   - Stack alignment requirements

#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

// ── Linux x86_64 syscall numbers ──────────────────────────────────
// From arch/x86/entry/syscalls/syscall_64.tbl in the Linux source.
// These are stable ABI — they never change.

#define NR_READ    0
#define NR_WRITE   1
#define NR_OPEN    2
#define NR_CLOSE   3
#define NR_BRK    12
#define NR_GETPID 39
#define NR_EXIT   60

// ── Raw syscall via inline assembly ───────────────────────────────
//
// SYSCALL instruction:
//   Input:  RAX = syscall number
//           RDI = arg1, RSI = arg2, RDX = arg3
//           R10 = arg4, R8 = arg5, R9 = arg6
//   Output: RAX = return value (or negated errno on error)
//   Clobbers: RCX (CPU saves RIP there), R11 (CPU saves RFLAGS there)
//
// Note: 4th arg is R10, NOT RCX — because SYSCALL overwrites RCX.

static long raw_syscall3(long nr, long a1, long a2, long a3) {
    long ret;
    __asm__ volatile (
        "syscall"
        : "=a" (ret)                          // output: RAX = return
        : "a" (nr), "D" (a1), "S" (a2), "d" (a3) // inputs: RAX, RDI, RSI, RDX
        : "rcx", "r11", "memory"              // clobbers: RCX, R11
    );
    return ret;
}

static long raw_syscall1(long nr, long a1) {
    long ret;
    __asm__ volatile (
        "syscall"
        : "=a" (ret)
        : "a" (nr), "D" (a1)
        : "rcx", "r11", "memory"
    );
    return ret;
}

static long raw_syscall0(long nr) {
    long ret;
    __asm__ volatile (
        "syscall"
        : "=a" (ret)
        : "a" (nr)
        : "rcx", "r11", "memory"
    );
    return ret;
}

// ── Syscall error checking ────────────────────────────────────────
// Linux returns negative values in [-4095, -1] on error.
// The negative value IS the errno.

static int is_syscall_error(long result) {
    return result >= -4095 && result < 0;
}

static const char *errno_name(long err) {
    switch (err) {
        case 1:  return "EPERM";
        case 2:  return "ENOENT";
        case 9:  return "EBADF";
        case 12: return "ENOMEM";
        case 13: return "EACCES";
        case 14: return "EFAULT";
        case 22: return "EINVAL";
        default: return "unknown";
    }
}

// ── System V AMD64 calling convention demonstration ───────────────
//
// Integer/pointer arguments: RDI, RSI, RDX, RCX, R8, R9
// Return value: RAX
// Caller-saved (volatile): RAX, RCX, RDX, RSI, RDI, R8-R11
// Callee-saved (non-volatile): RBX, RBP, R12-R15
// Stack: 16-byte aligned before CALL

// Force no inlining so the calling convention is actually used.
__attribute__((noinline))
long six_args(long a, long b, long c, long d, long e, long f) {
    // a → RDI, b → RSI, c → RDX, d → RCX, e → R8, f → R9
    return a + b + c + d + e + f;
}

__attribute__((noinline))
long seven_args(long a, long b, long c, long d, long e, long f, long g) {
    // a-f in registers, g on stack at [RSP+8] after return address
    return a + b + c + d + e + f + g;
}

// ── Large struct return — hidden pointer in RDI ───────────────────

typedef struct {
    long a, b, c, d;  // 32 bytes — too large for register return
} BigStruct;

__attribute__((noinline))
BigStruct make_big_struct(long x) {
    // The caller passes a hidden pointer in RDI for the return value.
    // Our 'x' parameter is actually in RSI (shifted right by one).
    BigStruct result = { x, x * 2, x * 3, x * 4 };
    return result;
}

int main(void) {
    printf("Syscalls and ABI — C demonstration:\n\n");

    // ── Direct syscalls via inline assembly ───────────────────────
    printf("1. Direct syscalls (inline assembly, no libc wrappers):\n");

    // write(1, "hello\n", ...) — syscall nr 1
    const char *msg = "  Hello from raw syscall!\n";
    long written = raw_syscall3(NR_WRITE, 1, (long)msg, (long)strlen(msg));
    if (is_syscall_error(written)) {
        printf("  write failed: errno %ld (%s)\n", -written, errno_name(-written));
    } else {
        printf("  write returned: %ld bytes\n", written);
    }
    assert(written == (long)strlen(msg));

    // getpid() — syscall nr 39, no arguments
    long pid = raw_syscall0(NR_GETPID);
    printf("  getpid via raw syscall: %ld\n", pid);
    assert(pid > 0);

    // Verify against libc's getpid
    pid_t libc_pid = getpid();
    printf("  getpid via libc:        %d\n", libc_pid);
    assert(pid == libc_pid);

    // brk(0) — query current heap break
    long brk_current = raw_syscall1(NR_BRK, 0);
    printf("  brk(0) = 0x%lX (current heap break)\n", brk_current);
    assert(brk_current > 0);

    // write to bad fd — error demonstration
    long bad_write = raw_syscall3(NR_WRITE, 999, (long)"nope", 4);
    printf("  write(fd=999) = %ld → errno %ld (%s)\n",
           bad_write, -bad_write, errno_name(-bad_write));
    assert(is_syscall_error(bad_write));

    // ── syscall() wrapper from unistd.h ───────────────────────────
    printf("\n2. syscall() wrapper (libc provides this):\n");

    long pid2 = syscall(SYS_getpid);
    printf("  syscall(SYS_getpid) = %ld\n", pid2);
    assert(pid2 == pid);

    // ── Calling convention demonstration ──────────────────────────
    printf("\n3. System V AMD64 calling convention:\n");

    long sum6 = six_args(1, 2, 3, 4, 5, 6);
    printf("  six_args(1..6) = %ld (args in RDI,RSI,RDX,RCX,R8,R9)\n", sum6);
    assert(sum6 == 21);

    long sum7 = seven_args(1, 2, 3, 4, 5, 6, 7);
    printf("  seven_args(1..7) = %ld (6 in regs, 7th on stack)\n", sum7);
    assert(sum7 == 28);

    // ── Large struct return ───────────────────────────────────────
    printf("\n4. Large struct return (hidden pointer in RDI):\n");

    BigStruct big = make_big_struct(10);
    printf("  make_big_struct(10) = {%ld, %ld, %ld, %ld}\n",
           big.a, big.b, big.c, big.d);
    printf("  sizeof(BigStruct) = %zu bytes (>16, so hidden pointer used)\n",
           sizeof(BigStruct));
    assert(big.a == 10 && big.b == 20 && big.c == 30 && big.d == 40);

    // ── Register summary ──────────────────────────────────────────
    printf("\n5. Register mapping comparison:\n");
    printf("  %-8s %-10s %-10s\n", "Arg", "Syscall", "Function");
    printf("  %-8s %-10s %-10s\n", "---", "-------", "--------");

    const char *sys_regs[] =  {"rdi", "rsi", "rdx", "r10", "r8", "r9"};
    const char *func_regs[] = {"rdi", "rsi", "rdx", "rcx", "r8", "r9"};
    for (int i = 0; i < 6; i++) {
        const char *mark = strcmp(sys_regs[i], func_regs[i]) != 0 ? " <-" : "";
        printf("  %-8d %-10s %-10s%s\n", i + 1, sys_regs[i], func_regs[i], mark);
    }
    printf("  (<- marks the difference: 4th arg is R10 for syscalls, RCX for calls)\n");

    // ── Key facts ─────────────────────────────────────────────────
    printf("\n6. Key facts:\n");
    printf("  - SYSCALL clobbers RCX (saves RIP) and R11 (saves RFLAGS)\n");
    printf("  - Negative return in [-4095,-1] = error (negate for errno)\n");
    printf("  - Stack must be 16-byte aligned before CALL\n");
    printf("  - Structs >16 bytes returned via hidden pointer in RDI\n");
    printf("  - Red zone: 128 bytes below RSP usable by leaf functions\n");

    return 0;
}
