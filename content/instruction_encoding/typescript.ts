// Vidya — Instruction Encoding in TypeScript
//
// Demonstrates x86_64 machine code encoding — how assembly mnemonics
// become the actual bytes the CPU executes. This is what an assembler does.
//
// x86_64 instruction format (simplified):
//   [REX prefix] [opcode] [ModR/M] [SIB] [displacement] [immediate]
//
// REX prefix (0x40-0x4F): extends registers to 64-bit, accesses r8-r15
//   Bits: 0100 W R X B
//   W=1: 64-bit operand size
//   R: extends ModR/M reg field (access r8-r15)
//   X: extends SIB index field
//   B: extends ModR/M r/m field or SIB base
//
// ModR/M byte: [mod(2)][reg(3)][r/m(3)]
//   mod=11: register direct
//   mod=00: memory indirect [r/m]
//   mod=01: memory + disp8
//   mod=10: memory + disp32
//
// TypeScript idioms: Uint8Array for byte buffers, enum-like maps for
// register encoding, verification against known-good byte sequences.

// ── Register encoding ───────────────────────────────────────────────

// x86_64 register numbers (3-bit encoding within ModR/M)
const REG = {
    rax: 0, rcx: 1, rdx: 2, rbx: 3,
    rsp: 4, rbp: 5, rsi: 6, rdi: 7,
    // Extended registers need REX.R or REX.B
    r8: 0, r9: 1, r10: 2, r11: 3,
    r12: 4, r13: 5, r14: 6, r15: 7,
} as const;

type RegName = keyof typeof REG;

// Extended registers (r8-r15) need REX extension bits
function isExtended(reg: RegName): boolean {
    return reg.startsWith("r") && reg.length >= 2 && !isNaN(Number(reg.slice(1)));
}

// ── REX prefix builder ──────────────────────────────────────────────

function rexPrefix(w: boolean, r: boolean, x: boolean, b: boolean): number {
    let rex = 0x40;
    if (w) rex |= 0x08; // W bit: 64-bit operand
    if (r) rex |= 0x04; // R bit: extend reg field
    if (x) rex |= 0x02; // X bit: extend SIB index
    if (b) rex |= 0x01; // B bit: extend r/m or SIB base
    return rex;
}

// ── ModR/M byte builder ─────────────────────────────────────────────

function modRM(mod: number, reg: number, rm: number): number {
    return ((mod & 0x3) << 6) | ((reg & 0x7) << 3) | (rm & 0x7);
}

// ── Instruction encoder ─────────────────────────────────────────────

class X86Encoder {
    private buffer: number[] = [];

    private emit(byte: number): void {
        this.buffer.push(byte & 0xff);
    }

    private emitImm32(value: number): void {
        this.emit(value & 0xff);
        this.emit((value >> 8) & 0xff);
        this.emit((value >> 16) & 0xff);
        this.emit((value >> 24) & 0xff);
    }

    private emitImm64(value: number): void {
        // JavaScript numbers are 64-bit floats; safe for values up to 2^53
        this.emitImm32(value & 0xffffffff);
        this.emitImm32(Math.floor(value / 0x100000000) & 0xffffffff);
    }

    // MOV reg64, imm64 (REX.W + B8+rd io)
    // This is the 10-byte absolute move: movabs
    encodeMOVImm64(dst: RegName, imm: number): void {
        const dstNum = REG[dst];
        const ext = isExtended(dst);
        this.emit(rexPrefix(true, false, false, ext)); // REX.W (+ REX.B if extended)
        this.emit(0xb8 + dstNum); // B8+rd
        this.emitImm64(imm);
    }

    // MOV reg64, reg64 (REX.W + 89 /r)
    encodeMOVRegReg(dst: RegName, src: RegName): void {
        const srcNum = REG[src];
        const dstNum = REG[dst];
        this.emit(rexPrefix(true, isExtended(src), false, isExtended(dst)));
        this.emit(0x89); // MOV r/m64, r64
        this.emit(modRM(0b11, srcNum, dstNum)); // mod=11 (register direct)
    }

    // ADD reg64, reg64 (REX.W + 01 /r)
    encodeADDRegReg(dst: RegName, src: RegName): void {
        const srcNum = REG[src];
        const dstNum = REG[dst];
        this.emit(rexPrefix(true, isExtended(src), false, isExtended(dst)));
        this.emit(0x01); // ADD r/m64, r64
        this.emit(modRM(0b11, srcNum, dstNum));
    }

    // ADD reg64, imm32 (REX.W + 81 /0 id)
    encodeADDImm32(dst: RegName, imm: number): void {
        const dstNum = REG[dst];
        this.emit(rexPrefix(true, false, false, isExtended(dst)));
        this.emit(0x81);
        this.emit(modRM(0b11, 0, dstNum)); // /0 means reg field = 0
        this.emitImm32(imm);
    }

    // SUB reg64, reg64 (REX.W + 29 /r)
    encodeSUBRegReg(dst: RegName, src: RegName): void {
        const srcNum = REG[src];
        const dstNum = REG[dst];
        this.emit(rexPrefix(true, isExtended(src), false, isExtended(dst)));
        this.emit(0x29);
        this.emit(modRM(0b11, srcNum, dstNum));
    }

    // JMP rel32 (E9 cd)
    encodeJMPRel32(offset: number): void {
        this.emit(0xe9);
        this.emitImm32(offset);
    }

    // RET (C3)
    encodeRET(): void {
        this.emit(0xc3);
    }

    // NOP (90)
    encodeNOP(): void {
        this.emit(0x90);
    }

    // PUSH reg64 (50+rd, with REX.B for extended)
    encodePUSH(reg: RegName): void {
        const regNum = REG[reg];
        if (isExtended(reg)) {
            this.emit(rexPrefix(false, false, false, true));
        }
        this.emit(0x50 + regNum);
    }

    // POP reg64 (58+rd, with REX.B for extended)
    encodePOP(reg: RegName): void {
        const regNum = REG[reg];
        if (isExtended(reg)) {
            this.emit(rexPrefix(false, false, false, true));
        }
        this.emit(0x58 + regNum);
    }

    getBytes(): Uint8Array {
        return new Uint8Array(this.buffer);
    }

    reset(): void {
        this.buffer = [];
    }
}

// ── Helpers ──────────────────────────────────────────────────────────

function hexBytes(bytes: Uint8Array): string {
    return Array.from(bytes).map(b => b.toString(16).padStart(2, "0")).join(" ");
}

function assertBytes(actual: Uint8Array, expected: number[], msg: string): void {
    const ok = actual.length === expected.length &&
               actual.every((b, i) => b === expected[i]);
    if (!ok) {
        throw new Error(
            `Assertion failed: ${msg}\n` +
            `  expected: ${expected.map(b => b.toString(16).padStart(2, "0")).join(" ")}\n` +
            `  actual:   ${hexBytes(actual)}`
        );
    }
}

// ── Tests ────────────────────────────────────────────────────────────

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function testREXPrefix(): void {
    // REX.W (64-bit operand, no extensions)
    assert(rexPrefix(true, false, false, false) === 0x48, "REX.W = 0x48");
    // REX.WB (64-bit + extended r/m)
    assert(rexPrefix(true, false, false, true) === 0x49, "REX.WB = 0x49");
    // REX.WR (64-bit + extended reg)
    assert(rexPrefix(true, true, false, false) === 0x4c, "REX.WR = 0x4c");
    // REX.WRB
    assert(rexPrefix(true, true, false, true) === 0x4d, "REX.WRB = 0x4d");
    // Plain REX (no bits set)
    assert(rexPrefix(false, false, false, false) === 0x40, "REX = 0x40");
}

function testModRM(): void {
    // mod=11 (register), reg=rax(0), r/m=rcx(1)
    assert(modRM(0b11, 0, 1) === 0xc1, "mod=11 reg=0 rm=1");
    // mod=11, reg=rcx(1), r/m=rax(0)
    assert(modRM(0b11, 1, 0) === 0xc8, "mod=11 reg=1 rm=0");
    // mod=00, reg=rax(0), r/m=rbx(3)
    assert(modRM(0b00, 0, 3) === 0x03, "mod=00 reg=0 rm=3");
}

function testMOVRegReg(): void {
    const enc = new X86Encoder();

    // mov rax, rcx  →  48 89 c8
    // REX.W(48) + MOV(89) + ModR/M(mod=11, reg=rcx(1), r/m=rax(0))
    enc.encodeMOVRegReg("rax", "rcx");
    assertBytes(enc.getBytes(), [0x48, 0x89, 0xc8], "mov rax, rcx");

    enc.reset();

    // mov rbx, rdx  →  48 89 d3
    enc.encodeMOVRegReg("rbx", "rdx");
    assertBytes(enc.getBytes(), [0x48, 0x89, 0xd3], "mov rbx, rdx");
}

function testMOVImm64(): void {
    const enc = new X86Encoder();

    // movabs rax, 0x42  →  48 b8 42 00 00 00 00 00 00 00
    enc.encodeMOVImm64("rax", 0x42);
    const bytes = enc.getBytes();
    assert(bytes.length === 10, "movabs is 10 bytes");
    assert(bytes[0] === 0x48, "REX.W prefix");
    assert(bytes[1] === 0xb8, "B8+rax opcode");
    assert(bytes[2] === 0x42, "immediate low byte");
    // Remaining bytes should be zero for small immediate
    for (let i = 3; i < 10; i++) {
        assert(bytes[i] === 0, `byte ${i} should be 0`);
    }
}

function testADDRegReg(): void {
    const enc = new X86Encoder();

    // add rax, rcx  →  48 01 c8
    enc.encodeADDRegReg("rax", "rcx");
    assertBytes(enc.getBytes(), [0x48, 0x01, 0xc8], "add rax, rcx");
}

function testADDImm32(): void {
    const enc = new X86Encoder();

    // add rax, 0x10  →  48 81 c0 10 00 00 00
    enc.encodeADDImm32("rax", 0x10);
    assertBytes(enc.getBytes(), [0x48, 0x81, 0xc0, 0x10, 0x00, 0x00, 0x00],
        "add rax, 0x10");
}

function testSUBRegReg(): void {
    const enc = new X86Encoder();

    // sub rax, rcx  →  48 29 c8
    enc.encodeSUBRegReg("rax", "rcx");
    assertBytes(enc.getBytes(), [0x48, 0x29, 0xc8], "sub rax, rcx");
}

function testJMPRel32(): void {
    const enc = new X86Encoder();

    // jmp +0x10  →  e9 10 00 00 00
    enc.encodeJMPRel32(0x10);
    assertBytes(enc.getBytes(), [0xe9, 0x10, 0x00, 0x00, 0x00], "jmp +0x10");

    enc.reset();

    // jmp -5 (backward jump)  →  e9 fb ff ff ff
    enc.encodeJMPRel32(-5);
    assertBytes(enc.getBytes(), [0xe9, 0xfb, 0xff, 0xff, 0xff], "jmp -5");
}

function testSimpleInstructions(): void {
    const enc = new X86Encoder();

    enc.encodeRET();
    assertBytes(enc.getBytes(), [0xc3], "ret");

    enc.reset();
    enc.encodeNOP();
    assertBytes(enc.getBytes(), [0x90], "nop");
}

function testPushPop(): void {
    const enc = new X86Encoder();

    // push rax  →  50
    enc.encodePUSH("rax");
    assertBytes(enc.getBytes(), [0x50], "push rax");

    enc.reset();

    // push rbp  →  55
    enc.encodePUSH("rbp");
    assertBytes(enc.getBytes(), [0x55], "push rbp");

    enc.reset();

    // pop rax  →  58
    enc.encodePOP("rax");
    assertBytes(enc.getBytes(), [0x58], "pop rax");

    enc.reset();

    // pop rbp  →  5d
    enc.encodePOP("rbp");
    assertBytes(enc.getBytes(), [0x5d], "pop rbp");
}

function testExtendedRegisters(): void {
    const enc = new X86Encoder();

    // push r8  →  41 50  (REX.B + 50+r8)
    enc.encodePUSH("r8");
    assertBytes(enc.getBytes(), [0x41, 0x50], "push r8");

    enc.reset();

    // pop r15  →  41 5f  (REX.B + 58+r15)
    enc.encodePOP("r15");
    assertBytes(enc.getBytes(), [0x41, 0x5f], "pop r15");
}

function testFunctionPrologue(): void {
    // Standard x86_64 function prologue:
    //   push rbp       → 55
    //   mov rbp, rsp   → 48 89 e5
    //   sub rsp, 0x20  → 48 81 ec 20 00 00 00
    const enc = new X86Encoder();
    enc.encodePUSH("rbp");
    enc.encodeMOVRegReg("rbp", "rsp");
    enc.encodeSUBRegReg("rsp", "rax"); // simplified — real would use sub imm
    enc.encodeRET();

    const bytes = enc.getBytes();
    assert(bytes[0] === 0x55, "prologue starts with push rbp");
    assert(bytes[1] === 0x48, "REX.W for mov");
    assert(bytes[bytes.length - 1] === 0xc3, "ends with ret");
}

// ── Main ─────────────────────────────────────────────────────────────

function main(): void {
    testREXPrefix();
    testModRM();
    testMOVRegReg();
    testMOVImm64();
    testADDRegReg();
    testADDImm32();
    testSUBRegReg();
    testJMPRel32();
    testSimpleInstructions();
    testPushPop();
    testExtendedRegisters();
    testFunctionPrologue();

    console.log("All instruction encoding tests passed.");
}

main();
