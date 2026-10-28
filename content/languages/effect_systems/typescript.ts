// Vidya — Effect Systems — TypeScript port.
//
// Side effects made explicit: a program that yields effect requests
// (Ask, Log, Fail), handlers that decide what each one means (resume with
// an answer, or stop), state threaded through step(state, input),
// capabilities passed as parameters, and a pure core behind a thin shell.
//
// OCaml 5, Koka, Unison and Eff have native effect handlers; TypeScript
// does not. A generator is the nearest native shape: the program yields
// a request and stays suspended until the handler loop resumes it with
// gen.next(answer). A handler that does not resume never calls next
// again, and gen.return() closes the rest of the program.

let passCount = 0;
let failCount = 0;
function check(cond: boolean, name: string): void {
    if (cond) {
        passCount++;
    } else {
        failCount++;
        console.log(`  FAIL: ${name}`);
    }
}

// --- Shared helpers: null-safe log reads and the one real output channel ---
// A missing line is a failed check, not an undefined that slips through.
function logLineIs(log: readonly string[], i: number, s: string): boolean {
    return i < log.length && log[i] === s;
}

// Counted beside the write, so a check can see who printed.
let stdoutLines = 0;
function stdoutLine(msg: string): void {
    console.log(`  [prod] ${msg}`);
    stdoutLines++;
}

// --- 1. Effects as data, and an interpreter ---
// A request names an effect and carries its payload; the program never
// performs it. There is no Done request: a generator's `return` ends it,
// and the interpreter sees { done: true, value }.
type Eff =
    | { readonly tag: "Ask"; readonly key: string }
    | { readonly tag: "Log"; readonly msg: string }
    | { readonly tag: "Fail"; readonly reason: string };

// The program yields requests, receives a number back from each yield
// (Ask's answer; Log's is ignored) and returns a number.
type Program = Generator<Eff, number, number>;

// A handler answers a request: resume with a value, or stop with a
// reason (null when it gives none).
type Reply =
    | { readonly resume: true; readonly value: number }
    | { readonly resume: false; readonly reason: string | null };
type Handler = (request: Eff) => Reply;

// What running a program under a handler gives back.
type Outcome =
    | { readonly tag: "Finished"; readonly value: number }
    | { readonly tag: "Stopped"; readonly reason: string | null };

function finished(o: Outcome, value: number): boolean {
    return o.tag === "Finished" && o.value === value;
}
function stopped(o: Outcome, reason: string | null): boolean {
    return o.tag === "Stopped" && o.reason === reason;
}

// The program in direct style: each `yield` is an effect, written where
// OCaml 5 would write `perform` and Koka would call the operation.
function* checkout(qty: number): Program {
    const rate = yield { tag: "Ask", key: "rate" };
    yield { tag: "Log", msg: `rate=${rate}` };
    if (qty <= 0) {
        yield { tag: "Fail", reason: "empty order" };
    }
    yield { tag: "Log", msg: `total=${qty * rate}` };
    return qty * rate;
}

// The interpreter: run any generator program under any handler. It does
// not know what Ask, Log or Fail mean: the handler decides. `steps`
// counts how many times the program was started or resumed (4 for a
// full checkout: Ask, Log, Log, then the return).
function handleWith(handler: Handler, program: Program): { outcome: Outcome; steps: number } {
    let steps = 0;
    let answer = 0;
    for (;;) {
        steps++;
        const r = program.next(answer); // the first next() starts it; its argument is dropped
        if (r.done) return { outcome: { tag: "Finished", value: r.value }, steps };
        const reply = handler(r.value);
        if (!reply.resume) {
            program.return(0); // the code after this yield never runs
            return { outcome: { tag: "Stopped", reason: reply.reason }, steps };
        }
        answer = reply.value;
    }
}

// Production handler: Ask reads the process configuration, Log writes
// to stdout, Fail is reported and stops the program.
const config: ReadonlyMap<string, number> = new Map([["rate", 4]]);

function prodHandler(request: Eff): Reply {
    switch (request.tag) {
        case "Ask": {
            const v = config.get(request.key);
            return v === undefined ? { resume: false, reason: "unknown key" } : { resume: true, value: v };
        }
        case "Log":
            stdoutLine(request.msg);
            return { resume: true, value: 0 };
        case "Fail":
            stdoutLine(request.reason);
            return { resume: false, reason: request.reason };
    }
}

// Test handler: a fixed environment (the rate it answers) and a log
// buffer it records into. No I/O, nothing global.
function testHandler(rate: number, log: string[]): Handler {
    const env: ReadonlyMap<string, number> = new Map([["rate", rate]]);
    return (request) => {
        switch (request.tag) {
            case "Ask": {
                const v = env.get(request.key);
                return v === undefined ? { resume: false, reason: "unknown key" } : { resume: true, value: v };
            }
            case "Log":
                log.push(request.msg);
                return { resume: true, value: 0 };
            case "Fail":
                return { resume: false, reason: request.reason }; // do not resume: the failure is the result
        }
    };
}

// --- 2. Resumable handlers ---
// Ask is answered and the program RESUMES with the answer: next(value)
// makes `yield { tag: "Ask" }` evaluate to value. Two handlers that
// answer differently get different results from the same program. A
// generator is one-shot, like an OCaml 5 continuation: each yield is
// resumed at most once, and a paused generator cannot be copied.

// --- 3. A non-resuming effect is an early exit ---
// The test handler answers Fail by NOT resuming, so the rest of the
// program never runs: no "total=" line, and no further steps. return()
// still runs the program's `finally` blocks; its remaining effects do
// not run. That is an exception built from a handler, and the same
// mechanism is the gotcha when it is an accident: a handler that
// forgets to resume after Log stops the program just as silently.
function forgetfulHandler(rate: number, log: string[]): Handler {
    return (request) => {
        switch (request.tag) {
            case "Ask":
                return { resume: true, value: rate };
            case "Log":
                log.push(request.msg);
                return { resume: false, reason: null }; // BUG: should be { resume: true, value: 0 }
            case "Fail":
                return { resume: false, reason: request.reason };
        }
    };
}

// --- 4. State as an effect ---
// step(state, input) -> [output, newState]. The state is a value the
// caller threads through, not a hidden variable: tallyStep builds a new
// record and never writes the one it was given, so every earlier state
// is still readable. A State effect (Get / Put) interpreted by a handler
// comes down to exactly this threading. The output is the running mean,
// floor(total / count). `readonly` is checked by tsc only: at run time
// the object is writable, so the check that s0 is unchanged stays.
type Tally = { readonly count: number; readonly total: number };

function tallyStep(st: Tally, x: number): [number, Tally] {
    const next: Tally = { count: st.count + 1, total: st.total + x };
    return [Math.floor(next.total / next.count), next];
}

// --- 5. Capability passing ---
// sessionCheck needs the time and a logger. It takes them as a
// capability record instead of reaching for Date.now() and console.log,
// so a test can pass a fake clock and a recording logger.
type Caps = { readonly now: () => number; readonly log: (msg: string) => void };

function sessionCheck(caps: Caps, expiresAt: number): boolean {
    const now = caps.now();
    if (now < expiresAt) {
        caps.log(`valid at ${now}`);
        return true;
    }
    caps.log(`expired at ${now}`);
    return false;
}

// Production capabilities. A real program would pass Date.now; this
// file stays deterministic, so the "system clock" is a global that moves
// forward on every read. That global is exactly the hidden state the
// capability keeps out of sessionCheck.
let sysTime = 1000;
let clockReads = 0;
function sysClock(): number {
    clockReads++;
    return sysTime++;
}
function sysLog(msg: string): void {
    stdoutLine(msg);
}

// Test capabilities: a clock stopped at t, and a logger into a buffer.
function fakeClock(t: number): () => number {
    return () => t;
}
function fakeLogger(log: string[]): (msg: string) => void {
    return (msg) => {
        log.push(msg);
    };
}

// --- 6. Functional core, imperative shell ---
// A thermostat. The core, decide(heater, temp) -> [newHeater, commands],
// is pure: it reads only its arguments and returns the commands as data.
// Hysteresis: heat on below 19, off above 21; an alarm at 15 or below.
// The heater is a boolean (false = off). The shell is the only code that
// touches the device.
type Cmd = { readonly tag: "HEAT_ON" | "HEAT_OFF" | "ALARM"; readonly temp: number };

function cmdIs(cmds: readonly Cmd[], i: number, tag: Cmd["tag"], temp: number): boolean {
    const c = cmds[i];
    return c !== undefined && c.tag === tag && c.temp === temp;
}

function decide(heater: boolean, temp: number): [boolean, Cmd[]] {
    const out: Cmd[] = [];
    let next = heater;
    if (!heater && temp < 19) {
        next = true;
        out.push({ tag: "HEAT_ON", temp });
    }
    if (heater && temp > 21) {
        next = false;
        out.push({ tag: "HEAT_OFF", temp });
    }
    if (temp <= 15) out.push({ tag: "ALARM", temp });
    return [next, out];
}

// The core over a run of events: still pure (it only calls decide).
function coreRun(events: readonly number[]): [boolean, Cmd[]] {
    let heater = false;
    const all: Cmd[] = [];
    for (const temp of events) {
        const [next, cmds] = decide(heater, temp);
        all.push(...cmds);
        heater = next;
    }
    return [heater, all];
}

// The shell: the device registers it drives, and the loop that executes
// each command the core returns.
let heaterPin = 0;
let alarmsRaised = 0;
function shellExecute(cmds: readonly Cmd[]): void {
    for (const c of cmds) {
        switch (c.tag) {
            case "HEAT_ON": heaterPin = 1; break;
            case "HEAT_OFF": heaterPin = 0; break;
            case "ALARM": alarmsRaised++; break;
        }
    }
}
function shellRun(events: readonly number[]): boolean {
    let heater = false;
    for (const temp of events) {
        const [next, cmds] = decide(heater, temp);
        shellExecute(cmds);
        heater = next;
    }
    return heater;
}

// === Tests ===

function testEffectsAsData(): void {
    const log: string[] = [];
    const { outcome } = handleWith(testHandler(3, log), checkout(10));
    check(outcome.tag === "Finished", "test handler: checkout(10) finished");
    check(finished(outcome, 30), "test handler: checkout(10) at rate 3 = 30");
    check(log.length === 2, "test handler captured 2 log lines");
    check(logLineIs(log, 0, "rate=3"), 'log line 0 is "rate=3"');
    check(logLineIs(log, 1, "total=30"), 'log line 1 is "total=30"');

    // The same program under the production handler: real output.
    const before = stdoutLines;
    const prod = handleWith(prodHandler, checkout(10)).outcome;
    check(prod.tag === "Finished", "production handler: checkout(10) finished");
    check(finished(prod, 40), "production handler: config rate 4 gives 40");
    check(stdoutLines - before === 2, "production handler wrote its 2 log lines to stdout");
}

function testResumable(): void {
    const log3: string[] = [];
    const log5: string[] = [];
    const o3 = handleWith(testHandler(3, log3), checkout(10)).outcome;
    const o5 = handleWith(testHandler(5, log5), checkout(10)).outcome;
    check(finished(o3, 30), "resumed with 3: 10 * 3 = 30");
    check(finished(o5, 50), "resumed with 5: 10 * 5 = 50");
    check(o3.tag === "Finished" && o5.tag === "Finished" && o3.value !== o5.value,
        "the answer the handler supplies decides the result");
    check(logLineIs(log5, 0, "rate=5"), "the resumed program logged the answer it got");
}

function testEarlyExit(): void {
    const log: string[] = [];
    const program = checkout(0);
    const { outcome, steps } = handleWith(testHandler(3, log), program);
    check(outcome.tag === "Stopped", "Fail is not resumed: the run stops");
    check(stopped(outcome, "empty order"), 'the handler returns the failure, "empty order"');
    check(log.length === 1, 'only "rate=3" was logged: the "total=" step never ran');
    check(steps === 3, "the program ran 3 steps (Ask, Log, Fail), not 4");
    // A closed generator answers every later next() with done: true, so
    // nothing can resume the stopped program and reach "total=".
    check(program.next(3).done === true, "the stopped program is closed: nothing can resume it later");

    // The gotcha: a handler that forgets to resume after Log.
    const flog: string[] = [];
    const f = handleWith(forgetfulHandler(3, flog), checkout(10));
    check(f.outcome.tag === "Stopped", "forgetful handler: the run stopped after the first Log");
    check(stopped(f.outcome, null), "forgetful handler: and the stop carries no reason at all");
    check(f.steps === 2, "forgetful handler: 2 steps ran (Ask, Log), not 4");
}

function testStateThreading(): void {
    const inputs = [5, 10, 20];
    const outs: number[] = [];
    const s0: Tally = { count: 0, total: 0 };
    let st = s0;
    for (const x of inputs) {
        const [out, next] = tallyStep(st, x);
        outs.push(out);
        st = next;
    }
    check(outs[0] === 5, "running mean after 5: 5 / 1 = 5");
    check(outs[1] === 7, "running mean after 10: floor(15 / 2) = 7");
    check(outs[2] === 11, "running mean after 20: floor(35 / 3) = 11");
    check(st.count === 3, "final state: count 3");
    check(st.total === 35, "final state: total 35");
    check(s0.count === 0, "initial state unchanged: count still 0");
    check(s0.total === 0, "initial state unchanged: total still 0");

    // Replaying from s0 gives the same final state: nothing hidden moved.
    let again = s0;
    for (const x of inputs) again = tallyStep(again, x)[1];
    check(again.total === st.total, "replaying from s0 reaches the same total");
}

function testCapabilities(): void {
    const reads0 = clockReads;
    const lines0 = stdoutLines;

    const logA: string[] = [];
    const at100: Caps = { now: fakeClock(100), log: fakeLogger(logA) };
    check(sessionCheck(at100, 150) === true, "fake clock at 100, expiry 150: valid");
    check(logLineIs(logA, 0, "valid at 100"), 'fake logger recorded "valid at 100"');

    const logB: string[] = [];
    const at200: Caps = { now: fakeClock(200), log: fakeLogger(logB) };
    check(sessionCheck(at200, 150) === false, "fake clock at 200, expiry 150: expired");
    check(logLineIs(logB, 0, "expired at 200"), 'fake logger recorded "expired at 200"');

    check(clockReads - reads0 === 0, "the fakes never read the system clock");
    check(stdoutLines - lines0 === 0, "the fakes never wrote to stdout");

    // The same function with the production capabilities.
    const prod: Caps = { now: sysClock, log: sysLog };
    check(sessionCheck(prod, 150) === false, "production clock at 1000, expiry 150: expired");
    check(clockReads - reads0 === 1, "production read the system clock once");
}

function testFunctionalCore(): void {
    // Every threshold is hit exactly, so an off-by-one comparison fails:
    // 19 while off and 21 while on emit nothing (not below 19, not above
    // 21), 15 alarms and 16 does not. 17 arrives while the heater is on
    // and 23 while it is off, so a decide that ignores its state fails
    // too, and 14 alarms with the heater already on.
    const events = [19, 18, 17, 21, 22, 23, 15, 16, 14];

    // The pure core alone: no device, just the commands it returns.
    const [heater, cmds] = coreRun(events);
    check(cmds.length === 5, "core emitted 5 commands for 9 events");
    check(cmdIs(cmds, 0, "HEAT_ON", 18), "command 0 is HEAT_ON(18)");
    check(cmdIs(cmds, 1, "HEAT_OFF", 22), "command 1 is HEAT_OFF(22)");
    check(cmdIs(cmds, 2, "HEAT_ON", 15), "command 2 is HEAT_ON(15)");
    check(cmdIs(cmds, 3, "ALARM", 15), "command 3 is ALARM(15)");
    check(cmdIs(cmds, 4, "ALARM", 14), "command 4 is ALARM(14)");
    check(heater === true, "core's final state: heater on");

    const [stillOn, none] = decide(true, 20);
    check(none.length === 0, "decide(on, 20): inside the band, no commands");
    check(stillOn === true, "decide(on, 20): the heater stays on");
    check(heaterPin + alarmsRaised === 0, "the core never touched the device");

    // The shell runs the same core and executes what it returns. The
    // first 6 events end just after HEAT_OFF(22): the pin must be off
    // there, which the final pin (on again) cannot show.
    shellRun(events.slice(0, 6));
    check(heaterPin === 0, "shell, first 6 events: HEAT_OFF(22) drove the pin off");
    check(shellRun(events) === true, "shell: final state heater on");
    check(heaterPin === 1, "shell drove the heater pin on");
    check(alarmsRaised === 2, "shell raised the alarm twice");
}

testEffectsAsData();
testResumable();
testEarlyExit();
testStateThreading();
testCapabilities();
testFunctionalCore();
if (failCount > 0) {
    console.log(`${passCount} passed, ${failCount} failed`);
    process.exit(1);
}
console.log("All effect system examples passed.");
process.exit(0);
