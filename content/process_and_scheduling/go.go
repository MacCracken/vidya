// Vidya — Process and Scheduling in Go
//
// Models OS process management and CPU scheduling:
//   1. Process states and transitions (new/ready/running/blocked/zombie)
//   2. Process Control Block (PCB) with register context
//   3. Round-robin scheduler with time quantum
//   4. CFS (Completely Fair Scheduler) with vruntime
//   5. Context switch — saving and restoring register blocks
//   6. Priority and niceness
//
// Real schedulers run in kernel space with hardware timer interrupts.
// Here we simulate the data structures and algorithms that drive
// scheduling decisions.

package main

import (
	"fmt"
	"math"
	"sort"
)

func main() {
	testProcessStates()
	testRegisterContext()
	testRoundRobin()
	testCFSScheduler()
	testContextSwitch()
	testPriorityAndNice()

	fmt.Println("All process and scheduling examples passed.")
}

// ── Process States ───────────────────────────────────────────────────
// A process transitions through well-defined states. The kernel
// maintains these states in the task_struct (Linux) or PCB.

type ProcessState int

const (
	StateNew     ProcessState = iota // created, not yet ready
	StateReady                       // in run queue, waiting for CPU
	StateRunning                     // currently executing on a CPU
	StateBlocked                     // waiting for I/O or event
	StateZombie                      // exited, waiting for parent to reap
)

func (s ProcessState) String() string {
	switch s {
	case StateNew:
		return "new"
	case StateReady:
		return "ready"
	case StateRunning:
		return "running"
	case StateBlocked:
		return "blocked"
	case StateZombie:
		return "zombie"
	default:
		return "unknown"
	}
}

// ── Register Context ─────────────────────────────────────────────────
// On context switch, the kernel saves all general-purpose registers,
// the instruction pointer, stack pointer, and flags. This is the
// minimum state needed to resume a process.

type RegisterContext struct {
	// General-purpose registers (x86_64)
	RAX, RBX, RCX, RDX uint64
	RSI, RDI, RBP, RSP uint64
	R8, R9, R10, R11   uint64
	R12, R13, R14, R15 uint64

	// Special registers
	RIP    uint64 // instruction pointer
	RFLAGS uint64 // CPU flags
	CS     uint16 // code segment
	SS     uint16 // stack segment

	// FPU/SSE state would be here in a real kernel (512+ bytes)
}

// ── Process Control Block ────────────────────────────────────────────

type Process struct {
	PID       int
	Name      string
	State     ProcessState
	Priority  int    // lower = higher priority
	Nice      int    // -20 to 19
	Vruntime  uint64 // CFS virtual runtime (nanoseconds)
	TimeSlice int    // remaining time quantum (ticks)
	Context   RegisterContext
}

func testProcessStates() {
	fmt.Println("1. Process state transitions:")

	p := &Process{PID: 1, Name: "init", State: StateNew}
	assert(p.State == StateNew, "starts as new")

	// Valid transitions:
	// new -> ready (admitted to run queue)
	p.State = StateReady
	assert(p.State == StateReady, "new -> ready")

	// ready -> running (scheduler picks this process)
	p.State = StateRunning
	assert(p.State == StateRunning, "ready -> running")

	// running -> blocked (process calls read(), waits for I/O)
	p.State = StateBlocked
	assert(p.State == StateBlocked, "running -> blocked")

	// blocked -> ready (I/O completes, process can run again)
	p.State = StateReady
	assert(p.State == StateReady, "blocked -> ready")

	// ready -> running -> zombie (process exits)
	p.State = StateRunning
	p.State = StateZombie
	assert(p.State == StateZombie, "running -> zombie")

	fmt.Println("   new -> ready -> running -> blocked -> ready -> running -> zombie")
	fmt.Println("   Key: running->blocked on I/O, blocked->ready on I/O complete")
}

func testRegisterContext() {
	fmt.Println("\n2. Register context (x86_64 layout):")

	ctx := RegisterContext{
		RAX:    0,           // syscall return value
		RDI:    0x7FFE_0000, // first argument
		RSI:    1024,        // second argument
		RSP:    0x7FFF_F000, // stack pointer
		RBP:    0x7FFF_F100, // frame pointer
		RIP:    0x0040_0100, // instruction pointer
		RFLAGS: 0x202,       // IF=1 (interrupts enabled)
		CS:     0x33,        // user code segment (ring 3)
		SS:     0x2B,        // user stack segment (ring 3)
	}

	// User mode: CS DPL = 3
	assert(ctx.CS&3 == 3, "user mode ring 3")
	assert(ctx.SS&3 == 3, "user stack ring 3")

	// Stack grows down on x86_64
	assert(ctx.RSP < 0x8000_0000_0000, "stack in user space")

	// RFLAGS bit 9 = IF (interrupt flag)
	assert(ctx.RFLAGS&(1<<9) != 0, "interrupts enabled")

	// Kernel mode context would have CS=0x08, SS=0x10
	kernelCtx := RegisterContext{
		RIP: 0xFFFF_8000_0010_0000,
		RSP: 0xFFFF_C900_0000_F000,
		CS:  0x08,
		SS:  0x10,
	}
	assert(kernelCtx.CS&3 == 0, "kernel ring 0")

	fmt.Printf("   User context:   RIP=0x%X RSP=0x%X CS=0x%02X (ring %d)\n",
		ctx.RIP, ctx.RSP, ctx.CS, ctx.CS&3)
	fmt.Printf("   Kernel context: RIP=0x%X CS=0x%02X (ring %d)\n",
		kernelCtx.RIP, kernelCtx.CS, kernelCtx.CS&3)
	fmt.Printf("   RFLAGS: 0x%X (IF=%d)\n", ctx.RFLAGS, (ctx.RFLAGS>>9)&1)
}

// ── Round-Robin Scheduler ────────────────────────────────────────────
// Each process gets a fixed time quantum. When it expires, the process
// goes to the back of the queue. Simple, fair, but not optimal for
// interactive workloads.

type RoundRobinScheduler struct {
	queue    []*Process
	quantum  int // ticks per time slice
	current  int // index of running process
	ticks    int // total ticks elapsed
}

func NewRoundRobin(quantum int) *RoundRobinScheduler {
	return &RoundRobinScheduler{quantum: quantum}
}

func (rr *RoundRobinScheduler) AddProcess(p *Process) {
	p.TimeSlice = rr.quantum
	p.State = StateReady
	rr.queue = append(rr.queue, p)
}

// Tick advances the scheduler by one tick. Returns the running process.
func (rr *RoundRobinScheduler) Tick() *Process {
	if len(rr.queue) == 0 {
		return nil
	}
	rr.ticks++

	p := rr.queue[rr.current]
	p.State = StateRunning
	p.TimeSlice--

	if p.TimeSlice <= 0 {
		// Quantum expired — move to back of queue
		p.State = StateReady
		p.TimeSlice = rr.quantum
		rr.current = (rr.current + 1) % len(rr.queue)
	}

	return p
}

func testRoundRobin() {
	fmt.Println("\n3. Round-robin scheduler (quantum=3):")

	rr := NewRoundRobin(3)
	rr.AddProcess(&Process{PID: 1, Name: "A"})
	rr.AddProcess(&Process{PID: 2, Name: "B"})
	rr.AddProcess(&Process{PID: 3, Name: "C"})

	// Track which process runs each tick
	schedule := make([]string, 0, 12)
	for i := 0; i < 12; i++ {
		p := rr.Tick()
		schedule = append(schedule, p.Name)
	}

	// With quantum=3 and 3 processes: A,A,A,B,B,B,C,C,C,A,A,A
	expected := []string{"A", "A", "A", "B", "B", "B", "C", "C", "C", "A", "A", "A"}
	for i, s := range schedule {
		assert(s == expected[i], fmt.Sprintf("tick %d: got %s want %s", i, s, expected[i]))
	}

	fmt.Printf("   Quantum: %d ticks\n", rr.quantum)
	fmt.Printf("   Schedule: ")
	for i, s := range schedule {
		if i > 0 && i%3 == 0 {
			fmt.Print("| ")
		}
		fmt.Print(s, " ")
	}
	fmt.Println()
	fmt.Println("   Fair: each process gets equal CPU time")
	fmt.Println("   Weakness: no priority, poor for interactive tasks")
}

// ── CFS Scheduler ────────────────────────────────────────────────────
// Linux's Completely Fair Scheduler tracks virtual runtime (vruntime).
// The process with the smallest vruntime runs next. Higher-priority
// processes accumulate vruntime more slowly (they get more real time).
//
// vruntime += delta * (NICE_0_WEIGHT / weight[nice])
//
// Nice 0 has weight 1024. Nice -20 has weight ~88761 (runs ~87x slower
// in virtual time). Nice 19 has weight ~15 (runs ~68x faster in vtime).

type CFSScheduler struct {
	tasks      []*Process
	minVruntime uint64
}

func NewCFS() *CFSScheduler {
	return &CFSScheduler{}
}

// niceToWeight returns the CFS weight for a given nice value.
// Simplified from the real kernel's sched_prio_to_weight table.
func niceToWeight(nice int) uint64 {
	// Real kernel uses a precomputed table. Key entries:
	//   nice -20 -> 88761
	//   nice   0 -> 1024
	//   nice  19 -> 15
	// Each nice level is ~1.25x the adjacent weight.
	base := 1024.0
	factor := math.Pow(1.25, float64(-nice))
	w := uint64(base * factor)
	if w < 1 {
		w = 1
	}
	return w
}

func (cfs *CFSScheduler) AddTask(p *Process) {
	p.Vruntime = cfs.minVruntime // new tasks start at min vruntime
	p.State = StateReady
	cfs.tasks = append(cfs.tasks, p)
}

// PickNext returns the task with the smallest vruntime.
// In the real kernel, this is an O(1) operation using a red-black tree.
func (cfs *CFSScheduler) PickNext() *Process {
	if len(cfs.tasks) == 0 {
		return nil
	}

	var best *Process
	for _, t := range cfs.tasks {
		if t.State == StateReady || t.State == StateRunning {
			if best == nil || t.Vruntime < best.Vruntime {
				best = t
			}
		}
	}
	return best
}

// RunFor simulates running the picked task for `deltaNs` nanoseconds.
func (cfs *CFSScheduler) RunFor(p *Process, deltaNs uint64) {
	weight := niceToWeight(p.Nice)
	// vruntime increases inversely with weight
	// Higher weight (lower nice) = slower vruntime growth = more CPU
	vruntimeDelta := deltaNs * 1024 / weight
	p.Vruntime += vruntimeDelta
	p.State = StateRunning

	// Update min vruntime
	if p.Vruntime > cfs.minVruntime {
		// In real CFS, min_vruntime = max(min_vruntime, min(all vruntimes))
		min := p.Vruntime
		for _, t := range cfs.tasks {
			if (t.State == StateReady || t.State == StateRunning) && t.Vruntime < min {
				min = t.Vruntime
			}
		}
		cfs.minVruntime = min
	}
}

func testCFSScheduler() {
	fmt.Println("\n4. CFS scheduler (vruntime-based):")

	cfs := NewCFS()

	// Three tasks: high priority (nice -5), normal (nice 0), low (nice 5)
	high := &Process{PID: 1, Name: "high-pri", Nice: -5}
	normal := &Process{PID: 2, Name: "normal", Nice: 0}
	low := &Process{PID: 3, Name: "low-pri", Nice: 5}

	cfs.AddTask(high)
	cfs.AddTask(normal)
	cfs.AddTask(low)

	// Verify weights
	wHigh := niceToWeight(-5)
	wNormal := niceToWeight(0)
	wLow := niceToWeight(5)
	assert(wHigh > wNormal, "high-pri has higher weight")
	assert(wNormal > wLow, "normal has higher weight than low")
	assert(wNormal == 1024, "nice 0 = weight 1024")

	// Simulate 10 scheduling rounds (1ms each)
	runCounts := map[string]int{}
	for i := 0; i < 30; i++ {
		p := cfs.PickNext()
		assert(p != nil, "must have runnable task")
		cfs.RunFor(p, 1_000_000) // 1ms
		p.State = StateReady
		runCounts[p.Name]++
	}

	// Higher priority should run more often
	assert(runCounts["high-pri"] > runCounts["normal"],
		"high-pri runs more than normal")
	assert(runCounts["normal"] > runCounts["low-pri"],
		"normal runs more than low-pri")

	fmt.Printf("   Weights: high=%d (nice -5), normal=%d (nice 0), low=%d (nice 5)\n",
		wHigh, wNormal, wLow)
	fmt.Printf("   Runs in 30 rounds: high=%d, normal=%d, low=%d\n",
		runCounts["high-pri"], runCounts["normal"], runCounts["low-pri"])
	fmt.Printf("   Vruntimes: high=%d, normal=%d, low=%d\n",
		high.Vruntime, normal.Vruntime, low.Vruntime)
	fmt.Println("   Key: lower vruntime = gets picked next")
	fmt.Println("   Higher weight = vruntime grows slower = more CPU time")
}

// ── Context Switch ───────────────────────────────────────────────────
// A context switch saves the current process's registers and loads
// the next process's registers. On x86_64 this involves:
//   1. Save GP registers to current task's kernel stack or PCB
//   2. Switch stack pointer (RSP) to new task's kernel stack
//   3. Restore GP registers from new task's PCB
//   4. Switch CR3 if address spaces differ (TLB flush)

func contextSwitch(current, next *Process) {
	// Save current process state
	// In a real kernel: pushes all registers to kernel stack
	current.State = StateReady

	// Load next process state
	// In a real kernel: pops all registers from next's kernel stack
	next.State = StateRunning
}

func testContextSwitch() {
	fmt.Println("\n5. Context switch simulation:")

	proc1 := &Process{
		PID:  1,
		Name: "proc1",
		Context: RegisterContext{
			RIP: 0x0040_0100,
			RSP: 0x7FFF_E000,
			RAX: 42,
			CS:  0x33,
		},
	}
	proc2 := &Process{
		PID:  2,
		Name: "proc2",
		Context: RegisterContext{
			RIP: 0x0040_2000,
			RSP: 0x7FFF_C000,
			RAX: 99,
			CS:  0x33,
		},
	}

	proc1.State = StateRunning

	// Context switch: proc1 -> proc2
	contextSwitch(proc1, proc2)
	assert(proc1.State == StateReady, "proc1 now ready")
	assert(proc2.State == StateRunning, "proc2 now running")

	// Registers are preserved in each process's context
	assert(proc1.Context.RIP == 0x0040_0100, "proc1 RIP preserved")
	assert(proc2.Context.RIP == 0x0040_2000, "proc2 RIP loaded")
	assert(proc1.Context.RAX == 42, "proc1 RAX preserved")
	assert(proc2.Context.RAX == 99, "proc2 RAX loaded")

	fmt.Printf("   proc1: RIP=0x%X RSP=0x%X RAX=%d -> saved (ready)\n",
		proc1.Context.RIP, proc1.Context.RSP, proc1.Context.RAX)
	fmt.Printf("   proc2: RIP=0x%X RSP=0x%X RAX=%d -> loaded (running)\n",
		proc2.Context.RIP, proc2.Context.RSP, proc2.Context.RAX)
	fmt.Println("   Real cost: save/restore ~16 GP regs + FPU/SSE state")
	fmt.Println("   If address spaces differ: CR3 write flushes TLB (~1000 cycles)")
}

// ── Priority and Nice ────────────────────────────────────────────────

func testPriorityAndNice() {
	fmt.Println("\n6. Priority and nice values:")

	type NiceEntry struct {
		nice   int
		weight uint64
		label  string
	}
	entries := []NiceEntry{
		{-20, niceToWeight(-20), "highest priority (root only)"},
		{-10, niceToWeight(-10), "high priority"},
		{0, niceToWeight(0), "default"},
		{10, niceToWeight(10), "low priority"},
		{19, niceToWeight(19), "lowest priority"},
	}

	// Weights must be monotonically decreasing
	for i := 1; i < len(entries); i++ {
		assert(entries[i-1].weight > entries[i].weight,
			fmt.Sprintf("nice %d weight > nice %d weight", entries[i-1].nice, entries[i].nice))
	}

	// Nice 0 is always weight 1024
	assert(entries[2].weight == 1024, "nice 0 = 1024")

	// Sort by weight descending (= priority order)
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].weight > entries[j].weight
	})
	assert(entries[0].nice == -20, "nice -20 is highest weight")

	fmt.Printf("   %-6s %-8s %s\n", "Nice", "Weight", "Description")
	fmt.Printf("   %-6s %-8s %s\n", "----", "------", "-----------")
	for _, e := range entries {
		fmt.Printf("   %-6d %-8d %s\n", e.nice, e.weight, e.label)
	}

	// Ratio between nice -20 and nice 19
	ratio := float64(niceToWeight(-20)) / float64(niceToWeight(19))
	assert(ratio > 100, "nice -20 gets >100x more CPU than nice 19")
	fmt.Printf("\n   nice -20 / nice 19 ratio: %.0fx CPU time difference\n", ratio)
	fmt.Println("   Each nice level ~= 10%% CPU share change (1.25x weight)")
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
