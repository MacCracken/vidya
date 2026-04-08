// Vidya — Compiler Bootstrapping in Zig
//
// Two-pass assembler: first pass collects label addresses, second pass
// emits bytes with resolved references. Zig's comptime enums model
// the instruction set, hash maps hold the symbol table, and ArrayList
// accumulates the output code buffer. This mirrors how real assemblers
// bootstrap: you need two passes because forward references can't be
// resolved until every label address is known.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    try testTwoPassAssembler();
    try testForwardReference();
    try testMultipleLabels();

    std.debug.print("All compiler bootstrapping examples passed.\n", .{});
}

// ── Instruction Set ──────────────────────────────────────────────────
// A minimal instruction set for a toy assembler. Each instruction
// encodes to a fixed number of bytes so address calculation is simple.
const Opcode = enum(u8) {
    nop = 0x00,
    load_imm = 0x01, // LOAD R, imm8  → 3 bytes: [op, reg, imm]
    add = 0x02, // ADD  R, R     → 3 bytes: [op, dst, src]
    store = 0x03, // STORE addr16  → 3 bytes: [op, lo, hi]
    jmp = 0x04, // JMP   addr16  → 3 bytes: [op, lo, hi]
    halt = 0xFF, // HALT          → 1 byte:  [op]
};

const Instruction = union(enum) {
    nop: void,
    load_imm: struct { reg: u8, value: u8 },
    add: struct { dst: u8, src: u8 },
    store: struct { label: []const u8 },
    jmp: struct { label: []const u8 },
    halt: void,

    /// How many bytes this instruction occupies in the output.
    fn size(self: Instruction) usize {
        return switch (self) {
            .nop => 1,
            .load_imm => 3,
            .add => 3,
            .store => 3,
            .jmp => 3,
            .halt => 1,
        };
    }
};

// ── Source Line ───────────────────────────────────────────────────────
// A line is optionally labelled. Labels mark addresses in the output.
const SourceLine = struct {
    label: ?[]const u8,
    inst: Instruction,
};

// ── Two-Pass Assembler ───────────────────────────────────────────────
const Assembler = struct {
    symbols: std.StringHashMap(u16),
    code: std.ArrayListUnmanaged(u8) = .empty,
    alloc: Allocator,

    fn init(alloc: Allocator) Assembler {
        return .{
            .symbols = std.StringHashMap(u16).init(alloc),
            .alloc = alloc,
        };
    }

    fn deinit(self: *Assembler) void {
        self.symbols.deinit();
        self.code.deinit(self.alloc);
    }

    /// Pass 1: walk every line, track the current address, record
    /// each label → address mapping. No bytes are emitted.
    fn pass1(self: *Assembler, program: []const SourceLine) !void {
        var addr: u16 = 0;
        for (program) |line| {
            if (line.label) |name| {
                try self.symbols.put(name, addr);
            }
            addr += @intCast(line.inst.size());
        }
    }

    /// Pass 2: emit bytes. Label references are resolved from the
    /// symbol table built in pass 1.
    fn pass2(self: *Assembler, program: []const SourceLine) !void {
        for (program) |line| {
            switch (line.inst) {
                .nop => try self.code.append(self.alloc,@intFromEnum(Opcode.nop)),
                .load_imm => |op| {
                    try self.code.append(self.alloc,@intFromEnum(Opcode.load_imm));
                    try self.code.append(self.alloc,op.reg);
                    try self.code.append(self.alloc,op.value);
                },
                .add => |op| {
                    try self.code.append(self.alloc,@intFromEnum(Opcode.add));
                    try self.code.append(self.alloc,op.dst);
                    try self.code.append(self.alloc,op.src);
                },
                .store => |op| {
                    const addr = self.symbols.get(op.label) orelse return error.UndefinedLabel;
                    try self.code.append(self.alloc,@intFromEnum(Opcode.store));
                    try self.code.append(self.alloc,@truncate(addr & 0xFF));
                    try self.code.append(self.alloc,@truncate(addr >> 8));
                },
                .jmp => |op| {
                    const addr = self.symbols.get(op.label) orelse return error.UndefinedLabel;
                    try self.code.append(self.alloc,@intFromEnum(Opcode.jmp));
                    try self.code.append(self.alloc,@truncate(addr & 0xFF));
                    try self.code.append(self.alloc,@truncate(addr >> 8));
                },
                .halt => try self.code.append(self.alloc,@intFromEnum(Opcode.halt)),
            }
        }
    }

    /// Assemble a program: pass 1 then pass 2.
    fn assemble(self: *Assembler, program: []const SourceLine) ![]const u8 {
        try self.pass1(program);
        try self.pass2(program);
        return self.code.items;
    }
};

// ── Tests ────────────────────────────────────────────────────────────
fn testTwoPassAssembler() !void {
    var asm_ = Assembler.init(std.heap.page_allocator);
    defer asm_.deinit();

    // Simple program: load two values, add them, halt
    const program = [_]SourceLine{
        .{ .label = "start", .inst = .{ .load_imm = .{ .reg = 0, .value = 10 } } },
        .{ .label = null, .inst = .{ .load_imm = .{ .reg = 1, .value = 20 } } },
        .{ .label = null, .inst = .{ .add = .{ .dst = 0, .src = 1 } } },
        .{ .label = "end", .inst = .halt },
    };

    const code = try asm_.assemble(&program);

    // Verify total size: 3 + 3 + 3 + 1 = 10 bytes
    try expect(code.len == 10);

    // Verify opcode bytes
    try expect(code[0] == @intFromEnum(Opcode.load_imm));
    try expect(code[1] == 0); // reg 0
    try expect(code[2] == 10); // immediate
    try expect(code[3] == @intFromEnum(Opcode.load_imm));
    try expect(code[6] == @intFromEnum(Opcode.add));
    try expect(code[9] == @intFromEnum(Opcode.halt));

    // Verify label addresses
    try expect(asm_.symbols.get("start").? == 0);
    try expect(asm_.symbols.get("end").? == 9);
}

fn testForwardReference() !void {
    var asm_ = Assembler.init(std.heap.page_allocator);
    defer asm_.deinit();

    // Jump to a label defined AFTER the jump — this is why two passes
    // are essential. Pass 1 collects "done" at address 4, pass 2
    // resolves the forward reference.
    const program = [_]SourceLine{
        .{ .label = null, .inst = .{ .jmp = .{ .label = "done" } } },
        .{ .label = null, .inst = .{ .load_imm = .{ .reg = 0, .value = 99 } } },
        .{ .label = "done", .inst = .halt },
    };

    const code = try asm_.assemble(&program);

    // JMP instruction at offset 0: [04, lo, hi]
    try expect(code[0] == @intFromEnum(Opcode.jmp));
    // "done" is at address 6 (3 + 3)
    try expect(code[1] == 6); // lo byte
    try expect(code[2] == 0); // hi byte
    try expect(code[6] == @intFromEnum(Opcode.halt));
}

fn testMultipleLabels() !void {
    var asm_ = Assembler.init(std.heap.page_allocator);
    defer asm_.deinit();

    const program = [_]SourceLine{
        .{ .label = "a", .inst = .nop },
        .{ .label = "b", .inst = .nop },
        .{ .label = "c", .inst = .{ .store = .{ .label = "a" } } },
        .{ .label = "d", .inst = .halt },
    };

    const code = try asm_.assemble(&program);

    // Addresses: a=0, b=1, c=2, d=5
    try expect(asm_.symbols.get("a").? == 0);
    try expect(asm_.symbols.get("b").? == 1);
    try expect(asm_.symbols.get("c").? == 2);
    try expect(asm_.symbols.get("d").? == 5);

    // STORE references label "a" (address 0)
    try expect(code[2] == @intFromEnum(Opcode.store));
    try expect(code[3] == 0); // lo
    try expect(code[4] == 0); // hi
    try expect(code.len == 6);
}
