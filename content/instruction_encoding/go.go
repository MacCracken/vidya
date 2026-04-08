// Vidya — Instruction Encoding in Go
//
// Demonstrates x86_64 machine code encoding:
//   - REX prefix construction (W, R, X, B bits)
//   - ModR/M byte encoding (mod, reg, r/m fields)
//   - Encoding MOV, ADD, SUB, XOR, CMP, JMP, NOP
//   - Building byte slices and verifying against expected machine code
//
// x86_64 instruction format:
//   [Legacy Prefixes] [REX] [Opcode] [ModR/M] [SIB] [Displacement] [Immediate]
//
// The REX prefix (0x40-0x4F) enables 64-bit operand size and access
// to registers R8-R15. ModR/M selects addressing modes and operands.

package main

import "fmt"

// ── Register Encoding ────────────────────────────────────────────────
// x86_64 registers are encoded as 3-bit values (0-7).
// Registers R8-R15 use the same 3-bit codes but set the REX.R or REX.B bit.

type X86Reg uint8

const (
	RAX X86Reg = 0
	RCX X86Reg = 1
	RDX X86Reg = 2
	RBX X86Reg = 3
	RSP X86Reg = 4
	RBP X86Reg = 5
	RSI X86Reg = 6
	RDI X86Reg = 7
	R8  X86Reg = 8
	R9  X86Reg = 9
	R10 X86Reg = 10
	R11 X86Reg = 11
	R12 X86Reg = 12
	R13 X86Reg = 13
	R14 X86Reg = 14
	R15 X86Reg = 15
)

var regNames = map[X86Reg]string{
	RAX: "rax", RCX: "rcx", RDX: "rdx", RBX: "rbx",
	RSP: "rsp", RBP: "rbp", RSI: "rsi", RDI: "rdi",
	R8: "r8", R9: "r9", R10: "r10", R11: "r11",
	R12: "r12", R13: "r13", R14: "r14", R15: "r15",
}

func (r X86Reg) String() string {
	if name, ok := regNames[r]; ok {
		return name
	}
	return fmt.Sprintf("r?%d", r)
}

// Low3 returns the 3-bit register code (for ModR/M encoding).
func (r X86Reg) Low3() uint8 { return uint8(r) & 0x07 }

// IsExtended returns true for R8-R15 (needs REX bit).
func (r X86Reg) IsExtended() bool { return r >= 8 }

// ── REX Prefix ───────────────────────────────────────────────────────
// Bit layout: 0100 W R X B
//   W: 1 = 64-bit operand size (most common)
//   R: extends ModR/M.reg field (for R8-R15 as reg operand)
//   X: extends SIB.index field
//   B: extends ModR/M.r/m field (for R8-R15 as r/m operand)

const rexBase uint8 = 0x40

func rexByte(w, r, x, b bool) uint8 {
	rex := rexBase
	if w {
		rex |= 0x08 // bit 3
	}
	if r {
		rex |= 0x04 // bit 2
	}
	if x {
		rex |= 0x02 // bit 1
	}
	if b {
		rex |= 0x01 // bit 0
	}
	return rex
}

// rexFor builds a REX prefix for a reg-reg instruction with 64-bit operands.
func rexFor(reg, rm X86Reg) uint8 {
	return rexByte(true, reg.IsExtended(), false, rm.IsExtended())
}

// ── ModR/M Byte ──────────────────────────────────────────────────────
// Bit layout: [mod:2][reg:3][r/m:3]
//   mod=11: register direct (reg, reg)
//   mod=00: [r/m] memory, no displacement
//   mod=01: [r/m] + disp8
//   mod=10: [r/m] + disp32
//   reg: register operand or opcode extension (/0-/7)
//   r/m: register or memory operand

func modRM(mod, reg, rm uint8) uint8 {
	return (mod << 6) | ((reg & 0x07) << 3) | (rm & 0x07)
}

// modRMRegReg builds a ModR/M byte for register-register addressing (mod=11).
func modRMRegReg(reg, rm X86Reg) uint8 {
	return modRM(0x03, reg.Low3(), rm.Low3())
}

// ── Instruction Encoder ─────────────────────────────────────────────

type Encoder struct {
	buf []byte
}

func NewEncoder() *Encoder {
	return &Encoder{}
}

func (e *Encoder) emit(bytes ...byte) {
	e.buf = append(e.buf, bytes...)
}

func (e *Encoder) emitImm32(v int32) {
	e.buf = append(e.buf,
		byte(v),
		byte(v>>8),
		byte(v>>16),
		byte(v>>24),
	)
}

func (e *Encoder) emitImm64(v int64) {
	for i := 0; i < 8; i++ {
		e.buf = append(e.buf, byte(v>>(i*8)))
	}
}

func (e *Encoder) Bytes() []byte { return e.buf }
func (e *Encoder) Reset()       { e.buf = e.buf[:0] }

// ── MOV Instructions ─────────────────────────────────────────────────

// MovRegReg encodes: mov dst, src (64-bit register to register)
// Encoding: REX.W + 0x89 + ModR/M(11, src, dst)
// Note: 0x89 has direction bit 0 = src→dst, so reg=src, r/m=dst
func (e *Encoder) MovRegReg(dst, src X86Reg) {
	e.emit(rexFor(src, dst))
	e.emit(0x89) // MOV r/m64, r64
	e.emit(modRMRegReg(src, dst))
}

// MovRegImm64 encodes: mov reg, imm64 (load 64-bit immediate)
// Encoding: REX.W + 0xB8+rd + imm64
// This is the only x86 instruction that takes a full 64-bit immediate.
func (e *Encoder) MovRegImm64(dst X86Reg, imm int64) {
	e.emit(rexByte(true, false, false, dst.IsExtended()))
	e.emit(0xB8 + dst.Low3()) // MOV r64, imm64
	e.emitImm64(imm)
}

// MovRegImm32 encodes: mov reg, imm32 (load 32-bit, zero-extends to 64)
// Encoding: [REX.B if extended] + 0xB8+rd + imm32
// Shorter than imm64 when the value fits in 32 bits.
func (e *Encoder) MovRegImm32(dst X86Reg, imm int32) {
	if dst.IsExtended() {
		e.emit(rexByte(false, false, false, true))
	}
	e.emit(0xB8 + dst.Low3())
	e.emitImm32(imm)
}

// ── ADD/SUB/XOR/CMP Instructions ─────────────────────────────────────
// These share the ALU encoding pattern: REX.W + opcode + ModR/M

// AddRegReg encodes: add dst, src (64-bit)
// Encoding: REX.W + 0x01 + ModR/M(11, src, dst)
func (e *Encoder) AddRegReg(dst, src X86Reg) {
	e.emit(rexFor(src, dst))
	e.emit(0x01)
	e.emit(modRMRegReg(src, dst))
}

// AddRegImm32 encodes: add dst, imm32 (64-bit)
// Encoding: REX.W + 0x81 + ModR/M(11, /0, dst) + imm32
func (e *Encoder) AddRegImm32(dst X86Reg, imm int32) {
	e.emit(rexByte(true, false, false, dst.IsExtended()))
	e.emit(0x81)
	e.emit(modRM(0x03, 0, dst.Low3())) // /0 = ADD
	e.emitImm32(imm)
}

// SubRegReg encodes: sub dst, src (64-bit)
func (e *Encoder) SubRegReg(dst, src X86Reg) {
	e.emit(rexFor(src, dst))
	e.emit(0x29) // SUB r/m64, r64
	e.emit(modRMRegReg(src, dst))
}

// XorRegReg encodes: xor dst, src (64-bit)
// Common use: xor rax, rax to zero a register (3 bytes, fast)
func (e *Encoder) XorRegReg(dst, src X86Reg) {
	e.emit(rexFor(src, dst))
	e.emit(0x31) // XOR r/m64, r64
	e.emit(modRMRegReg(src, dst))
}

// CmpRegReg encodes: cmp dst, src (64-bit, sets flags)
func (e *Encoder) CmpRegReg(dst, src X86Reg) {
	e.emit(rexFor(src, dst))
	e.emit(0x39) // CMP r/m64, r64
	e.emit(modRMRegReg(src, dst))
}

// ── Control Flow ─────────────────────────────────────────────────────

// JmpRel32 encodes: jmp rel32 (near jump, PC-relative)
// Encoding: 0xE9 + rel32
func (e *Encoder) JmpRel32(offset int32) {
	e.emit(0xE9)
	e.emitImm32(offset)
}

// Ret encodes: ret (return from procedure)
func (e *Encoder) Ret() {
	e.emit(0xC3)
}

// Nop encodes: nop (no operation, 1 byte)
func (e *Encoder) Nop() {
	e.emit(0x90)
}

// Syscall encodes: syscall (2 bytes)
func (e *Encoder) Syscall() {
	e.emit(0x0F, 0x05)
}

// ── Push/Pop ─────────────────────────────────────────────────────────

// PushReg encodes: push reg (64-bit, no REX.W needed — default 64-bit in long mode)
func (e *Encoder) PushReg(reg X86Reg) {
	if reg.IsExtended() {
		e.emit(rexByte(false, false, false, true))
	}
	e.emit(0x50 + reg.Low3())
}

// PopReg encodes: pop reg
func (e *Encoder) PopReg(reg X86Reg) {
	if reg.IsExtended() {
		e.emit(rexByte(false, false, false, true))
	}
	e.emit(0x58 + reg.Low3())
}

// ── Hex Formatting ───────────────────────────────────────────────────

func hexBytes(data []byte) string {
	if len(data) == 0 {
		return "(empty)"
	}
	result := ""
	for i, b := range data {
		if i > 0 {
			result += " "
		}
		result += fmt.Sprintf("%02x", b)
	}
	return result
}

func bytesEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func main() {
	fmt.Println("Instruction Encoding — Go demonstration:\n")

	// ── 1. REX prefix construction ───────────────────────────────────
	fmt.Println("1. REX prefix bit layout: 0100 WRXB")

	rexTests := []struct {
		w, r, x, b bool
		expected    uint8
		desc        string
	}{
		{false, false, false, false, 0x40, "bare REX (no extensions)"},
		{true, false, false, false, 0x48, "REX.W (64-bit operand size)"},
		{true, true, false, false, 0x4C, "REX.WR (64-bit + extended reg)"},
		{true, false, false, true, 0x49, "REX.WB (64-bit + extended r/m)"},
		{true, true, false, true, 0x4D, "REX.WRB (64-bit + both extended)"},
	}

	for _, tc := range rexTests {
		got := rexByte(tc.w, tc.r, tc.x, tc.b)
		assert(got == tc.expected,
			fmt.Sprintf("REX(%v,%v,%v,%v): expected 0x%02x, got 0x%02x",
				tc.w, tc.r, tc.x, tc.b, tc.expected, got))
		fmt.Printf("  0x%02x — %s\n", got, tc.desc)
	}

	// ── 2. ModR/M byte construction ──────────────────────────────────
	fmt.Println("\n2. ModR/M byte: [mod:2][reg:3][r/m:3]")

	modrmTests := []struct {
		mod, reg, rm uint8
		expected     uint8
		desc         string
	}{
		{0x03, 0, 0, 0xC0, "mod=11, reg=rax, r/m=rax"},
		{0x03, 1, 0, 0xC8, "mod=11, reg=rcx, r/m=rax"},
		{0x03, 0, 1, 0xC1, "mod=11, reg=rax, r/m=rcx"},
		{0x00, 0, 5, 0x05, "mod=00, reg=rax, r/m=101 (RIP-relative!)"},
		{0x01, 0, 5, 0x45, "mod=01, reg=rax, r/m=rbp (disp8)"},
	}

	for _, tc := range modrmTests {
		got := modRM(tc.mod, tc.reg, tc.rm)
		assert(got == tc.expected,
			fmt.Sprintf("ModR/M(%d,%d,%d): expected 0x%02x, got 0x%02x",
				tc.mod, tc.reg, tc.rm, tc.expected, got))
		fmt.Printf("  0x%02x — %s\n", got, tc.desc)
	}

	// Highlight the RBP gotcha
	fmt.Println("  Note: mod=00, r/m=101 is RIP-relative, NOT [RBP]!")
	fmt.Println("  To encode [RBP], use mod=01 with disp8=0x00.")

	// ── 3. MOV encoding ─────────────────────────────────────────────
	fmt.Println("\n3. MOV instruction encoding:")

	enc := NewEncoder()

	// mov rax, rbx  →  48 89 d8
	enc.Reset()
	enc.MovRegReg(RAX, RBX)
	expected := []byte{0x48, 0x89, 0xD8}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("mov rax, rbx: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  mov rax, rbx     → %s\n", hexBytes(enc.Bytes()))

	// mov rcx, rdx  →  48 89 d1
	enc.Reset()
	enc.MovRegReg(RCX, RDX)
	expected = []byte{0x48, 0x89, 0xD1}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("mov rcx, rdx: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  mov rcx, rdx     → %s\n", hexBytes(enc.Bytes()))

	// mov r8, rax  →  49 89 c0  (REX.WB because r8 is extended)
	enc.Reset()
	enc.MovRegReg(R8, RAX)
	expected = []byte{0x49, 0x89, 0xC0}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("mov r8, rax: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  mov r8, rax      → %s  (REX.WB for R8)\n", hexBytes(enc.Bytes()))

	// mov rax, 0x42  →  48 b8 42 00 00 00 00 00 00 00  (imm64)
	enc.Reset()
	enc.MovRegImm64(RAX, 0x42)
	assert(len(enc.Bytes()) == 10, "mov rax, imm64 must be 10 bytes")
	assert(enc.Bytes()[0] == 0x48, "REX.W prefix")
	assert(enc.Bytes()[1] == 0xB8, "opcode B8+rd")
	assert(enc.Bytes()[2] == 0x42, "immediate low byte")
	fmt.Printf("  mov rax, 0x42    → %s  (10 bytes, imm64)\n", hexBytes(enc.Bytes()))

	// mov eax, 0x42  →  b8 42 00 00 00  (imm32, zero-extends, 5 bytes — shorter!)
	enc.Reset()
	enc.MovRegImm32(RAX, 0x42)
	assert(len(enc.Bytes()) == 5, "mov eax, imm32 must be 5 bytes")
	fmt.Printf("  mov eax, 0x42    → %s  (5 bytes, imm32 zero-extends)\n", hexBytes(enc.Bytes()))

	// ── 4. ALU encoding ──────────────────────────────────────────────
	fmt.Println("\n4. ALU instruction encoding:")

	// add rax, rcx  →  48 01 c8
	enc.Reset()
	enc.AddRegReg(RAX, RCX)
	expected = []byte{0x48, 0x01, 0xC8}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("add rax, rcx: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  add rax, rcx     → %s\n", hexBytes(enc.Bytes()))

	// add rax, 100  →  48 81 c0 64 00 00 00
	enc.Reset()
	enc.AddRegImm32(RAX, 100)
	expected = []byte{0x48, 0x81, 0xC0, 0x64, 0x00, 0x00, 0x00}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("add rax, 100: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  add rax, 100     → %s\n", hexBytes(enc.Bytes()))

	// sub rdx, rsi  →  48 29 f2
	enc.Reset()
	enc.SubRegReg(RDX, RSI)
	expected = []byte{0x48, 0x29, 0xF2}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("sub rdx, rsi: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  sub rdx, rsi     → %s\n", hexBytes(enc.Bytes()))

	// xor rax, rax  →  48 31 c0  (canonical register zeroing)
	enc.Reset()
	enc.XorRegReg(RAX, RAX)
	expected = []byte{0x48, 0x31, 0xC0}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("xor rax, rax: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  xor rax, rax     → %s  (idiomatic zero)\n", hexBytes(enc.Bytes()))

	// cmp rdi, rsi  →  48 39 f7
	enc.Reset()
	enc.CmpRegReg(RDI, RSI)
	expected = []byte{0x48, 0x39, 0xF7}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("cmp rdi, rsi: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  cmp rdi, rsi     → %s\n", hexBytes(enc.Bytes()))

	// ── 5. Control flow encoding ─────────────────────────────────────
	fmt.Println("\n5. Control flow encoding:")

	// jmp +0  →  e9 00 00 00 00
	enc.Reset()
	enc.JmpRel32(0)
	expected = []byte{0xE9, 0x00, 0x00, 0x00, 0x00}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("jmp +0: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  jmp +0           → %s  (5 bytes, rel32)\n", hexBytes(enc.Bytes()))

	// jmp -5  →  e9 fb ff ff ff  (jump back to self)
	enc.Reset()
	enc.JmpRel32(-5)
	assert(enc.Bytes()[0] == 0xE9, "opcode E9")
	fmt.Printf("  jmp -5           → %s  (infinite loop)\n", hexBytes(enc.Bytes()))

	// ret  →  c3
	enc.Reset()
	enc.Ret()
	assert(bytesEqual(enc.Bytes(), []byte{0xC3}), "ret must be C3")
	fmt.Printf("  ret              → %s  (1 byte)\n", hexBytes(enc.Bytes()))

	// nop  →  90
	enc.Reset()
	enc.Nop()
	assert(bytesEqual(enc.Bytes(), []byte{0x90}), "nop must be 90")
	fmt.Printf("  nop              → %s  (1 byte)\n", hexBytes(enc.Bytes()))

	// syscall  →  0f 05
	enc.Reset()
	enc.Syscall()
	assert(bytesEqual(enc.Bytes(), []byte{0x0F, 0x05}), "syscall must be 0F 05")
	fmt.Printf("  syscall          → %s  (2 bytes)\n", hexBytes(enc.Bytes()))

	// ── 6. Push/Pop encoding ─────────────────────────────────────────
	fmt.Println("\n6. Push/Pop encoding:")

	// push rbp  →  55
	enc.Reset()
	enc.PushReg(RBP)
	assert(bytesEqual(enc.Bytes(), []byte{0x55}), "push rbp must be 55")
	fmt.Printf("  push rbp         → %s  (1 byte)\n", hexBytes(enc.Bytes()))

	// pop rbp  →  5d
	enc.Reset()
	enc.PopReg(RBP)
	assert(bytesEqual(enc.Bytes(), []byte{0x5D}), "pop rbp must be 5D")
	fmt.Printf("  pop rbp          → %s  (1 byte)\n", hexBytes(enc.Bytes()))

	// push r12  →  41 54  (REX.B because R12 is extended)
	enc.Reset()
	enc.PushReg(R12)
	expected = []byte{0x41, 0x54}
	assert(bytesEqual(enc.Bytes(), expected),
		fmt.Sprintf("push r12: expected %s, got %s", hexBytes(expected), hexBytes(enc.Bytes())))
	fmt.Printf("  push r12         → %s  (REX.B for extended register)\n", hexBytes(enc.Bytes()))

	// ── 7. Function prologue/epilogue ────────────────────────────────
	fmt.Println("\n7. Complete function prologue/epilogue:")

	enc.Reset()
	enc.PushReg(RBP)                 // push rbp
	enc.MovRegReg(RBP, RSP)          // mov rbp, rsp
	enc.AddRegImm32(RSP, -16)        // sub rsp, 16 (via add -16)
	// ... function body would go here ...
	enc.MovRegReg(RSP, RBP)          // mov rsp, rbp (or use 'leave')
	enc.PopReg(RBP)                  // pop rbp
	enc.Ret()                        // ret

	fmt.Printf("  prologue+epilogue → %s\n", hexBytes(enc.Bytes()))
	fmt.Printf("  Total: %d bytes\n", len(enc.Bytes()))

	// Verify prologue starts with push rbp (0x55)
	assert(enc.Bytes()[0] == 0x55, "prologue must start with push rbp")
	// Verify epilogue ends with ret (0xC3)
	assert(enc.Bytes()[len(enc.Bytes())-1] == 0xC3, "epilogue must end with ret")

	// ── 8. Encoding size comparison ──────────────────────────────────
	fmt.Println("\n8. Encoding size comparison:")
	fmt.Println("  Prefer shorter encodings for better I-cache utilization:")
	fmt.Println()

	// mov rax, 0x42 — imm64 vs imm32
	enc.Reset()
	enc.MovRegImm64(RAX, 0x42)
	longSize := len(enc.Bytes())

	enc.Reset()
	enc.MovRegImm32(RAX, 0x42)
	shortSize := len(enc.Bytes())

	fmt.Printf("  mov rax, 0x42:  imm64=%d bytes, imm32=%d bytes (save %d)\n",
		longSize, shortSize, longSize-shortSize)
	assert(shortSize < longSize, "imm32 encoding must be shorter")

	// xor eax, eax (32-bit, 2 bytes) vs xor rax, rax (64-bit, 3 bytes)
	// Note: xor eax, eax zero-extends to rax, so it's equivalent but shorter
	fmt.Println("  xor eax, eax:   2 bytes (zero-extends to rax)")
	fmt.Println("  xor rax, rax:   3 bytes (REX.W adds 1 byte, same effect)")
	fmt.Println("  → Assemblers should prefer the 32-bit form for zeroing.")

	fmt.Println("\nAll instruction encoding examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
