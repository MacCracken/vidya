// Vidya — Code Generation in Zig
//
// Stack-based code generator: walks an expression AST and emits
// x86_64-style assembly strings. Each sub-expression pushes its
// result onto the stack; binary ops pop two operands and push the
// result. This is the simplest correct code generation strategy —
// no register allocation needed, just push/pop discipline.
//
// Demonstrates: tagged unions for AST, comptime string formatting,
// ArrayList for instruction buffer, stack frame layout.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    try testCodegenLiteral();
    try testCodegenAdd();
    try testCodegenPrecedence();
    try testStackFrameLayout();

    std.debug.print("All code generation examples passed.\n", .{});
}

// ── AST ──────────────────────────────────────────────────────────────
const BinOp = enum { add, sub, mul, div };

const Expr = union(enum) {
    literal: i64,
    binary: struct {
        op: BinOp,
        left: *const Expr,
        right: *const Expr,
    },
};

// ── Instruction buffer ───────────────────────────────────────────────
// We accumulate assembly lines as fixed-size strings to avoid
// allocating per-line. In a real compiler you'd emit to a writer.
const MAX_LINE = 64;

const AsmLine = struct {
    buf: [MAX_LINE]u8,
    len: usize,

    fn slice(self: *const AsmLine) []const u8 {
        return self.buf[0..self.len];
    }
};

fn makeLine(comptime fmt: []const u8, args: anytype) AsmLine {
    var line: AsmLine = .{ .buf = undefined, .len = 0 };
    const result = std.fmt.bufPrint(&line.buf, fmt, args) catch {
        // Truncate if too long
        line.len = MAX_LINE;
        return line;
    };
    line.len = result.len;
    return line;
}

// ── Code Generator ───────────────────────────────────────────────────
const CodeGen = struct {
    lines: std.ArrayListUnmanaged(AsmLine) = .empty,
    alloc: Allocator,

    fn init(alloc: Allocator) CodeGen {
        return .{ .alloc = alloc };
    }

    fn deinit(self: *CodeGen) void {
        self.lines.deinit(self.alloc);
    }

    fn emit(self: *CodeGen, comptime fmt: []const u8, args: anytype) !void {
        try self.lines.append(self.alloc, makeLine(fmt, args));
    }

    /// Generate code for an expression. After this call, the result
    /// of the expression is on top of the stack.
    fn genExpr(self: *CodeGen, expr: *const Expr) !void {
        switch (expr.*) {
            .literal => |val| {
                // Push immediate value onto stack
                try self.emit("    mov rax, {d}", .{val});
                try self.emit("    push rax", .{});
            },
            .binary => |bop| {
                // Generate left, then right — results land on stack
                try self.genExpr(bop.left);
                try self.genExpr(bop.right);

                // Pop operands: right into rcx, left into rax
                try self.emit("    pop rcx", .{});
                try self.emit("    pop rax", .{});

                // Instruction selection based on operator
                switch (bop.op) {
                    .add => try self.emit("    add rax, rcx", .{}),
                    .sub => try self.emit("    sub rax, rcx", .{}),
                    .mul => try self.emit("    imul rax, rcx", .{}),
                    .div => {
                        try self.emit("    cqo", .{}); // sign-extend rax → rdx:rax
                        try self.emit("    idiv rcx", .{});
                    },
                }

                // Push result
                try self.emit("    push rax", .{});
            },
        }
    }

    /// Generate a complete function with prologue/epilogue.
    fn genFunction(self: *CodeGen, name: []const u8, body: *const Expr) !void {
        // Function prologue — set up stack frame
        try self.emit("{s}:", .{name});
        try self.emit("    push rbp", .{});
        try self.emit("    mov rbp, rsp", .{});

        // Generate expression body
        try self.genExpr(body);

        // Result is on stack — pop into rax (return value)
        try self.emit("    pop rax", .{});

        // Function epilogue — tear down stack frame
        try self.emit("    mov rsp, rbp", .{});
        try self.emit("    pop rbp", .{});
        try self.emit("    ret", .{});
    }

    /// Concatenate all emitted lines for inspection.
    fn dump(self: *const CodeGen, alloc: Allocator) ![]u8 {
        var total: usize = 0;
        for (self.lines.items) |line| {
            total += line.len + 1; // +1 for newline
        }
        var output = try alloc.alloc(u8, total);
        var offset: usize = 0;
        for (self.lines.items) |line| {
            @memcpy(output[offset .. offset + line.len], line.slice());
            output[offset + line.len] = '\n';
            offset += line.len + 1;
        }
        return output;
    }
};

// ── Stack Frame Layout ───────────────────────────────────────────────
// Documents x86_64 SysV calling convention frame structure.
const StackSlot = struct {
    name: []const u8,
    offset: i32, // negative = below rbp, positive = above (args)
    size: u32,
};

const FrameLayout = struct {
    slots: [8]StackSlot,
    slot_count: usize,
    frame_size: u32,

    fn addLocal(self: *FrameLayout, name: []const u8, size: u32) void {
        // Locals grow downward from rbp
        var offset: i32 = 0;
        if (self.slot_count > 0) {
            const prev = self.slots[self.slot_count - 1];
            offset = prev.offset - @as(i32, @intCast(prev.size));
        } else {
            offset = -@as(i32, @intCast(size));
        }
        self.slots[self.slot_count] = .{ .name = name, .offset = offset, .size = size };
        self.slot_count += 1;
        self.frame_size += size;
    }
};

// ── Helper: build AST nodes on the stack ─────────────────────────────
fn lit(val: i64) Expr {
    return .{ .literal = val };
}

fn bin(op: BinOp, left: *const Expr, right: *const Expr) Expr {
    return .{ .binary = .{ .op = op, .left = left, .right = right } };
}

// ── Tests ────────────────────────────────────────────────────────────
fn testCodegenLiteral() !void {
    var cg = CodeGen.init(std.heap.page_allocator);
    defer cg.deinit();

    const expr = lit(42);
    try cg.genExpr(&expr);

    // Should emit: mov rax, 42 / push rax
    try expect(cg.lines.items.len == 2);
    try expect(mem.indexOf(u8, cg.lines.items[0].slice(), "42") != null);
    try expect(mem.indexOf(u8, cg.lines.items[1].slice(), "push rax") != null);
}

fn testCodegenAdd() !void {
    var cg = CodeGen.init(std.heap.page_allocator);
    defer cg.deinit();

    // 3 + 5
    const left = lit(3);
    const right = lit(5);
    const expr = bin(.add, &left, &right);
    try cg.genExpr(&expr);

    // Should generate: mov+push (left=2), mov+push (right=2), pop+pop (2), add (1), push (1) = 8
    try expect(cg.lines.items.len == 8);

    // The add instruction should be present
    var found_add = false;
    for (cg.lines.items) |line| {
        if (mem.indexOf(u8, line.slice(), "add rax, rcx") != null) {
            found_add = true;
        }
    }
    try expect(found_add);
}

fn testCodegenPrecedence() !void {
    var cg = CodeGen.init(std.heap.page_allocator);
    defer cg.deinit();

    // 2 + 3 * 4: the AST encodes precedence structurally
    const two = lit(2);
    const three = lit(3);
    const four = lit(4);
    const mul = bin(.mul, &three, &four);
    const add = bin(.add, &two, &mul);

    try cg.genFunction("evaluate", &add);

    const output = try cg.dump(std.heap.page_allocator);
    defer std.heap.page_allocator.free(output);

    // Verify prologue and epilogue present
    try expect(mem.indexOf(u8, output, "evaluate:") != null);
    try expect(mem.indexOf(u8, output, "push rbp") != null);
    try expect(mem.indexOf(u8, output, "ret") != null);
    // Verify imul appears (for the multiplication)
    try expect(mem.indexOf(u8, output, "imul rax, rcx") != null);
}

fn testStackFrameLayout() !void {
    var frame = FrameLayout{
        .slots = undefined,
        .slot_count = 0,
        .frame_size = 0,
    };

    frame.addLocal("x", 8); // -8(%rbp)
    frame.addLocal("y", 8); // -16(%rbp)
    frame.addLocal("flag", 4); // -24(%rbp) (4-byte, but next offset from -16-8)

    try expect(frame.slot_count == 3);
    try expect(frame.slots[0].offset == -8);
    try expect(frame.slots[1].offset == -16);
    try expect(frame.slots[2].offset == -24);
    try expect(frame.frame_size == 20);
}
