// Intermediate Representations — Rust Implementation
//
// Demonstrates core IR concepts:
//   1. Three-address code generation from an AST
//   2. Basic block construction and CFG building
//   3. SSA construction with phi nodes
//   4. Simple constant folding on SSA form
//
// This is what happens between parsing and codegen in any optimizing compiler.

use std::collections::HashMap;
use std::fmt;

// ── Three-Address Code (TAC) ──────────────────────────────────────────────

/// A virtual register (SSA: each assignment creates a new version).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
struct Reg(u32);

impl fmt::Display for Reg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "v{}", self.0)
    }
}

/// Three-address code instruction.
#[derive(Debug, Clone)]
enum Tac {
    /// dst = immediate constant
    LoadConst { dst: Reg, value: i64 },
    /// dst = lhs op rhs
    BinOp { dst: Reg, op: BinOpKind, lhs: Reg, rhs: Reg },
    /// dst = -src
    Neg { dst: Reg, src: Reg },
    /// Conditional branch: if cond > 0, goto then_block, else goto else_block
    BranchPos { cond: Reg, then_block: usize, else_block: usize },
    /// Unconditional jump
    Jump { target: usize },
    /// Return a value
    Return { value: Reg },
    /// Phi node: dst = phi(inputs) where inputs are (block_id, reg) pairs
    Phi { dst: Reg, inputs: Vec<(usize, Reg)> },
}

#[derive(Debug, Clone, Copy)]
enum BinOpKind {
    Add,
    Sub,
    Mul,
}

impl fmt::Display for BinOpKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BinOpKind::Add => write!(f, "+"),
            BinOpKind::Sub => write!(f, "-"),
            BinOpKind::Mul => write!(f, "*"),
        }
    }
}

impl fmt::Display for Tac {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Tac::LoadConst { dst, value } => write!(f, "{} = {}", dst, value),
            Tac::BinOp { dst, op, lhs, rhs } => write!(f, "{} = {} {} {}", dst, lhs, op, rhs),
            Tac::Neg { dst, src } => write!(f, "{} = -{}", dst, src),
            Tac::BranchPos { cond, then_block, else_block } => {
                write!(f, "if {} > 0 goto B{} else B{}", cond, then_block, else_block)
            }
            Tac::Jump { target } => write!(f, "goto B{}", target),
            Tac::Return { value } => write!(f, "return {}", value),
            Tac::Phi { dst, inputs } => {
                write!(f, "{} = phi(", dst)?;
                for (i, (block, reg)) in inputs.iter().enumerate() {
                    if i > 0 {
                        write!(f, ", ")?;
                    }
                    write!(f, "B{}:{}", block, reg)?;
                }
                write!(f, ")")
            }
        }
    }
}

// ── Basic Blocks and CFG ──────────────────────────────────────────────────

#[derive(Debug)]
struct BasicBlock {
    id: usize,
    instructions: Vec<Tac>,
    predecessors: Vec<usize>,
    successors: Vec<usize>,
}

impl BasicBlock {
    fn new(id: usize) -> Self {
        Self {
            id,
            instructions: Vec::new(),
            predecessors: Vec::new(),
            successors: Vec::new(),
        }
    }
}

struct Cfg {
    blocks: Vec<BasicBlock>,
}

impl fmt::Display for Cfg {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for block in &self.blocks {
            writeln!(
                f,
                "  B{} (preds: {:?}, succs: {:?}):",
                block.id, block.predecessors, block.successors
            )?;
            for inst in &block.instructions {
                writeln!(f, "    {}", inst)?;
            }
        }
        Ok(())
    }
}

// ── TAC/CFG Builder ───────────────────────────────────────────────────────

/// Simple AST for demonstration.
#[derive(Debug)]
enum Expr {
    Lit(i64),
    Add(Box<Expr>, Box<Expr>),
    Sub(Box<Expr>, Box<Expr>),
    Mul(Box<Expr>, Box<Expr>),
    Neg(Box<Expr>),
    /// if cond > 0 then a else b
    IfPos(Box<Expr>, Box<Expr>, Box<Expr>),
}

struct IrBuilder {
    blocks: Vec<BasicBlock>,
    current_block: usize,
    next_reg: u32,
}

impl IrBuilder {
    fn new() -> Self {
        let entry = BasicBlock::new(0);
        Self {
            blocks: vec![entry],
            current_block: 0,
            next_reg: 0,
        }
    }

    fn fresh_reg(&mut self) -> Reg {
        let r = Reg(self.next_reg);
        self.next_reg += 1;
        r
    }

    fn new_block(&mut self) -> usize {
        let id = self.blocks.len();
        self.blocks.push(BasicBlock::new(id));
        id
    }

    fn emit(&mut self, inst: Tac) {
        self.blocks[self.current_block].instructions.push(inst);
    }

    fn add_edge(&mut self, from: usize, to: usize) {
        self.blocks[from].successors.push(to);
        self.blocks[to].predecessors.push(from);
    }

    /// Generate three-address code for an expression. Returns the register holding the result.
    fn gen_expr(&mut self, expr: &Expr) -> Reg {
        match expr {
            Expr::Lit(n) => {
                let dst = self.fresh_reg();
                self.emit(Tac::LoadConst { dst, value: *n });
                dst
            }
            Expr::Add(l, r) => {
                let lhs = self.gen_expr(l);
                let rhs = self.gen_expr(r);
                let dst = self.fresh_reg();
                self.emit(Tac::BinOp { dst, op: BinOpKind::Add, lhs, rhs });
                dst
            }
            Expr::Sub(l, r) => {
                let lhs = self.gen_expr(l);
                let rhs = self.gen_expr(r);
                let dst = self.fresh_reg();
                self.emit(Tac::BinOp { dst, op: BinOpKind::Sub, lhs, rhs });
                dst
            }
            Expr::Mul(l, r) => {
                let lhs = self.gen_expr(l);
                let rhs = self.gen_expr(r);
                let dst = self.fresh_reg();
                self.emit(Tac::BinOp { dst, op: BinOpKind::Mul, lhs, rhs });
                dst
            }
            Expr::Neg(e) => {
                let src = self.gen_expr(e);
                let dst = self.fresh_reg();
                self.emit(Tac::Neg { dst, src });
                dst
            }
            Expr::IfPos(cond, then_expr, else_expr) => {
                let cond_reg = self.gen_expr(cond);

                let then_block = self.new_block();
                let else_block = self.new_block();
                let merge_block = self.new_block();

                let cond_block = self.current_block;
                self.emit(Tac::BranchPos {
                    cond: cond_reg,
                    then_block,
                    else_block,
                });
                self.add_edge(cond_block, then_block);
                self.add_edge(cond_block, else_block);

                // Then branch
                self.current_block = then_block;
                let then_reg = self.gen_expr(then_expr);
                let then_exit = self.current_block;
                self.emit(Tac::Jump { target: merge_block });
                self.add_edge(then_exit, merge_block);

                // Else branch
                self.current_block = else_block;
                let else_reg = self.gen_expr(else_expr);
                let else_exit = self.current_block;
                self.emit(Tac::Jump { target: merge_block });
                self.add_edge(else_exit, merge_block);

                // Merge with phi node
                self.current_block = merge_block;
                let result = self.fresh_reg();
                self.emit(Tac::Phi {
                    dst: result,
                    inputs: vec![
                        (then_exit, then_reg),
                        (else_exit, else_reg),
                    ],
                });

                result
            }
        }
    }

    fn build(mut self, expr: &Expr) -> Cfg {
        let result = self.gen_expr(expr);
        self.emit(Tac::Return { value: result });
        Cfg {
            blocks: self.blocks,
        }
    }
}

// ── Constant Folding (SSA optimization) ───────────────────────────────────

fn constant_fold(cfg: &mut Cfg) -> usize {
    let mut constants: HashMap<Reg, i64> = HashMap::new();
    let mut folded = 0;

    for block in &mut cfg.blocks {
        let mut new_instructions = Vec::new();

        for inst in &block.instructions {
            match inst {
                Tac::LoadConst { dst, value } => {
                    constants.insert(*dst, *value);
                    new_instructions.push(inst.clone());
                }
                Tac::BinOp { dst, op, lhs, rhs } => {
                    if let (Some(&l), Some(&r)) = (constants.get(lhs), constants.get(rhs)) {
                        let result = match op {
                            BinOpKind::Add => l + r,
                            BinOpKind::Sub => l - r,
                            BinOpKind::Mul => l * r,
                        };
                        constants.insert(*dst, result);
                        new_instructions.push(Tac::LoadConst { dst: *dst, value: result });
                        folded += 1;
                    } else {
                        new_instructions.push(inst.clone());
                    }
                }
                Tac::Neg { dst, src } => {
                    if let Some(&val) = constants.get(src) {
                        constants.insert(*dst, -val);
                        new_instructions.push(Tac::LoadConst { dst: *dst, value: -val });
                        folded += 1;
                    } else {
                        new_instructions.push(inst.clone());
                    }
                }
                _ => {
                    new_instructions.push(inst.clone());
                }
            }
        }

        block.instructions = new_instructions;
    }

    folded
}

fn main() {
    println!("Intermediate Representations — TAC, CFG, and SSA:\n");

    // Example 1: Simple arithmetic — shows TAC generation
    println!("1. Simple expression: (2 + 3) * 4");
    let expr1 = Expr::Mul(
        Box::new(Expr::Add(
            Box::new(Expr::Lit(2)),
            Box::new(Expr::Lit(3)),
        )),
        Box::new(Expr::Lit(4)),
    );
    let cfg1 = IrBuilder::new().build(&expr1);
    println!("{}", cfg1);

    // Example 2: With branching — shows CFG + phi nodes
    println!("2. Branching expression: if 1 > 0 then 100 else 200");
    let expr2 = Expr::IfPos(
        Box::new(Expr::Lit(1)),
        Box::new(Expr::Lit(100)),
        Box::new(Expr::Lit(200)),
    );
    let cfg2 = IrBuilder::new().build(&expr2);
    println!("{}", cfg2);

    // Example 3: Nested — shows multi-level CFG
    println!("3. Nested: if 1 > 0 then (2 + 3) * 4 else -(5 + 6)");
    let expr3 = Expr::IfPos(
        Box::new(Expr::Lit(1)),
        Box::new(Expr::Mul(
            Box::new(Expr::Add(Box::new(Expr::Lit(2)), Box::new(Expr::Lit(3)))),
            Box::new(Expr::Lit(4)),
        )),
        Box::new(Expr::Neg(Box::new(Expr::Add(
            Box::new(Expr::Lit(5)),
            Box::new(Expr::Lit(6)),
        )))),
    );
    let cfg3 = IrBuilder::new().build(&expr3);
    println!("{}", cfg3);

    // Example 4: Constant folding optimization
    println!("4. Constant folding on: (10 + 20) * (3 - 1)");
    let expr4 = Expr::Mul(
        Box::new(Expr::Add(Box::new(Expr::Lit(10)), Box::new(Expr::Lit(20)))),
        Box::new(Expr::Sub(Box::new(Expr::Lit(3)), Box::new(Expr::Lit(1)))),
    );
    let mut cfg4 = IrBuilder::new().build(&expr4);
    println!("  Before folding:");
    print!("{}", cfg4);
    let folded = constant_fold(&mut cfg4);
    println!("  After folding ({} operations folded):", folded);
    print!("{}", cfg4);
}
