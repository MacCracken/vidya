// Vidya — Process and Scheduling in Zig
//
// Processes are the OS abstraction for running programs. Each has its
// own address space, register state, and scheduling priority. Zig's
// explicit memory management and packed structs model the kernel data
// structures cleanly: saved register contexts, process control blocks,
// and scheduler run queues.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testProcessStates();
    try testSavedRegisterContext();
    try testProcessControlBlock();
    try testRoundRobinScheduler();
    try testCfsScheduler();
    try testContextSwitch();
    try testPriorityLevels();

    std.debug.print("All process and scheduling examples passed.\n", .{});
}

// ── Process States ───────────────────────────────────────────────────
// Linux process state machine:
//   Created → Ready → Running → (Blocked | Zombie | Stopped)
//   Blocked → Ready (when I/O completes or signal arrives)
const ProcessState = enum(u8) {
    created = 0, // fork() just returned
    ready = 1, // On the run queue, waiting for CPU
    running = 2, // Currently executing on a CPU
    blocked = 3, // Waiting for I/O, lock, or event
    stopped = 4, // SIGSTOP / ptrace — suspended
    zombie = 5, // Exited, waiting for parent to wait()

    fn canTransitionTo(self: ProcessState, next: ProcessState) bool {
        return switch (self) {
            .created => next == .ready,
            .ready => next == .running,
            .running => next == .ready or next == .blocked or next == .stopped or next == .zombie,
            .blocked => next == .ready,
            .stopped => next == .ready,
            .zombie => false, // terminal state
        };
    }
};

fn testProcessStates() !void {
    // Valid transitions
    try expect(ProcessState.created.canTransitionTo(.ready));
    try expect(ProcessState.ready.canTransitionTo(.running));
    try expect(ProcessState.running.canTransitionTo(.ready)); // preempted
    try expect(ProcessState.running.canTransitionTo(.blocked)); // I/O wait
    try expect(ProcessState.running.canTransitionTo(.zombie)); // exit()
    try expect(ProcessState.blocked.canTransitionTo(.ready)); // I/O done

    // Invalid transitions
    try expect(!ProcessState.created.canTransitionTo(.running)); // must be ready first
    try expect(!ProcessState.zombie.canTransitionTo(.ready)); // zombie is terminal
    try expect(!ProcessState.blocked.canTransitionTo(.running)); // must go through ready
    try expect(!ProcessState.ready.canTransitionTo(.blocked)); // can't block without running
}

// ── Saved Register Context (x86_64) ─────────────────────────────────
// On context switch, the kernel saves all registers to the outgoing
// process's task struct and loads them from the incoming process.
const SavedContext = extern struct {
    // General-purpose registers (callee-saved in System V ABI)
    rbx: u64,
    rbp: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    // Instruction pointer and stack pointer
    rip: u64,
    rsp: u64,
    // Flags register
    rflags: u64,
    // CR3: page table base — each process has its own
    cr3: u64,
    // Segment registers (needed for user/kernel transition)
    cs: u16,
    ss: u16,
    ds: u16,
    es: u16,
};

fn testSavedRegisterContext() !void {
    comptime {
        // 10 * 8 + 4 * 2 = 88 bytes, but extern struct pads to 8-byte align = 88
        std.debug.assert(@sizeOf(SavedContext) == 88);
    }

    const ctx = SavedContext{
        .rbx = 0,
        .rbp = 0xFFFF_8000_0000_F000, // kernel stack frame
        .r12 = 0,
        .r13 = 0,
        .r14 = 0,
        .r15 = 0,
        .rip = 0xFFFF_8000_0010_0000, // kernel code
        .rsp = 0xFFFF_8000_0000_E000,
        .rflags = 0x202, // IF set (interrupts enabled)
        .cs = 0x08, // kernel code segment
        .ss = 0x10, // kernel data segment
        .ds = 0x10,
        .es = 0x10,
        .cr3 = 0x1000, // page table base
    };

    // rflags bit 9 = IF (Interrupt Flag)
    try expect(ctx.rflags & (1 << 9) != 0); // interrupts enabled
    // rflags bit 1 is always set
    try expect(ctx.rflags & (1 << 1) != 0);

    // Kernel code segment selector = 0x08 (GDT entry 1, RPL 0)
    try expect(ctx.cs == 0x08);
    // CR3 holds the physical address of PML4
    try expect(ctx.cr3 != 0);
}

// ── Process Control Block ────────────────────────────────────────────
const Pid = u32;

const Process = struct {
    pid: Pid,
    ppid: Pid, // parent process ID
    state: ProcessState,
    context: SavedContext,
    priority: i8, // nice value: -20 (highest) to 19 (lowest)
    vruntime: u64, // CFS virtual runtime (nanoseconds)
    time_slice: u64, // remaining time quantum (nanoseconds)
    total_runtime: u64, // total CPU time used
    name: []const u8,

    fn isKernelThread(self: *const Process) bool {
        return self.ppid == 2; // kthreadd is PID 2 in Linux
    }

    fn effectivePriority(self: *const Process) i16 {
        // Linux: priority = 120 + nice
        return 120 + @as(i16, self.priority);
    }
};

fn testProcessControlBlock() !void {
    const init_ctx = SavedContext{
        .rbx = 0,
        .rbp = 0,
        .r12 = 0,
        .r13 = 0,
        .r14 = 0,
        .r15 = 0,
        .rip = 0x400000,
        .rsp = 0x7FFF_FFFF_F000,
        .rflags = 0x202,
        .cs = 0x2B, // user code segment (GDT entry 5, RPL 3)
        .ss = 0x23, // user data segment
        .ds = 0x23,
        .es = 0x23,
        .cr3 = 0x2000,
    };

    var proc = Process{
        .pid = 1,
        .ppid = 0, // init has no parent
        .state = .running,
        .context = init_ctx,
        .priority = 0, // default nice
        .vruntime = 0,
        .time_slice = 4_000_000, // 4ms
        .total_runtime = 0,
        .name = "init",
    };

    try expect(proc.pid == 1);
    try expect(proc.effectivePriority() == 120);
    try expect(!proc.isKernelThread());

    // Simulate running for 1ms
    proc.total_runtime += 1_000_000;
    proc.time_slice -= 1_000_000;
    try expect(proc.time_slice == 3_000_000);
}

// ── Round-Robin Scheduler ────────────────────────────────────────────
// Simplest preemptive scheduler: each process gets equal time quantum
const RoundRobinScheduler = struct {
    queue: [MAX_PROCS]*Process,
    count: usize,
    next: usize, // index of next process to consider
    quantum_ns: u64, // time slice in nanoseconds

    const MAX_PROCS = 16;

    fn init(quantum_ns: u64) RoundRobinScheduler {
        return .{
            .queue = undefined,
            .count = 0,
            .next = 0,
            .quantum_ns = quantum_ns,
        };
    }

    fn addProcess(self: *RoundRobinScheduler, proc: *Process) void {
        if (self.count < MAX_PROCS) {
            self.queue[self.count] = proc;
            self.count += 1;
            proc.state = .ready;
            proc.time_slice = self.quantum_ns;
        }
    }

    // Returns the next process to run
    fn schedule(self: *RoundRobinScheduler) ?*Process {
        if (self.count == 0) return null;

        // Preempt any currently running process
        for (self.queue[0..self.count]) |p| {
            if (p.state == .running) {
                p.state = .ready;
                p.time_slice = self.quantum_ns;
            }
        }

        // Find next ready process starting from self.next (round-robin)
        var checked: usize = 0;
        while (checked < self.count) : (checked += 1) {
            const idx = (self.next + checked) % self.count;
            if (self.queue[idx].state == .ready) {
                self.queue[idx].state = .running;
                self.next = (idx + 1) % self.count;
                return self.queue[idx];
            }
        }
        return null;
    }
};

fn testRoundRobinScheduler() !void {
    const dummy_ctx = SavedContext{
        .rbx = 0, .rbp = 0, .r12 = 0, .r13 = 0, .r14 = 0, .r15 = 0,
        .rip = 0, .rsp = 0, .rflags = 0x202, .cs = 0x2B, .ss = 0x23,
        .ds = 0x23, .es = 0x23, .cr3 = 0,
    };

    var p1 = Process{ .pid = 1, .ppid = 0, .state = .created, .context = dummy_ctx, .priority = 0, .vruntime = 0, .time_slice = 0, .total_runtime = 0, .name = "bash" };
    var p2 = Process{ .pid = 2, .ppid = 1, .state = .created, .context = dummy_ctx, .priority = 0, .vruntime = 0, .time_slice = 0, .total_runtime = 0, .name = "vim" };
    var p3 = Process{ .pid = 3, .ppid = 1, .state = .created, .context = dummy_ctx, .priority = 0, .vruntime = 0, .time_slice = 0, .total_runtime = 0, .name = "gcc" };

    var sched = RoundRobinScheduler.init(10_000_000); // 10ms quantum
    sched.addProcess(&p1);
    sched.addProcess(&p2);
    sched.addProcess(&p3);

    try expect(sched.count == 3);

    // First schedule: picks p1 (first ready)
    const first = sched.schedule().?;
    try expect(first.pid == 1);
    try expect(first.state == .running);

    // Second schedule: p1 preempted, picks p2
    const second = sched.schedule().?;
    try expect(second.pid == 2);
    try expect(p1.state == .ready); // p1 back to ready

    // Third schedule: picks p3
    const third = sched.schedule().?;
    try expect(third.pid == 3);

    // Fourth schedule: wraps around to p1
    const fourth = sched.schedule().?;
    try expect(fourth.pid == 1);
}

// ── CFS (Completely Fair Scheduler) ──────────────────────────────────
// Linux's default scheduler since 2.6.23. Uses a red-black tree sorted
// by vruntime. Process with lowest vruntime runs next.
// vruntime = wall_time * (weight_nice0 / weight_process)
const CfsScheduler = struct {
    procs: [MAX_PROCS]*Process,
    count: usize,
    min_granularity_ns: u64, // minimum time slice

    const MAX_PROCS = 16;
    const NICE0_WEIGHT: u64 = 1024;

    fn init() CfsScheduler {
        return .{
            .procs = undefined,
            .count = 0,
            .min_granularity_ns = 750_000, // 0.75ms
        };
    }

    fn addProcess(self: *CfsScheduler, proc: *Process) void {
        if (self.count < MAX_PROCS) {
            self.procs[self.count] = proc;
            self.count += 1;
            proc.state = .ready;
        }
    }

    // Weight for a nice value (simplified — real kernel uses a lookup table)
    fn niceToWeight(nice: i8) u64 {
        // Each nice level is ~1.25x ratio
        // nice 0 = 1024, nice -1 = 1277, nice 1 = 820
        if (nice == 0) return NICE0_WEIGHT;
        if (nice < 0) {
            var w: u64 = NICE0_WEIGHT;
            var n: i8 = nice;
            while (n < 0) : (n += 1) {
                w = w * 5 / 4;
            }
            return w;
        } else {
            var w: u64 = NICE0_WEIGHT;
            var n: i8 = nice;
            while (n > 0) : (n -= 1) {
                w = w * 4 / 5;
            }
            return w;
        }
    }

    // Update vruntime: higher weight → slower vruntime growth → more CPU
    fn updateVruntime(proc: *Process, wall_ns: u64) void {
        const weight = niceToWeight(proc.priority);
        // vruntime += wall_time * (NICE0_WEIGHT / weight)
        proc.vruntime += wall_ns * NICE0_WEIGHT / weight;
    }

    // Pick the process with the lowest vruntime (most "owed" CPU time)
    fn schedule(self: *CfsScheduler) ?*Process {
        if (self.count == 0) return null;

        var min_vrt: u64 = std.math.maxInt(u64);
        var best: ?*Process = null;

        for (self.procs[0..self.count]) |p| {
            if (p.state == .ready and p.vruntime < min_vrt) {
                min_vrt = p.vruntime;
                best = p;
            }
        }

        if (best) |b| {
            b.state = .running;
        }
        return best;
    }
};

fn testCfsScheduler() !void {
    const dummy_ctx = SavedContext{
        .rbx = 0, .rbp = 0, .r12 = 0, .r13 = 0, .r14 = 0, .r15 = 0,
        .rip = 0, .rsp = 0, .rflags = 0x202, .cs = 0x2B, .ss = 0x23,
        .ds = 0x23, .es = 0x23, .cr3 = 0,
    };

    // nice -5 (high priority) vs nice 5 (low priority)
    var high = Process{ .pid = 1, .ppid = 0, .state = .created, .context = dummy_ctx, .priority = -5, .vruntime = 0, .time_slice = 0, .total_runtime = 0, .name = "high_prio" };
    var low = Process{ .pid = 2, .ppid = 0, .state = .created, .context = dummy_ctx, .priority = 5, .vruntime = 0, .time_slice = 0, .total_runtime = 0, .name = "low_prio" };

    var cfs = CfsScheduler.init();
    cfs.addProcess(&high);
    cfs.addProcess(&low);

    // Both start at vruntime 0 — high prio picked first (lower index tie-break)
    const first = cfs.schedule().?;
    try expect(first.pid == 1);

    // Simulate: both run for 1ms wall time
    first.state = .ready;
    CfsScheduler.updateVruntime(&high, 1_000_000);
    CfsScheduler.updateVruntime(&low, 1_000_000);

    // High priority (nice -5) has lower vruntime growth
    // because its weight is higher
    try expect(high.vruntime < low.vruntime);

    // Weight ratio check
    const w_high = CfsScheduler.niceToWeight(-5);
    const w_low = CfsScheduler.niceToWeight(5);
    try expect(w_high > CfsScheduler.NICE0_WEIGHT);
    try expect(w_low < CfsScheduler.NICE0_WEIGHT);
    try expect(w_high > w_low); // higher weight = more CPU time
}

// ── Context Switch ───────────────────────────────────────────────────
// What happens during a context switch:
const ContextSwitchStep = struct {
    order: u8,
    action: []const u8,
};

fn testContextSwitch() !void {
    const steps = [_]ContextSwitchStep{
        .{ .order = 1, .action = "Save registers to outgoing task's kernel stack" },
        .{ .order = 2, .action = "Save FPU/SSE/AVX state (XSAVE)" },
        .{ .order = 3, .action = "Switch kernel stack pointer (RSP)" },
        .{ .order = 4, .action = "Switch page tables (load new CR3)" },
        .{ .order = 5, .action = "Flush TLB entries (or use PCID to avoid)" },
        .{ .order = 6, .action = "Restore FPU/SSE/AVX state (XRSTOR)" },
        .{ .order = 7, .action = "Restore registers from incoming task's stack" },
        .{ .order = 8, .action = "Return to new task's instruction pointer" },
    };

    try expect(steps.len == 8);
    try expect(steps[0].order == 1);
    try expect(steps[7].order == 8);

    // Context switch cost: ~1-5 microseconds on modern hardware
    // Dominated by TLB flush and cache pollution
    // PCID (Process Context ID) avoids full TLB flush on CR3 load
    for (steps, 1..) |step, i| {
        try expect(step.order == i);
    }
}

// ── Priority Levels ──────────────────────────────────────────────────
fn testPriorityLevels() !void {
    // Linux priority model:
    // Real-time: 0-99 (higher = more priority)
    // Normal (CFS): 100-139 (maps to nice -20 to +19)

    // nice to kernel priority
    const nice_min: i8 = -20; // highest normal priority
    const nice_max: i8 = 19; // lowest normal priority

    try expect(120 + @as(i16, nice_min) == 100);
    try expect(120 + @as(i16, nice_max) == 139);

    // Scheduling classes (Linux, highest to lowest priority):
    const SchedClass = enum(u8) {
        stop = 0, // CPU stopper (migration)
        deadline = 1, // SCHED_DEADLINE: earliest deadline first
        realtime = 2, // SCHED_FIFO / SCHED_RR
        fair = 3, // SCHED_NORMAL (CFS)
        idle = 4, // SCHED_IDLE
    };

    try expect(@intFromEnum(SchedClass.deadline) < @intFromEnum(SchedClass.realtime));
    try expect(@intFromEnum(SchedClass.realtime) < @intFromEnum(SchedClass.fair));
    try expect(@intFromEnum(SchedClass.fair) < @intFromEnum(SchedClass.idle));
}
