// Vidya — Effect Systems — Rust port.
//
// Side effects made explicit: a program that returns effect requests
// (Ask, Log, Fail), handlers that decide what each one means (resume with
// an answer, or stop), state threaded through step(state, input),
// capabilities passed as parameters, and a pure core behind a thin shell.
//
// OCaml 5, Koka, Unison and Eff have native effect handlers; Rust does
// not, and its coroutines (`#![feature(coroutines)]`) are unstable. So the
// program is an explicit step function (the state machine the compiler
// builds from an async fn) and a handler loop feeds each answer back in.
// Handlers are trait objects; section 5's capabilities are generics.

use std::sync::atomic::{AtomicI64, Ordering};

struct Checks {
    pass: u32,
    fail: u32,
}

impl Checks {
    fn check(&mut self, cond: bool, name: &str) {
        if cond {
            self.pass += 1;
        } else {
            self.fail += 1;
            println!("  FAIL: {name}");
        }
    }
}

// --- Shared helpers: null-safe log reads and the one real output channel ---
// A missing line is a failed check, not an index panic.
fn log_line_is(log: &[String], i: usize, s: &str) -> bool {
    log.get(i).is_some_and(|line| line == s)
}

// Counted beside the write, so a check can see who printed. Atomics are
// how safe Rust spells a mutable global.
static STDOUT_LINES: AtomicI64 = AtomicI64::new(0);

fn stdout_line(msg: &str) {
    println!("  [prod] {msg}");
    STDOUT_LINES.fetch_add(1, Ordering::Relaxed);
}

fn stdout_lines() -> i64 {
    STDOUT_LINES.load(Ordering::Relaxed)
}

// --- 1. Effects as data, and an interpreter ---
// A request names an effect and carries its payload; the program never
// performs it. Done is not an effect: it is how the program returns.
enum Eff {
    Ask(&'static str),
    Log(String),
    Fail(&'static str),
    Done(i64),
}

// A handler's answer: resume the program with a value, or stop it,
// with a reason or without one.
enum Resume {
    Continue(i64),
    Stop(Option<&'static str>),
}

// What running a program under a handler gives back.
#[derive(Debug, PartialEq)]
enum Outcome {
    Finished(i64),
    Stopped(Option<&'static str>),
}

// Any step-function program: each call runs it up to its next request,
// resumed with the answer to the previous one.
trait Program {
    fn step(&mut self, answer: i64) -> Eff;
}

trait Handler {
    fn handle(&mut self, request: Eff) -> Resume;
}

// The program, as it would read with native handlers (OCaml 5, Koka):
//   rate = perform Ask("rate")
//   perform Log("rate=" ^ rate)
//   if qty <= 0 then perform Fail("empty order")
//   perform Log("total=" ^ qty * rate)
//   return qty * rate
// Checkout is that program cut at each effect. Its fields are the
// suspended rest of the program; `steps` counts how many times it ran,
// so a check can see what a handler cut short.
struct Checkout {
    pc: u8,
    qty: i64,
    rate: i64,
    steps: u32,
}

impl Checkout {
    fn new(qty: i64) -> Self {
        Checkout { pc: 0, qty, rate: 0, steps: 0 }
    }
}

impl Program for Checkout {
    fn step(&mut self, answer: i64) -> Eff {
        self.steps += 1;
        match self.pc {
            0 => {
                self.pc = 1;
                Eff::Ask("rate")
            }
            1 => {
                self.rate = answer; // resumed with Ask's answer
                self.pc = 2;
                Eff::Log(format!("rate={answer}"))
            }
            2 => {
                self.pc = 3;
                if self.qty <= 0 {
                    return Eff::Fail("empty order");
                }
                Eff::Log(format!("total={}", self.qty * self.rate))
            }
            _ => {
                self.pc = 4;
                Eff::Done(self.qty * self.rate)
            }
        }
    }
}

// The interpreter: run any program under any handler. It does not know
// what Ask, Log or Fail mean: the handler decides.
fn handle_with(handler: &mut dyn Handler, program: &mut dyn Program) -> Outcome {
    let mut answer = 0;
    loop {
        match program.step(answer) {
            Eff::Done(value) => return Outcome::Finished(value),
            request => match handler.handle(request) {
                Resume::Continue(value) => answer = value,
                Resume::Stop(reason) => return Outcome::Stopped(reason),
            },
        }
    }
}

// Production handler: Ask reads the process configuration, Log writes
// to stdout, Fail is reported and stops the program.
const CONFIG: &[(&str, i64)] = &[("rate", 4)];

struct ProdHandler;

impl Handler for ProdHandler {
    fn handle(&mut self, request: Eff) -> Resume {
        match request {
            Eff::Ask(key) => match CONFIG.iter().find(|(k, _)| *k == key) {
                Some(&(_, value)) => Resume::Continue(value),
                None => Resume::Stop(Some("unknown key")),
            },
            Eff::Log(msg) => {
                stdout_line(&msg);
                Resume::Continue(0)
            }
            Eff::Fail(reason) => {
                stdout_line(reason);
                Resume::Stop(Some(reason))
            }
            Eff::Done(_) => Resume::Stop(None),
        }
    }
}

// Test handler: a fixed environment (the rate it answers) and a log
// buffer it records into. No I/O, nothing global.
struct TestHandler {
    rate: i64,
    log: Vec<String>,
}

fn test_handler(rate: i64) -> TestHandler {
    TestHandler { rate, log: Vec::new() }
}

impl Handler for TestHandler {
    fn handle(&mut self, request: Eff) -> Resume {
        match request {
            Eff::Ask("rate") => Resume::Continue(self.rate),
            Eff::Ask(_) => Resume::Stop(Some("unknown key")),
            Eff::Log(msg) => {
                self.log.push(msg);
                Resume::Continue(0)
            }
            Eff::Fail(reason) => Resume::Stop(Some(reason)), // do not resume: the failure is the result
            Eff::Done(_) => Resume::Stop(None),
        }
    }
}

// --- 2. Resumable handlers ---
// Ask is answered and the program RESUMES with the answer: the
// interpreter passes the handler's value to the next step call. Two
// handlers that answer differently get different results from the same
// program. (A native handler resumes a captured continuation; OCaml 5's
// are one-shot: a second `continue` raises
// Effect.Continuation_already_resumed.)

// --- 3. A non-resuming effect is an early exit ---
// The test handler answers Fail by NOT resuming, so the rest of the
// program never runs: no "total=" line, and no further steps. That is
// an exception built from a handler, and the same mechanism is the
// gotcha when it is an accident: a handler that forgets to resume after
// Log stops the program just as silently.
struct ForgetfulHandler {
    rate: i64,
    log: Vec<String>,
}

impl Handler for ForgetfulHandler {
    fn handle(&mut self, request: Eff) -> Resume {
        match request {
            Eff::Ask(_) => Resume::Continue(self.rate),
            Eff::Log(msg) => {
                self.log.push(msg);
                Resume::Stop(None) // BUG: should be Resume::Continue(0)
            }
            Eff::Fail(reason) => Resume::Stop(Some(reason)),
            Eff::Done(_) => Resume::Stop(None),
        }
    }
}

// --- 4. State as an effect ---
// step(state, input) -> (output, new_state). The state is a value the
// caller threads through, not a hidden variable: tally_step builds a new
// record and never writes the one it was given, so every earlier state
// is still readable. A State effect (Get / Put) interpreted by a handler
// comes down to exactly this threading. The output is the running mean,
// total / count (i64 division truncates, which is floor here: nothing
// is negative). Taking &Tally, not &mut Tally, makes the borrow checker
// refuse any write; the check that s0 is unchanged tests that promise.
// Tally is deliberately not Copy: `let st = s0` would copy it, and a
// check on the original could then never see a write to the copy.
#[derive(Clone)]
struct Tally {
    count: i64,
    total: i64,
}

fn tally_step(st: &Tally, x: i64) -> (i64, Tally) {
    let next = Tally { count: st.count + 1, total: st.total + x };
    (next.total / next.count, next)
}

// Run the inputs from s0 and keep every state: states[0] is s0 itself,
// the very value the first step reads, and states[i + 1] the state
// after input i.
fn tally_run(s0: Tally, inputs: &[i64]) -> (Vec<i64>, Vec<Tally>) {
    let mut outs = Vec::new();
    let mut states = vec![s0];
    for (i, &x) in inputs.iter().enumerate() {
        let (out, next) = tally_step(&states[i], x);
        outs.push(out);
        states.push(next);
    }
    (outs, states)
}

// --- 5. Capability passing ---
// session_check needs the time and a logger. It takes them as a
// capability record instead of reaching for SystemTime::now() and
// println!, so a test can pass a fake clock and a recording logger.
// The record is generic, so each call is compiled for its concrete
// clock and logger: direct calls the optimizer can inline. A
// `&mut dyn Clock` would work too, at the price of an indirect call.
trait Clock {
    fn now(&self) -> i64;
}

trait Logger {
    fn log(&mut self, msg: String);
}

struct Caps<C: Clock, L: Logger> {
    clock: C,
    logger: L,
}

fn session_check<C: Clock, L: Logger>(caps: &mut Caps<C, L>, expires_at: i64) -> bool {
    let now = caps.clock.now();
    if now < expires_at {
        caps.logger.log(format!("valid at {now}"));
        return true;
    }
    caps.logger.log(format!("expired at {now}"));
    false
}

// Production capabilities. A real program would read SystemTime::now();
// this file stays deterministic, so the "system clock" is a global that
// moves forward on every read. That global is exactly the hidden state
// the capability keeps out of session_check.
static SYS_TIME: AtomicI64 = AtomicI64::new(1000);
static CLOCK_READS: AtomicI64 = AtomicI64::new(0);

fn clock_reads() -> i64 {
    CLOCK_READS.load(Ordering::Relaxed)
}

struct SysClock;

impl Clock for SysClock {
    fn now(&self) -> i64 {
        CLOCK_READS.fetch_add(1, Ordering::Relaxed);
        SYS_TIME.fetch_add(1, Ordering::Relaxed)
    }
}

struct SysLog;

impl Logger for SysLog {
    fn log(&mut self, msg: String) {
        stdout_line(&msg);
    }
}

// Test capabilities: a clock stopped at t, and a logger into a buffer.
struct FakeClock(i64);

impl Clock for FakeClock {
    fn now(&self) -> i64 {
        self.0
    }
}

struct FakeLogger(Vec<String>);

impl Logger for FakeLogger {
    fn log(&mut self, msg: String) {
        self.0.push(msg);
    }
}

// --- 6. Functional core, imperative shell ---
// A thermostat. The core, decide(heater, temp) -> (new_heater, commands),
// is pure: it reads only its arguments and returns the commands as data.
// Hysteresis: heat on below 19, off above 21; an alarm at 15 or below.
// The heater is a bool (false = off). The shell is the only code that
// touches the device.
#[derive(Debug, PartialEq)]
enum Cmd {
    HeatOn(i64),
    HeatOff(i64),
    Alarm(i64),
}

fn decide(heater: bool, temp: i64) -> (bool, Vec<Cmd>) {
    let mut out = Vec::new();
    let mut next = heater;
    if !heater && temp < 19 {
        next = true;
        out.push(Cmd::HeatOn(temp));
    }
    if heater && temp > 21 {
        next = false;
        out.push(Cmd::HeatOff(temp));
    }
    if temp <= 15 {
        out.push(Cmd::Alarm(temp));
    }
    (next, out)
}

// The core over a run of events: still pure (it only calls decide).
fn core_run(events: &[i64]) -> (bool, Vec<Cmd>) {
    let mut heater = false;
    let mut all = Vec::new();
    for &temp in events {
        let (next, cmds) = decide(heater, temp);
        all.extend(cmds);
        heater = next;
    }
    (heater, all)
}

// The shell: the device registers it drives, and the loop that executes
// each command the core returns.
static HEATER_PIN: AtomicI64 = AtomicI64::new(0);
static ALARMS_RAISED: AtomicI64 = AtomicI64::new(0);

fn shell_execute(cmds: &[Cmd]) {
    for cmd in cmds {
        match cmd {
            Cmd::HeatOn(_) => HEATER_PIN.store(1, Ordering::Relaxed),
            Cmd::HeatOff(_) => HEATER_PIN.store(0, Ordering::Relaxed),
            Cmd::Alarm(_) => {
                ALARMS_RAISED.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
}

fn shell_run(events: &[i64]) -> bool {
    let mut heater = false;
    for &temp in events {
        let (next, cmds) = decide(heater, temp);
        shell_execute(&cmds);
        heater = next;
    }
    heater
}

fn device(reg: &AtomicI64) -> i64 {
    reg.load(Ordering::Relaxed)
}

// === Tests ===

fn test_effects_as_data(c: &mut Checks) {
    let mut h = test_handler(3);
    let outcome = handle_with(&mut h, &mut Checkout::new(10));
    c.check(matches!(outcome, Outcome::Finished(_)), "test handler: checkout(10) finished");
    c.check(outcome == Outcome::Finished(30), "test handler: checkout(10) at rate 3 = 30");
    c.check(h.log.len() == 2, "test handler captured 2 log lines");
    c.check(log_line_is(&h.log, 0, "rate=3"), "log line 0 is \"rate=3\"");
    c.check(log_line_is(&h.log, 1, "total=30"), "log line 1 is \"total=30\"");

    // The same program under the production handler: real output.
    let before = stdout_lines();
    let prod = handle_with(&mut ProdHandler, &mut Checkout::new(10));
    c.check(matches!(prod, Outcome::Finished(_)), "production handler: checkout(10) finished");
    c.check(prod == Outcome::Finished(40), "production handler: config rate 4 gives 40");
    c.check(stdout_lines() - before == 2, "production handler wrote its 2 log lines to stdout");
}

fn test_resumable(c: &mut Checks) {
    let mut h3 = test_handler(3);
    let mut h5 = test_handler(5);
    let o3 = handle_with(&mut h3, &mut Checkout::new(10));
    let o5 = handle_with(&mut h5, &mut Checkout::new(10));
    c.check(o3 == Outcome::Finished(30), "resumed with 3: 10 * 3 = 30");
    c.check(o5 == Outcome::Finished(50), "resumed with 5: 10 * 5 = 50");
    c.check(o3 != o5, "the answer the handler supplies decides the result");
    c.check(log_line_is(&h5.log, 0, "rate=5"), "the resumed program logged the answer it got");
}

fn test_early_exit(c: &mut Checks) {
    let mut h = test_handler(3);
    let mut program = Checkout::new(0);
    let outcome = handle_with(&mut h, &mut program);
    c.check(matches!(outcome, Outcome::Stopped(_)), "Fail is not resumed: the run stops");
    c.check(
        outcome == Outcome::Stopped(Some("empty order")),
        "the handler returns the failure, \"empty order\"",
    );
    c.check(h.log.len() == 1, "only \"rate=3\" was logged: the \"total=\" step never ran");
    c.check(program.steps == 3, "the program ran 3 steps (Ask, Log, Fail), not 4");

    // The gotcha: a handler that forgets to resume after Log.
    let mut fh = ForgetfulHandler { rate: 3, log: Vec::new() };
    let mut fprogram = Checkout::new(10);
    let f = handle_with(&mut fh, &mut fprogram);
    c.check(matches!(f, Outcome::Stopped(_)), "forgetful handler: the run stopped after the first Log");
    c.check(f == Outcome::Stopped(None), "forgetful handler: and the stop carries no reason at all");
    c.check(fprogram.steps == 2, "forgetful handler: 2 steps ran (Ask, Log), not 4");
}

fn test_state_threading(c: &mut Checks) {
    let inputs = [5, 10, 20];
    let (outs, states) = tally_run(Tally { count: 0, total: 0 }, &inputs);
    let (s0, st) = (&states[0], &states[inputs.len()]);
    c.check(outs.first() == Some(&5), "running mean after 5: 5 / 1 = 5");
    c.check(outs.get(1) == Some(&7), "running mean after 10: 15 / 2 = 7");
    c.check(outs.get(2) == Some(&11), "running mean after 20: 35 / 3 = 11");
    c.check(st.count == 3, "final state: count 3");
    c.check(st.total == 35, "final state: total 35");
    c.check(s0.count == 0, "initial state unchanged: count still 0");
    c.check(s0.total == 0, "initial state unchanged: total still 0");

    // Replaying from s0 gives the same final state: nothing hidden moved.
    let (_, replay) = tally_run(s0.clone(), &inputs);
    c.check(
        replay.last().is_some_and(|again| again.total == st.total),
        "replaying from s0 reaches the same total",
    );
}

fn test_capabilities(c: &mut Checks) {
    let reads0 = clock_reads();
    let lines0 = stdout_lines();

    let mut at100 = Caps { clock: FakeClock(100), logger: FakeLogger(Vec::new()) };
    c.check(session_check(&mut at100, 150), "fake clock at 100, expiry 150: valid");
    c.check(log_line_is(&at100.logger.0, 0, "valid at 100"), "fake logger recorded \"valid at 100\"");

    let mut at200 = Caps { clock: FakeClock(200), logger: FakeLogger(Vec::new()) };
    c.check(!session_check(&mut at200, 150), "fake clock at 200, expiry 150: expired");
    c.check(log_line_is(&at200.logger.0, 0, "expired at 200"), "fake logger recorded \"expired at 200\"");

    c.check(clock_reads() - reads0 == 0, "the fakes never read the system clock");
    c.check(stdout_lines() - lines0 == 0, "the fakes never wrote to stdout");

    // The same function with the production capabilities.
    let mut prod = Caps { clock: SysClock, logger: SysLog };
    c.check(!session_check(&mut prod, 150), "production clock at 1000, expiry 150: expired");
    c.check(clock_reads() - reads0 == 1, "production read the system clock once");
}

fn test_functional_core(c: &mut Checks) {
    // Every threshold is hit exactly, so an off-by-one comparison fails:
    // 19 while off and 21 while on emit nothing (not below 19, not above
    // 21), 15 alarms and 16 does not. 17 arrives while the heater is on
    // and 23 while it is off, so a decide that ignores its state fails
    // too, and 14 alarms with the heater already on.
    let events = [19, 18, 17, 21, 22, 23, 15, 16, 14];

    // The pure core alone: no device, just the commands it returns.
    let (heater, cmds) = core_run(&events);
    c.check(cmds.len() == 5, "core emitted 5 commands for 9 events");
    c.check(cmds.first() == Some(&Cmd::HeatOn(18)), "command 0 is HEAT_ON(18)");
    c.check(cmds.get(1) == Some(&Cmd::HeatOff(22)), "command 1 is HEAT_OFF(22)");
    c.check(cmds.get(2) == Some(&Cmd::HeatOn(15)), "command 2 is HEAT_ON(15)");
    c.check(cmds.get(3) == Some(&Cmd::Alarm(15)), "command 3 is ALARM(15)");
    c.check(cmds.get(4) == Some(&Cmd::Alarm(14)), "command 4 is ALARM(14)");
    c.check(heater, "core's final state: heater on");

    let (still_on, none) = decide(true, 20);
    c.check(none.is_empty(), "decide(on, 20): inside the band, no commands");
    c.check(still_on, "decide(on, 20): the heater stays on");
    c.check(
        device(&HEATER_PIN) + device(&ALARMS_RAISED) == 0,
        "the core never touched the device",
    );

    // The shell runs the same core and executes what it returns. The
    // first 6 events end just after HEAT_OFF(22): the pin must be off
    // there, which the final pin (on again) cannot show.
    shell_run(&events[..6]);
    c.check(device(&HEATER_PIN) == 0, "shell, first 6 events: HEAT_OFF(22) drove the pin off");
    c.check(shell_run(&events), "shell: final state heater on");
    c.check(device(&HEATER_PIN) == 1, "shell drove the heater pin on");
    c.check(device(&ALARMS_RAISED) == 2, "shell raised the alarm twice");
}

fn main() {
    let mut c = Checks { pass: 0, fail: 0 };
    test_effects_as_data(&mut c);
    test_resumable(&mut c);
    test_early_exit(&mut c);
    test_state_threading(&mut c);
    test_capabilities(&mut c);
    test_functional_core(&mut c);
    if c.fail > 0 {
        println!("{} passed, {} failed", c.pass, c.fail);
        std::process::exit(1);
    }
    println!("All effect system examples passed.");
}
