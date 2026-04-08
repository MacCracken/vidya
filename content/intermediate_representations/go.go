// Vidya — Intermediate Representations in Go
//
// Demonstrates core IR concepts using Go's interfaces and structs:
//   1. Three-address code (TAC) with virtual registers
//   2. Basic blocks and control flow graphs (CFGs)
//   3. SSA construction with phi nodes
//   4. Simple constant folding on SSA form
//
// Go's interfaces make IR instruction types extensible — each
// instruction kind implements the Instruction interface. Slices of
// instructions form basic blocks. The CFG is a slice of blocks with
// successor/predecessor edges.

package main

import (
	"fmt"
	"strings"
)

// ── Virtual Registers ────────────────────────────────────────────────
// In SSA, each assignment creates a new register (v0, v1, v2, ...).
// A register is never reassigned — this makes def-use chains trivial.

type Reg uint32

func (r Reg) String() string { return fmt.Sprintf("v%d", r) }

// ── Binary Operators ─────────────────────────────────────────────────

type BinOp int

const (
	OpAdd BinOp = iota
	OpSub
	OpMul
)

func (op BinOp) String() string {
	switch op {
	case OpAdd:
		return "add"
	case OpSub:
		return "sub"
	case OpMul:
		return "mul"
	default:
		return "?"
	}
}

// ── IR Instructions ──────────────────────────────────────────────────
// Each instruction type implements the Instruction interface.
// The interface has a Dest() method returning the register defined
// (or -1 for terminators), and a String() for display.

type Instruction interface {
	Dest() Reg // register defined by this instruction (-1 if none)
	String() string
}

// LoadConst: dst = immediate
type LoadConst struct {
	Dst   Reg
	Value int64
}

func (i LoadConst) Dest() Reg    { return i.Dst }
func (i LoadConst) String() string { return fmt.Sprintf("  %s = const %d", i.Dst, i.Value) }

// BinInst: dst = lhs op rhs
type BinInst struct {
	Dst Reg
	Op  BinOp
	Lhs Reg
	Rhs Reg
}

func (i BinInst) Dest() Reg { return i.Dst }
func (i BinInst) String() string {
	return fmt.Sprintf("  %s = %s %s, %s", i.Dst, i.Op, i.Lhs, i.Rhs)
}

// Phi: dst = phi(block0:reg0, block1:reg1, ...)
// Phi nodes appear at the start of a block where control flow merges.
// They select which value to use based on which predecessor executed.
type Phi struct {
	Dst    Reg
	Inputs []PhiInput
}

type PhiInput struct {
	Block int
	Value Reg
}

func (i Phi) Dest() Reg { return i.Dst }
func (i Phi) String() string {
	parts := make([]string, len(i.Inputs))
	for j, inp := range i.Inputs {
		parts[j] = fmt.Sprintf("bb%d:%s", inp.Block, inp.Value)
	}
	return fmt.Sprintf("  %s = phi(%s)", i.Dst, strings.Join(parts, ", "))
}

// Neg: dst = -src
type Neg struct {
	Dst Reg
	Src Reg
}

func (i Neg) Dest() Reg    { return i.Dst }
func (i Neg) String() string { return fmt.Sprintf("  %s = neg %s", i.Dst, i.Src) }

// Return: return value
type Return struct {
	Value Reg
}

func (i Return) Dest() Reg    { return Reg(0xFFFFFFFF) } // no def
func (i Return) String() string { return fmt.Sprintf("  ret %s", i.Value) }

// Jump: unconditional branch
type Jump struct {
	Target int
}

func (i Jump) Dest() Reg    { return Reg(0xFFFFFFFF) }
func (i Jump) String() string { return fmt.Sprintf("  jmp bb%d", i.Target) }

// Branch: conditional branch
type Branch struct {
	Cond      Reg
	ThenBlock int
	ElseBlock int
}

func (i Branch) Dest() Reg { return Reg(0xFFFFFFFF) }
func (i Branch) String() string {
	return fmt.Sprintf("  br %s, bb%d, bb%d", i.Cond, i.ThenBlock, i.ElseBlock)
}

// ── Basic Block ──────────────────────────────────────────────────────
// A maximal sequence of instructions with one entry and one exit.
// The last instruction is always a terminator (ret, jmp, br).

type BasicBlock struct {
	Label        string
	Instructions []Instruction
	Preds        []int // predecessor block indices
	Succs        []int // successor block indices
}

func (bb *BasicBlock) String() string {
	var sb strings.Builder
	sb.WriteString(bb.Label + ":\n")
	for _, inst := range bb.Instructions {
		sb.WriteString(inst.String() + "\n")
	}
	return sb.String()
}

// ── Function (CFG) ───────────────────────────────────────────────────
// A function is a slice of basic blocks forming a control flow graph.

type Function struct {
	Name   string
	Blocks []BasicBlock
}

func (f *Function) String() string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("fn %s:\n", f.Name))
	for _, bb := range f.Blocks {
		sb.WriteString(bb.String())
	}
	return sb.String()
}

// ── Register Allocator (simple counter) ──────────────────────────────

type RegAllocator struct {
	next uint32
}

func (ra *RegAllocator) Alloc() Reg {
	r := Reg(ra.next)
	ra.next++
	return r
}

// ── SSA Interpreter ──────────────────────────────────────────────────
// Walk the CFG, execute instructions, resolve phi nodes.
// This verifies SSA form is semantically correct.

type SSAInterpreter struct {
	Regs     map[Reg]int64
	PrevBlock int
}

func NewSSAInterpreter() *SSAInterpreter {
	return &SSAInterpreter{
		Regs:     make(map[Reg]int64),
		PrevBlock: -1,
	}
}

func (interp *SSAInterpreter) Run(f *Function) int64 {
	blockIdx := 0
	for {
		bb := &f.Blocks[blockIdx]
		for _, inst := range bb.Instructions {
			switch v := inst.(type) {
			case LoadConst:
				interp.Regs[v.Dst] = v.Value

			case BinInst:
				lhs := interp.Regs[v.Lhs]
				rhs := interp.Regs[v.Rhs]
				switch v.Op {
				case OpAdd:
					interp.Regs[v.Dst] = lhs + rhs
				case OpSub:
					interp.Regs[v.Dst] = lhs - rhs
				case OpMul:
					interp.Regs[v.Dst] = lhs * rhs
				}

			case Neg:
				interp.Regs[v.Dst] = -interp.Regs[v.Src]

			case Phi:
				// Select input based on which predecessor we came from
				for _, inp := range v.Inputs {
					if inp.Block == interp.PrevBlock {
						interp.Regs[v.Dst] = interp.Regs[inp.Value]
						break
					}
				}

			case Return:
				return interp.Regs[v.Value]

			case Jump:
				interp.PrevBlock = blockIdx
				blockIdx = v.Target
				goto nextBlock

			case Branch:
				interp.PrevBlock = blockIdx
				if interp.Regs[v.Cond] > 0 {
					blockIdx = v.ThenBlock
				} else {
					blockIdx = v.ElseBlock
				}
				goto nextBlock
			}
		}
		break
	nextBlock:
	}
	return 0
}

// ── Constant Folding Pass ────────────────────────────────────────────
// If both operands of a BinInst are constants (LoadConst), replace
// the BinInst with a LoadConst of the computed result.
// This is the simplest optimization pass and works on SSA form.

func constantFold(f *Function) int {
	// Build a map of register -> constant value
	constants := make(map[Reg]int64)
	folded := 0

	// First pass: find all constants
	for _, bb := range f.Blocks {
		for _, inst := range bb.Instructions {
			if lc, ok := inst.(LoadConst); ok {
				constants[lc.Dst] = lc.Value
			}
		}
	}

	// Second pass: fold binary operations with constant operands
	for bi := range f.Blocks {
		for ii := range f.Blocks[bi].Instructions {
			inst := f.Blocks[bi].Instructions[ii]
			bin, ok := inst.(BinInst)
			if !ok {
				continue
			}
			lhsVal, lhsConst := constants[bin.Lhs]
			rhsVal, rhsConst := constants[bin.Rhs]
			if !lhsConst || !rhsConst {
				continue
			}

			var result int64
			switch bin.Op {
			case OpAdd:
				result = lhsVal + rhsVal
			case OpSub:
				result = lhsVal - rhsVal
			case OpMul:
				result = lhsVal * rhsVal
			}

			// Replace with LoadConst
			f.Blocks[bi].Instructions[ii] = LoadConst{Dst: bin.Dst, Value: result}
			constants[bin.Dst] = result
			folded++
		}
	}

	return folded
}

func main() {
	fmt.Println("Intermediate Representations — Go demonstration:\n")

	// ── 1. Three-address code ────────────────────────────────────────
	// Express: result = (a + b) * (c - d)
	// where a=10, b=20, c=50, d=15
	fmt.Println("1. Three-address code (TAC):")

	ra := &RegAllocator{}
	a := ra.Alloc()  // v0
	b := ra.Alloc()  // v1
	c := ra.Alloc()  // v2
	d := ra.Alloc()  // v3
	t1 := ra.Alloc() // v4 = a + b
	t2 := ra.Alloc() // v5 = c - d
	t3 := ra.Alloc() // v6 = t1 * t2

	instructions := []Instruction{
		LoadConst{a, 10},
		LoadConst{b, 20},
		LoadConst{c, 50},
		LoadConst{d, 15},
		BinInst{t1, OpAdd, a, b},
		BinInst{t2, OpSub, c, d},
		BinInst{t3, OpMul, t1, t2},
		Return{t3},
	}

	fmt.Println("  TAC for (10 + 20) * (50 - 15):")
	for _, inst := range instructions {
		fmt.Println(inst.String())
	}

	// Verify with interpreter
	f := &Function{
		Name: "tac_test",
		Blocks: []BasicBlock{
			{Label: "bb0", Instructions: instructions},
		},
	}
	interp := NewSSAInterpreter()
	result := interp.Run(f)
	assert(result == 1050, fmt.Sprintf("expected 1050, got %d", result))
	fmt.Printf("  Result: %d (expected: 1050)\n", result)

	// ── 2. Basic blocks and CFG ──────────────────────────────────────
	// if (x > 0) { result = x * 2 } else { result = -x }
	fmt.Println("\n2. Basic blocks and CFG:")

	ra2 := &RegAllocator{}
	x := ra2.Alloc()       // v0 = input
	res1 := ra2.Alloc()    // v1 = x * 2 (then branch)
	two := ra2.Alloc()     // v2 = 2
	res2 := ra2.Alloc()    // v3 = -x (else branch)
	merged := ra2.Alloc()  // v4 = phi(v1, v3)

	cfgFunc := &Function{
		Name: "abs_double",
		Blocks: []BasicBlock{
			{
				Label: "entry",
				Instructions: []Instruction{
					LoadConst{x, 5},
					Branch{x, 1, 2}, // if x > 0 goto bb1 else bb2
				},
				Succs: []int{1, 2},
			},
			{
				Label: "then",
				Instructions: []Instruction{
					LoadConst{two, 2},
					BinInst{res1, OpMul, x, two},
					Jump{3},
				},
				Preds: []int{0},
				Succs: []int{3},
			},
			{
				Label: "else",
				Instructions: []Instruction{
					Neg{res2, x},
					Jump{3},
				},
				Preds: []int{0},
				Succs: []int{3},
			},
			{
				Label: "merge",
				Instructions: []Instruction{
					Phi{merged, []PhiInput{
						{Block: 1, Value: res1},
						{Block: 2, Value: res2},
					}},
					Return{merged},
				},
				Preds: []int{1, 2},
			},
		},
	}

	fmt.Print(cfgFunc.String())

	// Verify: x=5 > 0, so then branch: 5*2 = 10
	interp2 := NewSSAInterpreter()
	result2 := interp2.Run(cfgFunc)
	assert(result2 == 10, fmt.Sprintf("expected 10, got %d", result2))
	fmt.Printf("  Result with x=5: %d (expected: 10, took 'then' branch)\n", result2)

	// Verify: x=-3 <= 0, so else branch: -(-3) = 3
	cfgFunc.Blocks[0].Instructions[0] = LoadConst{x, -3}
	interp3 := NewSSAInterpreter()
	result3 := interp3.Run(cfgFunc)
	assert(result3 == 3, fmt.Sprintf("expected 3, got %d", result3))
	fmt.Printf("  Result with x=-3: %d (expected: 3, took 'else' branch)\n", result3)

	// ── 3. SSA properties ────────────────────────────────────────────
	fmt.Println("\n3. SSA properties:")
	fmt.Println("  - Every variable assigned exactly once")
	fmt.Println("  - Phi nodes at control flow merge points")
	fmt.Println("  - Def-use chains are trivial (single definition)")
	fmt.Println("  - No variable aliasing — each name is unique")

	// Verify SSA property: count definitions per register
	defs := make(map[Reg]int)
	for _, bb := range cfgFunc.Blocks {
		for _, inst := range bb.Instructions {
			d := inst.Dest()
			if d != Reg(0xFFFFFFFF) {
				defs[d]++
			}
		}
	}
	for reg, count := range defs {
		assert(count == 1, fmt.Sprintf("SSA violation: %s defined %d times", reg, count))
	}
	fmt.Printf("  Verified: %d registers, each defined exactly once.\n", len(defs))

	// ── 4. Phi node semantics ────────────────────────────────────────
	fmt.Println("\n4. Phi node semantics:")
	fmt.Println("  Phi nodes don't execute as instructions.")
	fmt.Println("  They're resolved based on which predecessor block ran.")
	fmt.Println("  During SSA destruction (before codegen), phi nodes become")
	fmt.Println("  copies inserted on each incoming edge:")
	fmt.Println()
	fmt.Println("  Before (SSA):")
	fmt.Println("    merge: v4 = phi(bb1:v1, bb2:v3)")
	fmt.Println()
	fmt.Println("  After (destructed):")
	fmt.Println("    then:  v4 = v1; jmp merge")
	fmt.Println("    else:  v4 = v3; jmp merge")
	fmt.Println("    merge: (v4 already has the right value)")

	// ── 5. Constant folding on SSA ───────────────────────────────────
	fmt.Println("\n5. Constant folding on SSA form:")

	ra5 := &RegAllocator{}
	ca := ra5.Alloc() // v0 = 10
	cb := ra5.Alloc() // v1 = 20
	cc := ra5.Alloc() // v2 = 3
	ct1 := ra5.Alloc() // v3 = v0 + v1 → 30
	ct2 := ra5.Alloc() // v4 = v3 * v2 → 90

	foldFunc := &Function{
		Name: "fold_test",
		Blocks: []BasicBlock{
			{
				Label: "bb0",
				Instructions: []Instruction{
					LoadConst{ca, 10},
					LoadConst{cb, 20},
					LoadConst{cc, 3},
					BinInst{ct1, OpAdd, ca, cb},
					BinInst{ct2, OpMul, ct1, cc},
					Return{ct2},
				},
			},
		},
	}

	fmt.Println("  Before folding:")
	for _, inst := range foldFunc.Blocks[0].Instructions {
		fmt.Println(inst.String())
	}

	// Run constant folding
	nFolded := constantFold(foldFunc)
	assert(nFolded == 2, fmt.Sprintf("expected 2 folds, got %d", nFolded))

	fmt.Println("  After folding:")
	for _, inst := range foldFunc.Blocks[0].Instructions {
		fmt.Println(inst.String())
	}

	// Verify the folded instructions are now LoadConst
	inst3 := foldFunc.Blocks[0].Instructions[3]
	lc3, ok := inst3.(LoadConst)
	assert(ok, "instruction 3 must be LoadConst after folding")
	assert(lc3.Value == 30, fmt.Sprintf("v3 must be 30, got %d", lc3.Value))

	inst4 := foldFunc.Blocks[0].Instructions[4]
	lc4, ok := inst4.(LoadConst)
	assert(ok, "instruction 4 must be LoadConst after folding")
	assert(lc4.Value == 90, fmt.Sprintf("v4 must be 90, got %d", lc4.Value))

	// Verify interpreter still gets the right answer
	interp5 := NewSSAInterpreter()
	result5 := interp5.Run(foldFunc)
	assert(result5 == 90, fmt.Sprintf("expected 90, got %d", result5))
	fmt.Printf("  Folded %d instructions. Result: %d (expected: 90)\n", nFolded, result5)

	fmt.Println("\nAll intermediate representation examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
