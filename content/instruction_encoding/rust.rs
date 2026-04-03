// Instruction Encoding — Rust Implementation
//
// Demonstrates x86_64 instruction encoding:
//   1. REX prefix construction (W, R, X, B bits)
//   2. ModR/M byte encoding (mod, reg, r/m fields)
//   3. SIB byte encoding (scale, index, base)
//   4. Complete instruction encoding for common instructions
//   5. Special cases: RBP/R13, RSP/R12, RIP-relative
//
// This is what an assembler does: convert mnemonics to bytes.
// Every byte decision here maps directly to the Intel manual.

use std::fmt;

// ── Register definitions ──────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq)]
#[allow(dead_code)]
enum Reg64 {
    RAX = 0, RCX = 1, RDX = 2, RBX = 3,
    RSP = 4, RBP = 5, RSI = 6, RDI = 7,
    R8 = 8, R9 = 9, R10 = 10, R11 = 11,
    R12 = 12, R13 = 13, R14 = 14, R15 = 15,
}

impl Reg64 {
    /// Low 3 bits (for ModR/M and SIB encoding).
    fn low3(self) -> u8 {
        (self as u8) & 0x7
    }

    /// Whether this register needs REX.R/REX.B (is R8-R15).
    fn needs_rex_ext(self) -> bool {
        (self as u8) >= 8
    }

    fn name(self) -> &'static str {
        match self {
            Self::RAX => "rax", Self::RCX => "rcx", Self::RDX => "rdx", Self::RBX => "rbx",
            Self::RSP => "rsp", Self::RBP => "rbp", Self::RSI => "rsi", Self::RDI => "rdi",
            Self::R8 => "r8", Self::R9 => "r9", Self::R10 => "r10", Self::R11 => "r11",
            Self::R12 => "r12", Self::R13 => "r13", Self::R14 => "r14", Self::R15 => "r15",
        }
    }
}

// ── Instruction Encoder ───────────────────────────────────────────────────

struct Encoder {
    bytes: Vec<u8>,
}

impl Encoder {
    fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    fn emit(&mut self, byte: u8) {
        self.bytes.push(byte);
    }

    fn emit_bytes(&mut self, bytes: &[u8]) {
        self.bytes.extend_from_slice(bytes);
    }

    fn clear(&mut self) {
        self.bytes.clear();
    }

    // ── REX prefix ────────────────────────────────────────────────────

    /// Build REX byte: 0100WRXB
    ///  W = 64-bit operand size
    ///  R = extends ModR/M.reg (for R8-R15)
    ///  X = extends SIB.index
    ///  B = extends ModR/M.r/m or SIB.base
    fn rex(w: bool, r: bool, x: bool, b: bool) -> u8 {
        0x40
            | if w { 0x08 } else { 0 }
            | if r { 0x04 } else { 0 }
            | if x { 0x02 } else { 0 }
            | if b { 0x01 } else { 0 }
    }

    // ── ModR/M byte ───────────────────────────────────────────────────

    /// Build ModR/M byte: [mod(2)][reg(3)][r/m(3)]
    fn modrm(mode: u8, reg: u8, rm: u8) -> u8 {
        ((mode & 0x3) << 6) | ((reg & 0x7) << 3) | (rm & 0x7)
    }

    // ── SIB byte ──────────────────────────────────────────────────────

    /// Build SIB byte: [scale(2)][index(3)][base(3)]
    fn sib(scale: u8, index: u8, base: u8) -> u8 {
        ((scale & 0x3) << 6) | ((index & 0x7) << 3) | (base & 0x7)
    }

    // ── Instruction encoders ──────────────────────────────────────────

    /// MOV r64, r64 (register to register)
    fn mov_reg_reg(&mut self, dst: Reg64, src: Reg64) {
        // REX.W prefix (always needed for 64-bit)
        // + REX.R if src is extended, REX.B if dst is extended
        self.emit(Self::rex(true, src.needs_rex_ext(), false, dst.needs_rex_ext()));
        self.emit(0x89); // MOV r/m64, r64
        self.emit(Self::modrm(0b11, src.low3(), dst.low3()));
    }

    /// MOV r64, imm64 (load 64-bit immediate)
    fn mov_reg_imm64(&mut self, dst: Reg64, imm: i64) {
        self.emit(Self::rex(true, false, false, dst.needs_rex_ext()));
        self.emit(0xB8 + dst.low3()); // MOV r64, imm64 (opcode + rd)
        self.emit_bytes(&imm.to_le_bytes());
    }

    /// ADD r64, r64
    fn add_reg_reg(&mut self, dst: Reg64, src: Reg64) {
        self.emit(Self::rex(true, src.needs_rex_ext(), false, dst.needs_rex_ext()));
        self.emit(0x01); // ADD r/m64, r64
        self.emit(Self::modrm(0b11, src.low3(), dst.low3()));
    }

    /// ADD r64, imm8 (sign-extended)
    fn add_reg_imm8(&mut self, dst: Reg64, imm: i8) {
        self.emit(Self::rex(true, false, false, dst.needs_rex_ext()));
        self.emit(0x83); // ADD r/m64, imm8
        self.emit(Self::modrm(0b11, 0, dst.low3())); // /0 = ADD
        self.emit(imm as u8);
    }

    /// MOV r64, [base] (memory load, handles RBP/R13 and RSP/R12 special cases)
    fn mov_reg_mem_base(&mut self, dst: Reg64, base: Reg64) {
        self.emit(Self::rex(true, dst.needs_rex_ext(), false, base.needs_rex_ext()));
        self.emit(0x8B); // MOV r64, r/m64

        match base.low3() {
            // RBP/R13: mod=00, r/m=101 means RIP-relative, NOT [RBP]
            // Use mod=01, disp8=0 instead
            5 => {
                self.emit(Self::modrm(0b01, dst.low3(), 5));
                self.emit(0x00); // disp8 = 0
            }
            // RSP/R12: r/m=100 means "SIB follows", NOT [RSP]
            // Use SIB byte 0x24 (base=RSP, index=none)
            4 => {
                self.emit(Self::modrm(0b00, dst.low3(), 4));
                self.emit(Self::sib(0, 4, 4)); // scale=0, index=RSP(none), base=RSP
            }
            _ => {
                self.emit(Self::modrm(0b00, dst.low3(), base.low3()));
            }
        }
    }

    /// MOV r64, [base + index*scale + disp32] (full SIB addressing)
    fn mov_reg_mem_sib(&mut self, dst: Reg64, base: Reg64, index: Reg64, scale: u8, disp: i32) {
        let log_scale = match scale {
            1 => 0, 2 => 1, 4 => 2, 8 => 3,
            _ => panic!("scale must be 1, 2, 4, or 8"),
        };

        self.emit(Self::rex(
            true,
            dst.needs_rex_ext(),
            index.needs_rex_ext(),
            base.needs_rex_ext(),
        ));
        self.emit(0x8B);

        if disp == 0 && base.low3() != 5 {
            self.emit(Self::modrm(0b00, dst.low3(), 4)); // mod=00, r/m=100 (SIB follows)
        } else if disp >= -128 && disp <= 127 {
            self.emit(Self::modrm(0b01, dst.low3(), 4)); // mod=01, disp8
        } else {
            self.emit(Self::modrm(0b10, dst.low3(), 4)); // mod=10, disp32
        }

        self.emit(Self::sib(log_scale, index.low3(), base.low3()));

        if disp == 0 && base.low3() != 5 {
            // no displacement
        } else if disp >= -128 && disp <= 127 {
            self.emit(disp as u8);
        } else {
            self.emit_bytes(&disp.to_le_bytes());
        }
    }

    /// CALL rel32 (relative call)
    fn call_rel32(&mut self, rel: i32) {
        self.emit(0xE8);
        self.emit_bytes(&rel.to_le_bytes());
    }

    /// SYSCALL
    fn syscall(&mut self) {
        self.emit(0x0F);
        self.emit(0x05);
    }

    /// RET
    fn ret(&mut self) {
        self.emit(0xC3);
    }
}

impl fmt::Display for Encoder {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (i, byte) in self.bytes.iter().enumerate() {
            if i > 0 {
                write!(f, " ")?;
            }
            write!(f, "{:02X}", byte)?;
        }
        Ok(())
    }
}

// ── Demo ──────────────────────────────────────────────────────────────────

fn show(enc: &mut Encoder, mnemonic: &str) {
    println!("  {:<45} → {}", mnemonic, enc);
    enc.clear();
}

fn main() {
    println!("Instruction Encoding — x86_64 machine code generation:\n");
    let mut enc = Encoder::new();

    // ── Register-register operations ──────────────────────────────────
    println!("1. Register-register (ModR/M mod=11):");
    enc.mov_reg_reg(Reg64::RAX, Reg64::RBX);
    show(&mut enc, "mov rax, rbx");

    enc.mov_reg_reg(Reg64::R8, Reg64::R15);
    show(&mut enc, "mov r8, r15  (REX.R + REX.B for extended regs)");

    enc.add_reg_reg(Reg64::RCX, Reg64::RDX);
    show(&mut enc, "add rcx, rdx");

    // ── Immediates ────────────────────────────────────────────────────
    println!("\n2. Immediate operands:");
    enc.mov_reg_imm64(Reg64::RAX, 0x400078);
    show(&mut enc, "mov rax, 0x400078  (imm64, 10 bytes)");

    enc.add_reg_imm8(Reg64::RSP, -8);
    show(&mut enc, "add rsp, -8  (imm8 sign-extended, 4 bytes)");

    enc.add_reg_imm8(Reg64::R12, 16);
    show(&mut enc, "add r12, 16  (imm8, REX.B for R12)");

    // ── Memory addressing: special cases ──────────────────────────────
    println!("\n3. Memory addressing special cases:");

    enc.mov_reg_mem_base(Reg64::RAX, Reg64::RCX);
    show(&mut enc, "mov rax, [rcx]  (normal base)");

    enc.mov_reg_mem_base(Reg64::RAX, Reg64::RBP);
    show(&mut enc, "mov rax, [rbp]  (needs mod=01, disp8=0)");

    enc.mov_reg_mem_base(Reg64::RAX, Reg64::RSP);
    show(&mut enc, "mov rax, [rsp]  (needs SIB byte 0x24)");

    enc.mov_reg_mem_base(Reg64::RAX, Reg64::R13);
    show(&mut enc, "mov rax, [r13]  (R13 = same encoding as RBP)");

    enc.mov_reg_mem_base(Reg64::RAX, Reg64::R12);
    show(&mut enc, "mov rax, [r12]  (R12 = same encoding as RSP)");

    // ── SIB addressing ────────────────────────────────────────────────
    println!("\n4. SIB addressing [base + index*scale + disp]:");

    enc.mov_reg_mem_sib(Reg64::RAX, Reg64::RBX, Reg64::RCX, 8, 0);
    show(&mut enc, "mov rax, [rbx + rcx*8]");

    enc.mov_reg_mem_sib(Reg64::RAX, Reg64::RBX, Reg64::RCX, 4, 16);
    show(&mut enc, "mov rax, [rbx + rcx*4 + 16]  (disp8)");

    enc.mov_reg_mem_sib(Reg64::R8, Reg64::R9, Reg64::R10, 2, 0x1000);
    show(&mut enc, "mov r8, [r9 + r10*2 + 0x1000]  (extended + disp32)");

    // ── Control flow ──────────────────────────────────────────────────
    println!("\n5. Control flow:");
    enc.call_rel32(0x100);
    show(&mut enc, "call +0x100  (rel32)");

    enc.call_rel32(-0x50);
    show(&mut enc, "call -0x50  (backward call)");

    enc.syscall();
    show(&mut enc, "syscall  (0F 05)");

    enc.ret();
    show(&mut enc, "ret  (C3)");

    // ── Encoding anatomy ──────────────────────────────────────────────
    println!("\n6. Encoding anatomy — mov rax, [rbx + rcx*8 + 16]:");
    println!("   REX.W   = 0x48  (W=1: 64-bit operand)");
    println!("   Opcode  = 0x8B  (MOV r64, r/m64)");
    println!("   ModR/M  = 0x44  (mod=01, reg=RAX(000), r/m=100(SIB))");
    println!("   SIB     = 0xCB  (scale=8(11), index=RCX(001), base=RBX(011))");
    println!("   Disp8   = 0x10  (displacement = 16)");
    println!("   Total: 5 bytes");

    println!("\n7. Special encoding rules:");
    println!("   [RBP]  → mod=01 + disp8(0x00)  (mod=00/rm=101 = RIP-relative)");
    println!("   [RSP]  → SIB(0x24) required     (rm=100 = 'SIB follows')");
    println!("   [R13]  → same as [RBP]           (low 3 bits = 101)");
    println!("   [R12]  → same as [RSP]           (low 3 bits = 100)");
    println!("   REX.B extends r/m field for R8-R15");
    println!("   REX.R extends reg field for R8-R15");
    println!("   REX.X extends SIB index field for R8-R15");
}
