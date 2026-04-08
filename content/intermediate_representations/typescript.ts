// Vidya — Intermediate Representations in TypeScript
//
// Demonstrates the core IR concepts that sit between parsing and codegen:
//   1. Three-Address Code (TAC): simple instructions with at most 3 operands
//   2. Basic Blocks: maximal sequences of straight-line instructions
//   3. SSA form with phi nodes: every variable assigned exactly once
//
// IRs decouple frontend from backend. M languages × N targets becomes
// M frontends + N backends through a shared IR. SSA makes dataflow
// analysis trivial because every use has exactly one reaching definition.
//
// TypeScript idioms: discriminated unions for IR operations,
// generics for the block graph, type guards for instruction filtering.

// ── Three-Address Code (TAC) ─────────────────────────────────────────
// Each instruction has at most one operation, two sources, one destination.
// This is the simplest useful IR — close to assembly but machine-independent.

type Operand =
    | { kind: "const"; value: number }
    | { kind: "var"; name: string }
    | { kind: "temp"; id: number };

type TACOp =
    | { kind: "assign"; dst: Operand; src: Operand }
    | { kind: "binop"; dst: Operand; op: "+" | "-" | "*" | "/"; left: Operand; right: Operand }
    | { kind: "jump"; target: string }
    | { kind: "cjump"; cond: Operand; ifTrue: string; ifFalse: string }
    | { kind: "label"; name: string }
    | { kind: "return"; value: Operand }
    | { kind: "phi"; dst: Operand; sources: Array<{ value: Operand; block: string }> };

// Type guard: is this a branching instruction?
function isTerminator(op: TACOp): boolean {
    return op.kind === "jump" || op.kind === "cjump" || op.kind === "return";
}

function operandToString(o: Operand): string {
    switch (o.kind) {
        case "const": return String(o.value);
        case "var":   return o.name;
        case "temp":  return `t${o.id}`;
    }
}

function tacToString(op: TACOp): string {
    switch (op.kind) {
        case "assign":
            return `${operandToString(op.dst)} = ${operandToString(op.src)}`;
        case "binop":
            return `${operandToString(op.dst)} = ${operandToString(op.left)} ${op.op} ${operandToString(op.right)}`;
        case "jump":
            return `jump ${op.target}`;
        case "cjump":
            return `if ${operandToString(op.cond)} goto ${op.ifTrue} else ${op.ifFalse}`;
        case "label":
            return `${op.name}:`;
        case "return":
            return `return ${operandToString(op.value)}`;
        case "phi":
            const srcs = op.sources.map(s => `${operandToString(s.value)}[${s.block}]`).join(", ");
            return `${operandToString(op.dst)} = phi(${srcs})`;
    }
}

// ── Basic Blocks ─────────────────────────────────────────────────────
// A basic block is a maximal sequence of instructions with:
//   - One entry point (the first instruction)
//   - One exit point (the last instruction — a terminator)
// No jumps in the middle, no labels except at the start.

interface BasicBlock {
    label: string;
    instructions: TACOp[];
    successors: string[];
}

function buildBasicBlocks(instructions: TACOp[]): BasicBlock[] {
    const blocks: BasicBlock[] = [];
    let current: TACOp[] = [];
    let currentLabel = "entry";

    for (const instr of instructions) {
        if (instr.kind === "label") {
            // End the current block (if it has instructions)
            if (current.length > 0) {
                blocks.push(finishBlock(currentLabel, current, instr.name));
                current = [];
            }
            currentLabel = instr.name;
        } else {
            current.push(instr);
            if (isTerminator(instr)) {
                blocks.push(finishBlock(currentLabel, current));
                current = [];
                currentLabel = `block_${blocks.length}`;
            }
        }
    }

    if (current.length > 0) {
        blocks.push(finishBlock(currentLabel, current));
    }

    return blocks;
}

function finishBlock(label: string, instrs: TACOp[], fallthrough?: string): BasicBlock {
    const last = instrs[instrs.length - 1];
    let successors: string[] = [];

    if (last) {
        switch (last.kind) {
            case "jump":
                successors = [last.target];
                break;
            case "cjump":
                successors = [last.ifTrue, last.ifFalse];
                break;
            case "return":
                successors = [];
                break;
            default:
                if (fallthrough) successors = [fallthrough];
                break;
        }
    }

    return { label, instructions: instrs, successors };
}

// ── SSA Construction ─────────────────────────────────────────────────
// Convert a sequence of assignments into SSA form.
// In SSA, every variable is assigned exactly once. When control flow
// merges (e.g., after an if/else), phi nodes select the right version.
//
// We demonstrate a simple renaming pass for straight-line code,
// and explicit phi node construction for merge points.

class SSABuilder {
    private versions: Map<string, number> = new Map();
    private nextTemp: number = 0;

    // Get current version of a variable
    private currentVersion(name: string): string {
        const v = this.versions.get(name) ?? 0;
        return `${name}_${v}`;
    }

    // Bump version for a new definition
    private newVersion(name: string): string {
        const v = (this.versions.get(name) ?? -1) + 1;
        this.versions.set(name, v);
        return `${name}_${v}`;
    }

    // Rename a straight-line block into SSA
    renameBlock(instrs: TACOp[]): TACOp[] {
        const result: TACOp[] = [];

        for (const instr of instrs) {
            switch (instr.kind) {
                case "assign": {
                    const src = this.renameOperand(instr.src);
                    const dstName = this.operandName(instr.dst);
                    const newName = this.newVersion(dstName);
                    result.push({
                        kind: "assign",
                        dst: { kind: "var", name: newName },
                        src,
                    });
                    break;
                }
                case "binop": {
                    const left = this.renameOperand(instr.left);
                    const right = this.renameOperand(instr.right);
                    const dstName = this.operandName(instr.dst);
                    const newName = this.newVersion(dstName);
                    result.push({
                        kind: "binop",
                        dst: { kind: "var", name: newName },
                        op: instr.op,
                        left,
                        right,
                    });
                    break;
                }
                case "return": {
                    const value = this.renameOperand(instr.value);
                    result.push({ kind: "return", value });
                    break;
                }
                default:
                    result.push(instr);
                    break;
            }
        }

        return result;
    }

    // Build a phi node for a variable at a merge point
    buildPhi(varName: string, incomingBlocks: Array<{ block: string; version: number }>): TACOp {
        const dstVersion = this.newVersion(varName);
        return {
            kind: "phi",
            dst: { kind: "var", name: dstVersion },
            sources: incomingBlocks.map(ib => ({
                value: { kind: "var", name: `${varName}_${ib.version}` },
                block: ib.block,
            })),
        };
    }

    private renameOperand(op: Operand): Operand {
        if (op.kind === "var") {
            return { kind: "var", name: this.currentVersion(op.name) };
        }
        return op;
    }

    private operandName(op: Operand): string {
        switch (op.kind) {
            case "var":  return op.name;
            case "temp": return `t${op.id}`;
            case "const": return `c${op.value}`;
        }
    }
}

// ── Tests ────────────────────────────────────────────────────────────

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function testTACCreation(): void {
    // x = 3 + 4
    // y = x * 2
    // return y
    const instrs: TACOp[] = [
        { kind: "binop", dst: { kind: "var", name: "x" }, op: "+",
          left: { kind: "const", value: 3 }, right: { kind: "const", value: 4 } },
        { kind: "binop", dst: { kind: "var", name: "y" }, op: "*",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 2 } },
        { kind: "return", value: { kind: "var", name: "y" } },
    ];

    assert(instrs.length === 3, "three instructions");
    assert(tacToString(instrs[0]) === "x = 3 + 4", "TAC string for binop");
    assert(tacToString(instrs[2]) === "return y", "TAC string for return");
}

function testBasicBlockConstruction(): void {
    const instrs: TACOp[] = [
        { kind: "binop", dst: { kind: "var", name: "x" }, op: "+",
          left: { kind: "const", value: 1 }, right: { kind: "const", value: 2 } },
        { kind: "cjump", cond: { kind: "var", name: "x" },
          ifTrue: "then", ifFalse: "else" },
        { kind: "label", name: "then" },
        { kind: "assign", dst: { kind: "var", name: "y" }, src: { kind: "const", value: 10 } },
        { kind: "jump", target: "end" },
        { kind: "label", name: "else" },
        { kind: "assign", dst: { kind: "var", name: "y" }, src: { kind: "const", value: 20 } },
        { kind: "jump", target: "end" },
        { kind: "label", name: "end" },
        { kind: "return", value: { kind: "var", name: "y" } },
    ];

    const blocks = buildBasicBlocks(instrs);

    assert(blocks.length === 4, `expected 4 blocks, got ${blocks.length}`);
    assert(blocks[0].label === "entry", "first block is entry");
    assert(blocks[0].successors.length === 2, "entry has two successors");
    assert(blocks[0].successors.includes("then"), "entry -> then");
    assert(blocks[0].successors.includes("else"), "entry -> else");

    assert(blocks[1].label === "then", "second block is then");
    assert(blocks[1].successors[0] === "end", "then -> end");

    assert(blocks[2].label === "else", "third block is else");
    assert(blocks[2].successors[0] === "end", "else -> end");

    assert(blocks[3].label === "end", "fourth block is end");
    assert(blocks[3].successors.length === 0, "end has no successors (return)");
}

function testSSARenaming(): void {
    // x = 1
    // x = x + 2
    // x = x * 3
    // return x
    const instrs: TACOp[] = [
        { kind: "assign", dst: { kind: "var", name: "x" }, src: { kind: "const", value: 1 } },
        { kind: "binop", dst: { kind: "var", name: "x" }, op: "+",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 2 } },
        { kind: "binop", dst: { kind: "var", name: "x" }, op: "*",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 3 } },
        { kind: "return", value: { kind: "var", name: "x" } },
    ];

    const ssa = new SSABuilder();
    const renamed = ssa.renameBlock(instrs);

    // Each assignment to x gets a new version
    assert(tacToString(renamed[0]) === "x_0 = 1", "first def is x_0");
    assert(tacToString(renamed[1]) === "x_1 = x_0 + 2", "second def is x_1, uses x_0");
    assert(tacToString(renamed[2]) === "x_2 = x_1 * 3", "third def is x_2, uses x_1");
    assert(tacToString(renamed[3]) === "return x_2", "return uses x_2");
}

function testPhiNode(): void {
    // After if/else merge, y could be y_0 (from "then") or y_1 (from "else")
    const ssa = new SSABuilder();
    const phi = ssa.buildPhi("y", [
        { block: "then", version: 0 },
        { block: "else", version: 1 },
    ]);

    assert(phi.kind === "phi", "should create phi node");
    const phiStr = tacToString(phi);
    assert(phiStr.includes("phi("), "should format as phi");
    assert(phiStr.includes("y_0[then]"), "should reference y_0 from then");
    assert(phiStr.includes("y_1[else]"), "should reference y_1 from else");
}

function testTerminatorDetection(): void {
    assert(isTerminator({ kind: "jump", target: "L1" }), "jump is terminator");
    assert(isTerminator({ kind: "cjump", cond: { kind: "const", value: 1 },
        ifTrue: "L1", ifFalse: "L2" }), "cjump is terminator");
    assert(isTerminator({ kind: "return", value: { kind: "const", value: 0 } }),
        "return is terminator");
    assert(!isTerminator({ kind: "assign", dst: { kind: "var", name: "x" },
        src: { kind: "const", value: 1 } }), "assign is not terminator");
}

function testBlockSuccessors(): void {
    // Single block with return — no successors
    const instrs: TACOp[] = [
        { kind: "assign", dst: { kind: "var", name: "x" }, src: { kind: "const", value: 42 } },
        { kind: "return", value: { kind: "var", name: "x" } },
    ];
    const blocks = buildBasicBlocks(instrs);
    assert(blocks.length === 1, "single block");
    assert(blocks[0].successors.length === 0, "return block has no successors");
}

function testMultipleVariablesSSA(): void {
    const instrs: TACOp[] = [
        { kind: "assign", dst: { kind: "var", name: "a" }, src: { kind: "const", value: 5 } },
        { kind: "assign", dst: { kind: "var", name: "b" }, src: { kind: "const", value: 10 } },
        { kind: "binop", dst: { kind: "var", name: "c" }, op: "+",
          left: { kind: "var", name: "a" }, right: { kind: "var", name: "b" } },
        { kind: "return", value: { kind: "var", name: "c" } },
    ];

    const ssa = new SSABuilder();
    const renamed = ssa.renameBlock(instrs);

    assert(tacToString(renamed[0]) === "a_0 = 5", "a_0");
    assert(tacToString(renamed[1]) === "b_0 = 10", "b_0");
    assert(tacToString(renamed[2]) === "c_0 = a_0 + b_0", "c_0 = a_0 + b_0");
    assert(tacToString(renamed[3]) === "return c_0", "return c_0");
}

// ── Main ─────────────────────────────────────────────────────────────

function main(): void {
    testTACCreation();
    testBasicBlockConstruction();
    testSSARenaming();
    testPhiNode();
    testTerminatorDetection();
    testBlockSuccessors();
    testMultipleVariablesSSA();

    console.log("All intermediate representations tests passed.");
}

main();
