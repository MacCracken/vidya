// Vidya — Lexing and Parsing in TypeScript
//
// Demonstrates a complete lexer + recursive-descent parser for arithmetic
// expressions. The pipeline mirrors what every hand-written compiler does:
//   1. Lexer: chars -> tokens (scanning with position tracking)
//   2. Parser: tokens -> AST (recursive descent with Pratt binding power)
//   3. Evaluator: AST -> result (tree-walk over the AST)
//
// Supports +, -, *, /, unary minus, and parenthesized sub-expressions.
// AST nodes use discriminated unions — TypeScript's idiomatic pattern matching.

// ── Tokens ────────────────────────────────────────────────────────────

type TokenKind =
    | "number"
    | "plus"
    | "minus"
    | "star"
    | "slash"
    | "lparen"
    | "rparen"
    | "eof";

interface Token {
    kind: TokenKind;
    text: string;
    pos: number;
}

// ── Lexer ─────────────────────────────────────────────────────────────

class Lexer {
    private source: string;
    private pos: number;

    constructor(source: string) {
        this.source = source;
        this.pos = 0;
    }

    private peek(): string | null {
        if (this.pos < this.source.length) return this.source[this.pos];
        return null;
    }

    private advance(): string | null {
        if (this.pos < this.source.length) return this.source[this.pos++];
        return null;
    }

    private skipWhitespace(): void {
        while (this.peek() !== null && /\s/.test(this.peek()!)) {
            this.advance();
        }
    }

    nextToken(): Token {
        this.skipWhitespace();
        const start = this.pos;

        const c = this.advance();
        if (c === null) {
            return { kind: "eof", text: "", pos: this.pos };
        }

        const singles: Record<string, TokenKind> = {
            "+": "plus",
            "-": "minus",
            "*": "star",
            "/": "slash",
            "(": "lparen",
            ")": "rparen",
        };

        if (c in singles) {
            return { kind: singles[c], text: c, pos: start };
        }

        if (/[0-9]/.test(c)) {
            while (this.peek() !== null && /[0-9]/.test(this.peek()!)) {
                this.advance();
            }
            return { kind: "number", text: this.source.slice(start, this.pos), pos: start };
        }

        throw new Error(`unexpected character '${c}' at position ${start}`);
    }
}

// ── AST (discriminated unions) ────────────────────────────────────────

type Expr =
    | { kind: "number"; value: number }
    | { kind: "unary_minus"; operand: Expr }
    | { kind: "binop"; op: string; left: Expr; right: Expr };

function numberExpr(value: number): Expr {
    return { kind: "number", value };
}

function unaryMinusExpr(operand: Expr): Expr {
    return { kind: "unary_minus", operand };
}

function binOpExpr(op: string, left: Expr, right: Expr): Expr {
    return { kind: "binop", op, left, right };
}

function exprToString(e: Expr): string {
    switch (e.kind) {
        case "number": return String(e.value);
        case "unary_minus": return `(-${exprToString(e.operand)})`;
        case "binop": return `(${exprToString(e.left)} ${e.op} ${exprToString(e.right)})`;
    }
}

// ── Pratt Parser ──────────────────────────────────────────────────────

function infixBindingPower(kind: TokenKind): [number, number] | null {
    switch (kind) {
        case "plus": case "minus": return [1, 2];
        case "star": case "slash": return [3, 4];
        default: return null;
    }
}

function prefixBindingPower(kind: TokenKind): number | null {
    if (kind === "minus") return 5;
    return null;
}

const OP_CHARS: Record<string, string> = {
    plus: "+", minus: "-", star: "*", slash: "/",
};

class Parser {
    private lexer: Lexer;
    private current: Token;

    constructor(source: string) {
        this.lexer = new Lexer(source);
        this.current = this.lexer.nextToken();
    }

    private advance(): Token {
        const prev = this.current;
        this.current = this.lexer.nextToken();
        return prev;
    }

    private expect(kind: TokenKind): void {
        if (this.current.kind !== kind) {
            throw new Error(
                `expected ${kind} at pos ${this.current.pos}, ` +
                `found ${this.current.kind} '${this.current.text}'`
            );
        }
        this.advance();
    }

    parseExpr(minBP: number = 0): Expr {
        // ── Prefix / atoms ───────────────────────────────────────
        let lhs: Expr;

        if (this.current.kind === "number") {
            const tok = this.advance();
            lhs = numberExpr(parseInt(tok.text, 10));
        } else if (this.current.kind === "lparen") {
            this.advance();
            lhs = this.parseExpr(0);
            this.expect("rparen");
        } else {
            const pbp = prefixBindingPower(this.current.kind);
            if (pbp !== null) {
                this.advance();
                const operand = this.parseExpr(pbp);
                lhs = unaryMinusExpr(operand);
            } else {
                throw new Error(
                    `expected expression at pos ${this.current.pos}, ` +
                    `found ${this.current.kind} '${this.current.text}'`
                );
            }
        }

        // ── Infix loop ──────────────────────────────────────────
        for (;;) {
            const opKind = this.current.kind;
            if (opKind === "eof" || opKind === "rparen") break;

            const bp = infixBindingPower(opKind);
            if (bp === null) break;

            const [lBP, rBP] = bp;
            if (lBP < minBP) break;

            const op = OP_CHARS[opKind];
            this.advance();
            const rhs = this.parseExpr(rBP);
            lhs = binOpExpr(op, lhs, rhs);
        }

        return lhs;
    }
}

// ── Tree-walk evaluator ───────────────────────────────────────────────

function evaluate(expr: Expr): number {
    switch (expr.kind) {
        case "number":
            return expr.value;
        case "unary_minus":
            return -evaluate(expr.operand);
        case "binop": {
            const l = evaluate(expr.left);
            const r = evaluate(expr.right);
            switch (expr.op) {
                case "+": return l + r;
                case "-": return l - r;
                case "*": return l * r;
                case "/": return Math.trunc(l / r);
                default: throw new Error(`unknown operator: ${expr.op}`);
            }
        }
    }
}

// ── Main ──────────────────────────────────────────────────────────────

function main(): void {
    const tests: [string, number][] = [
        ["42", 42],
        ["2 + 3", 5],
        ["2 + 3 * 4", 14],
        ["(2 + 3) * 4", 20],
        ["-5 + 3", -2],
        ["10 - 3 - 2", 5],
        ["2 * 3 + 4 * 5", 26],
        ["-(3 + 4) * 2", -14],
        ["3 + 4 * (2 - 1)", 7],
    ];

    for (const [input, expected] of tests) {
        const parser = new Parser(input);
        const ast = parser.parseExpr();
        const result = evaluate(ast);

        const status = result === expected ? "ok" : "FAIL";
        console.log(
            `${input.padEnd(25)} => ${String(result).padStart(4)}  ` +
            `(expected ${String(expected).padStart(4)}) ${status}`
        );

        if (result !== expected) {
            throw new Error(`failed on "${input}": got ${result}, expected ${expected}`);
        }
    }

    console.log(`\nAll ${tests.length} tests passed.`);
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
