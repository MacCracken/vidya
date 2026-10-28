#!/usr/bin/env python3
# Vidya — Effect Systems — Python port.
#
# Side effects made explicit: a program that yields effect requests
# (Ask, Log, Fail), handlers that decide what each one means (resume with
# an answer, or stop), state threaded through step(state, input),
# capabilities passed as parameters, and a pure core behind a thin shell.
#
# OCaml 5, Koka, Unison and Eff have native effect handlers; Python does
# not. A generator is the nearest native shape: the program `yield`s a
# request and stays suspended until the handler loop resumes it with
# gen.send(answer). A handler that does not resume never sends again,
# and gen.close() throws the rest of the program away.

import inspect
from collections.abc import Callable, Generator
from dataclasses import dataclass
from enum import Enum

PASS = 0
FAIL = 0


def check(cond, name):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print(f"  FAIL: {name}")


# --- Shared helpers: null-safe log reads and the one real output channel ---
def log_line_is(log, i, s):
    """A missing line is a failed check, not an IndexError."""
    return i < len(log) and log[i] == s


# Counted beside the write, so a check can see who printed.
STDOUT_LINES = 0


def stdout_line(msg):
    global STDOUT_LINES
    print(f"  [prod] {msg}")
    STDOUT_LINES += 1


# --- 1. Effects as data, and an interpreter ---
# A request names an effect and carries its payload; the program never
# performs it. There is no Done request: a generator's `return` ends it,
# and the value arrives in the interpreter as StopIteration.value.
@dataclass(frozen=True)
class Ask:
    key: str


@dataclass(frozen=True)
class Log:
    msg: str


@dataclass(frozen=True)
class Fail:
    reason: str


type Eff = Ask | Log | Fail

# The program yields requests, receives each answer from send(), and
# returns its result. A handler answers a request with (resume, value):
# (True, answer) resumes the program, (False, reason) stops it.
type Program = Generator[Eff, int | None, int]
type Handler = Callable[[Eff], tuple[bool, int | str | None]]


# What running a program under a handler gives back.
@dataclass(frozen=True)
class Finished:
    value: int


@dataclass(frozen=True)
class Stopped:
    reason: str | None


type Outcome = Finished | Stopped


# The program in direct style: each `yield` is an effect, written where
# OCaml 5 would write `perform` and Koka would call the operation.
def checkout(qty: int) -> Program:
    rate = yield Ask("rate")
    yield Log(f"rate={rate}")
    if qty <= 0:
        yield Fail("empty order")
    yield Log(f"total={qty * rate}")
    return qty * rate


# The interpreter: run any generator program under any handler. It does
# not know what Ask, Log or Fail mean: the handler decides. Returns the
# outcome and the steps, how many times the program was started or
# resumed (4 for a full checkout: Ask, Log, Log, then the return).
def handle_with(handler: Handler, program: Program) -> tuple[Outcome, int]:
    steps = 0
    answer = None
    while True:
        steps += 1
        try:
            request = program.send(answer)   # send(None) starts a fresh generator
        except StopIteration as done:
            return Finished(done.value), steps
        resume, value = handler(request)
        if not resume:
            program.close()                  # the code after this yield never runs
            return Stopped(value), steps
        answer = value


# Production handler: Ask reads the process configuration, Log writes
# to stdout, Fail is reported and stops the program.
CONFIG = {"rate": 4}


def prod_handler(request: Eff):
    match request:
        case Ask(key) if key in CONFIG:
            return True, CONFIG[key]
        case Ask(_):
            return False, "unknown key"
        case Log(msg):
            stdout_line(msg)
            return True, None
        case Fail(reason):
            stdout_line(reason)
            return False, reason
    return False, None


# Test handler: a fixed environment (the rate it answers) and a log
# buffer it records into. No I/O, nothing global.
def test_handler(rate: int, log: list[str]) -> Handler:
    env = {"rate": rate}

    def handle(request: Eff):
        match request:
            case Ask(key) if key in env:
                return True, env[key]
            case Ask(_):
                return False, "unknown key"
            case Log(msg):
                log.append(msg)
                return True, None
            case Fail(reason):
                return False, reason   # do not resume: the failure is the result
        return False, None

    return handle


# --- 2. Resumable handlers ---
# Ask is answered and the program RESUMES with the answer: send(value)
# makes `yield Ask("rate")` evaluate to value. Two handlers that answer
# differently get different results from the same program. A generator
# is one-shot, like an OCaml 5 continuation: each yield is resumed at
# most once, and there is no way to copy a paused generator and resume
# the copy too.

# --- 3. A non-resuming effect is an early exit ---
# The test handler answers Fail by NOT resuming, so the rest of the
# program never runs: no "total=" line, and no further steps. close()
# raises GeneratorExit at the paused yield, so the program's `finally`
# blocks still run; its remaining effects do not. That is an exception
# built from a handler, and the same mechanism is the gotcha when it is
# an accident: a handler that forgets to resume after Log stops the
# program just as silently.
def forgetful_handler(rate: int, log: list[str]) -> Handler:
    def handle(request: Eff):
        match request:
            case Ask(_):
                return True, rate
            case Log(msg):
                log.append(msg)
                return False, None     # BUG: should be (True, None)
        return False, None

    return handle


# --- 4. State as an effect ---
# step(state, input) -> (output, new_state). The state is a value the
# caller threads through, not a hidden variable: tally_step builds a new
# record and never writes the one it was given, so every earlier state
# is still readable. A State effect (Get / Put) interpreted by a handler
# comes down to exactly this threading. The output is the running mean,
# total // count (floor division). frozen=True makes a write raise, but
# only one level deep, so the check that s0 is unchanged stays.
@dataclass(frozen=True)
class Tally:
    count: int
    total: int


def tally_step(st: Tally, x: int) -> tuple[int, Tally]:
    nxt = Tally(st.count + 1, st.total + x)
    return nxt.total // nxt.count, nxt


# --- 5. Capability passing ---
# session_check needs the time and a logger. It takes them as a
# capability record instead of reaching for time.time() and print(), so
# a test can pass a fake clock and a recording logger.
@dataclass(frozen=True)
class Caps:
    now: Callable[[], int]
    log: Callable[[str], None]


def session_check(caps: Caps, expires_at: int) -> bool:
    now = caps.now()
    if now < expires_at:
        caps.log(f"valid at {now}")
        return True
    caps.log(f"expired at {now}")
    return False


# Production capabilities. A real program would pass time.time; this
# file stays deterministic, so the "system clock" is a global that moves
# forward on every read. That global is exactly the hidden state the
# capability keeps out of session_check.
SYS_TIME = 1000
CLOCK_READS = 0


def sys_clock() -> int:
    global SYS_TIME, CLOCK_READS
    CLOCK_READS += 1
    t = SYS_TIME
    SYS_TIME += 1
    return t


def sys_log(msg: str) -> None:
    stdout_line(msg)


# Test capabilities: a clock stopped at t, and a logger into a buffer.
def fake_clock(t: int) -> Callable[[], int]:
    return lambda: t


def fake_logger(log: list[str]) -> Callable[[str], None]:
    return log.append


# --- 6. Functional core, imperative shell ---
# A thermostat. The core, decide(heater, temp) -> (new_heater, commands),
# is pure: it reads only its arguments and returns the commands as data.
# Hysteresis: heat on below 19, off above 21; an alarm at 15 or below.
# The heater is a bool (False = off). The shell is the only code that
# touches the device.
class Tag(Enum):
    HEAT_ON = 1
    HEAT_OFF = 2
    ALARM = 3


@dataclass(frozen=True)
class Cmd:
    tag: Tag
    temp: int


def cmd_is(cmds, i, tag, temp):
    return i < len(cmds) and cmds[i] == Cmd(tag, temp)


def decide(heater: bool, temp: int) -> tuple[bool, list[Cmd]]:
    out = []
    nxt = heater
    if not heater and temp < 19:
        nxt = True
        out.append(Cmd(Tag.HEAT_ON, temp))
    if heater and temp > 21:
        nxt = False
        out.append(Cmd(Tag.HEAT_OFF, temp))
    if temp <= 15:
        out.append(Cmd(Tag.ALARM, temp))
    return nxt, out


# The core over a run of events: still pure (it only calls decide).
def core_run(events: list[int]) -> tuple[bool, list[Cmd]]:
    heater = False
    every = []
    for temp in events:
        heater, cmds = decide(heater, temp)
        every.extend(cmds)
    return heater, every


# The shell: the device registers it drives, and the loop that executes
# each command the core returns.
HEATER_PIN = 0
ALARMS_RAISED = 0


def shell_execute(cmds: list[Cmd]) -> None:
    global HEATER_PIN, ALARMS_RAISED
    for cmd in cmds:
        match cmd.tag:
            case Tag.HEAT_ON:
                HEATER_PIN = 1
            case Tag.HEAT_OFF:
                HEATER_PIN = 0
            case Tag.ALARM:
                ALARMS_RAISED += 1


def shell_run(events: list[int]) -> bool:
    heater = False
    for temp in events:
        heater, cmds = decide(heater, temp)
        shell_execute(cmds)
    return heater


# === Tests ===

def test_effects_as_data():
    log = []
    outcome, _ = handle_with(test_handler(3, log), checkout(10))
    check(isinstance(outcome, Finished), "test handler: checkout(10) finished")
    check(outcome == Finished(30), "test handler: checkout(10) at rate 3 = 30")
    check(len(log) == 2, "test handler captured 2 log lines")
    check(log_line_is(log, 0, "rate=3"), 'log line 0 is "rate=3"')
    check(log_line_is(log, 1, "total=30"), 'log line 1 is "total=30"')

    # The same program under the production handler: real output.
    before = STDOUT_LINES
    poutcome, _ = handle_with(prod_handler, checkout(10))
    check(isinstance(poutcome, Finished), "production handler: checkout(10) finished")
    check(poutcome == Finished(40), "production handler: config rate 4 gives 40")
    check(STDOUT_LINES - before == 2, "production handler wrote its 2 log lines to stdout")


def test_resumable():
    log3, log5 = [], []
    o3, _ = handle_with(test_handler(3, log3), checkout(10))
    o5, _ = handle_with(test_handler(5, log5), checkout(10))
    check(o3 == Finished(30), "resumed with 3: 10 * 3 = 30")
    check(o5 == Finished(50), "resumed with 5: 10 * 5 = 50")
    check(o3 != o5, "the answer the handler supplies decides the result")
    check(log_line_is(log5, 0, "rate=5"), "the resumed program logged the answer it got")


def test_early_exit():
    log = []
    program = checkout(0)
    outcome, steps = handle_with(test_handler(3, log), program)
    check(isinstance(outcome, Stopped), "Fail is not resumed: the run stops")
    check(outcome == Stopped("empty order"), 'the handler returns the failure, "empty order"')
    check(len(log) == 1, 'only "rate=3" was logged: the "total=" step never ran')
    check(steps == 3, "the program ran 3 steps (Ask, Log, Fail), not 4")
    check(inspect.getgeneratorstate(program) == inspect.GEN_CLOSED,
          "the stopped program is closed: nothing can resume it later")

    # The gotcha: a handler that forgets to resume after Log.
    flog = []
    foutcome, fsteps = handle_with(forgetful_handler(3, flog), checkout(10))
    check(isinstance(foutcome, Stopped), "forgetful handler: the run stopped after the first Log")
    check(foutcome == Stopped(None), "forgetful handler: and the stop carries no reason at all")
    check(fsteps == 2, "forgetful handler: 2 steps ran (Ask, Log), not 4")


def test_state_threading():
    inputs = [5, 10, 20]
    outs = []
    s0 = Tally(0, 0)
    st = s0
    for x in inputs:
        out, st = tally_step(st, x)
        outs.append(out)
    check(outs[0] == 5, "running mean after 5: 5 // 1 = 5")
    check(outs[1] == 7, "running mean after 10: 15 // 2 = 7")
    check(outs[2] == 11, "running mean after 20: 35 // 3 = 11")
    check(st.count == 3, "final state: count 3")
    check(st.total == 35, "final state: total 35")
    check(s0.count == 0, "initial state unchanged: count still 0")
    check(s0.total == 0, "initial state unchanged: total still 0")

    # Replaying from s0 gives the same final state: nothing hidden moved.
    again = s0
    for x in inputs:
        _, again = tally_step(again, x)
    check(again.total == st.total, "replaying from s0 reaches the same total")


def test_capabilities():
    reads0 = CLOCK_READS
    lines0 = STDOUT_LINES

    log_a = []
    at100 = Caps(now=fake_clock(100), log=fake_logger(log_a))
    check(session_check(at100, 150) is True, "fake clock at 100, expiry 150: valid")
    check(log_line_is(log_a, 0, "valid at 100"), 'fake logger recorded "valid at 100"')

    log_b = []
    at200 = Caps(now=fake_clock(200), log=fake_logger(log_b))
    check(session_check(at200, 150) is False, "fake clock at 200, expiry 150: expired")
    check(log_line_is(log_b, 0, "expired at 200"), 'fake logger recorded "expired at 200"')

    check(CLOCK_READS - reads0 == 0, "the fakes never read the system clock")
    check(STDOUT_LINES - lines0 == 0, "the fakes never wrote to stdout")

    # The same function with the production capabilities.
    prod = Caps(now=sys_clock, log=sys_log)
    check(session_check(prod, 150) is False, "production clock at 1000, expiry 150: expired")
    check(CLOCK_READS - reads0 == 1, "production read the system clock once")


def test_functional_core():
    # Every threshold is hit exactly, so an off-by-one comparison fails:
    # 19 while off and 21 while on emit nothing (not below 19, not above
    # 21), 15 alarms and 16 does not. 17 arrives while the heater is on
    # and 23 while it is off, so a decide that ignores its state fails
    # too, and 14 alarms with the heater already on.
    events = [19, 18, 17, 21, 22, 23, 15, 16, 14]

    # The pure core alone: no device, just the commands it returns.
    heater, cmds = core_run(events)
    check(len(cmds) == 5, "core emitted 5 commands for 9 events")
    check(cmd_is(cmds, 0, Tag.HEAT_ON, 18), "command 0 is HEAT_ON(18)")
    check(cmd_is(cmds, 1, Tag.HEAT_OFF, 22), "command 1 is HEAT_OFF(22)")
    check(cmd_is(cmds, 2, Tag.HEAT_ON, 15), "command 2 is HEAT_ON(15)")
    check(cmd_is(cmds, 3, Tag.ALARM, 15), "command 3 is ALARM(15)")
    check(cmd_is(cmds, 4, Tag.ALARM, 14), "command 4 is ALARM(14)")
    check(heater is True, "core's final state: heater on")

    still_on, none = decide(True, 20)
    check(len(none) == 0, "decide(on, 20): inside the band, no commands")
    check(still_on is True, "decide(on, 20): the heater stays on")
    check(HEATER_PIN + ALARMS_RAISED == 0, "the core never touched the device")

    # The shell runs the same core and executes what it returns. The
    # first 6 events end just after HEAT_OFF(22): the pin must be off
    # there, which the final pin (on again) cannot show.
    shell_run(events[:6])
    check(HEATER_PIN == 0, "shell, first 6 events: HEAT_OFF(22) drove the pin off")
    check(shell_run(events) is True, "shell: final state heater on")
    check(HEATER_PIN == 1, "shell drove the heater pin on")
    check(ALARMS_RAISED == 2, "shell raised the alarm twice")


if __name__ == "__main__":
    test_effects_as_data()
    test_resumable()
    test_early_exit()
    test_state_threading()
    test_capabilities()
    test_functional_core()
    if FAIL:
        print(f"{PASS} passed, {FAIL} failed")
        raise SystemExit(1)
    print("All effect system examples passed.")
    raise SystemExit(0)
