// Vidya — Interrupt Handling in Go
//
// Models x86_64 interrupt infrastructure:
//   1. IDT gate descriptor encoding (64-bit interrupt/trap gates)
//   2. PIC 8259A simulation — mask, unmask, EOI, cascaded pair
//   3. Exception table with CPU exception names and classes
//   4. Page fault error code decoding (CR2 + error code bits)
//   5. Interrupt priority and nesting
//
// On real hardware, the IDT is loaded via LIDT and the PIC is
// programmed via I/O ports. Here we model the data structures and
// control flow that a kernel must implement.

package main

import "fmt"

func main() {
	testIDTGateDescriptor()
	testExceptionTable()
	testPIC8259A()
	testPageFaultErrorCode()
	testInterruptDispatch()
	testInterruptPriority()

	fmt.Println("All interrupt handling examples passed.")
}

// ── IDT Gate Descriptor ──────────────────────────────────────────────
// x86_64 IDT entries are 16 bytes (128 bits). Each encodes:
//   - Handler address (split across 3 fields: offset_lo, offset_mid, offset_hi)
//   - Segment selector (code segment in GDT)
//   - Gate type (interrupt gate vs trap gate)
//   - DPL (descriptor privilege level)
//   - IST (interrupt stack table index)
//   - Present bit

const (
	GATE_INTERRUPT = 0xE // interrupt gate: clears IF (disables interrupts)
	GATE_TRAP      = 0xF // trap gate: leaves IF unchanged

	KERNEL_CS = 0x08 // typical kernel code segment selector
)

type GateDescriptor struct {
	raw [16]byte // 16 bytes = 128 bits
}

func NewGateDescriptor(handler uint64, selector uint16, ist uint8, gateType uint8, dpl uint8) GateDescriptor {
	var g GateDescriptor

	// Bytes 0-1: offset bits 15:0
	g.raw[0] = byte(handler)
	g.raw[1] = byte(handler >> 8)

	// Bytes 2-3: segment selector
	g.raw[2] = byte(selector)
	g.raw[3] = byte(selector >> 8)

	// Byte 4: IST (bits 2:0), rest zero
	g.raw[4] = ist & 0x07

	// Byte 5: type (3:0), S=0 (4), DPL (6:5), P=1 (7)
	g.raw[5] = (gateType & 0x0F) | ((dpl & 0x03) << 5) | (1 << 7)

	// Bytes 6-7: offset bits 31:16
	g.raw[6] = byte(handler >> 16)
	g.raw[7] = byte(handler >> 24)

	// Bytes 8-11: offset bits 63:32
	g.raw[8] = byte(handler >> 32)
	g.raw[9] = byte(handler >> 40)
	g.raw[10] = byte(handler >> 48)
	g.raw[11] = byte(handler >> 56)

	// Bytes 12-15: reserved (must be zero)
	return g
}

func (g *GateDescriptor) Handler() uint64 {
	lo := uint64(g.raw[0]) | uint64(g.raw[1])<<8
	mid := uint64(g.raw[6])<<16 | uint64(g.raw[7])<<24
	hi := uint64(g.raw[8])<<32 | uint64(g.raw[9])<<40 |
		uint64(g.raw[10])<<48 | uint64(g.raw[11])<<56
	return lo | mid | hi
}

func (g *GateDescriptor) Selector() uint16 {
	return uint16(g.raw[2]) | uint16(g.raw[3])<<8
}

func (g *GateDescriptor) IST() uint8     { return g.raw[4] & 0x07 }
func (g *GateDescriptor) GateType() uint8 { return g.raw[5] & 0x0F }
func (g *GateDescriptor) DPL() uint8     { return (g.raw[5] >> 5) & 0x03 }
func (g *GateDescriptor) Present() bool  { return g.raw[5]&0x80 != 0 }

func testIDTGateDescriptor() {
	fmt.Println("1. IDT gate descriptor encoding (16 bytes):")

	// Divide error handler at a typical kernel address
	handler := uint64(0xFFFF_8000_0010_1234)
	gate := NewGateDescriptor(handler, KERNEL_CS, 0, GATE_INTERRUPT, 0)

	assert(gate.Handler() == handler, "handler address roundtrip")
	assert(gate.Selector() == KERNEL_CS, "selector = kernel CS")
	assert(gate.IST() == 0, "IST = 0 (default stack)")
	assert(gate.GateType() == GATE_INTERRUPT, "interrupt gate")
	assert(gate.DPL() == 0, "ring 0")
	assert(gate.Present(), "present")

	fmt.Printf("   Handler:  0x%016X\n", gate.Handler())
	fmt.Printf("   Selector: 0x%04X (kernel CS)\n", gate.Selector())
	fmt.Printf("   Type:     0x%X (interrupt gate)\n", gate.GateType())
	fmt.Printf("   DPL:      %d (ring 0)\n", gate.DPL())
	fmt.Printf("   IST:      %d\n", gate.IST())

	// Trap gate with IST=1 for double fault
	df := NewGateDescriptor(0xFFFF_8000_0020_0000, KERNEL_CS, 1, GATE_TRAP, 0)
	assert(df.GateType() == GATE_TRAP, "trap gate")
	assert(df.IST() == 1, "double fault uses IST 1")

	// User-callable gate (DPL=3) for syscall via INT
	syscallGate := NewGateDescriptor(0xFFFF_8000_0030_0000, KERNEL_CS, 0, GATE_TRAP, 3)
	assert(syscallGate.DPL() == 3, "syscall gate DPL=3")

	fmt.Printf("   Double fault: IST=%d, type=trap (0x%X)\n", df.IST(), df.GateType())
	fmt.Printf("   Syscall gate: DPL=%d (user-callable)\n", syscallGate.DPL())
}

// ── Exception Table ──────────────────────────────────────────────────
// x86_64 defines 32 exception vectors (0-31). Each has a name, class
// (fault/trap/abort), and whether it pushes an error code.

type ExceptionClass int

const (
	Fault ExceptionClass = iota
	Trap
	Abort
	Interrupt
)

func (c ExceptionClass) String() string {
	switch c {
	case Fault:
		return "fault"
	case Trap:
		return "trap"
	case Abort:
		return "abort"
	case Interrupt:
		return "interrupt"
	default:
		return "unknown"
	}
}

type ExceptionInfo struct {
	Vector    uint8
	Mnemonic  string
	Name      string
	Class     ExceptionClass
	HasError  bool // CPU pushes error code onto stack
}

var exceptions = []ExceptionInfo{
	{0, "#DE", "Divide Error", Fault, false},
	{1, "#DB", "Debug", Fault, false},         // fault or trap depending on cause
	{2, "NMI", "Non-Maskable Interrupt", Interrupt, false},
	{3, "#BP", "Breakpoint", Trap, false},
	{4, "#OF", "Overflow", Trap, false},
	{5, "#BR", "Bound Range Exceeded", Fault, false},
	{6, "#UD", "Invalid Opcode", Fault, false},
	{7, "#NM", "Device Not Available", Fault, false},
	{8, "#DF", "Double Fault", Abort, true},
	{10, "#TS", "Invalid TSS", Fault, true},
	{11, "#NP", "Segment Not Present", Fault, true},
	{12, "#SS", "Stack-Segment Fault", Fault, true},
	{13, "#GP", "General Protection", Fault, true},
	{14, "#PF", "Page Fault", Fault, true},
	{16, "#MF", "x87 FP Exception", Fault, false},
	{17, "#AC", "Alignment Check", Fault, true},
	{18, "#MC", "Machine Check", Abort, false},
	{19, "#XM", "SIMD FP Exception", Fault, false},
	{20, "#VE", "Virtualization Exception", Fault, false},
	{21, "#CP", "Control Protection", Fault, true},
}

func testExceptionTable() {
	fmt.Println("\n2. x86_64 exception table:")

	// Count exceptions with error codes
	withError := 0
	faults := 0
	for _, e := range exceptions {
		if e.HasError {
			withError++
		}
		if e.Class == Fault {
			faults++
		}
	}
	assert(withError == 8, "8 exceptions push error codes")
	assert(faults >= 14, "most exceptions are faults")

	// Verify specific vectors
	assert(exceptions[0].Vector == 0 && exceptions[0].Mnemonic == "#DE", "vector 0 = #DE")
	// Find page fault
	var pf *ExceptionInfo
	for i := range exceptions {
		if exceptions[i].Vector == 14 {
			pf = &exceptions[i]
			break
		}
	}
	assert(pf != nil, "page fault exists")
	assert(pf.HasError, "page fault has error code")
	assert(pf.Class == Fault, "page fault is a fault")

	fmt.Printf("   %-4s %-4s %-28s %-10s %s\n", "Vec", "Mnem", "Name", "Class", "Error?")
	fmt.Printf("   %-4s %-4s %-28s %-10s %s\n", "---", "----", "----", "-----", "------")
	for _, e := range exceptions[:8] {
		errStr := "no"
		if e.HasError {
			errStr = "yes"
		}
		fmt.Printf("   %-4d %-4s %-28s %-10s %s\n",
			e.Vector, e.Mnemonic, e.Name, e.Class, errStr)
	}
	fmt.Printf("   ... (%d total exceptions defined)\n", len(exceptions))
}

// ── PIC 8259A Simulation ─────────────────────────────────────────────
// The 8259A PIC manages 8 IRQ lines. Two PICs are cascaded:
//   Master: IRQ 0-7  (vectors 32-39 typically)
//   Slave:  IRQ 8-15 (vectors 40-47 typically)
// The slave connects to master's IRQ 2 (cascade).

type PIC8259A struct {
	name       string
	baseVector uint8  // first interrupt vector
	imr        uint8  // Interrupt Mask Register (1=masked)
	isr        uint8  // In-Service Register (1=being serviced)
	irr        uint8  // Interrupt Request Register (1=pending)
}

func NewPIC(name string, baseVector uint8) *PIC8259A {
	return &PIC8259A{
		name:       name,
		baseVector: baseVector,
		imr:        0xFF, // all masked by default
	}
}

func (p *PIC8259A) Mask(irq uint8) {
	p.imr |= 1 << irq
}

func (p *PIC8259A) Unmask(irq uint8) {
	p.imr &^= 1 << irq
}

func (p *PIC8259A) IsMasked(irq uint8) bool {
	return p.imr&(1<<irq) != 0
}

// RaiseIRQ signals an interrupt request on the given line.
func (p *PIC8259A) RaiseIRQ(irq uint8) {
	p.irr |= 1 << irq
}

// AcknowledgeIRQ returns the vector of the highest-priority pending,
// unmasked interrupt, or (0, false) if none available.
func (p *PIC8259A) AcknowledgeIRQ() (uint8, bool) {
	pending := p.irr & ^p.imr // pending AND not masked
	if pending == 0 {
		return 0, false
	}
	// Find lowest-numbered (highest-priority) bit
	for i := uint8(0); i < 8; i++ {
		if pending&(1<<i) != 0 {
			p.irr &^= 1 << i // clear from IRR
			p.isr |= 1 << i  // mark in-service
			return p.baseVector + i, true
		}
	}
	return 0, false
}

// EOI sends End-Of-Interrupt for the given IRQ line.
func (p *PIC8259A) EOI(irq uint8) {
	p.isr &^= 1 << irq
}

func testPIC8259A() {
	fmt.Println("\n3. PIC 8259A simulation (cascaded master+slave):")

	master := NewPIC("master", 32) // IRQ 0-7 -> vectors 32-39
	slave := NewPIC("slave", 40)   // IRQ 8-15 -> vectors 40-47

	// Initially all masked
	assert(master.IsMasked(0), "timer masked initially")
	assert(slave.IsMasked(0), "RTC masked initially")

	// Unmask timer (IRQ 0) and keyboard (IRQ 1)
	master.Unmask(0) // timer
	master.Unmask(1) // keyboard
	master.Unmask(2) // cascade (slave connection)
	slave.Unmask(0)  // RTC (IRQ 8)

	assert(!master.IsMasked(0), "timer unmasked")
	assert(!master.IsMasked(1), "keyboard unmasked")
	assert(master.IsMasked(3), "COM1 still masked")

	// Raise timer interrupt
	master.RaiseIRQ(0)
	vec, ok := master.AcknowledgeIRQ()
	assert(ok && vec == 32, "timer -> vector 32")

	// Timer is now in-service
	assert(master.isr&1 != 0, "timer in-service")

	// Send EOI
	master.EOI(0)
	assert(master.isr&1 == 0, "timer EOI clears ISR")

	// Raise keyboard while timer is masked
	master.Mask(0)
	master.RaiseIRQ(0) // timer (masked — should not fire)
	master.RaiseIRQ(1) // keyboard (unmasked)
	vec, ok = master.AcknowledgeIRQ()
	assert(ok && vec == 33, "keyboard -> vector 33 (timer masked)")
	master.EOI(1)

	// Slave interrupt (RTC = IRQ 8)
	slave.RaiseIRQ(0)
	vec, ok = slave.AcknowledgeIRQ()
	assert(ok && vec == 40, "RTC -> vector 40")
	slave.EOI(0)

	// No pending interrupts
	_, ok = master.AcknowledgeIRQ()
	assert(!ok, "no pending interrupts")

	fmt.Printf("   Master PIC: IRQ 0-7 -> vectors %d-%d\n", master.baseVector, master.baseVector+7)
	fmt.Printf("   Slave PIC:  IRQ 8-15 -> vectors %d-%d\n", slave.baseVector, slave.baseVector+7)
	fmt.Println("   Timer (IRQ 0) -> vector 32")
	fmt.Println("   Keyboard (IRQ 1) -> vector 33")
	fmt.Println("   RTC (IRQ 8/slave 0) -> vector 40")
	fmt.Println("   Masked IRQs suppressed, priority = lowest IRQ number")
}

// ── Page Fault Error Code ────────────────────────────────────────────
// When #PF (vector 14) fires, the CPU pushes an error code:
//   Bit 0 (P):    0=not-present, 1=protection violation
//   Bit 1 (W/R):  0=read, 1=write
//   Bit 2 (U/S):  0=supervisor, 1=user
//   Bit 3 (RSVD): 1=reserved bit set in page table
//   Bit 4 (I/D):  1=instruction fetch (NX violation)

const (
	PF_PRESENT    uint32 = 1 << 0
	PF_WRITE      uint32 = 1 << 1
	PF_USER       uint32 = 1 << 2
	PF_RESERVED   uint32 = 1 << 3
	PF_INSN_FETCH uint32 = 1 << 4
)

type PageFaultInfo struct {
	ErrorCode uint32
	CR2       uint64 // faulting virtual address
}

func (pf PageFaultInfo) IsPresent() bool    { return pf.ErrorCode&PF_PRESENT != 0 }
func (pf PageFaultInfo) IsWrite() bool      { return pf.ErrorCode&PF_WRITE != 0 }
func (pf PageFaultInfo) IsUser() bool       { return pf.ErrorCode&PF_USER != 0 }
func (pf PageFaultInfo) IsReserved() bool   { return pf.ErrorCode&PF_RESERVED != 0 }
func (pf PageFaultInfo) IsInsnFetch() bool  { return pf.ErrorCode&PF_INSN_FETCH != 0 }

func (pf PageFaultInfo) Describe() string {
	cause := "not-present"
	if pf.IsPresent() {
		cause = "protection violation"
	}
	access := "read"
	if pf.IsWrite() {
		access = "write"
	}
	if pf.IsInsnFetch() {
		access = "instruction fetch"
	}
	mode := "supervisor"
	if pf.IsUser() {
		mode = "user"
	}
	return fmt.Sprintf("%s %s from %s mode at 0x%X", cause, access, mode, pf.CR2)
}

func testPageFaultErrorCode() {
	fmt.Println("\n4. Page fault error code decoding:")

	// Case 1: user reads unmapped page (demand paging)
	demand := PageFaultInfo{ErrorCode: PF_USER, CR2: 0x7FFE_0000}
	assert(!demand.IsPresent(), "demand: page not present")
	assert(!demand.IsWrite(), "demand: was a read")
	assert(demand.IsUser(), "demand: user mode")
	fmt.Printf("   Error 0x%02X: %s\n", demand.ErrorCode, demand.Describe())

	// Case 2: user writes to read-only page (COW)
	cow := PageFaultInfo{ErrorCode: PF_PRESENT | PF_WRITE | PF_USER, CR2: 0x0040_1000}
	assert(cow.IsPresent(), "cow: page present")
	assert(cow.IsWrite(), "cow: was a write")
	fmt.Printf("   Error 0x%02X: %s\n", cow.ErrorCode, cow.Describe())

	// Case 3: instruction fetch on NX page (security)
	nx := PageFaultInfo{ErrorCode: PF_PRESENT | PF_INSN_FETCH | PF_USER, CR2: 0x7FFF_F000}
	assert(nx.IsInsnFetch(), "nx: instruction fetch")
	assert(nx.IsPresent(), "nx: page present but NX")
	fmt.Printf("   Error 0x%02X: %s\n", nx.ErrorCode, nx.Describe())

	// Case 4: kernel reads unmapped page (kernel bug)
	kbug := PageFaultInfo{ErrorCode: 0, CR2: 0xDEAD_0000}
	assert(!kbug.IsPresent(), "kbug: not present")
	assert(!kbug.IsUser(), "kbug: supervisor mode")
	fmt.Printf("   Error 0x%02X: %s\n", kbug.ErrorCode, kbug.Describe())
}

// ── Interrupt Dispatch ───────────────────────────────────────────────
// A simple IDT that maps vectors to handler functions.

type HandlerFunc func(vector uint8, errorCode uint32) string

type IDT struct {
	handlers map[uint8]struct {
		name    string
		handler HandlerFunc
		ist     uint8
	}
}

func NewIDT() *IDT {
	return &IDT{handlers: make(map[uint8]struct {
		name    string
		handler HandlerFunc
		ist     uint8
	})}
}

func (idt *IDT) Register(vector uint8, name string, ist uint8, h HandlerFunc) {
	idt.handlers[vector] = struct {
		name    string
		handler HandlerFunc
		ist     uint8
	}{name, h, ist}
}

func (idt *IDT) Dispatch(vector uint8, errorCode uint32) (string, bool) {
	entry, ok := idt.handlers[vector]
	if !ok {
		return "", false
	}
	return entry.handler(vector, errorCode), true
}

func testInterruptDispatch() {
	fmt.Println("\n5. Interrupt dispatch table:")

	idt := NewIDT()

	idt.Register(0, "#DE", 0, func(v uint8, _ uint32) string {
		return "handled divide error"
	})
	idt.Register(8, "#DF", 1, func(v uint8, ec uint32) string {
		return fmt.Sprintf("DOUBLE FAULT (error=0x%X) — fatal", ec)
	})
	idt.Register(14, "#PF", 0, func(v uint8, ec uint32) string {
		pf := PageFaultInfo{ErrorCode: ec}
		return fmt.Sprintf("page fault: %s", pf.Describe())
	})
	idt.Register(32, "Timer", 0, func(v uint8, _ uint32) string {
		return "timer tick"
	})

	// Dispatch known vectors
	r, ok := idt.Dispatch(0, 0)
	assert(ok && r == "handled divide error", "dispatch #DE")

	r, ok = idt.Dispatch(14, PF_WRITE|PF_USER)
	assert(ok, "dispatch #PF")

	r, ok = idt.Dispatch(32, 0)
	assert(ok && r == "timer tick", "dispatch timer")

	// Unknown vector
	_, ok = idt.Dispatch(255, 0)
	assert(!ok, "unknown vector not handled")

	// Double fault uses IST 1
	assert(idt.handlers[8].ist == 1, "double fault IST=1")

	fmt.Println("   Vector 0  (#DE) -> handled")
	fmt.Println("   Vector 14 (#PF) -> handled with error code")
	fmt.Println("   Vector 32 (Timer) -> handled")
	fmt.Println("   Vector 255 -> not registered")
}

// ── Interrupt Priority ───────────────────────────────────────────────
// Lower vector = higher priority for exceptions.
// For PIC, lower IRQ = higher priority.
// NMI (vector 2) is non-maskable — always delivered.

func testInterruptPriority() {
	fmt.Println("\n6. Interrupt priority and nesting:")

	// Priority order: NMI > exceptions > hardware IRQs > software INT
	type IntClass struct {
		name     string
		vectors  string
		priority int // lower = higher priority
	}
	classes := []IntClass{
		{"Machine Check", "18", 0},
		{"NMI", "2", 1},
		{"CPU Exceptions", "0-31", 2},
		{"Hardware IRQs", "32-47 (PIC)", 3},
		{"Software INT", "any", 4},
	}

	for i := 0; i < len(classes)-1; i++ {
		assert(classes[i].priority < classes[i+1].priority,
			fmt.Sprintf("%s > %s", classes[i].name, classes[i+1].name))
	}

	fmt.Printf("   %-20s %-15s %s\n", "Class", "Vectors", "Priority")
	fmt.Printf("   %-20s %-15s %s\n", "----", "-------", "--------")
	for _, c := range classes {
		fmt.Printf("   %-20s %-15s %d (lower=higher)\n", c.name, c.vectors, c.priority)
	}

	// Interrupt gate vs trap gate behavior
	fmt.Println("\n   Interrupt gate: clears IF -> interrupts disabled during handler")
	fmt.Println("   Trap gate:      IF unchanged -> interrupts stay enabled")
	fmt.Println("   NMI:            non-maskable -> IF has no effect")
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
