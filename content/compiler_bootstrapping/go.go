// Vidya — Compiler Bootstrapping in Go
//
// Demonstrates a minimal two-pass assembler.
// This is the pattern used to bootstrap a compiler from nothing:
//   Pass 1: collect labels and compute byte offsets
//   Pass 2: emit machine code with resolved label addresses
//
// The key insight: a compiler is just a function from text to bytes.
// Self-hosting means that function can process its own source code.

package main

import (
	"encoding/binary"
	"fmt"
	"sort"
)

// OpCode represents instruction types.
type OpCode int

const (
	OpLoadImm OpCode = iota // load immediate into register
	OpAdd                   // add two registers
	OpJump                  // jump to label
	OpLabel                 // label definition (no code emitted)
	OpHalt                  // stop execution
)

// Instruction represents a single assembler instruction.
type Instruction struct {
	Op    OpCode
	Reg   uint8
	Src   uint8
	Value int64
	Label string
}

// collectLabels performs Pass 1: scan instructions and record label offsets.
func collectLabels(insts []Instruction) map[string]int {
	labels := make(map[string]int)
	offset := 0
	for _, inst := range insts {
		switch inst.Op {
		case OpLabel:
			labels[inst.Label] = offset
			// Labels emit no bytes
		case OpLoadImm:
			offset += 10 // REX.W + opcode + imm64
		case OpAdd:
			offset += 3 // REX.W + opcode + ModR/M
		case OpJump:
			offset += 5 // opcode + rel32
		case OpHalt:
			offset += 1 // single byte
		}
	}
	return labels
}

// emitCode performs Pass 2: emit bytes with resolved label addresses.
func emitCode(insts []Instruction, labels map[string]int) []byte {
	var code []byte
	offset := 0
	for _, inst := range insts {
		switch inst.Op {
		case OpLoadImm:
			code = append(code, 0x48)          // REX.W
			code = append(code, 0xB8+inst.Reg) // opcode + reg
			imm := make([]byte, 8)
			binary.LittleEndian.PutUint64(imm, uint64(inst.Value))
			code = append(code, imm...)
			offset += 10
		case OpAdd:
			code = append(code, 0x48) // REX.W
			code = append(code, 0x01) // ADD opcode
			code = append(code, 0xC0|(inst.Src<<3)|inst.Reg) // ModR/M
			offset += 3
		case OpJump:
			target := labels[inst.Label]
			rel := int32(target - (offset + 5))
			code = append(code, 0xE9) // JMP rel32
			relBytes := make([]byte, 4)
			binary.LittleEndian.PutUint32(relBytes, uint32(rel))
			code = append(code, relBytes...)
			offset += 5
		case OpLabel:
			// no bytes
		case OpHalt:
			code = append(code, 0xF4) // HLT
			offset += 1
		}
	}
	return code
}

func main() {
	// A tiny program: load 10 into r0, load 32 into r1, add them, loop
	program := []Instruction{
		{Op: OpLabel, Label: "start"},
		{Op: OpLoadImm, Reg: 0, Value: 10},
		{Op: OpLoadImm, Reg: 1, Value: 32},
		{Op: OpAdd, Reg: 0, Src: 1},
		{Op: OpJump, Label: "start"},
		{Op: OpHalt},
	}

	labels := collectLabels(program)
	code := emitCode(program, labels)

	// Print labels sorted for deterministic output
	keys := make([]string, 0, len(labels))
	for k := range labels {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	fmt.Print("Labels: {")
	for i, k := range keys {
		if i > 0 {
			fmt.Print(", ")
		}
		fmt.Printf("%s=%d", k, labels[k])
	}
	fmt.Println("}")

	// Print code bytes
	fmt.Printf("Code (%d bytes): [", len(code))
	for i, b := range code {
		if i > 0 {
			fmt.Print(" ")
		}
		fmt.Printf("%02X", b)
	}
	fmt.Println("]")
	fmt.Println("Bootstrap chain: source -> labels -> machine code")

	// Verify output: LOAD(10) + LOAD(10) + ADD(3) + JMP(5) + HLT(1) = 29 bytes
	if len(code) != 29 {
		panic(fmt.Sprintf("expected 29 bytes, got %d", len(code)))
	}
	if code[0] != 0x48 {
		panic("first byte should be REX.W")
	}
	if code[1] != 0xB8 {
		panic("second byte should be MOV r0 opcode")
	}
	if code[23] != 0xE9 {
		panic("jump opcode at offset 23")
	}
	if code[28] != 0xF4 {
		panic("halt at offset 28")
	}
	if labels["start"] != 0 {
		panic("start label should be at offset 0")
	}
	fmt.Println("All verifications passed.")
}
