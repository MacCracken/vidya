// Vidya — Optimization Passes in TypeScript
//
// Demonstrates three fundamental compiler optimization passes on a
// simple IR. Each pass transforms the IR without changing behavior:
//
//   1. Constant Folding: evaluate operations on known constants at
//      compile time instead of runtime (3 + 4 → 7)
//   2. Dead Code Elimination (DCE): remove instructions whose results
//      are never used — they waste cycles for nothing
//   3. Strength Reduction: replace expensive operations with cheaper
//      equivalents (x * 2 → x + x, x * 8 → x << 3)
//
// Passes compose: fold constants → eliminate dead code → reduce strength.
// The output of one feeds the next. Some passes enable others —
// folding may create new dead code, strength reduction may create
// new folding opportunities.
//
// TypeScript idioms: discriminated unions for IR, Set for liveness,
// Map for constant tracking, generic pass pipeline.

// ── IR (discriminated union) ─────────────────────────────────────────

type Operand =
    | { kind: "const"; value: number }
    | { kind: "var"; name: string };

type IRInstr =
    | { kind: "assign"; dst: string; src: Operand }
    | { kind: "binop"; dst: string; op: "+" | "-" | "*" | "/" | "<<" | ">>"; left: Operand; right: Operand }
    | { kind: "return"; value: Operand };

function operandStr(o: Operand): string {
    return o.kind === "const" ? String(o.value) : o.name;
}

function instrStr(i: IRInstr): string {
    switch (i.kind) {
        case "assign": return `${i.dst} = ${operandStr(i.src)}`;
        case "binop":  return `${i.dst} = ${operandStr(i.left)} ${i.op} ${operandStr(i.right)}`;
        case "return": return `return ${operandStr(i.value)}`;
    }
}

// ── Pass 1: Constant Folding ─────────────────────────────────────────
// If both operands of a binop are constants, compute the result now.
// Also propagate known constants through assignments.

function constantFold(instrs: IRInstr[]): IRInstr[] {
    const constants: Map<string, number> = new Map();

    function resolve(op: Operand): Operand {
        if (op.kind === "var" && constants.has(op.name)) {
            return { kind: "const", value: constants.get(op.name)! };
        }
        return op;
    }

    function evalBinop(op: string, a: number, b: number): number {
        switch (op) {
            case "+": return a + b;
            case "-": return a - b;
            case "*": return a * b;
            case "/": return Math.trunc(a / b);
            case "<<": return a << b;
            case ">>": return a >> b;
            default: throw new Error(`unknown op: ${op}`);
        }
    }

    return instrs.map((instr): IRInstr => {
        switch (instr.kind) {
            case "assign": {
                const src = resolve(instr.src);
                if (src.kind === "const") {
                    constants.set(instr.dst, src.value);
                }
                return { kind: "assign", dst: instr.dst, src };
            }
            case "binop": {
                const left = resolve(instr.left);
                const right = resolve(instr.right);
                if (left.kind === "const" && right.kind === "const") {
                    const value = evalBinop(instr.op, left.value, right.value);
                    constants.set(instr.dst, value);
                    return { kind: "assign", dst: instr.dst, src: { kind: "const", value } };
                }
                return { kind: "binop", dst: instr.dst, op: instr.op, left, right };
            }
            case "return":
                return { kind: "return", value: resolve(instr.value) };
        }
    });
}

// ── Pass 2: Dead Code Elimination ────────────────────────────────────
// Walk backwards through instructions. If a variable is never used
// after its definition, the definition is dead — remove it.

function deadCodeEliminate(instrs: IRInstr[]): IRInstr[] {
    // Collect all used variables
    const used: Set<string> = new Set();

    function markUsed(op: Operand): void {
        if (op.kind === "var") used.add(op.name);
    }

    // Walk backwards to find what's actually used
    for (let i = instrs.length - 1; i >= 0; i--) {
        const instr = instrs[i];
        switch (instr.kind) {
            case "return":
                markUsed(instr.value);
                break;
            case "assign":
                if (used.has(instr.dst)) {
                    markUsed(instr.src);
                }
                break;
            case "binop":
                if (used.has(instr.dst)) {
                    markUsed(instr.left);
                    markUsed(instr.right);
                }
                break;
        }
    }

    // Keep only instructions whose results are used (or returns)
    return instrs.filter(instr => {
        switch (instr.kind) {
            case "return": return true;
            case "assign": return used.has(instr.dst);
            case "binop":  return used.has(instr.dst);
        }
    });
}

// ── Pass 3: Strength Reduction ───────────────────────────────────────
// Replace expensive operations with cheaper equivalents:
//   x * 2   → x + x       (shift or add is cheaper than multiply)
//   x * 2^n → x << n      (shift is much cheaper than multiply)
//   x * 1   → x           (identity)
//   x * 0   → 0           (annihilation)
//   x + 0   → x           (identity)
//   x - 0   → x           (identity)

function isPowerOfTwo(n: number): boolean {
    return n > 0 && (n & (n - 1)) === 0;
}

function log2(n: number): number {
    let result = 0;
    while (n > 1) {
        n >>= 1;
        result++;
    }
    return result;
}

function strengthReduce(instrs: IRInstr[]): IRInstr[] {
    return instrs.map((instr): IRInstr => {
        if (instr.kind !== "binop") return instr;

        const { dst, op, left, right } = instr;

        // Multiply by constant
        if (op === "*") {
            // x * 0 → 0
            if (right.kind === "const" && right.value === 0) {
                return { kind: "assign", dst, src: { kind: "const", value: 0 } };
            }
            // x * 1 → x
            if (right.kind === "const" && right.value === 1) {
                return { kind: "assign", dst, src: left };
            }
            // x * 2 → x + x
            if (right.kind === "const" && right.value === 2) {
                return { kind: "binop", dst, op: "+", left, right: left };
            }
            // x * 2^n → x << n
            if (right.kind === "const" && isPowerOfTwo(right.value) && right.value > 2) {
                return { kind: "binop", dst, op: "<<", left,
                         right: { kind: "const", value: log2(right.value) } };
            }
        }

        // Addition/subtraction identities
        if (op === "+" && right.kind === "const" && right.value === 0) {
            return { kind: "assign", dst, src: left };
        }
        if (op === "-" && right.kind === "const" && right.value === 0) {
            return { kind: "assign", dst, src: left };
        }

        return instr;
    });
}

// ── Pass pipeline ────────────────────────────────────────────────────

type Pass = (instrs: IRInstr[]) => IRInstr[];

function runPipeline(instrs: IRInstr[], passes: Pass[]): IRInstr[] {
    let result = instrs;
    for (const pass of passes) {
        result = pass(result);
    }
    return result;
}

// ── Tests ────────────────────────────────────────────────────────────

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function assertIR(instrs: IRInstr[], expected: string[], label: string): void {
    const actual = instrs.map(instrStr);
    assert(actual.length === expected.length,
        `${label}: expected ${expected.length} instrs, got ${actual.length}\n` +
        `  actual: [${actual.join("; ")}]`);
    for (let i = 0; i < expected.length; i++) {
        assert(actual[i] === expected[i],
            `${label}[${i}]: expected "${expected[i]}", got "${actual[i]}"`);
    }
}

function testConstantFolding(): void {
    const input: IRInstr[] = [
        { kind: "assign", dst: "a", src: { kind: "const", value: 3 } },
        { kind: "assign", dst: "b", src: { kind: "const", value: 4 } },
        { kind: "binop", dst: "c", op: "+", left: { kind: "var", name: "a" },
          right: { kind: "var", name: "b" } },
        { kind: "return", value: { kind: "var", name: "c" } },
    ];

    const folded = constantFold(input);
    // a and b are constants, so c = 3 + 4 should fold to c = 7
    assertIR(folded, [
        "a = 3",
        "b = 4",
        "c = 7",
        "return 7",
    ], "constant folding");
}

function testChainedFolding(): void {
    const input: IRInstr[] = [
        { kind: "assign", dst: "x", src: { kind: "const", value: 10 } },
        { kind: "binop", dst: "y", op: "*", left: { kind: "var", name: "x" },
          right: { kind: "const", value: 2 } },
        { kind: "binop", dst: "z", op: "+", left: { kind: "var", name: "y" },
          right: { kind: "const", value: 5 } },
        { kind: "return", value: { kind: "var", name: "z" } },
    ];

    const folded = constantFold(input);
    // x=10, y=20, z=25 — everything folds
    assertIR(folded, [
        "x = 10",
        "y = 20",
        "z = 25",
        "return 25",
    ], "chained folding");
}

function testDCE(): void {
    const input: IRInstr[] = [
        { kind: "assign", dst: "used", src: { kind: "const", value: 42 } },
        { kind: "assign", dst: "dead", src: { kind: "const", value: 99 } },
        { kind: "binop", dst: "also_dead", op: "+",
          left: { kind: "var", name: "dead" }, right: { kind: "const", value: 1 } },
        { kind: "return", value: { kind: "var", name: "used" } },
    ];

    const optimized = deadCodeEliminate(input);
    assertIR(optimized, [
        "used = 42",
        "return used",
    ], "dead code elimination");
}

function testStrengthReduction(): void {
    const input: IRInstr[] = [
        { kind: "binop", dst: "a", op: "*",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 2 } },
        { kind: "binop", dst: "b", op: "*",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 8 } },
        { kind: "binop", dst: "c", op: "*",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 1 } },
        { kind: "binop", dst: "d", op: "*",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 0 } },
        { kind: "binop", dst: "e", op: "+",
          left: { kind: "var", name: "x" }, right: { kind: "const", value: 0 } },
        { kind: "return", value: { kind: "var", name: "a" } },
    ];

    const reduced = strengthReduce(input);
    assertIR(reduced, [
        "a = x + x",      // x * 2 → x + x
        "b = x << 3",     // x * 8 → x << 3
        "c = x",           // x * 1 → x
        "d = 0",           // x * 0 → 0
        "e = x",           // x + 0 → x
        "return a",
    ], "strength reduction");
}

function testFullPipeline(): void {
    // A program with all three optimization opportunities:
    // a = 5
    // b = 10
    // c = a + b        → constant fold to c = 15
    // d = c * 2        → fold to d = 30, then strength reduce is moot
    // dead = 999       → DCE removes this
    // return d
    const input: IRInstr[] = [
        { kind: "assign", dst: "a", src: { kind: "const", value: 5 } },
        { kind: "assign", dst: "b", src: { kind: "const", value: 10 } },
        { kind: "binop", dst: "c", op: "+",
          left: { kind: "var", name: "a" }, right: { kind: "var", name: "b" } },
        { kind: "binop", dst: "d", op: "*",
          left: { kind: "var", name: "c" }, right: { kind: "const", value: 2 } },
        { kind: "assign", dst: "dead", src: { kind: "const", value: 999 } },
        { kind: "return", value: { kind: "var", name: "d" } },
    ];

    const optimized = runPipeline(input, [
        constantFold,
        strengthReduce,
        deadCodeEliminate,
    ]);

    // After folding: a=5, b=10, c=15, d=30, dead=999, return 30
    // After strength reduce: no change (all folded to assigns)
    // After DCE: return uses constant 30 directly, so d is dead too
    assertIR(optimized, [
        "return 30",
    ], "full pipeline");
}

function testPartialFolding(): void {
    // When one operand is unknown, folding stops — but still propagates what it can
    const input: IRInstr[] = [
        { kind: "assign", dst: "known", src: { kind: "const", value: 7 } },
        { kind: "binop", dst: "result", op: "+",
          left: { kind: "var", name: "unknown" }, right: { kind: "var", name: "known" } },
        { kind: "return", value: { kind: "var", name: "result" } },
    ];

    const folded = constantFold(input);
    // "known" is propagated to 7, but unknown stays unknown
    assertIR(folded, [
        "known = 7",
        "result = unknown + 7",
        "return result",
    ], "partial folding");
}

function testPowerOfTwoStrength(): void {
    assert(isPowerOfTwo(1), "1 is 2^0");
    assert(isPowerOfTwo(2), "2 is 2^1");
    assert(isPowerOfTwo(4), "4 is 2^2");
    assert(isPowerOfTwo(1024), "1024 is 2^10");
    assert(!isPowerOfTwo(3), "3 is not power of 2");
    assert(!isPowerOfTwo(0), "0 is not power of 2");
    assert(log2(8) === 3, "log2(8) = 3");
    assert(log2(1024) === 10, "log2(1024) = 10");
}

// ── Main ─────────────────────────────────────────────────────────────

function main(): void {
    testConstantFolding();
    testChainedFolding();
    testDCE();
    testStrengthReduction();
    testFullPipeline();
    testPartialFolding();
    testPowerOfTwoStrength();

    console.log("All optimization passes tests passed.");
}

main();
