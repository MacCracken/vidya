# Process and Scheduling — Python Implementation
#
# Demonstrates operating system scheduling concepts:
#   1. Task (process) representation with saved state
#   2. Context switch mechanics (register save/restore)
#   3. Round-robin scheduler with time quantum
#   4. CFS-like fair scheduler with virtual runtime
#   5. Process lifecycle state transitions
#
# In a real kernel, context_switch is assembly. Here we simulate the
# state transitions and scheduling decisions.

from dataclasses import dataclass, field
from enum import Enum, auto

# ── Task State ────────────────────────────────────────────────────────────


class TaskState(Enum):
    READY = auto()
    RUNNING = auto()
    BLOCKED = auto()
    TERMINATED = auto()


# ── Saved Registers ──────────────────────────────────────────────────────

@dataclass
class SavedRegisters:
    """Callee-saved registers on x86_64.

    On context switch, the kernel only saves callee-saved registers
    (RBX, RBP, R12-R15, RSP) because the calling convention guarantees
    the caller already saved the rest. RIP is saved as the return address
    on the kernel stack.
    """
    rsp: int = 0
    rbp: int = 0
    rbx: int = 0
    r12: int = 0
    r13: int = 0
    r14: int = 0
    r15: int = 0
    rip: int = 0  # return address (where to resume)


# ── Task Control Block ───────────────────────────────────────────────────

@dataclass
class Task:
    """A task (process/thread) control block.

    In a real kernel (e.g., Linux task_struct), this holds:
      - Register state for context switching
      - Scheduling metadata (priority, CPU time, vruntime)
      - Memory mapping info (mm_struct, page tables / CR3)
      - File descriptors, signals, etc.
    """
    pid: int
    name: str
    nice: int = 0
    state: TaskState = TaskState.READY
    regs: SavedRegisters = field(default_factory=SavedRegisters)
    cpu_time: int = 0       # total CPU ticks consumed
    vruntime: int = 0       # CFS virtual runtime
    time_slice: int = 10    # remaining ticks in current quantum
    switches: int = 0       # context switch count

    def weight(self) -> int:
        """CFS weight based on nice value. Nice 0 = weight 1024.

        Each nice level changes priority by ~1.25x. Lower nice (higher
        priority) = higher weight = vruntime grows slower = more CPU time.
        """
        base = 1024
        if self.nice >= 0:
            return base >> min(self.nice, 10)
        return base << min(-self.nice, 10)

    def __str__(self) -> str:
        return (f"PID={self.pid:<3} {self.name:<12} {self.state.name:>10} "
                f"nice={self.nice:>3} vrt={self.vruntime:<6} "
                f"cpu={self.cpu_time:<4} sw={self.switches}")


# ── Round-Robin Scheduler ─────────────────────────────────────────────────

class RoundRobinScheduler:
    """Simple round-robin: equal time quantum for every task.

    Each task gets `time_quantum` ticks before being preempted.
    Fair but ignores priority — every task gets equal CPU share.
    """

    def __init__(self, time_quantum: int):
        self.tasks: list[Task] = []
        self.current: int | None = None
        self.tick_count: int = 0
        self.time_quantum = time_quantum

    def add_task(self, task: Task) -> None:
        self.tasks.append(task)

    def schedule(self) -> int | None:
        """Pick the next READY task in round-robin order. Returns PID or None."""
        n = len(self.tasks)
        start = ((self.current or 0) + 1) % n if self.current is not None else 0

        for i in range(n):
            idx = (start + i) % n
            if self.tasks[idx].state == TaskState.READY:
                # Preempt current task
                if self.current is not None:
                    prev = self.tasks[self.current]
                    if prev.state == TaskState.RUNNING:
                        prev.state = TaskState.READY

                # Switch to new task
                task = self.tasks[idx]
                task.state = TaskState.RUNNING
                task.time_slice = self.time_quantum
                task.switches += 1
                self.current = idx
                return task.pid

        return None

    def tick(self) -> None:
        """Advance one tick. Preempt if time slice expired."""
        self.tick_count += 1
        if self.current is not None:
            task = self.tasks[self.current]
            task.cpu_time += 1
            task.time_slice -= 1
            if task.time_slice == 0:
                task.state = TaskState.READY

    def terminate(self, pid: int) -> None:
        for task in self.tasks:
            if task.pid == pid:
                task.state = TaskState.TERMINATED
                break


# ── CFS-like Fair Scheduler ───────────────────────────────────────────────

class CfsScheduler:
    """Completely Fair Scheduler — pick the task with lowest virtual runtime.

    vruntime = actual_time * (default_weight / task_weight)

    Higher-priority tasks (lower nice, higher weight) accumulate vruntime
    slower, so they get selected more often. The result is that CPU time
    is distributed proportionally to weight.

    Real CFS uses a red-black tree for O(log n) min-vruntime lookup.
    We use a linear scan for clarity.
    """

    def __init__(self, min_granularity: int = 1):
        self.tasks: list[Task] = []
        self.current: int | None = None
        self.tick_count: int = 0
        self.min_granularity = min_granularity

    def add_task(self, task: Task) -> None:
        self.tasks.append(task)

    def schedule(self) -> int | None:
        """Pick the task with the smallest virtual runtime."""
        candidates = [
            (i, t) for i, t in enumerate(self.tasks)
            if t.state in (TaskState.READY, TaskState.RUNNING)
        ]
        if not candidates:
            return None

        idx, _ = min(candidates, key=lambda x: x[1].vruntime)

        # Context switch if different task
        if self.current is not None and self.current != idx:
            prev = self.tasks[self.current]
            if prev.state == TaskState.RUNNING:
                prev.state = TaskState.READY

        task = self.tasks[idx]
        task.state = TaskState.RUNNING
        if self.current != idx:
            task.switches += 1
        self.current = idx
        return task.pid

    def tick(self) -> None:
        """Advance one tick. Update vruntime weighted by priority."""
        self.tick_count += 1
        if self.current is not None:
            task = self.tasks[self.current]
            task.cpu_time += 1
            # vruntime grows slower for higher-weight (higher-priority) tasks
            # Scale by 1024 to avoid integer division rounding to zero
            weight = task.weight()
            task.vruntime += (1024 * 1024) // weight


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    print("Process and Scheduling — scheduler simulation:\n")

    # ── 1. Round-Robin ────────────────────────────────────────────────
    print("1. Round-Robin Scheduler (quantum=3 ticks):")
    rr = RoundRobinScheduler(time_quantum=3)
    rr.add_task(Task(pid=1, name="init"))
    rr.add_task(Task(pid=2, name="compiler"))
    rr.add_task(Task(pid=3, name="editor"))

    history: list[int] = []
    for _ in range(15):
        # Check if we need to (re)schedule
        needs_schedule = (
            rr.current is None
            or rr.tasks[rr.current].state != TaskState.RUNNING
        )
        if needs_schedule:
            rr.schedule()
        if rr.current is not None:
            history.append(rr.tasks[rr.current].pid)
        rr.tick()

    print(f"   Timeline (15 ticks): {history}")
    print("   Task states:")
    for task in rr.tasks:
        print(f"     {task}")

    # Each task ran for some ticks; total should be 15
    total_cpu = sum(t.cpu_time for t in rr.tasks)
    assert total_cpu == 15, f"total CPU ticks {total_cpu} != 15"
    # Verify round-robin pattern: 1,1,1,2,2,2,3,3,3,...
    assert history[:3] == [1, 1, 1]
    assert history[3:6] == [2, 2, 2]
    assert history[6:9] == [3, 3, 3]

    # ── 2. CFS ────────────────────────────────────────────────────────
    print("\n2. CFS Fair Scheduler (nice-weighted):")
    cfs = CfsScheduler(min_granularity=1)
    cfs.add_task(Task(pid=1, name="high-prio", nice=-2))   # higher weight
    cfs.add_task(Task(pid=2, name="normal", nice=0))
    cfs.add_task(Task(pid=3, name="low-prio", nice=2))     # lower weight

    cfs_history: list[int] = []
    for _ in range(30):
        cfs.schedule()
        if cfs.current is not None:
            cfs_history.append(cfs.tasks[cfs.current].pid)
        cfs.tick()

    print(f"   Timeline (first 20): {cfs_history[:20]}")
    print("   Task states:")
    for task in cfs.tasks:
        cpu_pct = task.cpu_time / 30 * 100
        print(f"     {task} ({cpu_pct:.0f}% CPU, weight={task.weight()})")

    # Verify: high-prio task got the most CPU time
    high = next(t for t in cfs.tasks if t.pid == 1)
    low = next(t for t in cfs.tasks if t.pid == 3)
    assert high.cpu_time > low.cpu_time, "high-prio should get more CPU than low-prio"

    # Verify weight calculation
    assert Task(pid=0, name="t", nice=0).weight() == 1024
    assert Task(pid=0, name="t", nice=-1).weight() == 2048  # higher priority = more weight
    assert Task(pid=0, name="t", nice=1).weight() == 512   # lower priority = less weight

    # ── 3. Context switch anatomy ─────────────────────────────────────
    print("\n3. Context switch anatomy (x86_64):")
    print("   context_switch(prev, next):")
    print("     1. Save prev's RBX, RBP, R12-R15, RSP to prev->task_struct")
    print("     2. if prev.mm != next.mm:")
    print("          write_cr3(next.cr3)  // switch page tables, flush TLB")
    print("     3. Load next's RSP (now on next's kernel stack)")
    print("     4. Load next's RBX, RBP, R12-R15")
    print("     5. ret  // pops next's saved RIP, resumes next task")

    # Demonstrate register save/restore
    prev_regs = SavedRegisters(rsp=0xFFFF_0001_0000, rbp=0xFFFF_0001_0100,
                                rbx=42, r12=100, rip=0xFFFF_8000_0001_0000)
    next_regs = SavedRegisters(rsp=0xFFFF_0002_0000, rbp=0xFFFF_0002_0100,
                                rbx=99, r12=200, rip=0xFFFF_8000_0002_0000)
    print(f"\n   Before switch:")
    print(f"     prev RSP=0x{prev_regs.rsp:X} RIP=0x{prev_regs.rip:X}")
    print(f"     next RSP=0x{next_regs.rsp:X} RIP=0x{next_regs.rip:X}")
    # After switch, CPU is running with next's registers
    assert prev_regs.rsp != next_regs.rsp

    # ── 4. Task lifecycle ─────────────────────────────────────────────
    print("\n4. Task lifecycle:")
    transitions = [
        ("fork()",      "CREATED -> READY",      "added to runqueue"),
        ("schedule()",  "READY -> RUNNING",       "context switch in"),
        ("timer tick",  "RUNNING -> READY",       "preempted"),
        ("read(fd)",    "RUNNING -> BLOCKED",     "waiting for I/O"),
        ("I/O done",    "BLOCKED -> READY",       "woken by IRQ handler"),
        ("exit()",      "RUNNING -> TERMINATED",  "resources freed"),
        ("wait()",      "parent collects status",  "task_struct freed"),
    ]
    for event, transition, note in transitions:
        print(f"     {event:<15} {transition:<25} {note}")

    # Verify state transitions work
    t = Task(pid=99, name="test")
    assert t.state == TaskState.READY
    t.state = TaskState.RUNNING
    assert t.state == TaskState.RUNNING
    t.state = TaskState.BLOCKED
    assert t.state == TaskState.BLOCKED
    t.state = TaskState.READY
    t.state = TaskState.TERMINATED
    assert t.state == TaskState.TERMINATED

    print("\nAll assertions passed.")


if __name__ == "__main__":
    main()
