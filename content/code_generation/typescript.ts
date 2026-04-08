// Vidya — Code Generation in TypeScript
//
// Demonstrates AST-to-assembly code generation — the compiler backend.
// Takes a simple expression AST and emits x86_64-style assembly strings
// using a stack-based evaluation strategy with proper frame layout.
//
// Key concepts:
//   - Instruction selection: mapping AST nodes to machine instructions
//   - Stack-based codegen: push operands, pop for operations
//   - Function prologue/epilogue: frame pointer setup and teardown
//   - Register usage: rax as accumulator, rcx as scratch
//
// TypeScript idioms: discriminated unions for AST, generic emitter,
// class-based code generator with structured output.

// ── AST (discriminated union) ────────────────────────────────────────

type Expr =
    | { kind: "number"; value: number }
    | { kind: "var"; name: string }
    | { kind: "binop"; op: "+" | "-" | "*" | "/"; left: Expr; right: Expr }
    | { kind: "call"; name: string; args: Expr[] }
    | { kind: "let"; name: string; init: Expr; body: Expr };

type Stmt =
    | { kind: "expr_stmt"; expr: Expr }
    | { kind: "return"; expr: Expr }
    | { kind: "func_def"; name: string; params: string[]; body: Stmt[] };

// ── Code generator ───────────────────────────────────────────────────

class CodeGenerator {
    private lines: string[] = [];
    private labelCount: number = 0;
    // Map variable names to stack offsets (rbp-relative)
    private locals: Map<string, number> = new Map();
    private stackOffset: number = 0;

    private emit(line: string): void {
        this.lines.push(line);
    }

    private freshLabel(prefix: string): string {
        return `.L${prefix}_${this.labelCount++}`;
    }

    // Allocate a local variable on the stack, return its rbp offset
    private allocLocal(name: string): number {
        this.stackOffset += 8;
        const offset = -this.stackOffset;
        this.locals.set(name, offset);
        return offset;
    }

    // ── Expression codegen ───────────────────────────────────────
    // Result is always left in rax

    private genExpr(expr: Expr): void {
        switch (expr.kind) {
            case "number":
                this.emit(`    mov rax, ${expr.value}`);
                break;

            case "var": {
                const offset = this.locals.get(expr.name);
                if (offset === undefined) {
                    throw new Error(`undefined variable: ${expr.name}`);
                }
                this.emit(`    mov rax, [rbp${offset}]`);
                break;
            }

            case "binop": {
                // Evaluate right first, push, then left into rax
                this.genExpr(expr.right);
                this.emit("    push rax");
                this.genExpr(expr.left);
                this.emit("    pop rcx");

                switch (expr.op) {
                    case "+":
                        this.emit("    add rax, rcx");
                        break;
                    case "-":
                        this.emit("    sub rax, rcx");
                        break;
                    case "*":
                        this.emit("    imul rax, rcx");
                        break;
                    case "/":
                        // x86 idiv: rax = rdx:rax / rcx
                        this.emit("    cqo");
                        this.emit("    idiv rcx");
                        break;
                }
                break;
            }

            case "call": {
                // System V AMD64 ABI: first 6 args in rdi, rsi, rdx, rcx, r8, r9
                const argRegs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"];
                if (expr.args.length > argRegs.length) {
                    throw new Error("too many arguments (stack args not implemented)");
                }

                // Evaluate args right-to-left, push each
                for (let i = expr.args.length - 1; i >= 0; i--) {
                    this.genExpr(expr.args[i]);
                    this.emit("    push rax");
                }
                // Pop into argument registers left-to-right
                for (let i = 0; i < expr.args.length; i++) {
                    this.emit(`    pop ${argRegs[i]}`);
                }

                this.emit(`    call ${expr.name}`);
                // Result is in rax per calling convention
                break;
            }

            case "let": {
                // Evaluate initializer, store on stack, evaluate body
                this.genExpr(expr.init);
                const offset = this.allocLocal(expr.name);
                this.emit(`    mov [rbp${offset}], rax`);
                this.genExpr(expr.body);
                break;
            }
        }
    }

    // ── Statement codegen ────────────────────────────────────────

    private genStmt(stmt: Stmt): void {
        switch (stmt.kind) {
            case "expr_stmt":
                this.genExpr(stmt.expr);
                break;

            case "return":
                this.genExpr(stmt.expr);
                // Epilogue restores frame, ret pops return address
                this.emit("    leave");
                this.emit("    ret");
                break;

            case "func_def": {
                const savedLocals = new Map(this.locals);
                const savedOffset = this.stackOffset;
                this.locals.clear();
                this.stackOffset = 0;

                this.emit(`${stmt.name}:`);
                // Prologue: save old frame pointer, set new one
                this.emit("    push rbp");
                this.emit("    mov rbp, rsp");

                // Reserve stack space (we'll patch this)
                const reserveIdx = this.lines.length;
                this.emit("    sub rsp, 0"); // placeholder

                // Bind parameters to stack slots
                const argRegs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"];
                for (let i = 0; i < stmt.params.length; i++) {
                    const offset = this.allocLocal(stmt.params[i]);
                    this.emit(`    mov [rbp${offset}], ${argRegs[i]}`);
                }

                // Body
                for (const s of stmt.body) {
                    this.genStmt(s);
                }

                // Patch stack reservation (align to 16)
                const frameSize = Math.ceil(this.stackOffset / 16) * 16;
                this.lines[reserveIdx] = `    sub rsp, ${frameSize}`;

                this.locals = savedLocals;
                this.stackOffset = savedOffset;
                break;
            }
        }
    }

    // ── Public API ───────────────────────────────────────────────

    generate(stmts: Stmt[]): string[] {
        this.lines = [];
        this.emit("    .text");
        this.emit("    .globl main");
        this.emit("");

        for (const stmt of stmts) {
            this.genStmt(stmt);
        }

        return [...this.lines];
    }
}

// ── Tests ────────────────────────────────────────────────────────────

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function testSimpleReturn(): void {
    const gen = new CodeGenerator();
    const program: Stmt[] = [
        {
            kind: "func_def",
            name: "main",
            params: [],
            body: [
                { kind: "return", expr: { kind: "number", value: 42 } },
            ],
        },
    ];

    const asm = gen.generate(program);
    assert(asm.includes("main:"), "should emit function label");
    assert(asm.some(l => l.includes("mov rax, 42")), "should load 42 into rax");
    assert(asm.some(l => l.includes("push rbp")), "should have prologue");
    assert(asm.some(l => l.includes("leave")), "should have epilogue");
    assert(asm.some(l => l.includes("ret")), "should return");
}

function testArithmetic(): void {
    const gen = new CodeGenerator();
    // return 3 + 4 * 5
    const expr: Expr = {
        kind: "binop", op: "+",
        left: { kind: "number", value: 3 },
        right: {
            kind: "binop", op: "*",
            left: { kind: "number", value: 4 },
            right: { kind: "number", value: 5 },
        },
    };

    const program: Stmt[] = [
        {
            kind: "func_def", name: "calc", params: [],
            body: [{ kind: "return", expr }],
        },
    ];

    const asm = gen.generate(program);
    // Should see imul for multiplication, add for addition
    assert(asm.some(l => l.includes("imul")), "should use imul for *");
    assert(asm.some(l => l.includes("add rax")), "should use add for +");
    // Stack-based: right side evaluated first, pushed, then left
    assert(asm.some(l => l.includes("push rax")), "should push intermediate");
    assert(asm.some(l => l.includes("pop rcx")), "should pop into scratch");
}

function testLetBinding(): void {
    const gen = new CodeGenerator();
    // let x = 10 in x + 5
    const expr: Expr = {
        kind: "let", name: "x",
        init: { kind: "number", value: 10 },
        body: {
            kind: "binop", op: "+",
            left: { kind: "var", name: "x" },
            right: { kind: "number", value: 5 },
        },
    };

    const program: Stmt[] = [
        {
            kind: "func_def", name: "with_local", params: [],
            body: [{ kind: "return", expr }],
        },
    ];

    const asm = gen.generate(program);
    assert(asm.some(l => l.includes("[rbp-8]")), "should store local at rbp-8");
}

function testFunctionParams(): void {
    const gen = new CodeGenerator();
    // add(a, b) { return a + b; }
    const program: Stmt[] = [
        {
            kind: "func_def", name: "add", params: ["a", "b"],
            body: [
                {
                    kind: "return",
                    expr: {
                        kind: "binop", op: "+",
                        left: { kind: "var", name: "a" },
                        right: { kind: "var", name: "b" },
                    },
                },
            ],
        },
    ];

    const asm = gen.generate(program);
    // Parameters should be stored from rdi, rsi
    assert(asm.some(l => l.includes("mov [rbp-8], rdi")), "param a from rdi");
    assert(asm.some(l => l.includes("mov [rbp-16], rsi")), "param b from rsi");
}

function testCallExpression(): void {
    const gen = new CodeGenerator();
    const program: Stmt[] = [
        {
            kind: "func_def", name: "main", params: [],
            body: [
                {
                    kind: "return",
                    expr: {
                        kind: "call", name: "add",
                        args: [
                            { kind: "number", value: 3 },
                            { kind: "number", value: 4 },
                        ],
                    },
                },
            ],
        },
    ];

    const asm = gen.generate(program);
    assert(asm.some(l => l.includes("call add")), "should emit call instruction");
    assert(asm.some(l => l.includes("pop rdi")), "first arg in rdi");
    assert(asm.some(l => l.includes("pop rsi")), "second arg in rsi");
}

function testFrameAlignment(): void {
    const gen = new CodeGenerator();
    // 3 locals: should round up to 16-byte aligned frame
    const program: Stmt[] = [
        {
            kind: "func_def", name: "f", params: ["a", "b", "c"],
            body: [
                {
                    kind: "return",
                    expr: { kind: "var", name: "a" },
                },
            ],
        },
    ];

    const asm = gen.generate(program);
    // 3 params * 8 = 24 bytes, rounded to 32
    assert(asm.some(l => l.includes("sub rsp, 32")), "frame aligned to 16");
}

function testDivision(): void {
    const gen = new CodeGenerator();
    const program: Stmt[] = [
        {
            kind: "func_def", name: "div", params: [],
            body: [
                {
                    kind: "return",
                    expr: {
                        kind: "binop", op: "/",
                        left: { kind: "number", value: 100 },
                        right: { kind: "number", value: 3 },
                    },
                },
            ],
        },
    ];

    const asm = gen.generate(program);
    assert(asm.some(l => l.includes("cqo")), "should sign-extend for idiv");
    assert(asm.some(l => l.includes("idiv")), "should use idiv for division");
}

// ── Main ─────────────────────────────────────────────────────────────

function main(): void {
    testSimpleReturn();
    testArithmetic();
    testLetBinding();
    testFunctionParams();
    testCallExpression();
    testFrameAlignment();
    testDivision();

    console.log("All code generation tests passed.");
}

main();
