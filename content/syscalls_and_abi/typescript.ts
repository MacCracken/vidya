// Vidya — Syscalls and ABI in TypeScript
//
// System calls are the interface between user programs and the kernel.
// The ABI (Application Binary Interface) defines how arguments are passed
// in registers and on the stack. TypeScript cannot make raw syscalls, but
// we can document the concepts, model register mappings, compare ABIs,
// and use Node.js process bindings where they wrap syscalls.

function main(): void {
    testSyscallTable();
    testRegisterMapping();
    testAbiComparison();
    testSyscallErrorCodes();
    testNodeProcessBindings();
    testCallingConvention();
    testStackFrameLayout();

    console.log("All syscalls and ABI examples passed.");
}

// ── Linux x86_64 Syscall Number Table ───────────────────────────────

// Every syscall has a number. The kernel dispatches by reading RAX.
// These numbers are architecture-specific and never change (ABI stability).

interface SyscallDef {
    number: number;
    name: string;
    args: string[];    // parameter names in register order
    returnType: string;
}

const LINUX_X86_64_SYSCALLS: SyscallDef[] = [
    { number: 0,   name: "read",     args: ["fd", "buf", "count"],            returnType: "ssize_t" },
    { number: 1,   name: "write",    args: ["fd", "buf", "count"],            returnType: "ssize_t" },
    { number: 2,   name: "open",     args: ["filename", "flags", "mode"],     returnType: "int" },
    { number: 3,   name: "close",    args: ["fd"],                            returnType: "int" },
    { number: 9,   name: "mmap",     args: ["addr", "len", "prot", "flags", "fd", "offset"], returnType: "void*" },
    { number: 11,  name: "munmap",   args: ["addr", "len"],                   returnType: "int" },
    { number: 12,  name: "brk",      args: ["addr"],                          returnType: "void*" },
    { number: 39,  name: "getpid",   args: [],                                returnType: "pid_t" },
    { number: 56,  name: "clone",    args: ["flags", "stack", "ptid", "ctid", "regs"], returnType: "pid_t" },
    { number: 57,  name: "fork",     args: [],                                returnType: "pid_t" },
    { number: 59,  name: "execve",   args: ["filename", "argv", "envp"],      returnType: "int" },
    { number: 60,  name: "exit",     args: ["status"],                        returnType: "void" },
    { number: 62,  name: "kill",     args: ["pid", "sig"],                    returnType: "int" },
    { number: 231, name: "exit_group", args: ["status"],                      returnType: "void" },
];

function testSyscallTable(): void {
    // Verify well-known syscall numbers
    const write = LINUX_X86_64_SYSCALLS.find((s) => s.name === "write")!;
    assert(write.number === 1, "write is syscall 1");
    assert(write.args.length === 3, "write takes 3 args");

    const exit = LINUX_X86_64_SYSCALLS.find((s) => s.name === "exit")!;
    assert(exit.number === 60, "exit is syscall 60");
    assert(exit.args.length === 1, "exit takes 1 arg");

    const mmap = LINUX_X86_64_SYSCALLS.find((s) => s.name === "mmap")!;
    assert(mmap.number === 9, "mmap is syscall 9");
    assert(mmap.args.length === 6, "mmap takes 6 args (maximum)");

    const getpid = LINUX_X86_64_SYSCALLS.find((s) => s.name === "getpid")!;
    assert(getpid.args.length === 0, "getpid takes no args");
}

// ── Register Mapping ────────────────────────────────────────────────

// Syscall convention (Linux x86_64):
//   Syscall number: RAX
//   Arguments:      RDI, RSI, RDX, R10, R8, R9
//   Return value:   RAX
//   Clobbered:      RCX (saved RIP), R11 (saved RFLAGS)
//
// NOTE: arg4 uses R10, NOT RCX! The SYSCALL instruction clobbers RCX.
// This is different from the function calling convention.

const SYSCALL_REGS = {
    number: "rax",
    args: ["rdi", "rsi", "rdx", "r10", "r8", "r9"] as const,
    returnValue: "rax",
    clobbered: ["rcx", "r11"] as const,
};

// Function calling convention (System V AMD64 ABI):
//   Arguments:      RDI, RSI, RDX, RCX, R8, R9
//   Return value:   RAX (+ RDX for 128-bit)
//   Caller-saved:   RAX, RCX, RDX, RSI, RDI, R8-R11
//   Callee-saved:   RBX, RBP, R12-R15

const FUNCTION_REGS = {
    args: ["rdi", "rsi", "rdx", "rcx", "r8", "r9"] as const,
    returnValue: "rax",
    callerSaved: ["rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11"] as const,
    calleeSaved: ["rbx", "rbp", "r12", "r13", "r14", "r15"] as const,
};

function testRegisterMapping(): void {
    // First 3 args are the same for syscalls and functions
    assert(SYSCALL_REGS.args[0] === "rdi", "arg0 = rdi");
    assert(SYSCALL_REGS.args[1] === "rsi", "arg1 = rsi");
    assert(SYSCALL_REGS.args[2] === "rdx", "arg2 = rdx");

    // KEY DIFFERENCE: arg3 is R10 for syscalls, RCX for functions
    assert(SYSCALL_REGS.args[3] === "r10", "syscall arg3 = r10");
    assert(FUNCTION_REGS.args[3] === "rcx", "function arg3 = rcx");

    // SYSCALL clobbers RCX and R11
    assert(SYSCALL_REGS.clobbered.includes("rcx"), "rcx clobbered");
    assert(SYSCALL_REGS.clobbered.includes("r11"), "r11 clobbered");

    // Max 6 register arguments for both
    assert(SYSCALL_REGS.args.length === 6, "6 syscall arg regs");
    assert(FUNCTION_REGS.args.length === 6, "6 function arg regs");

    // Callee-saved registers (function convention)
    assert(FUNCTION_REGS.calleeSaved.includes("rbx"), "rbx callee-saved");
    assert(FUNCTION_REGS.calleeSaved.includes("rbp"), "rbp callee-saved");
    assert(FUNCTION_REGS.calleeSaved.length === 6, "6 callee-saved regs");
}

// ── ABI Comparison Across Architectures ─────────────────────────────

interface AbiInfo {
    arch: string;
    syscallInsn: string;         // instruction to enter kernel
    syscallNumReg: string;       // register holding syscall number
    argRegs: string[];           // argument registers
    returnReg: string;
    maxArgRegs: number;
}

const ABI_TABLE: AbiInfo[] = [
    {
        arch: "x86_64",
        syscallInsn: "syscall",
        syscallNumReg: "rax",
        argRegs: ["rdi", "rsi", "rdx", "r10", "r8", "r9"],
        returnReg: "rax",
        maxArgRegs: 6,
    },
    {
        arch: "aarch64",
        syscallInsn: "svc #0",
        syscallNumReg: "x8",
        argRegs: ["x0", "x1", "x2", "x3", "x4", "x5"],
        returnReg: "x0",
        maxArgRegs: 6,
    },
    {
        arch: "riscv64",
        syscallInsn: "ecall",
        syscallNumReg: "a7",
        argRegs: ["a0", "a1", "a2", "a3", "a4", "a5"],
        returnReg: "a0",
        maxArgRegs: 6,
    },
    {
        arch: "x86 (32-bit)",
        syscallInsn: "int 0x80",
        syscallNumReg: "eax",
        argRegs: ["ebx", "ecx", "edx", "esi", "edi", "ebp"],
        returnReg: "eax",
        maxArgRegs: 6,
    },
];

function testAbiComparison(): void {
    // All architectures support exactly 6 register arguments for syscalls
    for (const abi of ABI_TABLE) {
        assert(abi.maxArgRegs === 6, `${abi.arch} has 6 arg regs`);
        assert(abi.argRegs.length === 6, `${abi.arch} argRegs length`);
    }

    // x86_64 uses SYSCALL instruction (fast), not int 0x80 (slow legacy)
    const x64 = ABI_TABLE.find((a) => a.arch === "x86_64")!;
    assert(x64.syscallInsn === "syscall", "x86_64 uses syscall");

    // AArch64 uses SVC (supervisor call)
    const arm = ABI_TABLE.find((a) => a.arch === "aarch64")!;
    assert(arm.syscallInsn === "svc #0", "aarch64 uses svc");

    // Return register differs: RAX on x86_64, X0 on AArch64
    assert(x64.returnReg === "rax", "x86_64 returns in rax");
    assert(arm.returnReg === "x0", "aarch64 returns in x0");

    // Syscall number register differs too
    assert(x64.syscallNumReg === "rax", "x86_64 syscall# in rax");
    assert(arm.syscallNumReg === "x8", "aarch64 syscall# in x8");
}

// ── Syscall Error Codes ─────────────────────────────────────────────

// On Linux, a syscall returns a negative value on error.
// The value is -errno. For example, -2 means ENOENT (No such file).

const ERRNO_TABLE: Record<number, string> = {
    1:  "EPERM (Operation not permitted)",
    2:  "ENOENT (No such file or directory)",
    3:  "ESRCH (No such process)",
    9:  "EBADF (Bad file descriptor)",
    11: "EAGAIN (Resource temporarily unavailable)",
    12: "ENOMEM (Cannot allocate memory)",
    13: "EACCES (Permission denied)",
    14: "EFAULT (Bad address)",
    17: "EEXIST (File exists)",
    22: "EINVAL (Invalid argument)",
};

function decodeSyscallReturn(ret: bigint): { success: boolean; value: bigint; error?: string } {
    // Linux returns -4095..-1 for errors (negated errno)
    if (ret >= -4095n && ret < 0n) {
        const errno = Number(-ret);
        return {
            success: false,
            value: ret,
            error: ERRNO_TABLE[errno] ?? `errno ${errno}`,
        };
    }
    return { success: true, value: ret };
}

function testSyscallErrorCodes(): void {
    // Successful return
    const ok = decodeSyscallReturn(42n);
    assert(ok.success, "positive is success");
    assert(ok.value === 42n, "value preserved");

    // ENOENT (-2)
    const noent = decodeSyscallReturn(-2n);
    assert(!noent.success, "negative is error");
    assert(noent.error!.startsWith("ENOENT"), "ENOENT decoded");

    // EINVAL (-22)
    const inval = decodeSyscallReturn(-22n);
    assert(inval.error!.startsWith("EINVAL"), "EINVAL decoded");

    // Zero is success (e.g., close() returns 0)
    const zero = decodeSyscallReturn(0n);
    assert(zero.success, "zero is success");

    // Large positive is success (e.g., mmap returns address)
    const mmap = decodeSyscallReturn(0x7FFF_FFFF_0000n);
    assert(mmap.success, "large positive is success");
}

// ── Node.js Process Bindings ────────────────────────────────────────

// Node.js wraps many syscalls through its process and fs modules.
// These are the TypeScript-accessible equivalents.

function testNodeProcessBindings(): void {
    // process.pid wraps getpid() syscall
    const pid = process.pid;
    assert(pid > 0, "pid is positive");

    // process.ppid wraps getppid() syscall
    const ppid = process.ppid;
    assert(ppid > 0, "ppid is positive");
    assert(ppid !== pid, "ppid differs from pid");

    // process.arch reflects the ABI we are running under
    const arch = process.arch;
    assert(typeof arch === "string", "arch is string");
    // Common values: "x64", "arm64", "arm"

    // process.platform reflects the OS
    const platform = process.platform;
    assert(typeof platform === "string", "platform is string");
    // Common values: "linux", "darwin", "win32"

    // process.exit() wraps exit_group() syscall (not just exit())
    // exit_group terminates ALL threads, not just the calling thread.
    // We do not call it here — just document that it exists.

    // process.stdout.write wraps write(1, buf, len) syscall
    // process.stderr.write wraps write(2, buf, len) syscall
    // We verify stdout fd is correct
    assert(process.stdout.fd === 1, "stdout fd = 1");
    assert(process.stderr.fd === 2, "stderr fd = 2");
}

// ── Calling Convention ──────────────────────────────────────────────

// The System V AMD64 ABI defines how functions call each other.
// Understanding this is essential for writing compilers and debuggers.

interface CallFrame {
    returnAddr: bigint;     // pushed by CALL instruction
    savedRbp: bigint;       // pushed by function prologue
    locals: bigint[];       // local variables on the stack
}

function simulateCall(caller: string, callee: string): CallFrame {
    // Simulates what happens at a function call:
    // 1. Caller pushes arguments beyond 6 onto the stack (right to left)
    // 2. CALL instruction pushes return address
    // 3. Callee pushes RBP (frame pointer)
    // 4. Callee sets RBP = RSP
    // 5. Callee allocates locals by subtracting from RSP
    return {
        returnAddr: 0x40_1234n,  // where to return in caller
        savedRbp: 0x7FFF_F000n,  // caller's frame pointer
        locals: [0n, 0n, 0n],    // 3 local variables
    };
}

function testCallingConvention(): void {
    const frame = simulateCall("main", "compute");

    // Return address is set by CALL instruction
    assert(frame.returnAddr > 0n, "return address set");

    // Saved RBP links to caller's frame (forms a chain for backtraces)
    assert(frame.savedRbp > 0n, "saved rbp links to caller");

    // Stack grows downward on x86_64
    // Higher addresses are "earlier" in the call chain
    assert(frame.savedRbp > frame.returnAddr, "stack grows down");
}

// ── Stack Frame Layout ──────────────────────────────────────────────

// x86_64 stack frame (System V AMD64 ABI):
//
//   Higher addresses (earlier frames)
//   ┌──────────────────────┐
//   │ arg7 (if > 6 args)   │  ← pushed by caller
//   │ return address        │  ← pushed by CALL
//   │ saved RBP             │  ← pushed by callee prologue
//   │ local var 1           │
//   │ local var 2           │
//   │ ...                   │  ← RSP points here
//   └──────────────────────┘
//   Lower addresses (later frames)
//
// Red zone: 128 bytes below RSP that leaf functions can use
// without adjusting RSP. Kernel code MUST disable this (-mno-red-zone).

interface StackLayout {
    name: string;
    offset: number;  // relative to RBP
    size: number;
}

function describeStackFrame(): StackLayout[] {
    return [
        { name: "return address",  offset: 8,   size: 8 },
        { name: "saved RBP",       offset: 0,   size: 8 },
        { name: "local var 1",     offset: -8,  size: 8 },
        { name: "local var 2",     offset: -16, size: 8 },
        { name: "red zone start",  offset: -128, size: 128 },
    ];
}

function testStackFrameLayout(): void {
    const layout = describeStackFrame();

    // Return address is above saved RBP
    const retAddr = layout.find((l) => l.name === "return address")!;
    const savedRbp = layout.find((l) => l.name === "saved RBP")!;
    assert(retAddr.offset > savedRbp.offset, "ret addr above rbp");

    // Locals are below saved RBP (negative offsets)
    const local1 = layout.find((l) => l.name === "local var 1")!;
    assert(local1.offset < 0, "locals below rbp");

    // Red zone is 128 bytes below RSP
    const redZone = layout.find((l) => l.name === "red zone start")!;
    assert(redZone.size === 128, "red zone is 128 bytes");
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
