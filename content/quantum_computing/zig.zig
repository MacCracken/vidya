// Vidya — Quantum Computing in Zig
//
// Zig quantum simulation: comptime-known qubit counts enable
// stack-allocated state vectors, complex numbers as structs,
// and gate matrices as arrays. No allocator needed for small circuits.

const std = @import("std");
const expect = std.testing.expect;
const math = std.math;

pub fn main() !void {
    try testQubitBasics();
    try testHadamardGate();
    try testCnotGate();
    try testBellState();
    try testGrover2Qubit();
    try testQuantumPhase();
    try testGHZState();
    try testNoiseChannels();

    std.debug.print("All quantum computing examples passed.\n", .{});
}

// ── Complex number ────────────────────────────────────────────────────
const Complex = struct {
    re: f64,
    im: f64,

    fn init(re: f64, im: f64) Complex {
        return .{ .re = re, .im = im };
    }
    fn zero() Complex {
        return .{ .re = 0, .im = 0 };
    }
    fn one() Complex {
        return .{ .re = 1, .im = 0 };
    }
    fn mul(a: Complex, b: Complex) Complex {
        return .{
            .re = a.re * b.re - a.im * b.im,
            .im = a.re * b.im + a.im * b.re,
        };
    }
    fn add(a: Complex, b: Complex) Complex {
        return .{ .re = a.re + b.re, .im = a.im + b.im };
    }
    fn scale(a: Complex, s: f64) Complex {
        return .{ .re = a.re * s, .im = a.im * s };
    }
    fn normSq(a: Complex) f64 {
        return a.re * a.re + a.im * a.im;
    }
};

const H_VAL: f64 = 1.0 / @sqrt(2.0);

fn assertNear(a: f64, b: f64) !void {
    try expect(@abs(a - b) < 1e-10);
}

// ── Gate application ──────────────────────────────────────────────────
const Gate = [2][2]Complex;

fn applyGate(state: []Complex, target: usize, n_qubits: usize, gate: Gate) void {
    const size: usize = @as(usize, 1) << @intCast(n_qubits);
    const mask: usize = @as(usize, 1) << @intCast(target);
    for (0..size) |i| {
        if (i & mask != 0) continue;
        const j = i | mask;
        const a = state[i];
        const b = state[j];
        state[i] = gate[0][0].mul(a).add(gate[0][1].mul(b));
        state[j] = gate[1][0].mul(a).add(gate[1][1].mul(b));
    }
}

fn hadamard(state: []Complex, target: usize, n: usize) void {
    const h = Complex.init(H_VAL, 0);
    const mh = Complex.init(-H_VAL, 0);
    applyGate(state, target, n, .{ .{ h, h }, .{ h, mh } });
}

fn pauliX(state: []Complex, target: usize, n: usize) void {
    applyGate(state, target, n, .{
        .{ Complex.zero(), Complex.one() },
        .{ Complex.one(), Complex.zero() },
    });
}

fn pauliZ(state: []Complex, target: usize, n: usize) void {
    applyGate(state, target, n, .{
        .{ Complex.one(), Complex.zero() },
        .{ Complex.zero(), Complex.init(-1, 0) },
    });
}

fn cnot(state: []Complex, control: usize, target: usize, n_qubits: usize) void {
    const size: usize = @as(usize, 1) << @intCast(n_qubits);
    const cmask: usize = @as(usize, 1) << @intCast(control);
    const tmask: usize = @as(usize, 1) << @intCast(target);
    for (0..size) |i| {
        if ((i & cmask != 0) and (i & tmask == 0)) {
            const j = i | tmask;
            const tmp = state[i];
            state[i] = state[j];
            state[j] = tmp;
        }
    }
}

fn cz(state: []Complex, q0: usize, q1: usize, n_qubits: usize) void {
    const size: usize = @as(usize, 1) << @intCast(n_qubits);
    const m0: usize = @as(usize, 1) << @intCast(q0);
    const m1: usize = @as(usize, 1) << @intCast(q1);
    for (0..size) |i| {
        if ((i & m0 != 0) and (i & m1 != 0)) {
            state[i] = state[i].scale(-1);
        }
    }
}

fn initState(state: []Complex) void {
    for (state) |*s| s.* = Complex.zero();
    state[0] = Complex.one();
}

fn prob(state: []const Complex, idx: usize) f64 {
    return state[idx].normSq();
}

// ── Tests ─────────────────────────────────────────────────────────────
fn testQubitBasics() !void {
    var state: [2]Complex = undefined;
    initState(&state);
    try assertNear(prob(&state, 0), 1.0);
    try assertNear(prob(&state, 1), 0.0);

    initState(&state);
    pauliX(&state, 0, 1);
    try assertNear(prob(&state, 1), 1.0);
}

fn testHadamardGate() !void {
    var state: [2]Complex = undefined;
    initState(&state);
    hadamard(&state, 0, 1);
    try assertNear(prob(&state, 0), 0.5);
    try assertNear(prob(&state, 1), 0.5);
    hadamard(&state, 0, 1);
    try assertNear(prob(&state, 0), 1.0);
}

fn testCnotGate() !void {
    var state: [4]Complex = undefined;
    initState(&state);
    pauliX(&state, 1, 2);
    cnot(&state, 1, 0, 2);
    try assertNear(prob(&state, 0b11), 1.0);
}

fn testBellState() !void {
    var state: [4]Complex = undefined;
    initState(&state);
    hadamard(&state, 0, 2);
    cnot(&state, 0, 1, 2);
    try assertNear(prob(&state, 0b00), 0.5);
    try assertNear(prob(&state, 0b11), 0.5);
    try assertNear(prob(&state, 0b01), 0.0);
}

fn testGrover2Qubit() !void {
    var state: [4]Complex = undefined;
    initState(&state);
    hadamard(&state, 0, 2);
    hadamard(&state, 1, 2);
    cz(&state, 0, 1, 2);
    hadamard(&state, 0, 2);
    hadamard(&state, 1, 2);
    for (1..4) |i| {
        state[i] = state[i].scale(-1);
    }
    hadamard(&state, 0, 2);
    hadamard(&state, 1, 2);
    try assertNear(prob(&state, 0b11), 1.0);
}

fn testQuantumPhase() !void {
    var plus: [2]Complex = undefined;
    initState(&plus);
    hadamard(&plus, 0, 1);
    var minus: [2]Complex = undefined;
    initState(&minus);
    hadamard(&minus, 0, 1);
    pauliZ(&minus, 0, 1);

    try assertNear(prob(&plus, 0), prob(&minus, 0));
    try assertNear(plus[1].re, H_VAL);
    try assertNear(minus[1].re, -H_VAL);
}

fn testGHZState() !void {
    var state: [8]Complex = undefined;
    initState(&state);
    hadamard(&state, 0, 3);
    cnot(&state, 0, 1, 3);
    cnot(&state, 0, 2, 3);
    try assertNear(prob(&state, 0b000), 0.5);
    try assertNear(prob(&state, 0b111), 0.5);
    var total: f64 = 0;
    for (state) |s| total += s.normSq();
    try assertNear(total, 1.0);
}

fn testNoiseChannels() !void {
    // Depolarizing: prob(0) = 1 - 2p/3, total = 1
    const p: f64 = 0.1;
    const noisy_p0 = 1.0 - 2.0 * p / 3.0;
    const noisy_p1 = 2.0 * p / 3.0;
    try assertNear(noisy_p0 + noisy_p1, 1.0);

    // Dephasing
    const dephased: f64 = 0.5 * (1.0 - 0.2);
    try assertNear(dephased, 0.4);

    // Circuit fidelity
    const fidelity = math.pow(f64, 1.0 - 0.001, 100.0);
    try expect(@abs(fidelity - 0.9048) < 0.001);
}
