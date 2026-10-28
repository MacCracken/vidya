// Vidya — Audio Synthesis — Zig port. Q15 fixed-point.

const std = @import("std");

const SCALE: u6 = 15;
const ONE: i64 = 32768;
const PHASE_MASK: i64 = 65535;
const PHASE_HALF: i64 = 32768;

fn qMul(a: i64, b: i64) i64 {
    const p = a * b;
    return if (p < 0) -(@divTrunc(-p, 1 << SCALE)) else @divTrunc(p, 1 << SCALE);
}

fn phaseAdvance(current: i64, inc: i64) i64 {
    return (current + inc) & PHASE_MASK;
}

const SINE_TABLE = [_]i64{
    0, 12540, 23170, 30274, 32767, 30274, 23170, 12540,
    0, -12540, -23170, -30274, -32767, -30274, -23170, -12540,
};

fn oscSine(phase: i64) i64 { return SINE_TABLE[@intCast(phase >> 12)]; }
fn oscSaw(phase: i64) i64 { return phase - PHASE_HALF; }
fn oscSquare(phase: i64) i64 { return if (phase < PHASE_HALF) 32767 else -32767; }

const EnvState = enum { idle, attack, decay, sustain, release };

const Adsr = struct {
    state: EnvState = .idle,
    level: i64 = 0,
    stage_samples: i64 = 0,
    release_start: i64 = 0,
    attack_samples: i64 = 0,
    decay_samples: i64 = 0,
    sustain_level: i64 = 0,
    release_samples: i64 = 0,

    fn setParams(self: *Adsr, attack: i64, decay: i64, sustain: i64, release: i64) void {
        self.attack_samples = attack;
        self.decay_samples = decay;
        self.sustain_level = sustain;
        self.release_samples = release;
    }
    fn gateOn(self: *Adsr) void {
        self.state = .attack;
        self.stage_samples = 0;
    }
    fn gateOff(self: *Adsr) bool {
        if (self.state == .idle) return false;
        self.release_start = self.level;
        self.state = .release;
        self.stage_samples = 0;
        return true;
    }
    fn step(self: *Adsr) i64 {
        switch (self.state) {
            .idle => { self.level = 0; return 0; },
            .attack => {
                const inc = @divTrunc(ONE, self.attack_samples);
                self.level += inc;
                self.stage_samples += 1;
                if (self.stage_samples >= self.attack_samples) {
                    self.level = ONE;
                    self.state = .decay;
                    self.stage_samples = 0;
                }
                return self.level;
            },
            .decay => {
                const dec = @divTrunc(ONE - self.sustain_level, self.decay_samples);
                self.level -= dec;
                self.stage_samples += 1;
                if (self.stage_samples >= self.decay_samples) {
                    self.level = self.sustain_level;
                    self.state = .sustain;
                    self.stage_samples = 0;
                }
                return self.level;
            },
            .sustain => { self.level = self.sustain_level; return self.level; },
            .release => {
                const dec = @divTrunc(self.release_start, self.release_samples);
                self.level -= dec;
                self.stage_samples += 1;
                if (self.stage_samples >= self.release_samples) {
                    self.level = 0;
                    self.state = .idle;
                    self.stage_samples = 0;
                }
                return self.level;
            },
        }
    }
};

const Wave = enum { sine, saw, square };

const Voice = struct {
    waveform: Wave,
    phase: i64 = 0,
    phase_inc: i64,

    fn oscillator(self: *const Voice, phase: i64) i64 {
        return switch (self.waveform) {
            .sine => oscSine(phase),
            .saw => oscSaw(phase),
            .square => oscSquare(phase),
        };
    }
    fn step(self: *Voice, env: *Adsr) i64 {
        const osc = self.oscillator(self.phase);
        self.phase = phaseAdvance(self.phase, self.phase_inc);
        const e = env.step();
        return qMul(osc, e);
    }
};

var pass_count: i32 = 0;
var fail_count: i32 = 0;
fn check(cond: bool, name: []const u8) void {
    if (cond) {
        pass_count += 1;
    } else {
        fail_count += 1;
        std.debug.print("  FAIL: {s}\n", .{name});
    }
}

pub fn main() !void {
    check(phaseAdvance(60000, 10000) == 4464, "phase wraps");
    check(phaseAdvance(0, 1000) == 1000, "phase advances");

    check(oscSine(0) == 0, "sin(0)");
    check(oscSine(16384) == 32767, "sin(π/2)");
    check(oscSine(32768) == 0, "sin(π)");
    check(oscSine(49152) == -32767, "sin(3π/2)");

    check(oscSaw(0) == -PHASE_HALF, "saw(0)");
    check(oscSaw(PHASE_HALF) == 0, "saw(π)");
    check(oscSaw(65535) == 32767, "saw(near max)");

    check(oscSquare(0) == 32767, "square first half");
    check(oscSquare(PHASE_HALF) == -32767, "square second half");
    check(oscSquare(32767) == 32767, "square just before half");
    check(oscSquare(65535) == -32767, "square at end");

    {
        var e = Adsr{}; e.setParams(4, 4, 16384, 4); e.gateOn();
        var i: i32 = 0; while (i < 4) : (i += 1) _ = e.step();
        check(e.state == .decay, "attack → decay");
        check(e.level == ONE, "level = ONE");
    }
    {
        var e = Adsr{}; e.setParams(4, 4, 16384, 4); e.gateOn();
        var i: i32 = 0; while (i < 8) : (i += 1) _ = e.step();
        check(e.state == .sustain, "decay → sustain");
        check(e.level == 16384, "level = sustain");
    }
    {
        var e = Adsr{}; e.setParams(4, 4, 16384, 4); e.gateOn();
        var i: i32 = 0; while (i < 8) : (i += 1) _ = e.step();
        i = 0; while (i < 100) : (i += 1) _ = e.step();
        check(e.state == .sustain, "sustain holds");
        check(e.level == 16384, "level held");
    }
    {
        var e = Adsr{}; e.setParams(4, 4, 16384, 4); e.gateOn();
        var i: i32 = 0; while (i < 8) : (i += 1) _ = e.step();
        _ = e.gateOff();
        check(e.release_start == 16384, "release_start captured");
        i = 0; while (i < 4) : (i += 1) _ = e.step();
        check(e.state == .idle, "release → idle");
        check(e.level == 0, "level = 0");
    }
    {
        var e = Adsr{}; e.setParams(8, 4, 16384, 4); e.gateOn();
        _ = e.step(); _ = e.step();
        _ = e.gateOff();
        check(e.release_start == 8192, "release captures partial-attack level");
    }
    {
        var e = Adsr{}; e.setParams(4, 4, 16384, 4);
        var v = Voice{ .waveform = .sine, .phase_inc = 8192 };
        check(v.step(&e) == 0, "voice silent when idle");
    }
    {
        var e = Adsr{}; e.setParams(4, 4, 16384, 4);
        var v = Voice{ .waveform = .sine, .phase_inc = 8192 };
        e.gateOn();
        var any_nonzero = false;
        var i: i32 = 0;
        while (i < 16) : (i += 1) if (v.step(&e) != 0) { any_nonzero = true; };
        check(any_nonzero, "voice audible when gated");
    }

    std.debug.print("=== audio_synthesis ===\n", .{});
    std.debug.print("{d} passed, {d} failed ({d} total)\n", .{ pass_count, fail_count, pass_count + fail_count });
    if (fail_count > 0) std.process.exit(1);
}
