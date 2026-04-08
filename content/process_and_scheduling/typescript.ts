// Vidya — Process and Scheduling in TypeScript
//
// An OS scheduler decides which process runs on the CPU and for how long.
// We model process states and transitions, implement a round-robin
// scheduler with fixed time quanta, a CFS (Completely Fair Scheduler)
// with weighted virtual runtime, and describe the context switch layout.

function main(): void {
    testProcessStates();
    testRoundRobinScheduler();
    testCfsScheduler();
    testContextLayout();
    testTaskLifecycle();
    testPriorityWeight();

    console.log("All process and scheduling examples passed.");
}

// ── Process States ──────────────────────────────────────────────────

// A process is always in exactly one state. Transitions are triggered
// by system events (fork, schedule, I/O, exit).

type ProcessState = "created" | "ready" | "running" | "blocked" | "terminated";

// Valid state transitions:
//   created    → ready       (added to runqueue after fork)
//   ready      → running     (scheduler picks this task)
//   running    → ready       (preempted by timer)
//   running    → blocked     (waiting for I/O, lock, etc.)
//   blocked    → ready       (I/O complete, lock released)
//   running    → terminated  (exit() called)

const VALID_TRANSITIONS: Array<[ProcessState, ProcessState, string]> = [
    ["created",    "ready",      "fork/clone creates task"],
    ["ready",      "running",    "scheduler selects task"],
    ["running",    "ready",      "timer preemption"],
    ["running",    "blocked",    "I/O wait or lock"],
    ["blocked",    "ready",      "I/O complete or wakeup"],
    ["running",    "terminated", "exit() or signal"],
];

function isValidTransition(from: ProcessState, to: ProcessState): boolean {
    return VALID_TRANSITIONS.some(([f, t]) => f === from && t === to);
}

function testProcessStates(): void {
    assert(isValidTransition("created", "ready"), "created → ready");
    assert(isValidTransition("ready", "running"), "ready → running");
    assert(isValidTransition("running", "ready"), "running → ready (preempt)");
    assert(isValidTransition("running", "blocked"), "running → blocked");
    assert(isValidTransition("blocked", "ready"), "blocked → ready");
    assert(isValidTransition("running", "terminated"), "running → terminated");

    // Invalid transitions
    assert(!isValidTransition("blocked", "running"), "cannot go blocked → running");
    assert(!isValidTransition("terminated", "ready"), "cannot resurrect");
    assert(!isValidTransition("ready", "blocked"), "cannot block without running");
    assert(!isValidTransition("created", "running"), "must go through ready first");
}

// ── Saved CPU Registers (Context) ───────────────────────────────────

// When the scheduler switches tasks, it saves the current task's
// registers and restores the next task's. On x86_64, only callee-saved
// registers need explicit saving (the calling convention handles the rest).

interface SavedRegisters {
    rsp: bigint;   // stack pointer
    rbp: bigint;   // frame pointer
    rbx: bigint;   // callee-saved
    r12: bigint;
    r13: bigint;
    r14: bigint;
    r15: bigint;
    rip: bigint;   // return address (where to resume)
}

function defaultRegisters(): SavedRegisters {
    return { rsp: 0n, rbp: 0n, rbx: 0n, r12: 0n, r13: 0n, r14: 0n, r15: 0n, rip: 0n };
}

// ── Task (Process Control Block) ────────────────────────────────────

class Task {
    state: ProcessState = "created";
    regs: SavedRegisters;
    cpuTime = 0;       // total ticks consumed
    vruntime = 0;      // CFS virtual runtime
    timeSlice = 0;     // remaining ticks in current quantum
    switches = 0;      // context switch count

    constructor(
        public readonly pid: number,
        public readonly name: string,
        public readonly nice: number, // -20 to 19, lower = higher priority
    ) {
        this.regs = defaultRegisters();
    }

    /** CFS weight based on nice value. Nice 0 = weight 1024. */
    weight(): number {
        const base = 1024;
        if (this.nice >= 0) {
            return base >> Math.min(this.nice, 10);
        }
        return base << Math.min(-this.nice, 10);
    }

    toString(): string {
        return `PID=${this.pid} ${this.name.padEnd(12)} ${this.state.padStart(10)} nice=${String(this.nice).padStart(3)} vrt=${this.vruntime} cpu=${this.cpuTime}`;
    }
}

function testPriorityWeight(): void {
    // Nice 0: base weight
    const normal = new Task(1, "normal", 0);
    assert(normal.weight() === 1024, "nice 0 = weight 1024");

    // Nice -5: higher weight, gets MORE CPU
    const high = new Task(2, "high", -5);
    assert(high.weight() > normal.weight(), "negative nice = higher weight");
    assert(high.weight() === 1024 << 5, "nice -5 weight");

    // Nice 5: lower weight, gets LESS CPU
    const low = new Task(3, "low", 5);
    assert(low.weight() < normal.weight(), "positive nice = lower weight");
    assert(low.weight() === 1024 >> 5, "nice 5 weight");

    // Nice -10 vs nice 10: ~1000x weight difference
    const vhigh = new Task(4, "vhigh", -10);
    const vlow = new Task(5, "vlow", 10);
    assert(vhigh.weight() / vlow.weight() > 500, "large weight spread");
}

// ── Round-Robin Scheduler ───────────────────────────────────────────

// Each task gets an equal time quantum. When the quantum expires,
// the task is preempted and the next ready task runs. Simple but
// unfair to I/O-bound tasks that voluntarily yield early.

class RoundRobinScheduler {
    private tasks: Task[] = [];
    private currentIdx: number | null = null;
    tick = 0;

    constructor(private quantum: number) {}

    addTask(task: Task): void {
        task.state = "ready";
        this.tasks.push(task);
    }

    /** Pick the next ready task (round-robin from current position). */
    schedule(): number | null {
        const n = this.tasks.length;
        const start = this.currentIdx !== null ? (this.currentIdx + 1) % n : 0;

        for (let i = 0; i < n; i++) {
            const idx = (start + i) % n;
            if (this.tasks[idx].state === "ready") {
                // Preempt current task if running
                if (this.currentIdx !== null && this.tasks[this.currentIdx].state === "running") {
                    this.tasks[this.currentIdx].state = "ready";
                }

                this.tasks[idx].state = "running";
                this.tasks[idx].timeSlice = this.quantum;
                this.tasks[idx].switches++;
                this.currentIdx = idx;
                return this.tasks[idx].pid;
            }
        }
        return null;
    }

    /** Advance one tick. Preempts if time slice expires. */
    tickOnce(): void {
        this.tick++;
        if (this.currentIdx === null) return;

        const task = this.tasks[this.currentIdx];
        task.cpuTime++;
        task.timeSlice--;

        if (task.timeSlice <= 0) {
            task.state = "ready"; // preempted
        }
    }

    /** Block a task (simulates I/O wait). */
    block(pid: number): void {
        const task = this.tasks.find((t) => t.pid === pid);
        if (task && task.state === "running") {
            task.state = "blocked";
        }
    }

    /** Unblock a task (simulates I/O completion). */
    unblock(pid: number): void {
        const task = this.tasks.find((t) => t.pid === pid);
        if (task && task.state === "blocked") {
            task.state = "ready";
        }
    }

    /** Terminate a task. */
    terminate(pid: number): void {
        const task = this.tasks.find((t) => t.pid === pid);
        if (task) task.state = "terminated";
    }

    currentPid(): number | null {
        return this.currentIdx !== null && this.tasks[this.currentIdx].state === "running"
            ? this.tasks[this.currentIdx].pid
            : null;
    }

    getTask(pid: number): Task | undefined {
        return this.tasks.find((t) => t.pid === pid);
    }
}

function testRoundRobinScheduler(): void {
    const rr = new RoundRobinScheduler(3); // 3-tick quantum

    rr.addTask(new Task(1, "init", 0));
    rr.addTask(new Task(2, "compiler", 0));
    rr.addTask(new Task(3, "editor", 0));

    // Simulate 9 ticks: each task gets exactly one quantum (3 ticks)
    const history: number[] = [];
    for (let i = 0; i < 9; i++) {
        if (rr.currentPid() === null) {
            rr.schedule();
        }
        if (rr.currentPid() !== null) {
            history.push(rr.currentPid()!);
        }
        rr.tickOnce();
    }

    // Round-robin pattern: 1,1,1, 2,2,2, 3,3,3
    assert(history[0] === 1, "starts with PID 1");
    assert(history[3] === 2, "switches to PID 2 at tick 3");
    assert(history[6] === 3, "switches to PID 3 at tick 6");

    // Each task gets exactly 3 ticks (one quantum each)
    assert(rr.getTask(1)!.cpuTime === 3, "init: 3 ticks");
    assert(rr.getTask(2)!.cpuTime === 3, "compiler: 3 ticks");
    assert(rr.getTask(3)!.cpuTime === 3, "editor: 3 ticks");

    // Test blocking
    rr.schedule();
    const runningPid = rr.currentPid()!;
    rr.block(runningPid);
    assert(rr.getTask(runningPid)!.state === "blocked", "task blocked");
    // Scheduler skips blocked tasks
    rr.schedule();
    assert(rr.currentPid() !== runningPid, "skips blocked task");

    // Unblock and it becomes ready again
    rr.unblock(runningPid);
    assert(rr.getTask(runningPid)!.state === "ready", "task unblocked");
}

// ── CFS (Completely Fair Scheduler) ─────────────────────────────────

// CFS tracks "virtual runtime" (vruntime) for each task.
// It always runs the task with the SMALLEST vruntime.
// Higher-priority tasks (lower nice) accumulate vruntime slower,
// so they get more CPU time. This ensures fairness weighted by priority.

class CfsScheduler {
    private tasks: Task[] = [];
    private currentIdx: number | null = null;
    tick = 0;

    constructor(private minGranularity: number) {}

    addTask(task: Task): void {
        task.state = "ready";
        // New tasks start with the minimum vruntime of existing tasks
        // to prevent them from monopolizing the CPU
        if (this.tasks.length > 0) {
            const minVrt = Math.min(...this.tasks
                .filter((t) => t.state !== "terminated")
                .map((t) => t.vruntime));
            task.vruntime = minVrt;
        }
        this.tasks.push(task);
    }

    /** Pick the task with the smallest vruntime. */
    schedule(): number | null {
        let bestIdx: number | null = null;
        let bestVrt = Infinity;

        for (let i = 0; i < this.tasks.length; i++) {
            const t = this.tasks[i];
            if ((t.state === "ready" || t.state === "running") && t.vruntime < bestVrt) {
                bestVrt = t.vruntime;
                bestIdx = i;
            }
        }

        if (bestIdx === null) return null;

        // Preempt current
        if (this.currentIdx !== null && this.currentIdx !== bestIdx) {
            if (this.tasks[this.currentIdx].state === "running") {
                this.tasks[this.currentIdx].state = "ready";
            }
            this.tasks[bestIdx].switches++;
        }

        this.tasks[bestIdx].state = "running";
        this.currentIdx = bestIdx;
        return this.tasks[bestIdx].pid;
    }

    /** Advance one tick. Updates vruntime based on task weight. */
    tickOnce(): void {
        this.tick++;
        if (this.currentIdx === null) return;

        const task = this.tasks[this.currentIdx];
        task.cpuTime++;

        // vruntime increases inversely with weight:
        // vruntime_delta = actual_time * (base_weight / task_weight)
        // High-weight tasks: vruntime grows slowly → they run longer
        // Low-weight tasks: vruntime grows quickly → they run less
        const weight = task.weight();
        task.vruntime += Math.ceil(1024 / weight);
    }

    getTask(pid: number): Task | undefined {
        return this.tasks.find((t) => t.pid === pid);
    }
}

function testCfsScheduler(): void {
    const cfs = new CfsScheduler(1);

    // Three tasks with different priorities
    cfs.addTask(new Task(1, "high-prio", -5));  // weight 32768, vruntime grows slowly
    cfs.addTask(new Task(2, "normal", 0));       // weight 1024
    cfs.addTask(new Task(3, "low-prio", 5));     // weight 32, vruntime grows fast

    // Run for 60 ticks
    for (let i = 0; i < 60; i++) {
        cfs.schedule();
        cfs.tickOnce();
    }

    const high = cfs.getTask(1)!;
    const normal = cfs.getTask(2)!;
    const low = cfs.getTask(3)!;

    // High-priority task should get the most CPU time
    assert(high.cpuTime > normal.cpuTime, "high-prio gets more CPU than normal");
    assert(normal.cpuTime > low.cpuTime, "normal gets more CPU than low-prio");

    // Verify fairness: vruntimes should be roughly equal
    // (That is the point of CFS — equal virtual runtime)
    const maxVrt = Math.max(high.vruntime, normal.vruntime, low.vruntime);
    const minVrt = Math.min(high.vruntime, normal.vruntime, low.vruntime);
    // They should be within a small range of each other
    assert(maxVrt - minVrt <= 5, "vruntimes converge (fairness)");

    // Low-priority task has fewer context switches (longer quanta between preemptions)
    assert(low.switches <= normal.switches, "low-prio: fewer switches");
}

// ── Context Switch Layout ───────────────────────────────────────────

// A context switch saves one task's registers and restores another's.
// On x86_64, only callee-saved registers need explicit saving.

interface ContextSwitchStep {
    step: number;
    action: string;
    detail: string;
}

function describeContextSwitch(): ContextSwitchStep[] {
    return [
        {
            step: 1,
            action: "Save callee-saved registers",
            detail: "Push RBX, RBP, R12-R15 onto prev's kernel stack",
        },
        {
            step: 2,
            action: "Save stack pointer",
            detail: "Store RSP into prev->task_struct.rsp",
        },
        {
            step: 3,
            action: "Check address space",
            detail: "If prev->mm != next->mm: write next->cr3 to CR3 (flush TLB)",
        },
        {
            step: 4,
            action: "Restore stack pointer",
            detail: "Load next->task_struct.rsp into RSP (now on next's stack)",
        },
        {
            step: 5,
            action: "Restore callee-saved registers",
            detail: "Pop R15-R12, RBP, RBX from next's kernel stack",
        },
        {
            step: 6,
            action: "Return",
            detail: "RET pops saved RIP from next's stack, resuming next task",
        },
    ];
}

function testContextLayout(): void {
    const steps = describeContextSwitch();

    assert(steps.length === 6, "6 context switch steps");
    assert(steps[0].action.includes("Save"), "first: save registers");
    assert(steps[5].action.includes("Return"), "last: return to next task");

    // CR3 switch (step 3) only happens for different address spaces
    // Threads share mm_struct, so CR3 switch is skipped (huge optimization)
    const cr3Step = steps.find((s) => s.detail.includes("CR3"))!;
    assert(cr3Step.detail.includes("prev->mm != next->mm"), "CR3 conditional");

    // Context switch overhead is ~1-5 microseconds on modern hardware
    // The TLB flush from CR3 switch is the expensive part
}

// ── Task Lifecycle ──────────────────────────────────────────────────

function testTaskLifecycle(): void {
    const rr = new RoundRobinScheduler(5);

    // 1. Created → Ready (fork)
    const task = new Task(42, "worker", 0);
    assert(task.state === "created", "starts created");
    rr.addTask(task); // transitions to ready
    assert(rr.getTask(42)!.state === "ready", "fork → ready");

    // 2. Ready → Running (scheduled)
    rr.schedule();
    assert(rr.getTask(42)!.state === "running", "schedule → running");

    // 3. Running → Blocked (I/O wait)
    rr.block(42);
    assert(rr.getTask(42)!.state === "blocked", "I/O → blocked");

    // 4. Blocked → Ready (I/O complete)
    rr.unblock(42);
    assert(rr.getTask(42)!.state === "ready", "wakeup → ready");

    // 5. Ready → Running → Terminated (exit)
    rr.schedule();
    assert(rr.getTask(42)!.state === "running", "rescheduled");
    rr.terminate(42);
    assert(rr.getTask(42)!.state === "terminated", "exit → terminated");

    // Terminated tasks are never scheduled again
    const next = rr.schedule();
    assert(next === null, "no tasks to schedule");
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
