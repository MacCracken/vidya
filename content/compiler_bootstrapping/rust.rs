// Compiler Bootstrapping — Rust Implementation
//
// Demonstrates a minimal two-pass assembler in Rust.
// This is the pattern used by Cyrius seed (stage 0):
//   Pass 1: collect labels and compute offsets
//   Pass 2: emit machine code with resolved addresses
//
// The key insight: a compiler is just a function from text to bytes.
// Self-hosting means that function can process its own source code.

use std::collections::HashMap;

/// A minimal instruction set for demonstration.
#[derive(Debug)]
enum Instruction {
    LoadImm { reg: u8, value: i64 },
    Add { dst: u8, src: u8 },
    Jump { label: String },
    Label(String),
    Halt,
}

/// Pass 1: Scan instructions, record label positions.
fn collect_labels(instructions: &[Instruction]) -> HashMap<String, usize> {
    let mut labels = HashMap::new();
    let mut offset = 0usize;
    for inst in instructions {
        match inst {
            Instruction::Label(name) => {
                labels.insert(name.clone(), offset);
                // Labels emit no bytes
            }
            Instruction::LoadImm { .. } => offset += 10, // REX.W + opcode + imm64
            Instruction::Add { .. } => offset += 3,      // REX.W + opcode + ModR/M
            Instruction::Jump { .. } => offset += 5,      // opcode + rel32
            Instruction::Halt => offset += 1,              // single byte
        }
    }
    labels
}

/// Pass 2: Emit bytes with resolved label addresses.
fn emit_code(instructions: &[Instruction], labels: &HashMap<String, usize>) -> Vec<u8> {
    let mut code = Vec::new();
    let mut offset = 0usize;
    for inst in instructions {
        match inst {
            Instruction::LoadImm { reg, value } => {
                code.push(0x48); // REX.W
                code.push(0xB8 + reg);
                code.extend_from_slice(&value.to_le_bytes());
                offset += 10;
            }
            Instruction::Add { dst, src } => {
                code.push(0x48);
                code.push(0x01);
                code.push(0xC0 | (src << 3) | dst);
                offset += 3;
            }
            Instruction::Jump { label } => {
                let target = labels[label];
                let rel = target as i64 - (offset as i64 + 5);
                code.push(0xE9);
                code.extend_from_slice(&(rel as i32).to_le_bytes());
                offset += 5;
            }
            Instruction::Label(_) => {} // no bytes
            Instruction::Halt => {
                code.push(0xF4); // HLT
                offset += 1;
            }
        }
    }
    code
}

fn main() {
    // A tiny program: load 10 into r0, load 32 into r1, add them
    let program = vec![
        Instruction::Label("start".to_string()),
        Instruction::LoadImm { reg: 0, value: 10 },
        Instruction::LoadImm { reg: 1, value: 32 },
        Instruction::Add { dst: 0, src: 1 },
        Instruction::Jump { label: "start".to_string() },
        Instruction::Halt,
    ];

    let labels = collect_labels(&program);
    let code = emit_code(&program, &labels);

    println!("Labels: {:?}", labels);
    println!("Code ({} bytes): {:02X?}", code.len(), code);
    println!("Bootstrap chain: source → labels → machine code");
}
