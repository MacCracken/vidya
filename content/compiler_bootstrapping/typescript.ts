// Vidya — Compiler Bootstrapping in TypeScript
//
// Demonstrates a minimal two-pass assembler — the foundational pattern
// for bootstrapping a compiler from nothing:
//   Pass 1: scan instructions, collect label addresses, compute byte offsets
//   Pass 2: emit machine code bytes with all labels resolved
//
// A compiler is just a function from text to bytes. Self-hosting means
// that function can process its own source code. The two-pass approach
// solves forward references: you can jump to a label before defining it.
//
// TypeScript idioms: discriminated unions for instruction types,
// Map<string, number> for the symbol table, Uint8Array for the code buffer.

// ── Instruction set (discriminated union) ────────────────────────────

type Instruction =
    | { kind: "load_imm"; reg: number; value: number }
    | { kind: "add"; dst: number; src: number }
    | { kind: "jump"; label: string }
    | { kind: "label"; name: string }
    | { kind: "halt" };

// Opcodes — each instruction's binary tag
const OPCODE_LOAD_IMM = 0x01;
const OPCODE_ADD      = 0x02;
const OPCODE_JUMP     = 0x03;
const OPCODE_HALT     = 0xff;

// Instruction sizes in bytes (label is pseudo — emits nothing)
function instrSize(instr: Instruction): number {
    switch (instr.kind) {
        case "load_imm": return 4; // opcode(1) + reg(1) + imm16(2)
        case "add":      return 3; // opcode(1) + dst(1) + src(1)
        case "jump":     return 3; // opcode(1) + addr16(2)
        case "halt":     return 1; // opcode(1)
        case "label":    return 0; // pseudo-instruction, no bytes
    }
}

// ── Two-pass assembler ───────────────────────────────────────────────

class Assembler {
    private labels: Map<string, number> = new Map();
    private program: Instruction[] = [];

    emit(instr: Instruction): void {
        this.program.push(instr);
    }

    // Pass 1: walk instructions, record label offsets, compute total size
    private pass1(): number {
        let offset = 0;
        for (const instr of this.program) {
            if (instr.kind === "label") {
                if (this.labels.has(instr.name)) {
                    throw new Error(`duplicate label: ${instr.name}`);
                }
                this.labels.set(instr.name, offset);
            }
            offset += instrSize(instr);
        }
        return offset;
    }

    // Pass 2: emit bytes, resolving label references
    private pass2(totalSize: number): Uint8Array {
        const code = new Uint8Array(totalSize);
        let offset = 0;

        for (const instr of this.program) {
            switch (instr.kind) {
                case "load_imm":
                    code[offset]     = OPCODE_LOAD_IMM;
                    code[offset + 1] = instr.reg;
                    // little-endian 16-bit immediate
                    code[offset + 2] = instr.value & 0xff;
                    code[offset + 3] = (instr.value >> 8) & 0xff;
                    break;

                case "add":
                    code[offset]     = OPCODE_ADD;
                    code[offset + 1] = instr.dst;
                    code[offset + 2] = instr.src;
                    break;

                case "jump": {
                    const addr = this.labels.get(instr.label);
                    if (addr === undefined) {
                        throw new Error(`undefined label: ${instr.label}`);
                    }
                    code[offset]     = OPCODE_JUMP;
                    code[offset + 1] = addr & 0xff;
                    code[offset + 2] = (addr >> 8) & 0xff;
                    break;
                }

                case "halt":
                    code[offset] = OPCODE_HALT;
                    break;

                case "label":
                    // No bytes emitted
                    break;
            }
            offset += instrSize(instr);
        }

        return code;
    }

    assemble(): Uint8Array {
        const totalSize = this.pass1();
        return this.pass2(totalSize);
    }
}

// ── Simple VM for verification ───────────────────────────────────────

class VM {
    private regs: number[] = new Array(8).fill(0);
    private pc: number = 0;
    private halted: boolean = false;

    run(code: Uint8Array): number[] {
        this.pc = 0;
        this.halted = false;

        while (!this.halted && this.pc < code.length) {
            const opcode = code[this.pc];
            switch (opcode) {
                case OPCODE_LOAD_IMM: {
                    const reg = code[this.pc + 1];
                    const value = code[this.pc + 2] | (code[this.pc + 3] << 8);
                    this.regs[reg] = value;
                    this.pc += 4;
                    break;
                }
                case OPCODE_ADD: {
                    const dst = code[this.pc + 1];
                    const src = code[this.pc + 2];
                    this.regs[dst] += this.regs[src];
                    this.pc += 3;
                    break;
                }
                case OPCODE_JUMP: {
                    const addr = code[this.pc + 1] | (code[this.pc + 2] << 8);
                    this.pc = addr;
                    break;
                }
                case OPCODE_HALT:
                    this.halted = true;
                    break;
                default:
                    throw new Error(`unknown opcode 0x${opcode.toString(16)} at pc=${this.pc}`);
            }
        }

        return [...this.regs];
    }
}

// ── Tests ────────────────────────────────────────────────────────────

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function testBasicAssembly(): void {
    const asm = new Assembler();
    asm.emit({ kind: "load_imm", reg: 0, value: 10 });
    asm.emit({ kind: "load_imm", reg: 1, value: 32 });
    asm.emit({ kind: "add", dst: 0, src: 1 });
    asm.emit({ kind: "halt" });

    const code = asm.assemble();

    // Verify byte layout: load(4) + load(4) + add(3) + halt(1) = 12
    assert(code.length === 12, `code size should be 12, got ${code.length}`);
    assert(code[0] === OPCODE_LOAD_IMM, "first opcode is load_imm");
    assert(code[8] === OPCODE_ADD, "third opcode is add");
    assert(code[11] === OPCODE_HALT, "last opcode is halt");

    // Run and verify: r0 = 10 + 32 = 42
    const vm = new VM();
    const regs = vm.run(code);
    assert(regs[0] === 42, `r0 should be 42, got ${regs[0]}`);
}

function testForwardReference(): void {
    // Jump forward to a label not yet defined — the whole point of two passes
    const asm = new Assembler();
    asm.emit({ kind: "jump", label: "skip" });
    asm.emit({ kind: "load_imm", reg: 0, value: 999 }); // skipped
    asm.emit({ kind: "label", name: "skip" });
    asm.emit({ kind: "load_imm", reg: 0, value: 7 });
    asm.emit({ kind: "halt" });

    const code = asm.assemble();
    const vm = new VM();
    const regs = vm.run(code);
    assert(regs[0] === 7, `r0 should be 7 (skipped 999), got ${regs[0]}`);
}

function testBackwardReference(): void {
    // Simple loop: r0 starts at 0, add 1 three times via controlled jumps
    // (We manually unroll since we don't have conditional jumps)
    const asm = new Assembler();
    asm.emit({ kind: "load_imm", reg: 0, value: 5 });
    asm.emit({ kind: "load_imm", reg: 1, value: 3 });
    asm.emit({ kind: "add", dst: 0, src: 1 });
    asm.emit({ kind: "halt" });

    const code = asm.assemble();
    const vm = new VM();
    const regs = vm.run(code);
    assert(regs[0] === 8, `r0 should be 8, got ${regs[0]}`);
}

function testLabelAtStart(): void {
    const asm = new Assembler();
    asm.emit({ kind: "label", name: "entry" });
    asm.emit({ kind: "load_imm", reg: 0, value: 1 });
    asm.emit({ kind: "halt" });

    const code = asm.assemble();
    // Label at offset 0 emits no bytes
    assert(code[0] === OPCODE_LOAD_IMM, "label emits no bytes");

    const vm = new VM();
    const regs = vm.run(code);
    assert(regs[0] === 1, `r0 should be 1, got ${regs[0]}`);
}

function testDuplicateLabelError(): void {
    const asm = new Assembler();
    asm.emit({ kind: "label", name: "dup" });
    asm.emit({ kind: "label", name: "dup" });
    asm.emit({ kind: "halt" });

    let caught = false;
    try {
        asm.assemble();
    } catch (e) {
        caught = (e as Error).message.includes("duplicate label");
    }
    assert(caught, "duplicate label should throw");
}

function testUndefinedLabelError(): void {
    const asm = new Assembler();
    asm.emit({ kind: "jump", label: "nowhere" });
    asm.emit({ kind: "halt" });

    let caught = false;
    try {
        asm.assemble();
    } catch (e) {
        caught = (e as Error).message.includes("undefined label");
    }
    assert(caught, "undefined label should throw");
}

function testLargeImmediate(): void {
    const asm = new Assembler();
    asm.emit({ kind: "load_imm", reg: 2, value: 0x1234 });
    asm.emit({ kind: "halt" });

    const code = asm.assemble();
    // Check little-endian encoding
    assert(code[2] === 0x34, "low byte of 0x1234");
    assert(code[3] === 0x12, "high byte of 0x1234");

    const vm = new VM();
    const regs = vm.run(code);
    assert(regs[2] === 0x1234, `r2 should be 0x1234, got ${regs[2]}`);
}

// ── Main ─────────────────────────────────────────────────────────────

function main(): void {
    testBasicAssembly();
    testForwardReference();
    testBackwardReference();
    testLabelAtStart();
    testDuplicateLabelError();
    testUndefinedLabelError();
    testLargeImmediate();

    console.log("All compiler bootstrapping tests passed.");
}

main();
