// Vidya — SQL Parsing in Zig
//
// Idiomatic shape: an enum for token kinds and a `switch` on u8
// for character classification. The lexer walks a const u8 slice with
// a position cursor; tokens hold a kind plus a slice into the original
// SQL string (zero-copy). Keywords are matched case-insensitively by
// uppercasing each byte during the compare. Mirrors cyrius.cyr.

const std = @import("std");

const Tok = enum {
    eof,
    ident,
    int,
    star,
    eq,
    lparen,
    rparen,
    comma,
    select_kw,
    from_kw,
    where_kw,
};

const Token = struct {
    kind: Tok,
    text: []const u8,
};

fn isAlpha(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_';
}

fn isAlnum(c: u8) bool {
    return isAlpha(c) or (c >= '0' and c <= '9');
}

fn upper(c: u8) u8 {
    return if (c >= 'a' and c <= 'z') c - 32 else c;
}

fn kwEq(text: []const u8, kw: []const u8) bool {
    if (text.len != kw.len) return false;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (upper(text[i]) != kw[i]) return false;
    }
    return true;
}

fn classify(text: []const u8) Tok {
    if (kwEq(text, "SELECT")) return .select_kw;
    if (kwEq(text, "FROM")) return .from_kw;
    if (kwEq(text, "WHERE")) return .where_kw;
    return .ident;
}

const MAX_TOKENS = 128;

const TokBuf = struct {
    items: [MAX_TOKENS]Token,
    len: usize,

    fn push(self: *TokBuf, t: Token) error{TooManyTokens}!void {
        if (self.len >= MAX_TOKENS) return error.TooManyTokens; // untrusted input
        self.items[self.len] = t;
        self.len += 1;
    }
};

// An unknown byte is an error, never skipped: dropping it silently turns
// `id = -1` into `id = 1`, `a < 5` into `a 5` and `'x'` into the
// identifier x, and the validator then accepts the changed query.
fn tokenize(sql: []const u8, buf: *TokBuf) error{ TooManyTokens, UnexpectedCharacter }!void {
    buf.len = 0;
    var pos: usize = 0;

    while (pos < sql.len) {
        const c = sql[pos];
        switch (c) {
            ' ', '\t', '\n', '\r' => {
                pos += 1;
                continue;
            },
            else => {},
        }

        if (isAlpha(c)) {
            const start = pos;
            while (pos < sql.len and isAlnum(sql[pos])) : (pos += 1) {}
            const text = sql[start..pos];
            try buf.push(.{ .kind = classify(text), .text = text });
            continue;
        }

        if (c >= '0' and c <= '9') {
            const start = pos;
            while (pos < sql.len and sql[pos] >= '0' and sql[pos] <= '9') : (pos += 1) {}
            try buf.push(.{ .kind = .int, .text = sql[start..pos] });
            continue;
        }

        const k: ?Tok = switch (c) {
            '*' => .star,
            '=' => .eq,
            '(' => .lparen,
            ')' => .rparen,
            ',' => .comma,
            else => null,
        };
        const kk = k orelse return error.UnexpectedCharacter;
        try buf.push(.{ .kind = kk, .text = sql[pos .. pos + 1] });
        pos += 1;
    }

    try buf.push(.{ .kind = .eof, .text = "" });
}

fn isValidSelect(buf: *const TokBuf) bool {
    if (buf.len == 0 or buf.items[0].kind != .select_kw) return false;
    var from_idx: isize = -1;
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (buf.items[i].kind == .from_kw) {
            from_idx = @intCast(i);
            break;
        }
    }
    if (from_idx < 0 or from_idx == 1) return false;
    const fi: usize = @intCast(from_idx);
    if (fi + 1 >= buf.len or buf.items[fi + 1].kind != .ident) return false;
    // ...then end of input, or exactly WHERE <ident> = <int|ident>. Without
    // this, anything after the table name ("FROM t DROP TABLE t") passed.
    const tail = buf.items[fi + 2 .. buf.len];
    if (tail.len == 1) return tail[0].kind == .eof;
    return tail.len == 5 and tail[0].kind == .where_kw and tail[1].kind == .ident and
        tail[2].kind == .eq and (tail[3].kind == .int or tail[3].kind == .ident) and
        tail[4].kind == .eof;
}

fn assertKinds(buf: *const TokBuf, expected: []const Tok, msg: []const u8) !void {
    if (buf.len != expected.len) {
        std.debug.print("{s}: token count {d} != expected {d}\n", .{ msg, buf.len, expected.len });
        return error.KindMismatch;
    }
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (buf.items[i].kind != expected[i]) {
            std.debug.print("{s} [{d}]: kind mismatch\n", .{ msg, i });
            return error.KindMismatch;
        }
    }
}

fn textEq(t: Token, s: []const u8) bool {
    return std.mem.eql(u8, t.text, s);
}

pub fn main() !void {
    var buf: TokBuf = .{ .items = undefined, .len = 0 };

    // Test 1: canonical SELECT
    try tokenize("SELECT * FROM users WHERE id = 1", &buf);
    try assertKinds(&buf, &[_]Tok{
        .select_kw, .star, .from_kw, .ident, .where_kw,
        .ident,     .eq,   .int,     .eof,
    }, "canonical");
    if (!textEq(buf.items[3], "users")) return error.TextMismatch;
    if (!textEq(buf.items[5], "id")) return error.TextMismatch;
    if (!textEq(buf.items[7], "1")) return error.TextMismatch;

    // Test 2: case insensitive
    try tokenize("select * from T", &buf);
    try assertKinds(&buf, &[_]Tok{ .select_kw, .star, .from_kw, .ident, .eof }, "lowercase");
    try tokenize("Select * From T", &buf);
    try assertKinds(&buf, &[_]Tok{ .select_kw, .star, .from_kw, .ident, .eof }, "mixed");

    // Test 3: 'selected' is an identifier
    try tokenize("selected", &buf);
    if (buf.items[0].kind != .ident) return error.NotIdent;
    if (!textEq(buf.items[0], "selected")) return error.TextMismatch;

    // Test 4: parens + commas
    try tokenize("SELECT (a, b) FROM t", &buf);
    try assertKinds(&buf, &[_]Tok{
        .select_kw, .lparen, .ident,   .comma, .ident,
        .rparen,    .from_kw, .ident,   .eof,
    }, "parens");

    // Test 5: integer literal
    try tokenize("12345", &buf);
    if (buf.items[0].kind != .int) return error.NotInt;
    if (!textEq(buf.items[0], "12345")) return error.TextMismatch;

    // Test 6: validator
    try tokenize("SELECT * FROM t", &buf);
    if (!isValidSelect(&buf)) return error.ShouldBeValid;
    try tokenize("SELECT a FROM t WHERE id = 1", &buf);
    if (!isValidSelect(&buf)) return error.ShouldBeValid;
    try tokenize("FROM t", &buf);
    if (isValidSelect(&buf)) return error.ShouldBeInvalid;
    try tokenize("SELECT FROM t", &buf);
    if (isValidSelect(&buf)) return error.ShouldBeInvalid;
    try tokenize("SELECT * FROM", &buf);
    if (isValidSelect(&buf)) return error.ShouldBeInvalid;
    // Nothing may follow the table except one WHERE <ident> = <value>
    for ([_][]const u8{
        "SELECT * FROM t DROP TABLE t",       "SELECT * FROM t u",
        "SELECT * FROM t WHERE DROP TABLE t", "SELECT * FROM t WHERE id = 1 DROP TABLE t",
    }) |q| {
        try tokenize(q, &buf);
        if (isValidSelect(&buf)) return error.TrailingTokensAccepted;
    }

    // Test 6b: unknown characters are rejected, not dropped
    if (tokenize("SELECT * FROM t WHERE id = -1", &buf)) |_| return error.MinusDropped else |e| if (e != error.UnexpectedCharacter) return e;
    if (tokenize("SELECT * FROM t WHERE name = 'x'", &buf)) |_| return error.QuoteDropped else |e| if (e != error.UnexpectedCharacter) return e;

    // Test 7: whitespace tolerance
    try tokenize("  SELECT\t*\nFROM\tt  ", &buf);
    try assertKinds(&buf, &[_]Tok{ .select_kw, .star, .from_kw, .ident, .eof }, "whitespace");

    std.debug.print("All sql_parsing examples passed.\n", .{});
}
