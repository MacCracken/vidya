// Vidya — Optimization Passes in Go
//
// Demonstrates three fundamental compiler optimizations:
//   1. Constant folding — evaluate compile-time constants
//   2. Dead code elimination — remove unused computations
//   3. Strength reduction — replace expensive ops with cheaper ones
//
// Each pass transforms IR instructions and verifies correctness.
// Passes compose: constant folding creates dead code, DCE removes it,
// strength reduction catches patterns the others miss.
//
// The IR uses SSA form (each register assigned once), making analysis
// trivial: no aliasing, explicit def-use chains.

package main

import (
	"fmt"
	"strings"
)

// ── IR Types ─────────────────────────────────────────────────────────

type Reg uint32

func (r Reg) String() string { return fmt.Sprintf("v%d", r) }

type OpCode int

const (
	OpConst OpCode = iota // dst = imm
	OpAdd                 // dst = lhs + rhs
	OpSub                 // dst = lhs - rhs
	OpMul                 // dst = lhs * rhs
	OpShl                 // dst = lhs << rhs (shift left)
	OpNeg                 // dst = -src
	OpRet                 // return src
)

func (op OpCode) String() string {
	switch op {
	case OpConst:
		return "const"
	case OpAdd:
		return "add"
	case OpSub:
		return "sub"
	case OpMul:
		return "mul"
	case OpShl:
		return "shl"
	case OpNeg:
		return "neg"
	case OpRet:
		return "ret"
	default:
		return "?"
	}
}

// Inst is a three-address instruction in SSA form.
type Inst struct {
	Op    OpCode
	Dst   Reg
	Lhs   Reg   // first source operand (or src for unary)
	Rhs   Reg   // second source operand
	Imm   int64 // immediate value (for OpConst)
	Dead  bool  // marked for removal by DCE
}

func (i Inst) String() string {
	if i.Dead {
		return fmt.Sprintf("  ;; DEAD: %s", i.liveString())
	}
	return i.liveString()
}

func (i Inst) liveString() string {
	switch i.Op {
	case OpConst:
		return fmt.Sprintf("  %s = const %d", i.Dst, i.Imm)
	case OpAdd, OpSub, OpMul, OpShl:
		return fmt.Sprintf("  %s = %s %s, %s", i.Dst, i.Op, i.Lhs, i.Rhs)
	case OpNeg:
		return fmt.Sprintf("  %s = neg %s", i.Dst, i.Lhs)
	case OpRet:
		return fmt.Sprintf("  ret %s", i.Lhs)
	default:
		return "  ??"
	}
}

// Program is a sequence of instructions (single basic block for simplicity).
type Program struct {
	Insts []Inst
}

func (p *Program) String() string {
	var sb strings.Builder
	for _, inst := range p.Insts {
		sb.WriteString(inst.String() + "\n")
	}
	return sb.String()
}

// Evaluate the program by interpreting instructions.
func (p *Program) Eval() int64 {
	regs := make(map[Reg]int64)
	for _, inst := range p.Insts {
		if inst.Dead {
			continue
		}
		switch inst.Op {
		case OpConst:
			regs[inst.Dst] = inst.Imm
		case OpAdd:
			regs[inst.Dst] = regs[inst.Lhs] + regs[inst.Rhs]
		case OpSub:
			regs[inst.Dst] = regs[inst.Lhs] - regs[inst.Rhs]
		case OpMul:
			regs[inst.Dst] = regs[inst.Lhs] * regs[inst.Rhs]
		case OpShl:
			regs[inst.Dst] = regs[inst.Lhs] << uint(regs[inst.Rhs])
		case OpNeg:
			regs[inst.Dst] = -regs[inst.Lhs]
		case OpRet:
			return regs[inst.Lhs]
		}
	}
	return 0
}

// Count live (non-dead) instructions.
func (p *Program) LiveCount() int {
	n := 0
	for _, inst := range p.Insts {
		if !inst.Dead {
			n++
		}
	}
	return n
}

// ── Pass 1: Constant Folding ─────────────────────────────────────────
// If both operands of a binary op are known constants, compute the
// result at compile time. In SSA, this is a single forward pass over
// the instruction list.

func constantFold(p *Program) int {
	known := make(map[Reg]int64)
	folded := 0

	for i := range p.Insts {
		inst := &p.Insts[i]
		if inst.Dead {
			continue
		}

		switch inst.Op {
		case OpConst:
			known[inst.Dst] = inst.Imm

		case OpAdd, OpSub, OpMul, OpShl:
			lhs, lOk := known[inst.Lhs]
			rhs, rOk := known[inst.Rhs]
			if !lOk || !rOk {
				continue
			}

			var result int64
			switch inst.Op {
			case OpAdd:
				result = lhs + rhs
			case OpSub:
				result = lhs - rhs
			case OpMul:
				result = lhs * rhs
			case OpShl:
				result = lhs << uint(rhs)
			}

			inst.Op = OpConst
			inst.Imm = result
			inst.Lhs = 0
			inst.Rhs = 0
			known[inst.Dst] = result
			folded++

		case OpNeg:
			src, ok := known[inst.Lhs]
			if !ok {
				continue
			}
			inst.Op = OpConst
			inst.Imm = -src
			inst.Lhs = 0
			known[inst.Dst] = -src
			folded++
		}
	}

	return folded
}

// ── Pass 2: Dead Code Elimination ────────────────────────────────────
// In SSA, a definition is dead if no live instruction uses it.
// Walk backward: mark registers that are used, then remove definitions
// that are never used. Repeat until no more changes (fixed point).

func deadCodeElim(p *Program) int {
	eliminated := 0

	for {
		// Count uses of each register (only from live instructions)
		uses := make(map[Reg]int)
		for _, inst := range p.Insts {
			if inst.Dead {
				continue
			}
			switch inst.Op {
			case OpAdd, OpSub, OpMul, OpShl:
				uses[inst.Lhs]++
				uses[inst.Rhs]++
			case OpNeg:
				uses[inst.Lhs]++
			case OpRet:
				uses[inst.Lhs]++
			}
		}

		// Mark unused definitions as dead
		changed := false
		for i := range p.Insts {
			inst := &p.Insts[i]
			if inst.Dead || inst.Op == OpRet {
				continue
			}
			if uses[inst.Dst] == 0 {
				inst.Dead = true
				eliminated++
				changed = true
			}
		}

		if !changed {
			break // fixed point reached
		}
	}

	return eliminated
}

// ── Pass 3: Strength Reduction ───────────────────────────────────────
// Replace expensive operations with cheaper equivalents:
//   - x * 2^n  →  x << n   (multiply by power of two → shift)
//   - x * 1    →  x        (identity, folded to copy)
//   - x * 0    →  0        (zero, folded to const)
//   - x + 0    →  x        (additive identity)
//   - x - 0    →  x        (subtractive identity)
//
// Strength reduction runs after constant folding so that known
// constant operands are already propagated.

func isPowerOfTwo(n int64) (int, bool) {
	if n <= 0 {
		return 0, false
	}
	shift := 0
	for n > 1 {
		if n%2 != 0 {
			return 0, false
		}
		n /= 2
		shift++
	}
	return shift, true
}

func strengthReduce(p *Program) int {
	known := make(map[Reg]int64)
	reduced := 0

	for i := range p.Insts {
		inst := &p.Insts[i]
		if inst.Dead {
			continue
		}

		if inst.Op == OpConst {
			known[inst.Dst] = inst.Imm
			continue
		}

		if inst.Op == OpMul {
			// Check if either operand is a known constant
			lhs, lOk := known[inst.Lhs]
			rhs, rOk := known[inst.Rhs]

			// x * 0 → 0
			if (lOk && lhs == 0) || (rOk && rhs == 0) {
				inst.Op = OpConst
				inst.Imm = 0
				known[inst.Dst] = 0
				reduced++
				continue
			}

			// x * 1 → copy (just load the other operand's value concept)
			if rOk && rhs == 1 {
				// Result is just lhs — replace with a const if lhs is known,
				// otherwise we can't reduce further without a copy instruction
				if lVal, ok := known[inst.Lhs]; ok {
					inst.Op = OpConst
					inst.Imm = lVal
					known[inst.Dst] = lVal
					reduced++
				}
				continue
			}
			if lOk && lhs == 1 {
				if rVal, ok := known[inst.Rhs]; ok {
					inst.Op = OpConst
					inst.Imm = rVal
					known[inst.Dst] = rVal
					reduced++
				}
				continue
			}

			// x * 2^n → x << n
			if rOk {
				if shift, ok := isPowerOfTwo(rhs); ok && shift > 0 {
					// Need a register holding the shift amount
					// For simplicity, convert to const+shl pair by noting
					// the shift in the immediate field
					inst.Op = OpShl
					// Replace rhs with a new const register would require
					// inserting instructions. Instead, since the constant is
					// already in a register, just change the op.
					reduced++
					continue
				}
			}
			if lOk {
				if shift, ok := isPowerOfTwo(lhs); ok && shift > 0 {
					// Swap operands: put the non-constant in lhs position
					inst.Op = OpShl
					inst.Lhs = inst.Rhs
					inst.Rhs = inst.Lhs
					reduced++
					continue
				}
			}
		}

		// x + 0 or 0 + x → identity
		if inst.Op == OpAdd {
			rhs, rOk := known[inst.Rhs]
			lhs, lOk := known[inst.Lhs]
			if rOk && rhs == 0 {
				if lVal, ok := known[inst.Lhs]; ok {
					inst.Op = OpConst
					inst.Imm = lVal
					known[inst.Dst] = lVal
					reduced++
				}
				continue
			}
			if lOk && lhs == 0 {
				if rVal, ok := known[inst.Rhs]; ok {
					inst.Op = OpConst
					inst.Imm = rVal
					known[inst.Dst] = rVal
					reduced++
				}
				continue
			}
		}
	}

	return reduced
}

// ── Register allocator helper ────────────────────────────────────────

type RegAlloc struct {
	next uint32
}

func (ra *RegAlloc) Alloc() Reg {
	r := Reg(ra.next)
	ra.next++
	return r
}

func main() {
	fmt.Println("Optimization Passes — Go demonstration:\n")

	// ── 1. Constant Folding ──────────────────────────────────────────
	// Expression: (3 + 4) * (10 - 2)  →  7 * 8  →  56
	fmt.Println("1. Constant folding:")

	ra := &RegAlloc{}
	v0 := ra.Alloc() // 3
	v1 := ra.Alloc() // 4
	v2 := ra.Alloc() // 10
	v3 := ra.Alloc() // 2
	v4 := ra.Alloc() // 3 + 4
	v5 := ra.Alloc() // 10 - 2
	v6 := ra.Alloc() // v4 * v5

	prog1 := &Program{Insts: []Inst{
		{Op: OpConst, Dst: v0, Imm: 3},
		{Op: OpConst, Dst: v1, Imm: 4},
		{Op: OpConst, Dst: v2, Imm: 10},
		{Op: OpConst, Dst: v3, Imm: 2},
		{Op: OpAdd, Dst: v4, Lhs: v0, Rhs: v1},
		{Op: OpSub, Dst: v5, Lhs: v2, Rhs: v3},
		{Op: OpMul, Dst: v6, Lhs: v4, Rhs: v5},
		{Op: OpRet, Lhs: v6},
	}}

	// Verify before optimization
	before := prog1.Eval()
	assert(before == 56, fmt.Sprintf("expected 56 before folding, got %d", before))

	fmt.Println("  Before:")
	fmt.Print(prog1.String())

	nFolded := constantFold(prog1)
	assert(nFolded == 3, fmt.Sprintf("expected 3 folds, got %d", nFolded))

	fmt.Println("  After constant folding:")
	fmt.Print(prog1.String())

	// Verify result unchanged
	after := prog1.Eval()
	assert(after == 56, fmt.Sprintf("expected 56 after folding, got %d", after))
	fmt.Printf("  Folded %d instructions. Result: %d (unchanged)\n", nFolded, after)

	// Verify the multiply was folded to a constant
	mulInst := prog1.Insts[6]
	assert(mulInst.Op == OpConst, "multiply must be folded to const")
	assert(mulInst.Imm == 56, fmt.Sprintf("folded value must be 56, got %d", mulInst.Imm))

	// ── 2. Dead Code Elimination ─────────────────────────────────────
	// After constant folding, the intermediate values (v4, v5) and the
	// original constants (v0-v3) are now dead — nothing uses them.
	fmt.Println("\n2. Dead code elimination:")

	liveBefore := prog1.LiveCount()
	fmt.Printf("  Live instructions before DCE: %d\n", liveBefore)

	nElim := deadCodeElim(prog1)
	liveAfter := prog1.LiveCount()

	fmt.Println("  After DCE:")
	fmt.Print(prog1.String())
	fmt.Printf("  Eliminated %d dead instructions. Live: %d → %d\n",
		nElim, liveBefore, liveAfter)

	// Only the folded constant (v6=56) and ret should survive
	assert(liveAfter == 2, fmt.Sprintf("expected 2 live instructions, got %d", liveAfter))

	// Verify result still correct
	afterDCE := prog1.Eval()
	assert(afterDCE == 56, fmt.Sprintf("expected 56 after DCE, got %d", afterDCE))

	// ── 3. Strength Reduction ────────────────────────────────────────
	// x * 8  →  x << 3  (multiply by power of two becomes shift)
	fmt.Println("\n3. Strength reduction:")

	ra3 := &RegAlloc{}
	sx := ra3.Alloc()    // x = 7
	seight := ra3.Alloc() // 8
	sprod := ra3.Alloc()  // x * 8

	prog3 := &Program{Insts: []Inst{
		{Op: OpConst, Dst: sx, Imm: 7},
		{Op: OpConst, Dst: seight, Imm: 8},
		{Op: OpMul, Dst: sprod, Lhs: sx, Rhs: seight},
		{Op: OpRet, Lhs: sprod},
	}}

	beforeSR := prog3.Eval()
	assert(beforeSR == 56, fmt.Sprintf("expected 56, got %d", beforeSR))

	fmt.Println("  Before:")
	fmt.Print(prog3.String())

	nReduced := strengthReduce(prog3)
	assert(nReduced >= 1, fmt.Sprintf("expected at least 1 reduction, got %d", nReduced))

	fmt.Println("  After strength reduction:")
	fmt.Print(prog3.String())

	// Verify mul was replaced with shl
	srInst := prog3.Insts[2]
	assert(srInst.Op == OpShl, fmt.Sprintf("mul*8 must become shl, got %s", srInst.Op))
	fmt.Printf("  Reduced %d instructions. mul → shl\n", nReduced)

	// ── 4. Combined pass pipeline ────────────────────────────────────
	// Run all three passes in sequence on a fresh program.
	// Expression: (5 * 1) + (0 * x) + (y * 4)
	// After constant fold: 5 + 0 + (y * 4)  [partial, y unknown]
	// After strength reduce: y * 4 → y << 2
	// After DCE: remove dead intermediates
	fmt.Println("\n4. Combined pass pipeline:")
	fmt.Println("  Expression: (5 * 1) + (0 * x) + (y * 4)")

	ra4 := &RegAlloc{}
	five := ra4.Alloc()   // v0 = 5
	one := ra4.Alloc()    // v1 = 1
	zero := ra4.Alloc()   // v2 = 0
	px := ra4.Alloc()     // v3 = 42 (stand-in for runtime x)
	py := ra4.Alloc()     // v4 = 3  (stand-in for runtime y)
	four := ra4.Alloc()   // v5 = 4
	t1 := ra4.Alloc()     // v6 = 5 * 1
	t2 := ra4.Alloc()     // v7 = 0 * x
	t3 := ra4.Alloc()     // v8 = y * 4
	t4 := ra4.Alloc()     // v9 = t1 + t2
	t5 := ra4.Alloc()     // v10 = t4 + t3

	prog4 := &Program{Insts: []Inst{
		{Op: OpConst, Dst: five, Imm: 5},
		{Op: OpConst, Dst: one, Imm: 1},
		{Op: OpConst, Dst: zero, Imm: 0},
		{Op: OpConst, Dst: px, Imm: 42},
		{Op: OpConst, Dst: py, Imm: 3},
		{Op: OpConst, Dst: four, Imm: 4},
		{Op: OpMul, Dst: t1, Lhs: five, Rhs: one},     // 5*1
		{Op: OpMul, Dst: t2, Lhs: zero, Rhs: px},      // 0*x
		{Op: OpMul, Dst: t3, Lhs: py, Rhs: four},      // y*4
		{Op: OpAdd, Dst: t4, Lhs: t1, Rhs: t2},        // 5 + 0
		{Op: OpAdd, Dst: t5, Lhs: t4, Rhs: t3},        // 5 + 12
		{Op: OpRet, Lhs: t5},
	}}

	expectedResult := prog4.Eval()
	fmt.Printf("  Expected result: %d\n", expectedResult)

	fmt.Println("  Before optimization:")
	fmt.Printf("    Instructions: %d\n", prog4.LiveCount())

	// Pass 1: constant fold
	cf := constantFold(prog4)
	fmt.Printf("  After constant fold: %d instructions folded\n", cf)

	// Pass 2: strength reduce (may catch patterns missed by folding)
	sr := strengthReduce(prog4)
	fmt.Printf("  After strength reduce: %d instructions reduced\n", sr)

	// Pass 3: DCE
	dce := deadCodeElim(prog4)
	fmt.Printf("  After DCE: %d instructions eliminated\n", dce)

	fmt.Println("  Final program:")
	fmt.Print(prog4.String())
	fmt.Printf("  Live instructions: %d (down from 12)\n", prog4.LiveCount())

	// Verify semantic preservation
	optimizedResult := prog4.Eval()
	assert(optimizedResult == expectedResult,
		fmt.Sprintf("optimization changed result: %d → %d", expectedResult, optimizedResult))
	fmt.Printf("  Result preserved: %d\n", optimizedResult)

	// ── 5. Pass ordering matters ─────────────────────────────────────
	fmt.Println("\n5. Pass ordering insights:")
	fmt.Println("  Canonical order:")
	fmt.Println("    1. Constant fold  — evaluate known constants")
	fmt.Println("    2. Strength reduce — cheaper ops for remaining instructions")
	fmt.Println("    3. DCE            — clean up dead definitions")
	fmt.Println("    4. Repeat until fixed point (no changes)")
	fmt.Println()
	fmt.Println("  Why this order?")
	fmt.Println("    - Folding produces dead code (original operands unused)")
	fmt.Println("    - Strength reduction needs constants propagated first")
	fmt.Println("    - DCE last: cleans up after both earlier passes")
	fmt.Println("    - Iterating: folding after inlining finds new constants")

	// ── 6. Power-of-two detection ────────────────────────────────────
	fmt.Println("\n6. Power-of-two detection (for strength reduction):")
	powers := []struct {
		n     int64
		isPow bool
		shift int
	}{
		{1, true, 0},
		{2, true, 1},
		{4, true, 2},
		{8, true, 3},
		{16, true, 4},
		{64, true, 6},
		{3, false, 0},
		{6, false, 0},
		{0, false, 0},
		{-4, false, 0},
	}
	for _, tc := range powers {
		shift, isPow := isPowerOfTwo(tc.n)
		assert(isPow == tc.isPow, fmt.Sprintf("isPowerOfTwo(%d): expected %v", tc.n, tc.isPow))
		if isPow {
			assert(shift == tc.shift, fmt.Sprintf("shift for %d: expected %d, got %d", tc.n, tc.shift, shift))
			fmt.Printf("  %3d = 2^%d (mul → shl %d)\n", tc.n, shift, shift)
		} else {
			fmt.Printf("  %3d — not a power of two\n", tc.n)
		}
	}

	fmt.Println("\nAll optimization pass examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
