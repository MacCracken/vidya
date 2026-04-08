// Vidya — Optimization Passes in Zig
//
// Three classic compiler optimizations applied to a simple IR:
// 1. Constant folding — evaluate operations on known constants at compile time
// 2. Dead code elimination (DCE) — remove instructions whose results are unused
// 3. Strength reduction — replace expensive ops with cheaper equivalents
//
// Each pass transforms the IR in place and the tests verify the
// transformation is correct. Zig's tagged unions make pattern-matching
// on IR operations natural and exhaustive.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testConstantFolding();
    try testDeadCodeElimination();
    try testStrengthReduction();
    try testCombinedPasses();
    try testInterpreter();

    std.debug.print("All optimization passes examples passed.\n", .{});
}

// ── IR Definition ────────────────────────────────────────────────────
const BinOp = enum { add, sub, mul, div, shl, shr };

const IRInst = union(enum) {
    load_const: struct { dst: u16, val: i64 },
    binary: struct { op: BinOp, dst: u16, left: u16, right: u16 },
    copy: struct { dst: u16, src: u16 },
    ret: struct { src: u16 },
    nop: void, // dead instruction marker

    fn dst(self: IRInst) ?u16 {
        return switch (self) {
            .load_const => |op| op.dst,
            .binary => |op| op.dst,
            .copy => |op| op.dst,
            .ret, .nop => null,
        };
    }

    /// Check if this instruction references a given temp as a source.
    fn uses(self: IRInst, temp: u16) bool {
        return switch (self) {
            .load_const => false,
            .binary => |op| op.left == temp or op.right == temp,
            .copy => |op| op.src == temp,
            .ret => |op| op.src == temp,
            .nop => false,
        };
    }
};

const MAX_INSTS = 64;

const IRProgram = struct {
    insts: [MAX_INSTS]IRInst,
    len: usize,

    fn init() IRProgram {
        return .{ .insts = undefined, .len = 0 };
    }

    fn add(self: *IRProgram, inst: IRInst) void {
        self.insts[self.len] = inst;
        self.len += 1;
    }

    fn slice(self: *const IRProgram) []const IRInst {
        return self.insts[0..self.len];
    }
};

// ── Constant Folding ─────────────────────────────────────────────────
// If both operands of a binary op are known constants, replace the
// binary instruction with a load_const of the result.
fn constantFold(prog: *IRProgram) void {
    // Track which temps hold known constants
    var known: [256]?i64 = [_]?i64{null} ** 256;

    for (0..prog.len) |i| {
        switch (prog.insts[i]) {
            .load_const => |op| {
                known[op.dst] = op.val;
            },
            .binary => |op| {
                const lval = known[op.left];
                const rval = known[op.right];
                if (lval != null and rval != null) {
                    const result: ?i64 = switch (op.op) {
                        .add => lval.? +% rval.?,
                        .sub => lval.? -% rval.?,
                        .mul => lval.? *% rval.?,
                        .div => if (rval.? != 0) @divTrunc(lval.?, rval.?) else null,
                        .shl => lval.? << @intCast(@as(u6, @truncate(@as(u64, @bitCast(rval.?))))),
                        .shr => lval.? >> @intCast(@as(u6, @truncate(@as(u64, @bitCast(rval.?))))),
                    };
                    if (result) |val| {
                        prog.insts[i] = .{ .load_const = .{ .dst = op.dst, .val = val } };
                        known[op.dst] = val;
                    }
                } else {
                    known[op.dst] = null;
                }
            },
            .copy => |op| {
                known[op.dst] = known[op.src];
            },
            else => {},
        }
    }
}

// ── Dead Code Elimination ────────────────────────────────────────────
// An instruction is dead if its destination temp is never read by
// any subsequent instruction. We scan backward, tracking which temps
// are live (needed by later instructions).
fn eliminateDeadCode(prog: *IRProgram) void {
    var live: [256]bool = [_]bool{false} ** 256;

    // First pass: mark all temps that are used as sources
    for (prog.insts[0..prog.len]) |inst| {
        switch (inst) {
            .binary => |op| {
                live[op.left] = true;
                live[op.right] = true;
            },
            .copy => |op| {
                live[op.src] = true;
            },
            .ret => |op| {
                live[op.src] = true;
            },
            .load_const, .nop => {},
        }
    }

    // Second pass: kill instructions whose dst is never used
    for (0..prog.len) |i| {
        if (prog.insts[i].dst()) |d| {
            if (!live[d]) {
                prog.insts[i] = .nop;
            }
        }
    }
}

// ── Strength Reduction ───────────────────────────────────────────────
// Replace expensive operations with cheaper equivalents:
//   x * 2   → x + x        (or x << 1)
//   x * 1   → copy x
//   x * 0   → load_const 0
//   x + 0   → copy x
//   x - 0   → copy x
fn strengthReduce(prog: *IRProgram) void {
    var known: [256]?i64 = [_]?i64{null} ** 256;

    for (0..prog.len) |i| {
        switch (prog.insts[i]) {
            .load_const => |op| {
                known[op.dst] = op.val;
            },
            .binary => |op| {
                const lval = known[op.left];
                const rval = known[op.right];

                switch (op.op) {
                    .mul => {
                        // x * 0 → 0
                        if (rval != null and rval.? == 0) {
                            prog.insts[i] = .{ .load_const = .{ .dst = op.dst, .val = 0 } };
                            known[op.dst] = 0;
                            continue;
                        }
                        if (lval != null and lval.? == 0) {
                            prog.insts[i] = .{ .load_const = .{ .dst = op.dst, .val = 0 } };
                            known[op.dst] = 0;
                            continue;
                        }
                        // x * 1 → copy x
                        if (rval != null and rval.? == 1) {
                            prog.insts[i] = .{ .copy = .{ .dst = op.dst, .src = op.left } };
                            known[op.dst] = lval;
                            continue;
                        }
                        if (lval != null and lval.? == 1) {
                            prog.insts[i] = .{ .copy = .{ .dst = op.dst, .src = op.right } };
                            known[op.dst] = rval;
                            continue;
                        }
                        // x * 2 → x << 1 (strength reduction)
                        if (rval != null and rval.? == 2) {
                            prog.insts[i] = .{ .binary = .{
                                .op = .add,
                                .dst = op.dst,
                                .left = op.left,
                                .right = op.left,
                            } };
                            known[op.dst] = null;
                            continue;
                        }
                        known[op.dst] = null;
                    },
                    .add => {
                        // x + 0 → copy x
                        if (rval != null and rval.? == 0) {
                            prog.insts[i] = .{ .copy = .{ .dst = op.dst, .src = op.left } };
                            known[op.dst] = lval;
                            continue;
                        }
                        if (lval != null and lval.? == 0) {
                            prog.insts[i] = .{ .copy = .{ .dst = op.dst, .src = op.right } };
                            known[op.dst] = rval;
                            continue;
                        }
                        known[op.dst] = null;
                    },
                    .sub => {
                        // x - 0 → copy x
                        if (rval != null and rval.? == 0) {
                            prog.insts[i] = .{ .copy = .{ .dst = op.dst, .src = op.left } };
                            known[op.dst] = lval;
                            continue;
                        }
                        known[op.dst] = null;
                    },
                    else => {
                        known[op.dst] = null;
                    },
                }
            },
            .copy => |op| {
                known[op.dst] = known[op.src];
            },
            else => {},
        }
    }
}

// ── IR Interpreter ───────────────────────────────────────────────────
fn interpret(prog: *const IRProgram) !i64 {
    var temps: [256]i64 = [_]i64{0} ** 256;

    for (prog.insts[0..prog.len]) |inst| {
        switch (inst) {
            .load_const => |op| {
                temps[op.dst] = op.val;
            },
            .binary => |op| {
                const l = temps[op.left];
                const r = temps[op.right];
                temps[op.dst] = switch (op.op) {
                    .add => l +% r,
                    .sub => l -% r,
                    .mul => l *% r,
                    .div => if (r != 0) @divTrunc(l, r) else return error.DivisionByZero,
                    .shl => l << @intCast(@as(u6, @truncate(@as(u64, @bitCast(r))))),
                    .shr => l >> @intCast(@as(u6, @truncate(@as(u64, @bitCast(r))))),
                };
            },
            .copy => |op| {
                temps[op.dst] = temps[op.src];
            },
            .ret => |op| {
                return temps[op.src];
            },
            .nop => {},
        }
    }
    return error.NoReturn;
}

// ── Tests ────────────────────────────────────────────────────────────
fn testConstantFolding() !void {
    // t0 = 3, t1 = 4, t2 = t0 + t1
    // After folding: t2 should become load_const 7
    var prog = IRProgram.init();
    prog.add(.{ .load_const = .{ .dst = 0, .val = 3 } });
    prog.add(.{ .load_const = .{ .dst = 1, .val = 4 } });
    prog.add(.{ .binary = .{ .op = .add, .dst = 2, .left = 0, .right = 1 } });
    prog.add(.{ .ret = .{ .src = 2 } });

    constantFold(&prog);

    // The add should have been folded into a load_const
    switch (prog.insts[2]) {
        .load_const => |op| {
            try expect(op.dst == 2);
            try expect(op.val == 7);
        },
        else => return error.FoldingFailed,
    }

    // Chained folding: t0=2, t1=3, t2=t0*t1(=6), t3=t2+4(=10)
    var prog2 = IRProgram.init();
    prog2.add(.{ .load_const = .{ .dst = 0, .val = 2 } });
    prog2.add(.{ .load_const = .{ .dst = 1, .val = 3 } });
    prog2.add(.{ .binary = .{ .op = .mul, .dst = 2, .left = 0, .right = 1 } });
    prog2.add(.{ .load_const = .{ .dst = 3, .val = 4 } });
    prog2.add(.{ .binary = .{ .op = .add, .dst = 4, .left = 2, .right = 3 } });
    prog2.add(.{ .ret = .{ .src = 4 } });

    constantFold(&prog2);

    switch (prog2.insts[4]) {
        .load_const => |op| try expect(op.val == 10),
        else => return error.FoldingFailed,
    }
}

fn testDeadCodeElimination() !void {
    // t0 = 5          (dead — never used)
    // t1 = 10
    // t2 = 20
    // t3 = t1 + t2    (live — returned)
    // return t3
    var prog = IRProgram.init();
    prog.add(.{ .load_const = .{ .dst = 0, .val = 5 } }); // dead
    prog.add(.{ .load_const = .{ .dst = 1, .val = 10 } });
    prog.add(.{ .load_const = .{ .dst = 2, .val = 20 } });
    prog.add(.{ .binary = .{ .op = .add, .dst = 3, .left = 1, .right = 2 } });
    prog.add(.{ .ret = .{ .src = 3 } });

    eliminateDeadCode(&prog);

    // Instruction 0 (t0 = 5) should be eliminated
    switch (prog.insts[0]) {
        .nop => {}, // correct — dead code removed
        else => return error.DCEFailed,
    }

    // Instructions 1-4 should survive
    switch (prog.insts[1]) {
        .load_const => |op| try expect(op.val == 10),
        else => return error.DCEFailed,
    }
}

fn testStrengthReduction() !void {
    // t0 = x (unknown), t1 = 2, t2 = t0 * t1
    // After reduction: t2 = t0 + t0
    var prog = IRProgram.init();
    prog.add(.{ .load_const = .{ .dst = 0, .val = 7 } }); // pretend unknown at opt time
    prog.add(.{ .load_const = .{ .dst = 1, .val = 2 } });
    prog.add(.{ .binary = .{ .op = .mul, .dst = 2, .left = 0, .right = 1 } });
    prog.add(.{ .ret = .{ .src = 2 } });

    strengthReduce(&prog);

    // mul by 2 → add(x, x)
    switch (prog.insts[2]) {
        .binary => |op| {
            try expect(op.op == .add);
            try expect(op.left == 0);
            try expect(op.right == 0);
        },
        else => return error.ReductionFailed,
    }

    // x * 1 → copy x
    var prog2 = IRProgram.init();
    prog2.add(.{ .load_const = .{ .dst = 0, .val = 42 } });
    prog2.add(.{ .load_const = .{ .dst = 1, .val = 1 } });
    prog2.add(.{ .binary = .{ .op = .mul, .dst = 2, .left = 0, .right = 1 } });
    prog2.add(.{ .ret = .{ .src = 2 } });

    strengthReduce(&prog2);

    switch (prog2.insts[2]) {
        .copy => |op| try expect(op.src == 0),
        else => return error.ReductionFailed,
    }

    // x * 0 → 0
    var prog3 = IRProgram.init();
    prog3.add(.{ .load_const = .{ .dst = 0, .val = 99 } });
    prog3.add(.{ .load_const = .{ .dst = 1, .val = 0 } });
    prog3.add(.{ .binary = .{ .op = .mul, .dst = 2, .left = 0, .right = 1 } });
    prog3.add(.{ .ret = .{ .src = 2 } });

    strengthReduce(&prog3);

    switch (prog3.insts[2]) {
        .load_const => |op| try expect(op.val == 0),
        else => return error.ReductionFailed,
    }
}

fn testCombinedPasses() !void {
    // t0 = 3, t1 = 4, t2 = t0 + t1, t3 = 100 (dead), return t2
    // After constant folding + DCE:
    //   t2 = 7, t3 eliminated
    var prog = IRProgram.init();
    prog.add(.{ .load_const = .{ .dst = 0, .val = 3 } });
    prog.add(.{ .load_const = .{ .dst = 1, .val = 4 } });
    prog.add(.{ .binary = .{ .op = .add, .dst = 2, .left = 0, .right = 1 } });
    prog.add(.{ .load_const = .{ .dst = 3, .val = 100 } }); // dead
    prog.add(.{ .ret = .{ .src = 2 } });

    constantFold(&prog);
    eliminateDeadCode(&prog);

    // t0 and t1 are now dead (t2 was folded to a constant)
    switch (prog.insts[0]) {
        .nop => {},
        else => return error.PassFailed,
    }
    switch (prog.insts[1]) {
        .nop => {},
        else => return error.PassFailed,
    }
    // t3 = 100 is dead
    switch (prog.insts[3]) {
        .nop => {},
        else => return error.PassFailed,
    }
    // t2 is folded
    switch (prog.insts[2]) {
        .load_const => |op| try expect(op.val == 7),
        else => return error.PassFailed,
    }
}

fn testInterpreter() !void {
    // Verify that optimized and unoptimized programs produce the same result.
    // Original: (5 + 3) * 2
    var original = IRProgram.init();
    original.add(.{ .load_const = .{ .dst = 0, .val = 5 } });
    original.add(.{ .load_const = .{ .dst = 1, .val = 3 } });
    original.add(.{ .binary = .{ .op = .add, .dst = 2, .left = 0, .right = 1 } });
    original.add(.{ .load_const = .{ .dst = 3, .val = 2 } });
    original.add(.{ .binary = .{ .op = .mul, .dst = 4, .left = 2, .right = 3 } });
    original.add(.{ .ret = .{ .src = 4 } });

    const result_before = try interpret(&original);

    // Optimize
    var optimized = original;
    constantFold(&optimized);
    strengthReduce(&optimized);
    eliminateDeadCode(&optimized);

    const result_after = try interpret(&optimized);

    // Both must produce 16
    try expect(result_before == 16);
    try expect(result_after == 16);
}
