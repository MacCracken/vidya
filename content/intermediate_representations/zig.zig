// Vidya — Intermediate Representations in Zig
//
// Three representations used in real compilers:
// 1. Three-address code (TAC) — one operation per instruction, explicit temps
// 2. Basic blocks — straight-line sequences with a single entry/exit
// 3. SSA form — every variable assigned exactly once, phi nodes at joins
//
// Zig's tagged unions are ideal for IR: each IR operation is a union
// variant, and exhaustive switches ensure every case is handled when
// you add a new operation.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    try testThreeAddressCode();
    try testBasicBlocks();
    try testSSA();
    try testIRInterpreter();

    std.debug.print("All intermediate representations examples passed.\n", .{});
}

// ── Three-Address Code ───────────────────────────────────────────────
// Each instruction: result = left op right, or result = op arg.
// Variables are numbered temporaries (t0, t1, ...).

const TacOp = enum {
    add,
    sub,
    mul,
    div,
    neg,
    copy,
    load_const,
    ret,
};

const TacInst = struct {
    op: TacOp,
    dst: u16, // destination temp (ignored for ret)
    src1: i64, // left operand or constant or source temp
    src2: i64, // right operand temp (0 if unused)

    fn loadConst(dst: u16, val: i64) TacInst {
        return .{ .op = .load_const, .dst = dst, .src1 = val, .src2 = 0 };
    }

    fn binary(op: TacOp, dst: u16, left: u16, right: u16) TacInst {
        return .{ .op = op, .dst = dst, .src1 = left, .src2 = right };
    }

    fn copy(dst: u16, src: u16) TacInst {
        return .{ .op = .copy, .dst = dst, .src1 = src, .src2 = 0 };
    }

    fn ret(src: u16) TacInst {
        return .{ .op = .ret, .dst = 0, .src1 = src, .src2 = 0 };
    }
};

// ── Basic Block ──────────────────────────────────────────────────────
// A basic block is a maximal sequence of instructions with one entry
// point (the first instruction) and one exit (the last). No branches
// enter the middle; no branches leave except at the end.

const Terminator = union(enum) {
    ret: u16, // return temp
    jump: u16, // jump to block id
    branch: struct { // conditional branch
        cond: u16, // temp holding condition
        then_block: u16,
        else_block: u16,
    },
};

const BasicBlock = struct {
    id: u16,
    insts: [16]TacInst,
    inst_count: usize,
    term: Terminator,

    fn addInst(self: *BasicBlock, inst: TacInst) void {
        self.insts[self.inst_count] = inst;
        self.inst_count += 1;
    }
};

// ── SSA ──────────────────────────────────────────────────────────────
// In SSA form every variable is assigned exactly once. When control
// flow merges (e.g., after an if/else), phi nodes select which
// definition reaches the merge point.

const PhiSource = struct {
    block: u16, // predecessor block id
    value: u16, // SSA variable from that predecessor
};

const SSAOp = union(enum) {
    phi: struct {
        dst: u16,
        sources: [4]PhiSource,
        source_count: usize,
    },
    load_const: struct { dst: u16, val: i64 },
    binary: struct {
        op: TacOp,
        dst: u16,
        left: u16,
        right: u16,
    },
    copy: struct { dst: u16, src: u16 },
    ret: struct { src: u16 },
};

const SSABlock = struct {
    id: u16,
    ops: [16]SSAOp,
    op_count: usize,

    fn addOp(self: *SSABlock, op: SSAOp) void {
        self.ops[self.op_count] = op;
        self.op_count += 1;
    }
};

// ── Simple TAC Interpreter ───────────────────────────────────────────
// Executes a sequence of TAC instructions and returns the ret value.
fn interpretTac(program: []const TacInst) !i64 {
    var temps: [256]i64 = [_]i64{0} ** 256;

    for (program) |inst| {
        switch (inst.op) {
            .load_const => {
                temps[inst.dst] = inst.src1;
            },
            .add => {
                temps[inst.dst] = temps[@intCast(inst.src1)] + temps[@intCast(inst.src2)];
            },
            .sub => {
                temps[inst.dst] = temps[@intCast(inst.src1)] - temps[@intCast(inst.src2)];
            },
            .mul => {
                temps[inst.dst] = temps[@intCast(inst.src1)] * temps[@intCast(inst.src2)];
            },
            .div => {
                const divisor = temps[@intCast(inst.src2)];
                if (divisor == 0) return error.DivisionByZero;
                temps[inst.dst] = @divTrunc(temps[@intCast(inst.src1)], divisor);
            },
            .neg => {
                temps[inst.dst] = -temps[@intCast(inst.src1)];
            },
            .copy => {
                temps[inst.dst] = temps[@intCast(inst.src1)];
            },
            .ret => {
                return temps[@intCast(inst.src1)];
            },
        }
    }
    return error.NoReturn;
}

// ── Tests ────────────────────────────────────────────────────────────
fn testThreeAddressCode() !void {
    // Represent: result = (3 + 4) * (2 - 1)
    // t0 = 3
    // t1 = 4
    // t2 = t0 + t1     → 7
    // t3 = 2
    // t4 = 1
    // t5 = t3 - t4     → 1
    // t6 = t2 * t5     → 7
    // return t6
    const program = [_]TacInst{
        TacInst.loadConst(0, 3),
        TacInst.loadConst(1, 4),
        TacInst.binary(.add, 2, 0, 1),
        TacInst.loadConst(3, 2),
        TacInst.loadConst(4, 1),
        TacInst.binary(.sub, 5, 3, 4),
        TacInst.binary(.mul, 6, 2, 5),
        TacInst.ret(6),
    };

    try expect(program.len == 8);
    try expect(program[0].op == .load_const);
    try expect(program[2].op == .add);
    try expect(program[6].op == .mul);
}

fn testBasicBlocks() !void {
    // Two basic blocks:
    //   BB0: t0 = 10, t1 = 20, t2 = t0 + t1 → jump BB1
    //   BB1: return t2
    var bb0 = BasicBlock{
        .id = 0,
        .insts = undefined,
        .inst_count = 0,
        .term = .{ .jump = 1 },
    };
    bb0.addInst(TacInst.loadConst(0, 10));
    bb0.addInst(TacInst.loadConst(1, 20));
    bb0.addInst(TacInst.binary(.add, 2, 0, 1));

    try expect(bb0.inst_count == 3);
    try expect(bb0.id == 0);

    var bb1 = BasicBlock{
        .id = 1,
        .insts = undefined,
        .inst_count = 0,
        .term = .{ .ret = 2 },
    };
    _ = &bb1;

    // Verify the terminator types
    switch (bb0.term) {
        .jump => |target| try expect(target == 1),
        else => return error.WrongTerminator,
    }
    switch (bb1.term) {
        .ret => |src| try expect(src == 2),
        else => return error.WrongTerminator,
    }
}

fn testSSA() !void {
    // SSA for: if cond then x=1 else x=2; use x
    //   BB0: t0 = cond → branch(t0, BB1, BB2)
    //   BB1: t1 = 1 → jump BB3
    //   BB2: t2 = 2 → jump BB3
    //   BB3: t3 = phi(BB1:t1, BB2:t2), return t3

    var bb3 = SSABlock{
        .id = 3,
        .ops = undefined,
        .op_count = 0,
    };

    // Phi node: t3 = phi(BB1→t1, BB2→t2)
    bb3.addOp(.{ .phi = .{
        .dst = 3,
        .sources = .{
            .{ .block = 1, .value = 1 },
            .{ .block = 2, .value = 2 },
            undefined,
            undefined,
        },
        .source_count = 2,
    } });

    bb3.addOp(.{ .ret = .{ .src = 3 } });

    try expect(bb3.op_count == 2);

    // Verify phi node structure
    switch (bb3.ops[0]) {
        .phi => |phi| {
            try expect(phi.dst == 3);
            try expect(phi.source_count == 2);
            try expect(phi.sources[0].block == 1);
            try expect(phi.sources[0].value == 1);
            try expect(phi.sources[1].block == 2);
            try expect(phi.sources[1].value == 2);
        },
        else => return error.ExpectedPhi,
    }

    // SSA invariant: each variable assigned exactly once
    var bb1 = SSABlock{ .id = 1, .ops = undefined, .op_count = 0 };
    bb1.addOp(.{ .load_const = .{ .dst = 1, .val = 1 } });

    var bb2 = SSABlock{ .id = 2, .ops = undefined, .op_count = 0 };
    bb2.addOp(.{ .load_const = .{ .dst = 2, .val = 2 } });

    // t1 defined only in bb1, t2 only in bb2, t3 only in bb3
    try expect(bb1.op_count == 1);
    try expect(bb2.op_count == 1);
}

fn testIRInterpreter() !void {
    // Interpret: (10 + 20) * 3 = 90
    const program = [_]TacInst{
        TacInst.loadConst(0, 10),
        TacInst.loadConst(1, 20),
        TacInst.binary(.add, 2, 0, 1),
        TacInst.loadConst(3, 3),
        TacInst.binary(.mul, 4, 2, 3),
        TacInst.ret(4),
    };

    const result = try interpretTac(&program);
    try expect(result == 90);

    // Interpret: 100 / 4 - 5 = 20
    const program2 = [_]TacInst{
        TacInst.loadConst(0, 100),
        TacInst.loadConst(1, 4),
        TacInst.binary(.div, 2, 0, 1),
        TacInst.loadConst(3, 5),
        TacInst.binary(.sub, 4, 2, 3),
        TacInst.ret(4),
    };

    const result2 = try interpretTac(&program2);
    try expect(result2 == 20);
}
