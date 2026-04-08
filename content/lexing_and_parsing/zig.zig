// Vidya — Lexing and Parsing in Zig
//
// Tokenizer + recursive descent parser for arithmetic expressions.
// The parser uses Pratt-style precedence climbing to handle operator
// priority without explicit grammar rules per precedence level.
// Zig's tagged unions make tokens and AST nodes type-safe, and
// error unions propagate parse failures cleanly.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testTokenizer();
    try testParserSimple();
    try testParserPrecedence();
    try testParserParens();
    try testFullExpression();

    std.debug.print("All lexing and parsing examples passed.\n", .{});
}

// ── Token ────────────────────────────────────────────────────────────
const TokenTag = enum {
    number,
    plus,
    minus,
    star,
    slash,
    lparen,
    rparen,
    eof,
};

const Token = struct {
    tag: TokenTag,
    value: i64, // meaningful only for .number
};

// ── Lexer ────────────────────────────────────────────────────────────
// Walks a byte slice and yields tokens one at a time.
const Lexer = struct {
    src: []const u8,
    pos: usize,

    fn init(src: []const u8) Lexer {
        return .{ .src = src, .pos = 0 };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.src.len and self.src[self.pos] == ' ') {
            self.pos += 1;
        }
    }

    fn next(self: *Lexer) !Token {
        self.skipWhitespace();

        if (self.pos >= self.src.len) {
            return Token{ .tag = .eof, .value = 0 };
        }

        const ch = self.src[self.pos];

        // Single-character operators
        const single: ?TokenTag = switch (ch) {
            '+' => .plus,
            '-' => .minus,
            '*' => .star,
            '/' => .slash,
            '(' => .lparen,
            ')' => .rparen,
            else => null,
        };

        if (single) |tag| {
            self.pos += 1;
            return Token{ .tag = tag, .value = 0 };
        }

        // Number literal
        if (ch >= '0' and ch <= '9') {
            var val: i64 = 0;
            while (self.pos < self.src.len and self.src[self.pos] >= '0' and self.src[self.pos] <= '9') {
                val = val * 10 + @as(i64, self.src[self.pos] - '0');
                self.pos += 1;
            }
            return Token{ .tag = .number, .value = val };
        }

        return error.UnexpectedCharacter;
    }
};

// ── AST ──────────────────────────────────────────────────────────────
// Expression tree. Binary ops hold pointers to sub-expressions.
// We use a fixed-size node pool to avoid needing an allocator.
const BinOp = enum { add, sub, mul, div };

const ExprTag = enum { number, binary };

const Expr = union(ExprTag) {
    number: i64,
    binary: struct {
        op: BinOp,
        left: *const Expr,
        right: *const Expr,
    },
};

// ── Parser ───────────────────────────────────────────────────────────
// Pratt parser: each operator has a binding power (precedence).
// Higher binding power means tighter binding.
const Parser = struct {
    lexer: Lexer,
    current: Token,
    // Fixed node pool — avoids allocator for this demo
    pool: [64]Expr,
    pool_len: usize,

    fn init(src: []const u8) !Parser {
        var lexer = Lexer.init(src);
        const first = try lexer.next();
        return Parser{
            .lexer = lexer,
            .current = first,
            .pool = undefined,
            .pool_len = 0,
        };
    }

    fn allocNode(self: *Parser, expr: Expr) !*const Expr {
        if (self.pool_len >= self.pool.len) return error.PoolExhausted;
        self.pool[self.pool_len] = expr;
        const ptr = &self.pool[self.pool_len];
        self.pool_len += 1;
        return ptr;
    }

    fn advance(self: *Parser) !void {
        self.current = try self.lexer.next();
    }

    /// Binding power for infix operators. Returns null for non-infix tokens.
    fn infixBP(tag: TokenTag) ?struct { left: u8, right: u8 } {
        return switch (tag) {
            .plus, .minus => .{ .left = 1, .right = 2 },
            .star, .slash => .{ .left = 3, .right = 4 },
            else => null,
        };
    }

    fn tagToBinOp(tag: TokenTag) BinOp {
        return switch (tag) {
            .plus => .add,
            .minus => .sub,
            .star => .mul,
            .slash => .div,
            else => unreachable,
        };
    }

    const ParseError = error{ PoolExhausted, UnexpectedCharacter, UnexpectedToken, ExpectedRParen };

    /// Parse a primary expression: number or parenthesised expression.
    fn parsePrimary(self: *Parser) ParseError!*const Expr {
        if (self.current.tag == .number) {
            const node = try self.allocNode(.{ .number = self.current.value });
            try self.advance();
            return node;
        }

        if (self.current.tag == .lparen) {
            try self.advance(); // consume '('
            const inner = try self.parseExpr(0);
            if (self.current.tag != .rparen) return error.ExpectedRParen;
            try self.advance(); // consume ')'
            return inner;
        }

        return error.UnexpectedToken;
    }

    /// Pratt expression parser. min_bp is the minimum binding power
    /// that the caller will accept — anything weaker causes return.
    fn parseExpr(self: *Parser, min_bp: u8) ParseError!*const Expr {
        var left = try self.parsePrimary();

        while (true) {
            const bp = infixBP(self.current.tag) orelse break;
            if (bp.left < min_bp) break;

            const op = tagToBinOp(self.current.tag);
            try self.advance(); // consume operator

            const right = try self.parseExpr(bp.right);
            left = try self.allocNode(.{ .binary = .{
                .op = op,
                .left = left,
                .right = right,
            } });
        }

        return left;
    }

    fn parse(self: *Parser) ParseError!*const Expr {
        return self.parseExpr(0);
    }
};

// ── Evaluator ────────────────────────────────────────────────────────
fn eval(expr: *const Expr) !i64 {
    return switch (expr.*) {
        .number => |n| n,
        .binary => |b| {
            const l = try eval(b.left);
            const r = try eval(b.right);
            return switch (b.op) {
                .add => l + r,
                .sub => l - r,
                .mul => l * r,
                .div => if (r == 0) error.DivisionByZero else @divTrunc(l, r),
            };
        },
    };
}

// ── Tests ────────────────────────────────────────────────────────────
fn testTokenizer() !void {
    var lex = Lexer.init("42 + 7");
    const t1 = try lex.next();
    try expect(t1.tag == .number and t1.value == 42);
    const t2 = try lex.next();
    try expect(t2.tag == .plus);
    const t3 = try lex.next();
    try expect(t3.tag == .number and t3.value == 7);
    const t4 = try lex.next();
    try expect(t4.tag == .eof);
}

fn testParserSimple() !void {
    // 2 + 3 = 5
    var p = try Parser.init("2 + 3");
    const ast = try p.parse();
    try expect(try eval(ast) == 5);
}

fn testParserPrecedence() !void {
    // 2 + 3 * 4 = 14  (multiplication binds tighter)
    var p = try Parser.init("2 + 3 * 4");
    const ast = try p.parse();
    try expect(try eval(ast) == 14);
}

fn testParserParens() !void {
    // (2 + 3) * 4 = 20  (parens override precedence)
    var p = try Parser.init("(2 + 3) * 4");
    const ast = try p.parse();
    try expect(try eval(ast) == 20);
}

fn testFullExpression() !void {
    // 3 + 4 * (2 - 1) = 7
    var p = try Parser.init("3 + 4 * (2 - 1)");
    const ast = try p.parse();
    try expect(try eval(ast) == 7);
}
