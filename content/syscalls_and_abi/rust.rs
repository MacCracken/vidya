// Syscalls and ABI — Rust Implementation
//
// Demonstrates Linux x86_64 syscalls and System V AMD64 ABI concepts:
//   - Direct syscall invocation via inline assembly
//   - Calling convention layout (register assignments)
//   - Stack frame structure
//   - Syscall error handling
//
// These are the primitives a no-libc compiler uses to interact with the OS.

use std::arch::asm;

// ── Raw syscall wrappers ──────────────────────────────────────────────────

/// Invoke a Linux x86_64 syscall with 0-3 arguments.
///
/// Syscall number in RAX, args in RDI, RSI, RDX.
/// Returns: RAX (result or negated errno).
///
/// SAFETY: Caller must ensure syscall number and arguments are valid.
unsafe fn syscall3(nr: u64, a1: u64, a2: u64, a3: u64) -> i64 {
    let ret: i64;
    unsafe {
        asm!(
            "syscall",
            in("rax") nr,
            in("rdi") a1,
            in("rsi") a2,
            in("rdx") a3,
            // SYSCALL clobbers RCX (saves RIP) and R11 (saves RFLAGS)
            lateout("rcx") _,
            lateout("r11") _,
            lateout("rax") ret,
            options(nostack),
        );
    }
    ret
}

/// Linux syscall numbers (x86_64)
mod nr {
    pub const WRITE: u64 = 1;
    pub const BRK: u64 = 12;
    pub const GETPID: u64 = 39;
    pub const EXIT: u64 = 60;
}

/// Write bytes to a file descriptor. Returns bytes written or negative errno.
fn sys_write(fd: u64, buf: &[u8]) -> i64 {
    unsafe { syscall3(nr::WRITE, fd, buf.as_ptr() as u64, buf.len() as u64) }
}

/// Get current break (heap end). Pass 0 to query, non-zero to set.
fn sys_brk(addr: u64) -> i64 {
    unsafe { syscall3(nr::BRK, addr, 0, 0) }
}

/// Get process ID (useful for testing — no side effects).
fn sys_getpid() -> i64 {
    unsafe { syscall3(nr::GETPID, 0, 0, 0) }
}

// ── ABI demonstration ─────────────────────────────────────────────────────

/// Demonstrates System V AMD64 calling convention by examining
/// how Rust passes arguments to functions.
///
/// System V AMD64:
///   Integer args: RDI, RSI, RDX, RCX, R8, R9
///   Return: RAX
///   Caller-saved: RAX, RCX, RDX, RSI, RDI, R8-R11
///   Callee-saved: RBX, RBP, R12-R15
///
/// Rust uses the same registers (C ABI) for `extern "C"` functions.
#[inline(never)]
extern "C" fn six_args(a: u64, b: u64, c: u64, d: u64, e: u64, f: u64) -> u64 {
    // a → RDI, b → RSI, c → RDX, d → RCX, e → R8, f → R9
    a + b + c + d + e + f
}

/// Seventh argument goes on the stack per System V AMD64.
#[inline(never)]
extern "C" fn seven_args(a: u64, b: u64, c: u64, d: u64, e: u64, f: u64, g: u64) -> u64 {
    // a-f in registers, g on stack at [RSP+8] (after return address)
    a + b + c + d + e + f + g
}

/// Demonstrates struct return — large structs use hidden pointer.
#[repr(C)]
#[derive(Debug)]
struct BigStruct {
    a: u64,
    b: u64,
    c: u64,
    d: u64, // 32 bytes — too big for register return
}

/// Returns a struct > 16 bytes. Per ABI, caller passes hidden pointer in RDI.
#[inline(never)]
extern "C" fn make_big_struct(x: u64) -> BigStruct {
    // The 'real' first arg (x) is actually in RSI, because RDI is the hidden return pointer
    BigStruct {
        a: x,
        b: x * 2,
        c: x * 3,
        d: x * 4,
    }
}

// ── Stack frame layout ────────────────────────────────────────────────────

/// Demonstrates reading the current stack pointer and frame pointer.
fn show_stack_layout() {
    let rsp: u64;
    let rbp: u64;
    unsafe {
        asm!("mov {}, rsp", out(reg) rsp, options(nomem, nostack));
        asm!("mov {}, rbp", out(reg) rbp, options(nomem, nostack));
    }

    println!("  Stack layout:");
    println!("    RBP (frame pointer): 0x{:016X}", rbp);
    println!("    RSP (stack pointer): 0x{:016X}", rsp);
    println!("    Frame size:          {} bytes", rbp - rsp);
    println!(
        "    RSP aligned to 16:   {}",
        if rsp % 16 == 0 { "yes" } else { "no" }
    );
}

// ── Syscall error handling ────────────────────────────────────────────────

/// Linux syscall results: negative values in [-4095, -1] are errors.
fn check_syscall_result(result: i64, name: &str) {
    if (-4095..=-1).contains(&result) {
        let errno = -result;
        println!("  {} failed: errno = {} ({})", name, errno, errno_name(errno));
    } else {
        println!("  {} succeeded: {}", name, result);
    }
}

fn errno_name(errno: i64) -> &'static str {
    match errno {
        1 => "EPERM",
        2 => "ENOENT",
        9 => "EBADF",
        12 => "ENOMEM",
        13 => "EACCES",
        14 => "EFAULT",
        22 => "EINVAL",
        _ => "unknown",
    }
}

fn main() {
    println!("Syscalls and ABI — Linux x86_64 demonstration:\n");

    // ── Direct syscalls ───────────────────────────────────────────────
    println!("1. Direct syscalls (no libc):");

    // write(1, "hello\n", 6) — syscall nr 1
    let msg = b"  Hello from raw syscall!\n";
    let written = sys_write(1, msg);
    check_syscall_result(written, "write");

    // getpid() — syscall nr 39
    let pid = sys_getpid();
    check_syscall_result(pid, "getpid");

    // brk(0) — query current heap break
    let brk_current = sys_brk(0);
    check_syscall_result(brk_current, "brk(0)");

    // brk(current + 4096) — extend heap by one page
    let brk_new = sys_brk(brk_current as u64 + 4096);
    println!(
        "  brk extended: 0x{:X} → 0x{:X} ({} bytes)",
        brk_current, brk_new, brk_new - brk_current
    );

    // write to bad fd — demonstrates error handling
    let bad_write = sys_write(999, b"nope");
    check_syscall_result(bad_write, "write(fd=999)");

    // ── Calling convention ────────────────────────────────────────────
    println!("\n2. System V AMD64 calling convention:");
    let sum6 = six_args(1, 2, 3, 4, 5, 6);
    println!("  six_args(1,2,3,4,5,6) = {} (args in RDI,RSI,RDX,RCX,R8,R9)", sum6);

    let sum7 = seven_args(1, 2, 3, 4, 5, 6, 7);
    println!(
        "  seven_args(1..7) = {} (6 in regs, 7th on stack)",
        sum7
    );

    // ── Large struct return ───────────────────────────────────────────
    println!("\n3. Large struct return (hidden pointer in RDI):");
    let big = make_big_struct(10);
    println!("  make_big_struct(10) = {:?}", big);
    println!("  (Caller allocated {} bytes, passed pointer in RDI)", std::mem::size_of::<BigStruct>());

    // ── Stack frame ───────────────────────────────────────────────────
    println!("\n4. Stack frame:");
    show_stack_layout();

    // ── Syscall register summary ──────────────────────────────────────
    println!("\n5. Register summary:");
    println!("  Syscall: nr=RAX, args=RDI,RSI,RDX,R10,R8,R9, ret=RAX, clobbers=RCX,R11");
    println!("  Func call: args=RDI,RSI,RDX,RCX,R8,R9, ret=RAX, caller-saves=RAX,RCX,RDX,RSI,RDI,R8-R11");
    println!("  Key difference: syscall uses R10 (not RCX) for 4th arg");
}
