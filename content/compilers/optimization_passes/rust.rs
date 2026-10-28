// Optimization Passes — Rust Implementation
//
// Demonstrates classic compiler optimization passes on a simple IR:
//   1. Constant folding — evaluate constant expressions at compile time
//   2. Dead code elimination (DCE) — remove unused instructions
//   3. Constant propagation — replace variables with known constant values
//   4. Strength reduction — replace expensive ops with cheaper ones
//      (x * 2^k → x << k), plus single-instruction algebraic identities
//      (x * 1, x + 0, x * 0) of the kind a peephole pass applies
//
// Each pass transforms the IR, and passes compose: run them iteratively
// until no more changes occur (fixed point).

use std::collections::{HashMap, HashSet};
use std::fmt;

// ── Simple IR ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct Reg(u32);

impl fmt::Display for Reg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "v{}", self.0)
    }
}

#[derive(Debug, Clone)]
enum Inst {
    Const { dst: Reg, value: i64 },
    BinOp { dst: Reg, op: Op, lhs: Reg, rhs: Reg },
    Copy { dst: Reg, src: Reg },
    /// dst = src << shift (immediate) — the target of strength reduction
    ShlImm { dst: Reg, src: Reg, shift: u32 },
    Return { src: Reg },
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Op {
    Add,
    Sub,
    Mul,
}

impl fmt::Display for Op {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Op::Add => write!(f, "+"),
            Op::Sub => write!(f, "-"),
            Op::Mul => write!(f, "*"),
        }
    }
}

impl fmt::Display for Inst {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Inst::Const { dst, value } => write!(f, "{} = {}", dst, value),
            Inst::BinOp { dst, op, lhs, rhs } => write!(f, "{} = {} {} {}", dst, lhs, op, rhs),
            Inst::Copy { dst, src } => write!(f, "{} = {}", dst, src),
            Inst::ShlImm { dst, src, shift } => write!(f, "{} = {} << {}", dst, src, shift),
            Inst::Return { src } => write!(f, "return {}", src),
        }
    }
}

/// A simple program: list of instructions.
struct Program {
    instructions: Vec<Inst>,
}

impl fmt::Display for Program {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for inst in &self.instructions {
            writeln!(f, "    {}", inst)?;
        }
        Ok(())
    }
}

// ── Pass 1: Constant Folding ──────────────────────────────────────────────

fn constant_fold(prog: &mut Program) -> usize {
    let mut constants: HashMap<Reg, i64> = HashMap::new();
    let mut folded = 0;

    for inst in &mut prog.instructions {
        match inst {
            Inst::Const { dst, value } => {
                constants.insert(*dst, *value);
            }
            Inst::BinOp { dst, op, lhs, rhs } => {
                if let (Some(&l), Some(&r)) = (constants.get(lhs), constants.get(rhs)) {
                    let result = match op {
                        Op::Add => l + r,
                        Op::Sub => l - r,
                        Op::Mul => l * r,
                    };
                    constants.insert(*dst, result);
                    *inst = Inst::Const { dst: *dst, value: result };
                    folded += 1;
                }
            }
            Inst::Copy { dst, src } => {
                if let Some(&val) = constants.get(src) {
                    constants.insert(*dst, val);
                }
            }
            Inst::ShlImm { dst, src, shift } => {
                if let Some(&v) = constants.get(src) {
                    let result = v << *shift;
                    constants.insert(*dst, result);
                    *inst = Inst::Const { dst: *dst, value: result };
                    folded += 1;
                }
            }
            Inst::Return { .. } => {}
        }
    }

    folded
}

// ── Pass 2: Dead Code Elimination ─────────────────────────────────────────

fn dead_code_elimination(prog: &mut Program) -> usize {
    // Collect all used registers
    let mut used: HashSet<Reg> = HashSet::new();

    for inst in &prog.instructions {
        match inst {
            Inst::BinOp { lhs, rhs, .. } => {
                used.insert(*lhs);
                used.insert(*rhs);
            }
            Inst::Copy { src, .. } | Inst::ShlImm { src, .. } => {
                used.insert(*src);
            }
            Inst::Return { src } => {
                used.insert(*src);
            }
            Inst::Const { .. } => {}
        }
    }

    // Remove instructions whose dst is never used
    let before = prog.instructions.len();
    prog.instructions.retain(|inst| {
        match inst {
            Inst::Const { dst, .. }
            | Inst::BinOp { dst, .. }
            | Inst::Copy { dst, .. }
            | Inst::ShlImm { dst, .. } => used.contains(dst),
            Inst::Return { .. } => true,
        }
    });

    before - prog.instructions.len()
}

// ── Pass 3: Constant Propagation ──────────────────────────────────────────

fn constant_propagation(prog: &mut Program) -> usize {
    let mut constants: HashMap<Reg, i64> = HashMap::new();
    let mut propagated = 0;

    // First pass: collect constants
    for inst in &prog.instructions {
        if let Inst::Const { dst, value } = inst {
            constants.insert(*dst, *value);
        }
    }

    // Second pass: replace copies of constant registers with the constant.
    // (BinOps with constant operands are left to constant_fold, which reads
    // the same table. Counting them here without changing anything would
    // report "progress" every iteration and the fixed-point loop would
    // never terminate for a program with a non-constant input.)
    for inst in &mut prog.instructions {
        if let Inst::Copy { dst, src } = inst {
            if let Some(&val) = constants.get(src) {
                *inst = Inst::Const { dst: *dst, value: val };
                propagated += 1;
            }
        }
    }

    propagated
}

// ── Pass 4: Strength Reduction ────────────────────────────────────────────

fn strength_reduction(prog: &mut Program) -> usize {
    let mut constants: HashMap<Reg, i64> = HashMap::new();
    let mut reduced = 0;

    for inst in &prog.instructions {
        if let Inst::Const { dst, value } = inst {
            constants.insert(*dst, *value);
        }
    }

    for inst in &mut prog.instructions {
        if let Inst::BinOp { dst, op: Op::Mul, lhs, rhs } = inst {
            // x * 2^k → x << k, for x NOT known at compile time (when both
            // operands are constant, constant_fold has already done better)
            let pow2 = constants.get(rhs).copied().filter(|&v| v > 1 && (v as u64).is_power_of_two());
            if let (None, Some(val)) = (constants.get(lhs), pow2) {
                *inst = Inst::ShlImm { dst: *dst, src: *lhs, shift: val.trailing_zeros() };
                reduced += 1;
            }
            // Multiply by 0 → const 0
            else if constants.get(rhs) == Some(&0) || constants.get(lhs) == Some(&0) {
                *inst = Inst::Const { dst: *dst, value: 0 };
                reduced += 1;
            }
            // Multiply by 1 → copy
            else if constants.get(rhs) == Some(&1) {
                *inst = Inst::Copy { dst: *dst, src: *lhs };
                reduced += 1;
            } else if constants.get(lhs) == Some(&1) {
                *inst = Inst::Copy { dst: *dst, src: *rhs };
                reduced += 1;
            }
        }

        if let Inst::BinOp { dst, op: Op::Add, lhs, rhs } = inst {
            // Add 0 → copy
            if constants.get(rhs) == Some(&0) {
                *inst = Inst::Copy { dst: *dst, src: *lhs };
                reduced += 1;
            } else if constants.get(lhs) == Some(&0) {
                *inst = Inst::Copy { dst: *dst, src: *rhs };
                reduced += 1;
            }
        }
    }

    reduced
}

// ── Pass Manager: run all passes to fixed point ───────────────────────────

fn optimize(prog: &mut Program) {
    println!("  Running optimization passes to fixed point:");
    let mut iteration = 0;

    loop {
        iteration += 1;
        let mut changed = false;

        let folded = constant_fold(prog);
        if folded > 0 {
            println!("    iter {}: constant folding: {} ops folded", iteration, folded);
            changed = true;
        }

        let propagated = constant_propagation(prog);
        if propagated > 0 {
            println!("    iter {}: constant propagation: {} propagated", iteration, propagated);
            changed = true;
        }

        let reduced = strength_reduction(prog);
        if reduced > 0 {
            println!("    iter {}: strength reduction: {} reduced", iteration, reduced);
            changed = true;
        }

        let eliminated = dead_code_elimination(prog);
        if eliminated > 0 {
            println!("    iter {}: DCE: {} instructions removed", iteration, eliminated);
            changed = true;
        }

        if !changed {
            println!("    Fixed point reached after {} iterations", iteration);
            break;
        }
    }
}

fn main() {
    println!("Optimization Passes — compiler transformations:\n");

    // Example: (10 + 20) * (x + 0) * 1 where x = 5
    // Optimal result: just "return 150"
    println!("1. Input program: (10 + 20) * (x + 0) * 1 where x = 5");
    let mut prog = Program {
        instructions: vec![
            Inst::Const { dst: Reg(0), value: 10 },         // v0 = 10
            Inst::Const { dst: Reg(1), value: 20 },         // v1 = 20
            Inst::BinOp { dst: Reg(2), op: Op::Add, lhs: Reg(0), rhs: Reg(1) }, // v2 = v0 + v1
            Inst::Const { dst: Reg(3), value: 5 },          // v3 = 5 (x)
            Inst::Const { dst: Reg(4), value: 0 },          // v4 = 0
            Inst::BinOp { dst: Reg(5), op: Op::Add, lhs: Reg(3), rhs: Reg(4) }, // v5 = x + 0
            Inst::BinOp { dst: Reg(6), op: Op::Mul, lhs: Reg(2), rhs: Reg(5) }, // v6 = (10+20) * (x+0)
            Inst::Const { dst: Reg(7), value: 1 },          // v7 = 1
            Inst::BinOp { dst: Reg(8), op: Op::Mul, lhs: Reg(6), rhs: Reg(7) }, // v8 = v6 * 1
            Inst::Return { src: Reg(8) },
        ],
    };

    println!("  Before optimization ({} instructions):", prog.instructions.len());
    print!("{}", prog);

    optimize(&mut prog);

    println!("  After optimization ({} instructions):", prog.instructions.len());
    print!("{}", prog);

    assert_eq!(prog.instructions.len(), 2);
    assert!(matches!(prog.instructions[0], Inst::Const { value: 150, .. }));

    // Example 2: Strength reduction — multiply by power of 2. x must be
    // unknown at compile time (v0 is a function input with no defining
    // instruction); a constant x would simply be folded.
    println!("\n2. Strength reduction: x * 8 → x << 3");
    let mut prog2 = Program {
        instructions: vec![
            Inst::Const { dst: Reg(1), value: 8 },          // v1 = 8
            Inst::BinOp { dst: Reg(2), op: Op::Mul, lhs: Reg(0), rhs: Reg(1) }, // v2 = x * 8
            Inst::Return { src: Reg(2) },
        ],
    };

    println!("  Before:");
    print!("{}", prog2);

    optimize(&mut prog2);

    println!("  After:");
    print!("{}", prog2);
    assert!(matches!(prog2.instructions[0], Inst::ShlImm { src: Reg(0), shift: 3, .. }));
    assert_eq!(prog2.instructions.len(), 2); // v1 = 8 is now dead and removed

    // Example 3: Dead code
    println!("\n3. Dead code elimination:");
    let mut prog3 = Program {
        instructions: vec![
            Inst::Const { dst: Reg(0), value: 1 },
            Inst::Const { dst: Reg(1), value: 2 },
            Inst::Const { dst: Reg(2), value: 3 },    // dead — never used
            Inst::BinOp { dst: Reg(3), op: Op::Add, lhs: Reg(0), rhs: Reg(1) },
            Inst::Const { dst: Reg(4), value: 99 },    // dead — never used
            Inst::Return { src: Reg(3) },
        ],
    };

    println!("  Before ({} instructions):", prog3.instructions.len());
    print!("{}", prog3);

    optimize(&mut prog3);

    println!("  After ({} instructions):", prog3.instructions.len());
    print!("{}", prog3);
    assert_eq!(prog3.instructions.len(), 2);
    assert!(matches!(prog3.instructions[0], Inst::Const { value: 3, .. }));
}
