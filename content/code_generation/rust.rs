// Code Generation — Rust Implementation
//
// Demonstrates a simple compiler backend that takes an AST of arithmetic
// expressions and generates x86_64 machine code bytes. Includes:
//   - Instruction encoding (REX prefixes, ModR/M, immediates)
//   - Stack-based expression evaluation (push/pop for temporaries)
//   - Function prologue/epilogue with proper stack alignment
//   - A fixup table for forward jump patching
//
// This is the pattern used in every native code compiler:
//   AST → instruction selection → encoding → executable bytes

use std::fmt;

// ── AST (input to codegen) ────────────────────────────────────────────────

#[derive(Debug)]
enum Expr {
    Lit(i64),
    Add(Box<Expr>, Box<Expr>),
    Sub(Box<Expr>, Box<Expr>),
    Mul(Box<Expr>, Box<Expr>),
    IfPositive {
        cond: Box<Expr>,
        then_branch: Box<Expr>,
        else_branch: Box<Expr>,
    },
}

impl fmt::Display for Expr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Expr::Lit(n) => write!(f, "{}", n),
            Expr::Add(l, r) => write!(f, "({} + {})", l, r),
            Expr::Sub(l, r) => write!(f, "({} - {})", l, r),
            Expr::Mul(l, r) => write!(f, "({} * {})", l, r),
            Expr::IfPositive { cond, then_branch, else_branch } => {
                write!(f, "(if {} > 0 then {} else {})", cond, then_branch, else_branch)
            }
        }
    }
}

// ── x86_64 Code Buffer ───────────────────────────────────────────────────

struct CodeBuffer {
    bytes: Vec<u8>,
    fixups: Vec<Fixup>,
}

struct Fixup {
    /// Offset of the 4-byte rel32 placeholder in the code buffer
    patch_offset: usize,
    /// Target offset to jump to (filled in during resolution)
    target_offset: Option<usize>,
    /// Label ID for matching
    label: usize,
}

impl CodeBuffer {
    fn new() -> Self {
        Self {
            bytes: Vec::new(),
            fixups: Vec::new(),
        }
    }

    fn len(&self) -> usize {
        self.bytes.len()
    }

    fn emit(&mut self, byte: u8) {
        self.bytes.push(byte);
    }

    fn emit_bytes(&mut self, bytes: &[u8]) {
        self.bytes.extend_from_slice(bytes);
    }

    // ── x86_64 instruction helpers ────────────────────────────────────

    /// MOV RAX, imm64 (10 bytes: REX.W + B8 + 8-byte immediate)
    fn mov_rax_imm64(&mut self, value: i64) {
        self.emit(0x48); // REX.W
        self.emit(0xB8); // MOV RAX, imm64
        self.emit_bytes(&value.to_le_bytes());
    }

    /// PUSH RAX (1 byte)
    fn push_rax(&mut self) {
        self.emit(0x50);
    }

    /// POP RCX (1 byte) — pop into RCX so RAX is free for the next result
    fn pop_rcx(&mut self) {
        self.emit(0x59);
    }

    /// ADD RAX, RCX (3 bytes: REX.W + 01 + ModR/M)
    fn add_rax_rcx(&mut self) {
        self.emit(0x48); // REX.W
        self.emit(0x01); // ADD r/m64, r64
        self.emit(0xC8); // ModR/M: mod=11, reg=RCX(001), rm=RAX(000)
    }

    /// SUB RAX, RCX — but we want RCX - RAX, so: sub rcx, rax; mov rax, rcx
    fn sub_rcx_rax_to_rax(&mut self) {
        // SUB RCX, RAX (left - right, where left was pushed first)
        self.emit(0x48);
        self.emit(0x29); // SUB r/m64, r64
        self.emit(0xC1); // ModR/M: mod=11, reg=RAX(000), rm=RCX(001)
        // MOV RAX, RCX
        self.emit(0x48);
        self.emit(0x89); // MOV r/m64, r64
        self.emit(0xC8); // ModR/M: mod=11, reg=RCX(001), rm=RAX(000)
    }

    /// IMUL RAX, RCX (4 bytes: REX.W + 0F AF + ModR/M)
    fn imul_rax_rcx(&mut self) {
        self.emit(0x48); // REX.W
        self.emit(0x0F);
        self.emit(0xAF); // IMUL r64, r/m64
        self.emit(0xC1); // ModR/M: mod=11, reg=RAX(000), rm=RCX(001)
    }

    /// TEST RAX, RAX + JLE rel32 (forward jump if not positive)
    /// Returns a fixup index for patching the jump target later.
    fn test_rax_jle_forward(&mut self, label: usize) {
        // TEST RAX, RAX (sets flags based on RAX)
        self.emit(0x48);
        self.emit(0x85); // TEST r/m64, r64
        self.emit(0xC0); // ModR/M: mod=11, reg=RAX, rm=RAX
        // JLE rel32 (jump if less or equal to zero)
        self.emit(0x0F);
        self.emit(0x8E);
        let patch_offset = self.len();
        self.emit_bytes(&0i32.to_le_bytes()); // placeholder
        self.fixups.push(Fixup {
            patch_offset,
            target_offset: None,
            label,
        });
    }

    /// JMP rel32 (unconditional forward jump)
    fn jmp_forward(&mut self, label: usize) {
        self.emit(0xE9);
        let patch_offset = self.len();
        self.emit_bytes(&0i32.to_le_bytes()); // placeholder
        self.fixups.push(Fixup {
            patch_offset,
            target_offset: None,
            label,
        });
    }

    /// Mark a label at the current position and resolve all pending fixups for it.
    fn bind_label(&mut self, label: usize) {
        let target = self.len();
        for fixup in &mut self.fixups {
            if fixup.label == label && fixup.target_offset.is_none() {
                fixup.target_offset = Some(target);
                // Patch the rel32: target - (patch_offset + 4)
                let rel = target as i32 - (fixup.patch_offset as i32 + 4);
                let bytes = rel.to_le_bytes();
                self.bytes[fixup.patch_offset] = bytes[0];
                self.bytes[fixup.patch_offset + 1] = bytes[1];
                self.bytes[fixup.patch_offset + 2] = bytes[2];
                self.bytes[fixup.patch_offset + 3] = bytes[3];
            }
        }
    }

    /// Function prologue: push rbp; mov rbp, rsp
    fn prologue(&mut self) {
        self.emit(0x55); // PUSH RBP
        self.emit(0x48);
        self.emit(0x89);
        self.emit(0xE5); // MOV RBP, RSP
    }

    /// Function epilogue: mov rsp, rbp; pop rbp; ret
    fn epilogue(&mut self) {
        self.emit(0x48);
        self.emit(0x89);
        self.emit(0xEC); // MOV RSP, RBP
        self.emit(0x5D); // POP RBP
        self.emit(0xC3); // RET
    }
}

// ── Code Generation ───────────────────────────────────────────────────────

struct Codegen {
    buf: CodeBuffer,
    next_label: usize,
}

impl Codegen {
    fn new() -> Self {
        Self {
            buf: CodeBuffer::new(),
            next_label: 0,
        }
    }

    fn fresh_label(&mut self) -> usize {
        let l = self.next_label;
        self.next_label += 1;
        l
    }

    /// Generate code for an expression. Result ends up in RAX.
    /// Uses the stack for temporaries (stack-based codegen).
    fn gen_expr(&mut self, expr: &Expr) {
        match expr {
            Expr::Lit(n) => {
                self.buf.mov_rax_imm64(*n);
            }

            Expr::Add(left, right) => {
                self.gen_expr(left);       // result in RAX
                self.buf.push_rax();       // save left on stack
                self.gen_expr(right);      // result in RAX (right)
                self.buf.pop_rcx();        // RCX = left
                self.buf.add_rax_rcx();    // RAX = left + right
            }

            Expr::Sub(left, right) => {
                self.gen_expr(left);       // RAX = left
                self.buf.push_rax();       // save left
                self.gen_expr(right);      // RAX = right
                self.buf.pop_rcx();        // RCX = left
                self.buf.sub_rcx_rax_to_rax(); // RAX = left - right
            }

            Expr::Mul(left, right) => {
                self.gen_expr(left);
                self.buf.push_rax();
                self.gen_expr(right);
                self.buf.pop_rcx();        // RCX = left, RAX = right
                self.buf.imul_rax_rcx();   // RAX = left * right
            }

            Expr::IfPositive { cond, then_branch, else_branch } => {
                let else_label = self.fresh_label();
                let end_label = self.fresh_label();

                self.gen_expr(cond);
                self.buf.test_rax_jle_forward(else_label);

                // Then branch
                self.gen_expr(then_branch);
                self.buf.jmp_forward(end_label);

                // Else branch
                self.buf.bind_label(else_label);
                self.gen_expr(else_branch);

                // End
                self.buf.bind_label(end_label);
            }
        }
    }

    /// Generate a complete function that evaluates the expression and returns the result in RAX.
    fn compile(mut self, expr: &Expr) -> Vec<u8> {
        self.buf.prologue();
        self.gen_expr(expr);
        self.buf.epilogue();
        self.buf.bytes
    }
}

// ── Simple interpreter for verification ───────────────────────────────────

fn eval(expr: &Expr) -> i64 {
    match expr {
        Expr::Lit(n) => *n,
        Expr::Add(l, r) => eval(l) + eval(r),
        Expr::Sub(l, r) => eval(l) - eval(r),
        Expr::Mul(l, r) => eval(l) * eval(r),
        Expr::IfPositive { cond, then_branch, else_branch } => {
            if eval(cond) > 0 {
                eval(then_branch)
            } else {
                eval(else_branch)
            }
        }
    }
}

fn main() {
    let tests: Vec<(&str, Expr)> = vec![
        ("42", Expr::Lit(42)),
        (
            "10 + 32",
            Expr::Add(Box::new(Expr::Lit(10)), Box::new(Expr::Lit(32))),
        ),
        (
            "(2 + 3) * 4",
            Expr::Mul(
                Box::new(Expr::Add(Box::new(Expr::Lit(2)), Box::new(Expr::Lit(3)))),
                Box::new(Expr::Lit(4)),
            ),
        ),
        (
            "10 - 3 - 2",
            Expr::Sub(
                Box::new(Expr::Sub(Box::new(Expr::Lit(10)), Box::new(Expr::Lit(3)))),
                Box::new(Expr::Lit(2)),
            ),
        ),
        (
            "if 1>0 then 100 else 200",
            Expr::IfPositive {
                cond: Box::new(Expr::Lit(1)),
                then_branch: Box::new(Expr::Lit(100)),
                else_branch: Box::new(Expr::Lit(200)),
            },
        ),
        (
            "if -1>0 then 100 else 200",
            Expr::IfPositive {
                cond: Box::new(Expr::Lit(-1)),
                then_branch: Box::new(Expr::Lit(100)),
                else_branch: Box::new(Expr::Lit(200)),
            },
        ),
    ];

    println!("Code Generation — x86_64 machine code emission:");
    println!("{:<30} {:>8} {:>10}", "Expression", "Result", "Code size");
    println!("{}", "-".repeat(55));

    for (label, expr) in &tests {
        let expected = eval(expr);
        let code = Codegen::new().compile(expr);

        println!(
            "{:<30} {:>8} {:>7} bytes",
            label,
            expected,
            code.len(),
        );

        // Show first few bytes of generated code
        let preview: Vec<String> = code.iter().take(16).map(|b| format!("{:02X}", b)).collect();
        let suffix = if code.len() > 16 { "..." } else { "" };
        println!("  code: {}{}", preview.join(" "), suffix);
    }

    println!("\nKey patterns demonstrated:");
    println!("  - Stack-based expression evaluation (push/pop temporaries)");
    println!("  - Proper function prologue/epilogue (push rbp, mov rbp rsp)");
    println!("  - Forward jump patching with fixup table (if/else)");
    println!("  - REX.W prefix for 64-bit operations");
    println!("  - Two-operand IMUL (avoids RDX clobber)");
}
