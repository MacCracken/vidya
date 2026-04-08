// Vidya — Code Generation in Go
//
// Demonstrates a compiler backend using Go's interfaces for the AST
// and a visitor-style codegen pass. Same stack machine pattern as
// the Rust and C versions:
//   - Expression result always in rax
//   - Temporaries saved via push/pop
//   - No register allocation (optimize later)
//
// Go's interfaces make the AST extensible — new node types don't
// require modifying existing code (open recursion via interface).

package main

import (
	"fmt"
	"strings"
)

// ── AST Interfaces ───────────────────────────────────────────────────
// Each expression type implements the Expr interface.
// The codegen visitor does a type switch to select instructions.

type Expr interface {
	// Tag for display purposes; codegen uses type switch
	String() string
}

type Lit struct{ Value int64 }
type Add struct{ Left, Right Expr }
type Sub struct{ Left, Right Expr }
type Mul struct{ Left, Right Expr }
type Div struct{ Left, Right Expr }
type VarRef struct{ Name string }
type Assign struct {
	Name string
	Expr Expr
}

func (l Lit) String() string    { return fmt.Sprintf("%d", l.Value) }
func (a Add) String() string    { return fmt.Sprintf("(%s + %s)", a.Left, a.Right) }
func (s Sub) String() string    { return fmt.Sprintf("(%s - %s)", s.Left, s.Right) }
func (m Mul) String() string    { return fmt.Sprintf("(%s * %s)", m.Left, m.Right) }
func (d Div) String() string    { return fmt.Sprintf("(%s / %s)", d.Left, d.Right) }
func (v VarRef) String() string { return v.Name }
func (a Assign) String() string { return fmt.Sprintf("%s = %s", a.Name, a.Expr) }

// ── Stack-Based Code Generator ───────────────────────────────────────

type Codegen struct {
	lines      []string
	locals     map[string]int // name -> rbp offset (negative)
	nextOffset int            // next available stack slot
}

func NewCodegen() *Codegen {
	return &Codegen{
		locals:     make(map[string]int),
		nextOffset: -8, // first local at [rbp-8]
	}
}

func (cg *Codegen) emit(inst string) {
	cg.lines = append(cg.lines, "    "+inst)
}

func (cg *Codegen) emitRaw(line string) {
	cg.lines = append(cg.lines, line)
}

func (cg *Codegen) allocLocal(name string) int {
	if offset, exists := cg.locals[name]; exists {
		return offset
	}
	offset := cg.nextOffset
	cg.locals[name] = offset
	cg.nextOffset -= 8
	return offset
}

// GenExpr generates code for an expression. Result ends up in rax.
// This is the visitor pattern via type switch — Go's idiomatic approach
// to polymorphic dispatch on a closed set of types.
func (cg *Codegen) GenExpr(expr Expr) {
	switch e := expr.(type) {
	case Lit:
		cg.emit(fmt.Sprintf("mov rax, %d", e.Value))

	case VarRef:
		offset := cg.locals[e.Name]
		cg.emit(fmt.Sprintf("mov rax, [rbp%d]", offset))

	case Add:
		cg.GenExpr(e.Left)    // rax = left
		cg.emit("push rax")   // save left on stack
		cg.GenExpr(e.Right)   // rax = right
		cg.emit("pop rcx")    // rcx = left
		cg.emit("add rax, rcx")

	case Sub:
		cg.GenExpr(e.Left)
		cg.emit("push rax")
		cg.GenExpr(e.Right)
		cg.emit("pop rcx")         // rcx = left, rax = right
		cg.emit("sub rcx, rax")    // rcx = left - right
		cg.emit("mov rax, rcx")

	case Mul:
		cg.GenExpr(e.Left)
		cg.emit("push rax")
		cg.GenExpr(e.Right)
		cg.emit("pop rcx")
		cg.emit("imul rax, rcx") // two-operand form, no rdx clobber

	case Div:
		cg.GenExpr(e.Left)
		cg.emit("push rax")
		cg.GenExpr(e.Right)
		cg.emit("mov rcx, rax") // divisor in rcx
		cg.emit("pop rax")     // dividend in rax
		// CRITICAL: cqo sign-extends rax into rdx:rax
		// Using xor rdx,rdx before idiv gives wrong results
		// for negative dividends (-10/3 = 82, not -3)
		cg.emit("cqo")
		cg.emit("idiv rcx")

	case Assign:
		offset := cg.allocLocal(e.Name)
		cg.GenExpr(e.Expr)
		cg.emit(fmt.Sprintf("mov [rbp%d], rax", offset))

	default:
		panic(fmt.Sprintf("unknown expression type: %T", expr))
	}
}

// GenFunction generates a complete function with prologue/epilogue.
func (cg *Codegen) GenFunction(name string, stmts []Expr) string {
	cg.emitRaw(name + ":")
	cg.emit("push rbp")
	cg.emit("mov rbp, rsp")

	// Record placeholder position for frame size
	placeholderIdx := len(cg.lines)
	cg.emit("sub rsp, PLACEHOLDER")

	// Generate body
	for _, stmt := range stmts {
		cg.GenExpr(stmt)
	}

	// Patch frame size (round up to 16-byte alignment)
	numLocals := len(cg.locals)
	frameSize := ((numLocals*8 + 15) / 16) * 16
	if frameSize == 0 {
		frameSize = 16
	}
	cg.lines[placeholderIdx] = fmt.Sprintf("    sub rsp, %d", frameSize)

	// Epilogue — 'leave' is 1 byte vs 4 for mov rsp,rbp; pop rbp
	cg.emit("leave")
	cg.emit("ret")

	return strings.Join(cg.lines, "\n")
}

// Output returns the generated assembly as a single string.
func (cg *Codegen) Output() string {
	return strings.Join(cg.lines, "\n")
}

// ── Interpreter for Verification ─────────────────────────────────────

func eval(expr Expr) int64 {
	switch e := expr.(type) {
	case Lit:
		return e.Value
	case Add:
		return eval(e.Left) + eval(e.Right)
	case Sub:
		return eval(e.Left) - eval(e.Right)
	case Mul:
		return eval(e.Left) * eval(e.Right)
	case Div:
		return eval(e.Left) / eval(e.Right)
	default:
		panic(fmt.Sprintf("cannot eval: %T", expr))
	}
}

// ── Stack Frame Layout ───────────────────────────────────────────────

type FrameLayout struct {
	ParamOffsets map[string]int
	LocalOffsets map[string]int
	FrameSize    int
}

func computeFrameLayout(numParams, numLocals int) FrameLayout {
	layout := FrameLayout{
		ParamOffsets: make(map[string]int),
		LocalOffsets: make(map[string]int),
	}

	// Register params stored to stack: [rbp-8], [rbp-16], ...
	regParams := numParams
	if regParams > 6 {
		regParams = 6
	}
	for i := 0; i < regParams; i++ {
		layout.ParamOffsets[fmt.Sprintf("param_%d", i)] = -(i + 1) * 8
	}

	// Stack params (7+): [rbp+16], [rbp+24], ...
	for i := 6; i < numParams; i++ {
		layout.ParamOffsets[fmt.Sprintf("param_%d", i)] = 16 + (i-6)*8
	}

	// Locals after register params
	for i := 0; i < numLocals; i++ {
		layout.LocalOffsets[fmt.Sprintf("local_%d", i)] = -(regParams+i+1) * 8
	}

	// Frame size (16-byte aligned)
	totalSlots := regParams + numLocals
	layout.FrameSize = ((totalSlots*8 + 15) / 16) * 16
	return layout
}

// ── Calling Convention Constants ─────────────────────────────────────

var sysvArgRegs = [6]string{"rdi", "rsi", "rdx", "rcx", "r8", "r9"}
var syscallArgRegs = [6]string{"rdi", "rsi", "rdx", "r10", "r8", "r9"}

func main() {
	// ── Test expression codegen ────────────────────────────────────
	tests := []struct {
		label string
		expr  Expr
	}{
		{"42", Lit{42}},
		{"10 + 32", Add{Lit{10}, Lit{32}}},
		{"(2+3)*4", Mul{Add{Lit{2}, Lit{3}}, Lit{4}}},
		{"10-3-2", Sub{Sub{Lit{10}, Lit{3}}, Lit{2}}},
		{"100/10", Div{Lit{100}, Lit{10}}},
	}

	fmt.Println("Code Generation — stack-based x86_64 emission:")
	fmt.Printf("%-20s %8s\n", "Expression", "Expected")
	fmt.Println(strings.Repeat("-", 35))

	for _, tc := range tests {
		expected := eval(tc.expr)
		cg := NewCodegen()
		cg.GenExpr(tc.expr)
		output := cg.Output()

		fmt.Printf("%-20s %8d\n", tc.label, expected)
		assert(len(output) > 0, "codegen produced output for "+tc.label)
	}

	// ── Verify instruction patterns ────────────────────────────────
	{
		cg := NewCodegen()
		cg.GenExpr(Add{Lit{10}, Lit{32}})
		output := cg.Output()
		assert(strings.Contains(output, "push rax"), "stack codegen must push")
		assert(strings.Contains(output, "pop rcx"), "stack codegen must pop")
		assert(strings.Contains(output, "add rax, rcx"), "must emit add")
	}

	// Verify division uses cqo
	{
		cg := NewCodegen()
		cg.GenExpr(Div{Lit{100}, Lit{10}})
		output := cg.Output()
		assert(strings.Contains(output, "cqo"), "signed div must use cqo")
		assert(strings.Contains(output, "idiv"), "must emit idiv")
		assert(!strings.Contains(output, "xor"), "must NOT use xor rdx,rdx")
	}

	// ── Test function generation ───────────────────────────────────
	{
		cg := NewCodegen()
		stmts := []Expr{
			Assign{"x", Lit{10}},
			Assign{"y", Lit{20}},
			Assign{"z", Add{VarRef{"x"}, VarRef{"y"}}},
		}
		asm := cg.GenFunction("compute", stmts)
		assert(strings.Contains(asm, "push rbp"), "must have prologue")
		assert(strings.Contains(asm, "leave"), "must use leave")
		assert(strings.Contains(asm, "ret"), "must return")
		assert(strings.Contains(asm, "sub rsp"), "must allocate frame")
		assert(strings.Contains(asm, "[rbp-8]"), "first local at rbp-8")
		assert(strings.Contains(asm, "[rbp-16]"), "second local at rbp-16")
		fmt.Printf("\nGenerated function:\n%s\n", asm)
	}

	// ── Test stack frame layout ────────────────────────────────────
	fmt.Println("\nStack frame layout:")

	layout := computeFrameLayout(3, 2)
	assert(layout.ParamOffsets["param_0"] == -8, "param 0 at [rbp-8]")
	assert(layout.ParamOffsets["param_1"] == -16, "param 1 at [rbp-16]")
	assert(layout.ParamOffsets["param_2"] == -24, "param 2 at [rbp-24]")
	assert(layout.LocalOffsets["local_0"] == -32, "local 0 after params")
	assert(layout.LocalOffsets["local_1"] == -40, "local 1 after local 0")
	assert(layout.FrameSize%16 == 0, "frame size 16-byte aligned")
	fmt.Printf("  3 params + 2 locals: frame_size=%d bytes\n", layout.FrameSize)

	// 8 params — some on stack
	layout8 := computeFrameLayout(8, 0)
	assert(layout8.ParamOffsets["param_6"] == 16, "param 7 at [rbp+16]")
	assert(layout8.ParamOffsets["param_7"] == 24, "param 8 at [rbp+24]")
	fmt.Printf("  8 params: param_6=[rbp+%d], param_7=[rbp+%d]\n",
		layout8.ParamOffsets["param_6"], layout8.ParamOffsets["param_7"])

	// ── Verify calling convention constants ─────────────────────────
	assert(sysvArgRegs[0] == "rdi", "first arg in rdi")
	assert(sysvArgRegs[3] == "rcx", "function arg 4 in rcx")
	assert(syscallArgRegs[3] == "r10", "syscall arg 4 in r10 (not rcx)")

	fmt.Println("\nAll code generation examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
