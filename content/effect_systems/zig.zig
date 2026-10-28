// Vidya — Effect Systems in Zig
//
// A program that yields effect requests (ask, log, fail) instead of doing
// I/O, handlers that decide what each one means (resume with an answer, or
// stop), state threaded through step(state, input), capabilities passed as
// parameters, and a pure core behind a thin shell. Mirrors cyrius.cyr.
//
// OCaml 5, Koka, Unison and Eff have native effect handlers. Zig's
// async/suspend/resume went with the old C++ compiler in 0.11, so the
// program is a struct with a `step` method and a handler loop feeds each
// answer back in; a request is a `union(enum)`. std passes capabilities
// itself: files, stdout and clocks take the `Io` that `main(init)` receives.

const std = @import("std");
const Io = std.Io;
const print = std.debug.print;

fn check(ok: bool, what: []const u8) !void {
    if (!ok) {
        print("FAIL: {s}\n", .{what});
        return error.CheckFailed;
    }
}

// --- Shared helpers: messages and a log buffer ---
const LINE_CAP = 32;

// "rate=" ++ 3 -> "rate=3", written into buf. The prefix is comptime, so the
// compiler proves the longest i64 (20 characters) still fits: bufPrint
// cannot run out of room, and `catch unreachable` states a checked fact.
fn msgKv(buf: *[LINE_CAP]u8, comptime prefix: []const u8, n: i64) []const u8 {
    comptime std.debug.assert(prefix.len + 20 <= LINE_CAP);
    return std.fmt.bufPrint(buf, prefix ++ "{d}", .{n}) catch unreachable;
}

// A log buffer: up to LOG_CAP lines, each copied in.
const LOG_CAP = 8;
const Log = struct {
    count: usize = 0,
    lines: [LOG_CAP][LINE_CAP]u8 = undefined,
    lens: [LOG_CAP]usize = undefined,

    fn push(self: *Log, msg: []const u8) void {
        if (self.count == LOG_CAP) return;
        const n = @min(msg.len, LINE_CAP);
        @memcpy(self.lines[self.count][0..n], msg[0..n]);
        self.lens[self.count] = n;
        self.count += 1;
    }
    fn line(self: *const Log, i: usize) ?[]const u8 {
        if (i >= self.count) return null;
        return self.lines[i][0..self.lens[i]];
    }
    // Null-safe for the checks: a missing line is a failed check, not a crash.
    fn lineIs(self: *const Log, i: usize, s: []const u8) bool {
        return strIs(self.line(i), s);
    }
};

fn strIs(p: ?[]const u8, s: []const u8) bool {
    const v = p orelse return false;
    return std.mem.eql(u8, v, s);
}

// The one real output channel, used only by the production handlers. It
// needs the Io capability to write at all.
var g_stdout_lines: usize = 0;
fn stdoutLine(io: Io, msg: []const u8) !void {
    const out = Io.File.stdout();
    try out.writeStreamingAll(io, "  [prod] ");
    try out.writeStreamingAll(io, msg);
    try out.writeStreamingAll(io, "\n");
    g_stdout_lines += 1;
}

// --- 1. Effects as data, and an interpreter ---
// A request names an effect and carries its payload; the program never
// performs it. `done` is not an effect: it is how the program returns.
const Eff = union(enum) {
    ask: []const u8, // key
    log: []const u8, // message
    fail: []const u8, // reason
    done: i64, // the program's return value
};

// A handler's answer. `resume` is still a reserved word in Zig 0.17, a
// leftover of the removed async, hence `resume_with`.
const Reply = union(enum) {
    resume_with: i64,
    stop: ?[]const u8, // null: a stop that carries no reason
};

// What running a program under a handler gives back.
const Outcome = union(enum) {
    finished: i64,
    stopped: ?[]const u8,
};

// The program, as it would read with native handlers (OCaml 5, Koka):
//   rate = perform Ask("rate")
//   perform Log("rate=" ^ rate)
//   if qty <= 0 then perform Fail("empty order")
//   perform Log("total=" ^ qty * rate)
//   return qty * rate
// `step` is that program cut at each effect: it returns the next request,
// and the next call resumes it with the answer. The struct is the suspended
// rest of the program; `steps` counts how many times it ran, so a check can
// see what a handler cut short. A log message is a slice of `msg`, which
// the next step overwrites: a handler that keeps one must copy it.
const Checkout = struct {
    pc: u8 = 0,
    qty: i64,
    rate: i64 = 0,
    steps: u32 = 0,
    msg: [LINE_CAP]u8 = undefined,

    fn init(qty: i64) Checkout {
        return .{ .qty = qty };
    }

    fn step(self: *Checkout, answer: i64) Eff {
        self.steps += 1;
        switch (self.pc) {
            0 => {
                self.pc = 1;
                return .{ .ask = "rate" };
            },
            1 => {
                self.rate = answer; // resumed with Ask's answer
                self.pc = 2;
                return .{ .log = msgKv(&self.msg, "rate=", answer) };
            },
            2 => {
                self.pc = 3;
                if (self.qty <= 0) return .{ .fail = "empty order" };
                return .{ .log = msgKv(&self.msg, "total=", self.qty * self.rate) };
            },
            else => {
                self.pc = 4;
                return .{ .done = self.qty * self.rate };
            },
        }
    }
};

// A handler is a context pointer plus a fn pointer: one handleWith serves
// every handler value, through an indirect call.
const Handler = struct {
    ctx: *anyopaque,
    handleFn: *const fn (ctx: *anyopaque, req: Eff) Reply,

    fn handle(self: Handler, req: Eff) Reply {
        return self.handleFn(self.ctx, req);
    }
};

// The interpreter: run any step-function program under any handler. It does
// not know what ask, log or fail mean: the handler decides. The program is
// `anytype`: any type with a `step(answer) Eff` method works, checked at
// comptime, and each program type gets its own copy with a direct call.
fn handleWith(handler: Handler, program: anytype) Outcome {
    var answer: i64 = 0;
    while (true) {
        const req = program.step(answer);
        if (req == .done) return .{ .finished = req.done };
        switch (handler.handle(req)) {
            .resume_with => |v| answer = v,
            .stop => |reason| return .{ .stopped = reason },
        }
    }
}

// Production handler: ask reads the process configuration, log writes to
// stdout through the Io it holds, fail is reported and stops the program.
// A stdout write that fails is a stop too: the handler decides that.
const ProdEnv = struct {
    io: Io,
    config_rate: i64,
};

fn prodHandle(ctx: *anyopaque, req: Eff) Reply {
    const env: *ProdEnv = @ptrCast(@alignCast(ctx));
    switch (req) {
        .ask => |key| {
            if (std.mem.eql(u8, key, "rate")) return .{ .resume_with = env.config_rate };
            return .{ .stop = "unknown key" };
        },
        .log => |msg| {
            stdoutLine(env.io, msg) catch return .{ .stop = "stdout write failed" };
            return .{ .resume_with = 0 };
        },
        .fail => |reason| {
            stdoutLine(env.io, reason) catch {};
            return .{ .stop = reason };
        },
        .done => return .{ .stop = null },
    }
}

fn prodHandler(env: *ProdEnv) Handler {
    return .{ .ctx = env, .handleFn = prodHandle };
}

// Test handler: a fixed environment (the rate it answers) and a log buffer
// it records into. The env struct holds what a closure would capture; the
// caller owns it and keeps it alive for the whole run. No I/O, nothing global.
const TestEnv = struct {
    rate: i64,
    log: *Log,
};

fn testHandle(ctx: *anyopaque, req: Eff) Reply {
    const env: *TestEnv = @ptrCast(@alignCast(ctx));
    switch (req) {
        .ask => |key| {
            if (std.mem.eql(u8, key, "rate")) return .{ .resume_with = env.rate };
            return .{ .stop = "unknown key" };
        },
        .log => |msg| {
            env.log.push(msg);
            return .{ .resume_with = 0 };
        },
        .fail => |reason| return .{ .stop = reason }, // do not resume: the failure is the result
        .done => return .{ .stop = null },
    }
}

fn testHandler(env: *TestEnv) Handler {
    return .{ .ctx = env, .handleFn = testHandle };
}

// --- 2. Resumable handlers ---
// ask is answered and the program RESUMES with the answer: handleWith
// passes the handler's value to the next step call. Two handlers that
// answer differently get different results from the same program. (A
// native handler resumes a captured continuation, and OCaml 5's are
// one-shot. Here the continuation is a plain struct, so a copy of it could
// be resumed twice: nothing in Zig stops that.) Zig 0.17 refuses
// `suspend {}` with "async has not been implemented in the self-hosted
// compiler yet", and std.Io.async calls a function, at once or on another
// unit of concurrency, and hands back a Future for its result: neither
// gives a handler a paused function to resume.

// --- 3. A non-resuming effect is an early exit ---
// The test handler answers fail by NOT resuming, so the rest of the
// program never runs: no "total=" line, and no further steps. That is an
// exception built from a handler. The same mechanism is the gotcha when it
// is an accident: a handler that forgets to resume after log stops the
// program just as silently. The switch must name every tag, but nothing
// makes an arm resume.
fn forgetfulHandle(ctx: *anyopaque, req: Eff) Reply {
    const env: *TestEnv = @ptrCast(@alignCast(ctx));
    switch (req) {
        .ask => return .{ .resume_with = env.rate },
        .log => |msg| {
            env.log.push(msg);
            return .{ .stop = null }; // BUG: should be .{ .resume_with = 0 }
        },
        .fail => |reason| return .{ .stop = reason },
        .done => return .{ .stop = null },
    }
}

fn forgetfulHandler(env: *TestEnv) Handler {
    return .{ .ctx = env, .handleFn = forgetfulHandle };
}

// --- 4. State as an effect ---
// step(state, input) -> (output, new_state). The state is a value the
// caller threads through, not a hidden variable: tallyStep takes it as
// *const and builds a new one, so every earlier state is still readable.
// (*const refuses a direct write; @constCast could still defeat it, which
// the s0 checks below would catch.) A State effect (Get / Put) interpreted
// by a handler comes down to exactly this threading. The output is the
// running mean, @divFloor(total, count).
const Tally = struct {
    count: i64,
    total: i64,
};

const TallyStep = struct {
    out: i64,
    next: Tally,
};

fn tallyStep(st: *const Tally, x: i64) TallyStep {
    const next: Tally = .{ .count = st.count + 1, .total = st.total + x };
    return .{ .out = @divFloor(next.total, next.count), .next = next };
}

// --- 5. Capability passing ---
// sessionCheck needs the time and a logger. It takes them as a parameter
// instead of reaching for globals, so a test can pass a fake clock and a
// recording logger. `caps: anytype` is comptime duck typing: any value with
// `now()` and `log(msg)` methods works, each caps type gets its own copy of
// sessionCheck, and the calls are direct (inlinable): choosing the
// capability costs nothing at run time. A struct of fn pointers, like
// Handler above, would trade that for one compiled copy and an indirect call.
fn sessionCheck(caps: anytype, expires_at: i64) bool {
    const now = caps.now();
    var buf: [LINE_CAP]u8 = undefined;
    if (now < expires_at) {
        caps.log(msgKv(&buf, "valid at ", now));
        return true;
    }
    caps.log(msgKv(&buf, "expired at ", now));
    return false;
}

// Production capabilities. A real program would read
// `Io.Clock.real.now(io)`: in Zig the wall clock, too, is reached through
// the Io capability. This file stays deterministic, so the "system clock"
// is a global that moves forward on every read. That global is exactly the
// hidden state the capability keeps out of sessionCheck.
var g_sys_time: i64 = 1000;
var g_clock_reads: usize = 0;

const SysCaps = struct {
    io: Io,

    fn now(_: SysCaps) i64 {
        g_clock_reads += 1;
        const t = g_sys_time;
        g_sys_time += 1;
        return t;
    }
    fn log(self: SysCaps, msg: []const u8) void {
        stdoutLine(self.io, msg) catch {};
    }
};

// Test capabilities: a clock stopped at t, and a logger into a buffer.
const FakeCaps = struct {
    t: i64,
    out: *Log,

    fn now(self: FakeCaps) i64 {
        return self.t;
    }
    fn log(self: FakeCaps, msg: []const u8) void {
        self.out.push(msg);
    }
};

// --- 6. Functional core, imperative shell ---
// A thermostat. The core, decide(heater, temp) -> (new_heater, commands),
// is pure: it reads only its arguments and returns the commands as data.
// Hysteresis: heat on below 19, off above 21; an alarm at 15 or below.
// The shell is the only code that touches the device. Zig can prove the
// purity a little: the comptime block below runs coreRun inside the
// compiler, which works only because the core touches no runtime state.
// `comptime shellRun(...)` is refused ("unable to evaluate comptime
// expression": it writes the runtime device globals).
const Heater = enum { off, on };
const CmdTag = enum { heat_on, heat_off, alarm };
const Cmd = struct {
    tag: CmdTag,
    temp: i64,
};

const CMDS_CAP = 16;
const Cmds = struct {
    count: usize = 0,
    items: [CMDS_CAP]Cmd = undefined,

    fn push(self: *Cmds, tag: CmdTag, temp: i64) void {
        if (self.count == CMDS_CAP) return;
        self.items[self.count] = .{ .tag = tag, .temp = temp };
        self.count += 1;
    }
    fn slice(self: *const Cmds) []const Cmd {
        return self.items[0..self.count];
    }
    fn is(self: *const Cmds, i: usize, tag: CmdTag, temp: i64) bool {
        if (i >= self.count) return false;
        return self.items[i].tag == tag and self.items[i].temp == temp;
    }
};

const Decision = struct {
    heater: Heater,
    cmds: Cmds = .{},
};

fn decide(heater: Heater, temp: i64) Decision {
    var d: Decision = .{ .heater = heater };
    if (heater == .off and temp < 19) {
        d.heater = .on;
        d.cmds.push(.heat_on, temp);
    }
    if (heater == .on and temp > 21) {
        d.heater = .off;
        d.cmds.push(.heat_off, temp);
    }
    if (temp <= 15) d.cmds.push(.alarm, temp);
    return d;
}

// The core over a run of events: still pure (it only calls decide).
fn coreRun(evs: []const i64) Decision {
    var all: Decision = .{ .heater = .off };
    for (evs) |temp| {
        const d = decide(all.heater, temp);
        for (d.cmds.slice()) |c| all.cmds.push(c.tag, c.temp);
        all.heater = d.heater;
    }
    return all;
}

// Every threshold is hit exactly, so an off-by-one comparison fails: 19
// while off and 21 while on emit nothing (not below 19, not above 21), 15
// alarms and 16 does not. 17 arrives while the heater is on and 23 while it
// is off, so a decide that ignores its state fails too, and 14 alarms with
// the heater already on.
const events = [_]i64{ 19, 18, 17, 21, 22, 23, 15, 16, 14 };

comptime {
    if (coreRun(&events).cmds.count != 5) @compileError("the pure core runs at compile time: 5 commands");
}

// The shell: the device registers it drives, and the loop that executes
// each command the core returns.
var g_heater_pin: u1 = 0;
var g_alarms_raised: usize = 0;

fn shellExecute(cmds: *const Cmds) void {
    for (cmds.slice()) |c| switch (c.tag) {
        .heat_on => g_heater_pin = 1,
        .heat_off => g_heater_pin = 0,
        .alarm => g_alarms_raised += 1,
    };
}

fn shellRun(evs: []const i64) Heater {
    var heater: Heater = .off;
    for (evs) |temp| {
        const d = decide(heater, temp);
        shellExecute(&d.cmds);
        heater = d.heater;
    }
    return heater;
}

// === Tests ===

fn testEffectsAsData(io: Io) !void {
    var log: Log = .{};
    var env: TestEnv = .{ .rate = 3, .log = &log };
    var st = Checkout.init(10);
    const o = handleWith(testHandler(&env), &st);
    try check(o == .finished, "test handler: checkout(10) finished");
    try check(o == .finished and o.finished == 30, "test handler: checkout(10) at rate 3 = 30");
    try check(log.count == 2, "test handler captured 2 log lines");
    try check(log.lineIs(0, "rate=3"), "log line 0 is \"rate=3\"");
    try check(log.lineIs(1, "total=30"), "log line 1 is \"total=30\"");

    // The same program under the production handler: real output.
    const before = g_stdout_lines;
    var penv: ProdEnv = .{ .io = io, .config_rate = 4 };
    var pst = Checkout.init(10);
    const p = handleWith(prodHandler(&penv), &pst);
    try check(p == .finished, "production handler: checkout(10) finished");
    try check(p == .finished and p.finished == 40, "production handler: config rate 4 gives 40");
    try check(g_stdout_lines - before == 2, "production handler wrote its 2 log lines to stdout");
}

fn valueOf(o: Outcome) ?i64 {
    return switch (o) {
        .finished => |v| v,
        .stopped => null,
    };
}

fn testResumable() !void {
    var log3: Log = .{};
    var log5: Log = .{};
    var env3: TestEnv = .{ .rate = 3, .log = &log3 };
    var env5: TestEnv = .{ .rate = 5, .log = &log5 };
    var st3 = Checkout.init(10);
    var st5 = Checkout.init(10);
    const v3 = valueOf(handleWith(testHandler(&env3), &st3));
    const v5 = valueOf(handleWith(testHandler(&env5), &st5));
    try check(v3 == 30, "resumed with 3: 10 * 3 = 30");
    try check(v5 == 50, "resumed with 5: 10 * 5 = 50");
    try check(v3 != v5, "the answer the handler supplies decides the result");
    try check(log5.lineIs(0, "rate=5"), "the resumed program logged the answer it got");
}

fn reasonOf(o: Outcome) ?[]const u8 {
    return switch (o) {
        .finished => null,
        .stopped => |r| r,
    };
}

fn testEarlyExit() !void {
    var log: Log = .{};
    var env: TestEnv = .{ .rate = 3, .log = &log };
    var st = Checkout.init(0);
    const o = handleWith(testHandler(&env), &st);
    try check(o == .stopped, "fail is not resumed: the run stops");
    try check(strIs(reasonOf(o), "empty order"), "the handler returns the failure, \"empty order\"");
    try check(log.count == 1, "only \"rate=3\" was logged: the \"total=\" step never ran");
    try check(st.steps == 3, "the program ran 3 steps (ask, log, fail), not 4");

    // The gotcha: a handler that forgets to resume after log.
    var flog: Log = .{};
    var fenv: TestEnv = .{ .rate = 3, .log = &flog };
    var fst = Checkout.init(10);
    const f = handleWith(forgetfulHandler(&fenv), &fst);
    try check(f == .stopped, "forgetful handler: the run stopped after the first log");
    try check(f == .stopped and f.stopped == null, "forgetful handler: and the stop carries no reason at all");
    try check(fst.steps == 2, "forgetful handler: 2 steps ran (ask, log), not 4");
}

fn testStateThreading() !void {
    const inputs = [_]i64{ 5, 10, 20 };
    var outs: [3]i64 = undefined;
    // states[0] is s0; states[i + 1] is the state after input i.
    var states: [4]Tally = undefined;
    states[0] = .{ .count = 0, .total = 0 };
    for (inputs, 0..) |x, i| {
        const r = tallyStep(&states[i], x);
        outs[i] = r.out;
        states[i + 1] = r.next;
    }
    const s0 = &states[0];
    const st = &states[3];
    try check(outs[0] == 5, "running mean after 5: 5 / 1 = 5");
    try check(outs[1] == 7, "running mean after 10: 15 / 2 = 7");
    try check(outs[2] == 11, "running mean after 20: 35 / 3 = 11");
    try check(st.count == 3, "final state: count 3");
    try check(st.total == 35, "final state: total 35");
    try check(s0.count == 0, "initial state unchanged: count still 0");
    try check(s0.total == 0, "initial state unchanged: total still 0");

    // Replaying from s0 gives the same final state: nothing hidden moved.
    var again = s0.*;
    for (inputs) |x| again = tallyStep(&again, x).next;
    try check(again.total == st.total, "replaying from s0 reaches the same total");
}

fn testCapabilities(io: Io) !void {
    const reads0 = g_clock_reads;
    const lines0 = g_stdout_lines;

    var log_a: Log = .{};
    const at100: FakeCaps = .{ .t = 100, .out = &log_a };
    try check(sessionCheck(at100, 150), "fake clock at 100, expiry 150: valid");
    try check(log_a.lineIs(0, "valid at 100"), "fake logger recorded \"valid at 100\"");

    var log_b: Log = .{};
    const at200: FakeCaps = .{ .t = 200, .out = &log_b };
    try check(!sessionCheck(at200, 150), "fake clock at 200, expiry 150: expired");
    try check(log_b.lineIs(0, "expired at 200"), "fake logger recorded \"expired at 200\"");

    try check(g_clock_reads - reads0 == 0, "the fakes never read the system clock");
    try check(g_stdout_lines - lines0 == 0, "the fakes never wrote to stdout");

    // The same function with the production capabilities.
    const prod: SysCaps = .{ .io = io };
    try check(!sessionCheck(prod, 150), "production clock at 1000, expiry 150: expired");
    try check(g_clock_reads - reads0 == 1, "production read the system clock once");
}

fn testFunctionalCore() !void {
    // The pure core alone: no device, just the commands it returns.
    const run = coreRun(&events);
    try check(run.cmds.count == 5, "core emitted 5 commands for 9 events");
    try check(run.cmds.is(0, .heat_on, 18), "command 0 is HEAT_ON(18)");
    try check(run.cmds.is(1, .heat_off, 22), "command 1 is HEAT_OFF(22)");
    try check(run.cmds.is(2, .heat_on, 15), "command 2 is HEAT_ON(15)");
    try check(run.cmds.is(3, .alarm, 15), "command 3 is ALARM(15)");
    try check(run.cmds.is(4, .alarm, 14), "command 4 is ALARM(14)");
    try check(run.heater == .on, "core's final state: heater on");

    const none = decide(.on, 20);
    try check(none.cmds.count == 0, "decide(on, 20): inside the band, no commands");
    try check(none.heater == .on, "decide(on, 20): the heater stays on");
    try check(g_heater_pin == 0 and g_alarms_raised == 0, "the core never touched the device");

    // The shell runs the same core and executes what it returns. The first
    // 6 events end just after HEAT_OFF(22): the pin must be off there, which
    // the final pin (on again) cannot show.
    _ = shellRun(events[0..6]);
    try check(g_heater_pin == 0, "shell, first 6 events: HEAT_OFF(22) drove the pin off");
    try check(shellRun(&events) == .on, "shell: final state heater on");
    try check(g_heater_pin == 1, "shell drove the heater pin on");
    try check(g_alarms_raised == 2, "shell raised the alarm twice");
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    try testEffectsAsData(io);
    try testResumable();
    try testEarlyExit();
    try testStateThreading();
    try testCapabilities(io);
    try testFunctionalCore();
    try Io.File.stdout().writeStreamingAll(io, "All effect system examples passed.\n");
}
