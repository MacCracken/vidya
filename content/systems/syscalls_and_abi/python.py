# Vidya — Syscalls and ABI in Python
#
# Python can't execute raw SYSCALL instructions, but it can invoke
# syscalls through ctypes and the os module. This demonstrates:
#   - Linux x86_64 syscall number table
#   - System V AMD64 ABI register mapping for syscalls
#   - Making raw syscalls via ctypes (libc's syscall() wrapper)
#   - SYSCALL instruction clobbers RCX and R11
#   - Difference between syscall ABI and function-call ABI

import ctypes
import ctypes.util
import os
import sys

def main():
    # ── Syscall number table (Linux x86_64) ────────────────────────
    # These are assigned by the kernel and never change (stable ABI).
    # See: arch/x86/entry/syscalls/syscall_64.tbl in the Linux source.

    SYSCALL_TABLE = {
        "read":    0,
        "write":   1,
        "open":    2,
        "close":   3,
        "brk":    12,
        "getpid": 39,
        "exit":   60,
    }

    print("Syscalls and ABI — Python demonstration:\n")

    print("1. Linux x86_64 syscall number table:")
    for name, nr in SYSCALL_TABLE.items():
        print(f"  {name:>8} = {nr}")

    # ── Register mapping ───────────────────────────────────────────
    # Syscall ABI (SYSCALL instruction):
    #   Number: RAX
    #   Args:   RDI, RSI, RDX, R10, R8, R9
    #   Return: RAX
    #   Clobbers: RCX (saves RIP), R11 (saves RFLAGS)
    #
    # Function-call ABI (CALL instruction, System V AMD64):
    #   Args:   RDI, RSI, RDX, RCX, R8, R9
    #   Return: RAX
    #   Caller-saved: RAX, RCX, RDX, RSI, RDI, R8-R11
    #
    # Key difference: 4th arg is R10 for syscalls, RCX for function calls.
    # This is because SYSCALL overwrites RCX with the return address (RIP).

    SYSCALL_ARG_REGS = ["rdi", "rsi", "rdx", "r10", "r8", "r9"]
    FUNCALL_ARG_REGS = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]

    print("\n2. Register mapping — syscall vs function call:")
    print(f"  {'Arg':>5} {'Syscall':>10} {'Function':>10}")
    print(f"  {'---':>5} {'-------':>10} {'--------':>10}")
    for i in range(6):
        marker = " ←" if SYSCALL_ARG_REGS[i] != FUNCALL_ARG_REGS[i] else ""
        print(f"  {i+1:>5} {SYSCALL_ARG_REGS[i]:>10} {FUNCALL_ARG_REGS[i]:>10}{marker}")
    print("  (← marks where they differ: 4th arg)")

    # ── SYSCALL clobbers RCX and R11 ───────────────────────────────
    print("\n3. SYSCALL instruction side effects:")
    print("  Before SYSCALL executes, the CPU automatically:")
    print("    RCX ← RIP  (return address saved in RCX)")
    print("    R11 ← RFLAGS  (flags saved in R11)")
    print("  After SYSRET, the kernel restores RIP from RCX and RFLAGS from R11.")
    print("  Consequence: any value you had in RCX or R11 is destroyed.")
    print("  This is why the 4th syscall arg uses R10 instead of RCX.")

    # ── Raw syscalls via ctypes ────────────────────────────────────
    # libc exposes syscall() which lets us call any syscall by number.
    # Signature: long syscall(long number, ...);

    print("\n4. Raw syscalls via ctypes (libc's syscall() wrapper):")

    libc_name = ctypes.util.find_library("c")
    if libc_name is None:
        print("  [skipped — libc not found, not on Linux]")
    else:
        libc = ctypes.CDLL(libc_name, use_errno=True)
        libc.syscall.restype = ctypes.c_long

        # getpid — simplest syscall, no arguments, no side effects
        NR_GETPID = 39
        pid_from_syscall = libc.syscall(NR_GETPID)
        pid_from_os = os.getpid()
        print(f"  getpid via syscall({NR_GETPID}): {pid_from_syscall}")
        print(f"  getpid via os.getpid():    {pid_from_os}")
        assert pid_from_syscall == pid_from_os, "PIDs must match"
        print("  PIDs match — same underlying syscall.")

        # write — write to stdout via raw syscall
        NR_WRITE = 1
        message = b"  Hello from raw syscall via ctypes!\n"
        buf = ctypes.create_string_buffer(message)
        written = libc.syscall(NR_WRITE, 1, buf, len(message))
        print(f"  write returned: {written} bytes (expected {len(message)})")
        assert written == len(message), "short write"

        # write to bad fd — demonstrates error return
        bad_written = libc.syscall(NR_WRITE, 999, buf, len(message))
        errno = ctypes.get_errno()
        print(f"  write(fd=999) returned: {bad_written}, errno: {errno} (EBADF=9)")
        assert bad_written == -1, "bad fd must fail"
        assert errno == 9, "errno must be EBADF (9)"

    # ── os module — Pythonic syscall interface ─────────────────────
    print("\n5. os module — Python's high-level syscall wrappers:")

    # os.getpid() wraps the getpid syscall
    pid = os.getpid()
    print(f"  os.getpid() = {pid}")

    # os.write() wraps the write syscall (fd-level, not buffered)
    msg = b"  Hello from os.write()!\n"
    n = os.write(1, msg)
    print(f"  os.write(1, ...) wrote {n} bytes")
    assert n == len(msg)

    # os.uname() wraps the uname syscall
    info = os.uname()
    print(f"  os.uname().sysname  = {info.sysname}")
    print(f"  os.uname().machine  = {info.machine}")

    # ── Syscall cost awareness ─────────────────────────────────────
    print("\n6. Syscall cost — why buffering matters:")
    print("  A syscall (user→kernel transition) costs ~100-300 CPU cycles.")
    print("  A function call costs ~3-5 cycles.")
    print("  Writing 4096 bytes one byte at a time = 4096 syscalls = ~1.2M cycles.")
    print("  Writing 4096 bytes in one call = 1 syscall = ~600 cycles.")
    print("  Python's print() buffers internally to amortize this cost.")
    print("  os.write() does NOT buffer — it's one syscall per call.")

    # ── Summary ────────────────────────────────────────────────────
    print("\n7. Key takeaways:")
    print("  - Syscall nr in RAX, args in RDI,RSI,RDX,R10,R8,R9, return in RAX")
    print("  - SYSCALL clobbers RCX (←RIP) and R11 (←RFLAGS)")
    print("  - 4th arg is R10 for syscalls, RCX for function calls")
    print("  - Negative returns in [-4095,-1] are errors (negate for errno)")
    print("  - Minimize syscall count on hot paths — buffer I/O")

if __name__ == "__main__":
    main()
