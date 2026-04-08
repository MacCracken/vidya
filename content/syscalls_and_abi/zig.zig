// Vidya — Syscalls and ABI in Zig
//
// Zig provides std.os.linux for raw syscall access — no libc required.
// System V AMD64 ABI: args in rdi, rsi, rdx, r10, r8, r9; return in
// rax; syscall number in rax. Zig's own calling convention differs
// from C ABI but can interop via `callconv(.c)`.

const std = @import("std");
const expect = std.testing.expect;
const builtin = @import("builtin");

pub fn main() !void {
    try testSysVRegisters();
    try testSyscallNumbers();
    try testLinuxSyscalls();
    try testCallingConventions();
    try testAbiStructLayout();
    try testErrno();

    std.debug.print("All syscalls and ABI examples passed.\n", .{});
}

// ── System V AMD64 ABI Register Mapping ──────────────────────────────
// The kernel uses a slightly different convention than userspace C:
//   User C ABI:   rdi, rsi, rdx, rcx, r8, r9 (rcx for arg4)
//   Syscall ABI:  rdi, rsi, rdx, r10, r8, r9 (r10 for arg4)
// Reason: syscall instruction clobbers rcx (stores return address)
const SysVRegisters = struct {
    const arg1 = "rdi";
    const arg2 = "rsi";
    const arg3 = "rdx";
    const arg4_user = "rcx"; // C calling convention
    const arg4_kernel = "r10"; // syscall convention
    const arg5 = "r8";
    const arg6 = "r9";
    const return_val = "rax";
    const syscall_nr = "rax";

    // Caller-saved (scratch): rax, rcx, rdx, rsi, rdi, r8-r11
    // Callee-saved (preserved): rbx, rbp, r12-r15, rsp
    const caller_saved = [_][]const u8{ "rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11" };
    const callee_saved = [_][]const u8{ "rbx", "rbp", "r12", "r13", "r14", "r15" };
};

fn testSysVRegisters() !void {
    try expect(SysVRegisters.caller_saved.len == 9);
    try expect(SysVRegisters.callee_saved.len == 6);

    // Key difference: arg4 changes between user and kernel ABI
    try expect(!std.mem.eql(u8, SysVRegisters.arg4_user, SysVRegisters.arg4_kernel));
}

// ── Linux Syscall Numbers (x86_64) ──────────────────────────────────
const SyscallNr = struct {
    const read: usize = 0;
    const write: usize = 1;
    const open: usize = 2;
    const close: usize = 3;
    const stat: usize = 4;
    const fstat: usize = 5;
    const mmap: usize = 9;
    const mprotect: usize = 10;
    const brk: usize = 12;
    const ioctl: usize = 16;
    const getpid: usize = 39;
    const clone: usize = 56;
    const fork: usize = 57;
    const execve: usize = 59;
    const exit: usize = 60;
    const kill: usize = 62;
    const getuid: usize = 102;
    const getgid: usize = 104;
    const gettid: usize = 186;
    const exit_group: usize = 231;
};

fn testSyscallNumbers() !void {
    // Syscall numbers are stable — Linux never changes them
    try expect(SyscallNr.read == 0);
    try expect(SyscallNr.write == 1);
    try expect(SyscallNr.exit == 60);
    try expect(SyscallNr.getpid == 39);

    // Note: syscall numbers differ by architecture
    // x86_64: write=1, exit=60
    // aarch64: write=64, exit=93
}

// ── Raw Syscalls via Zig's std.os.linux ──────────────────────────────
fn testLinuxSyscalls() !void {
    if (builtin.os.tag != .linux) return;

    // write(fd=1, buf, len) — syscall number 1 on x86_64
    const msg = ""; // empty write to avoid output noise
    const ret = std.os.linux.syscall3(
        .write,
        @as(usize, 1), // fd: stdout
        @intFromPtr(msg.ptr),
        msg.len,
    );
    // write returns bytes written (0 for empty string)
    try expect(ret == 0);

    // getpid — no arguments, returns process ID
    const pid = std.os.linux.syscall0(.getpid);
    try expect(pid > 0); // PIDs are always positive

    // getuid — returns user ID
    const uid = std.os.linux.syscall0(.getuid);
    _ = uid; // valid even if 0 (root)

    // gettid — returns thread ID (== pid for main thread in single-threaded)
    const tid = std.os.linux.syscall0(.gettid);
    try expect(tid > 0);
}

// ── Calling Conventions ──────────────────────────────────────────────
// Zig functions default to Zig's own calling convention (optimized,
// not stable). Use callconv(.c) for C ABI interop.

// C ABI function — callable from C code, follows System V AMD64 ABI
fn addC(a: i32, b: i32) callconv(.c) i32 {
    return a + b;
}

// Zig calling convention — default, may pass args in any register
fn addZig(a: i32, b: i32) i32 {
    return a + b;
}

fn testCallingConventions() !void {
    // Both produce the same result but use different ABIs
    try expect(addC(3, 4) == 7);
    try expect(addZig(3, 4) == 7);

    // Function pointers can specify calling convention
    const c_fn: *const fn (i32, i32) callconv(.c) i32 = &addC;
    try expect(c_fn(10, 20) == 30);

    // Zig extern functions always use C calling convention
    // Example: const puts = @extern(*const fn([*:0]const u8) callconv(.c) c_int, .{ .name = "puts" });
}

// ── ABI Struct Layout ────────────────────────────────────────────────
// System V AMD64 ABI specifies alignment and passing conventions

// Packed: bit-packed into a backing integer — no padding between fields.
// In Zig, packed structs use the smallest power-of-2 integer that fits.
// u8 + u32 + u16 = 56 bits → backed by u64 (8 bytes with padding bits).
const PackedBitfield = packed struct {
    flags: u4, // 4 bits
    tag: u4, // 4 bits
    value: u16, // 16 bits
    reserved: u8, // 8 bits — total 32 bits = u32 backing
};

// Extern: C ABI layout with padding for alignment
const ExternExample = extern struct {
    a: u8, // 1 byte + 3 padding
    b: u32, // 4 bytes (aligned to 4)
    c: u16, // 2 bytes + 2 padding
};

// Default Zig struct: compiler may reorder fields
const ZigExample = struct {
    a: u8,
    b: u32,
    c: u16,
};

fn testAbiStructLayout() !void {
    // Packed bitfield: exactly 4 bytes (32 bits = u32 backing)
    comptime {
        std.debug.assert(@sizeOf(PackedBitfield) == 4);
    }

    // Extern: C ABI rules — alignment padding
    // a(1) + pad(3) + b(4) + c(2) + pad(2) = 12 bytes
    comptime {
        std.debug.assert(@sizeOf(ExternExample) == 12);
    }

    // Zig struct: compiler may optimize layout
    // Could reorder to b(4) + c(2) + a(1) + pad(1) = 8 bytes
    try expect(@sizeOf(ZigExample) <= 12);

    // System V ABI: structs <= 16 bytes can be passed in registers
    // Larger structs are passed by pointer on the stack
    try expect(@sizeOf(ExternExample) <= 16);

    // Verify packed struct field access — fields share a single integer
    const p = PackedBitfield{ .flags = 0xF, .tag = 0xA, .value = 0x1234, .reserved = 0xFF };
    try expect(p.flags == 0xF);
    try expect(p.tag == 0xA);
    try expect(p.value == 0x1234);

    // Extern struct field access — standard C layout
    const e = ExternExample{ .a = 0xFF, .b = 0xDEADBEEF, .c = 0x1234 };
    try expect(e.a == 0xFF);
    try expect(e.b == 0xDEADBEEF);
    try expect(e.c == 0x1234);
}

// ── Errno Handling ───────────────────────────────────────────────────
// Linux syscalls return negative errno on error (in rax).
// Zig's std.os.linux wraps this as E enum values.
fn testErrno() !void {
    // Common errno values
    const errnos = .{
        .{ "EPERM", 1 }, // Operation not permitted
        .{ "ENOENT", 2 }, // No such file or directory
        .{ "ESRCH", 3 }, // No such process
        .{ "EINTR", 4 }, // Interrupted system call
        .{ "EIO", 5 }, // I/O error
        .{ "ENOMEM", 12 }, // Out of memory
        .{ "EACCES", 13 }, // Permission denied
        .{ "EFAULT", 14 }, // Bad address
        .{ "EEXIST", 17 }, // File exists
        .{ "EINVAL", 22 }, // Invalid argument
        .{ "ENOSYS", 38 }, // Function not implemented
    };

    // Errno 1 = EPERM, always
    try expect(errnos[0][1] == 1);
    // ENOSYS = 38 — returned for unimplemented syscalls
    try expect(errnos[10][1] == 38);

    // Syscall error convention: return value > max_addr means error
    // Zig checks: if (ret > maxInt(usize) - 4096) it's an error
    const max_errno: usize = 4095;
    _ = max_errno;
}
