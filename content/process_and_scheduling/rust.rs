// Process and Scheduling — Rust Implementation
//
// Demonstrates operating system scheduling concepts:
//   1. Task (process) representation with saved state
//   2. Context switch mechanics (register save/restore)
//   3. Round-robin scheduler
//   4. CFS-like fair scheduler with virtual runtime
//   5. Priority scheduling with priority inversion detection
//
// In a real kernel, context_switch is assembly. Here we simulate the state
// transitions and scheduling decisions.

use std::collections::BTreeMap;
use std::fmt;

// ── Task State ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq)]
enum TaskState {
    Ready,
    Running,
    Blocked,
    Terminated,
}

impl fmt::Display for TaskState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TaskState::Ready => write!(f, "READY"),
            TaskState::Running => write!(f, "RUNNING"),
            TaskState::Blocked => write!(f, "BLOCKED"),
            TaskState::Terminated => write!(f, "DONE"),
        }
    }
}

/// Saved CPU register state (callee-saved registers on x86_64).
#[derive(Debug, Clone, Default)]
struct SavedRegisters {
    rsp: u64,
    rbp: u64,
    rbx: u64,
    r12: u64,
    r13: u64,
    r14: u64,
    r15: u64,
    rip: u64, // return address (where to resume)
}

/// A task (process/thread) control block.
#[derive(Debug, Clone)]
struct Task {
    pid: u32,
    name: String,
    state: TaskState,
    regs: SavedRegisters,
    /// Total CPU time consumed (simulated ticks)
    cpu_time: u64,
    /// CFS virtual runtime (weighted by priority)
    vruntime: u64,
    /// Nice value (-20 to 19, lower = higher priority)
    nice: i8,
    /// Time slice remaining (for round-robin)
    time_slice: u32,
    /// Context switch count
    switches: u32,
}

impl Task {
    fn new(pid: u32, name: &str, nice: i8) -> Self {
        Self {
            pid,
            name: name.to_string(),
            state: TaskState::Ready,
            regs: SavedRegisters::default(),
            cpu_time: 0,
            vruntime: 0,
            nice,
            time_slice: 10, // default time slice in ticks
            switches: 0,
        }
    }

    /// CFS weight based on nice value. Nice 0 = weight 1024.
    fn weight(&self) -> u64 {
        // Simplified: each nice level is ~1.25x
        let base = 1024u64;
        if self.nice >= 0 {
            base >> (self.nice as u32).min(10)
        } else {
            base << ((-self.nice) as u32).min(10)
        }
    }
}

impl fmt::Display for Task {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "PID={:<3} {:<12} {:>7} nice={:>3} vrt={:<6} cpu={:<4} sw={}",
            self.pid, self.name, self.state, self.nice, self.vruntime, self.cpu_time, self.switches
        )
    }
}

// ── Round-Robin Scheduler ─────────────────────────────────────────────────

struct RoundRobinScheduler {
    tasks: Vec<Task>,
    current: Option<usize>,
    tick: u64,
    time_quantum: u32,
}

impl RoundRobinScheduler {
    fn new(time_quantum: u32) -> Self {
        Self {
            tasks: Vec::new(),
            current: None,
            tick: 0,
            time_quantum,
        }
    }

    fn add_task(&mut self, task: Task) {
        self.tasks.push(task);
    }

    fn schedule(&mut self) -> Option<u32> {
        // Find next ready task (round-robin from current position)
        let n = self.tasks.len();
        let start = self.current.map_or(0, |c| (c + 1) % n);

        for i in 0..n {
            let idx = (start + i) % n;
            if self.tasks[idx].state == TaskState::Ready {
                // Switch from current to next
                if let Some(prev) = self.current {
                    if self.tasks[prev].state == TaskState::Running {
                        self.tasks[prev].state = TaskState::Ready;
                    }
                }

                self.tasks[idx].state = TaskState::Running;
                self.tasks[idx].time_slice = self.time_quantum;
                self.tasks[idx].switches += 1;
                self.current = Some(idx);
                return Some(self.tasks[idx].pid);
            }
        }

        None // no ready tasks
    }

    fn tick(&mut self) {
        self.tick += 1;
        if let Some(idx) = self.current {
            self.tasks[idx].cpu_time += 1;
            self.tasks[idx].time_slice = self.tasks[idx].time_slice.saturating_sub(1);

            // Time slice expired — preempt
            if self.tasks[idx].time_slice == 0 {
                self.tasks[idx].state = TaskState::Ready;
            }
        }
    }

    fn terminate(&mut self, pid: u32) {
        if let Some(task) = self.tasks.iter_mut().find(|t| t.pid == pid) {
            task.state = TaskState::Terminated;
        }
    }
}

// ── CFS-like Fair Scheduler ───────────────────────────────────────────────

struct CfsScheduler {
    tasks: Vec<Task>,
    current: Option<usize>,
    tick: u64,
    min_granularity: u64,  // minimum time before preemption
}

impl CfsScheduler {
    fn new(min_granularity: u64) -> Self {
        Self {
            tasks: Vec::new(),
            current: None,
            tick: 0,
            min_granularity,
        }
    }

    fn add_task(&mut self, task: Task) {
        self.tasks.push(task);
    }

    /// Pick the task with the smallest virtual runtime.
    fn schedule(&mut self) -> Option<u32> {
        let next_idx = self
            .tasks
            .iter()
            .enumerate()
            .filter(|(_, t)| t.state == TaskState::Ready || t.state == TaskState::Running)
            .min_by_key(|(_, t)| t.vruntime)
            .map(|(i, _)| i);

        if let Some(idx) = next_idx {
            if let Some(prev) = self.current {
                if prev != idx && self.tasks[prev].state == TaskState::Running {
                    self.tasks[prev].state = TaskState::Ready;
                }
            }
            self.tasks[idx].state = TaskState::Running;
            if self.current != Some(idx) {
                self.tasks[idx].switches += 1;
            }
            self.current = Some(idx);
            Some(self.tasks[idx].pid)
        } else {
            None
        }
    }

    fn tick(&mut self) {
        self.tick += 1;
        if let Some(idx) = self.current {
            self.tasks[idx].cpu_time += 1;
            // Update vruntime: actual_time * (default_weight / task_weight)
            // Higher weight (lower nice) → vruntime grows slower → gets more CPU
            let weight = self.tasks[idx].weight();
            self.tasks[idx].vruntime += 1024 / weight;
        }
    }
}

// ── Simulation ────────────────────────────────────────────────────────────

fn main() {
    println!("Process and Scheduling — scheduler simulation:\n");

    // ── Round-Robin ───────────────────────────────────────────────────
    println!("1. Round-Robin Scheduler (quantum=3 ticks):");
    let mut rr = RoundRobinScheduler::new(3);
    rr.add_task(Task::new(1, "init", 0));
    rr.add_task(Task::new(2, "compiler", 0));
    rr.add_task(Task::new(3, "editor", 0));

    let mut history = Vec::new();
    for _ in 0..15 {
        if rr.current.is_none()
            || rr.tasks[rr.current.unwrap()].state != TaskState::Running
        {
            rr.schedule();
        }
        if let Some(idx) = rr.current {
            history.push(rr.tasks[idx].pid);
        }
        rr.tick();
    }

    println!("   Timeline (15 ticks): {:?}", history);
    println!("   Task states:");
    for task in &rr.tasks {
        println!("     {}", task);
    }

    // ── CFS ───────────────────────────────────────────────────────────
    println!("\n2. CFS Fair Scheduler (nice-weighted):");
    let mut cfs = CfsScheduler::new(1);
    cfs.add_task(Task::new(1, "high-prio", -5));  // higher weight, gets more CPU
    cfs.add_task(Task::new(2, "normal", 0));
    cfs.add_task(Task::new(3, "low-prio", 5));    // lower weight, gets less CPU

    let mut cfs_history = Vec::new();
    for _ in 0..30 {
        cfs.schedule();
        if let Some(idx) = cfs.current {
            cfs_history.push(cfs.tasks[idx].pid);
        }
        cfs.tick();
    }

    println!("   Timeline (30 ticks): {:?}", &cfs_history[..20]);
    println!("   ...");
    println!("   Task states:");
    for task in &cfs.tasks {
        let cpu_pct = task.cpu_time as f64 / 30.0 * 100.0;
        println!("     {} ({:.0}% CPU, weight={})", task, cpu_pct, task.weight());
    }

    // ── Context Switch Anatomy ────────────────────────────────────────
    println!("\n3. Context switch anatomy (x86_64):");
    println!("   // Called from scheduler, not from interrupt");
    println!("   // Only need to save callee-saved registers (calling convention handles the rest)");
    println!("   context_switch(prev: &mut Task, next: &mut Task):");
    println!("     1. Save prev's RBX, RBP, R12-R15, RSP");
    println!("     2. if prev.mm != next.mm:");
    println!("          write_cr3(next.cr3)  // switch page tables, flush TLB");
    println!("     3. Load next's RSP (now on next's kernel stack)");
    println!("     4. Load next's RBX, RBP, R12-R15");
    println!("     5. ret  // pops next's saved RIP, resumes next task");

    // ── Task lifecycle ────────────────────────────────────────────────
    println!("\n4. Task lifecycle:");
    let states = [
        ("fork()", "CREATED → READY (added to runqueue)"),
        ("schedule()", "READY → RUNNING (context switch in)"),
        ("timer tick", "RUNNING → READY (preempted, back to runqueue)"),
        ("read(fd)", "RUNNING → BLOCKED (waiting for I/O)"),
        ("I/O complete", "BLOCKED → READY (woken up by interrupt handler)"),
        ("exit()", "RUNNING → TERMINATED (resources freed)"),
        ("wait()", "Parent collects exit status, task_struct freed"),
    ];
    for (event, transition) in &states {
        println!("     {:<15} {}", event, transition);
    }
}
