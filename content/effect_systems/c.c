// Vidya — Effect Systems in C (C23)
//
// A program that yields effect requests (Ask, Log, Fail) instead of doing
// I/O, handlers that decide what each one means (resume with an answer, or
// stop), state threaded through step(state, input), capabilities passed as
// parameters, and a pure core behind a thin shell. Mirrors cyrius.cyr.
//
// OCaml 5, Koka, Unison and Eff have native effect handlers; C cannot
// suspend a function, so the program is a step function over a state
// struct and a handler loop feeds each answer back in. A request is a
// tagged struct (enum tag + union payload); a handler is a function
// pointer plus an env pointer. No malloc: every buffer is fixed.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void check(bool ok, const char *what) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        exit(1);
    }
}

/* --- Shared helpers: messages and a log buffer --- */
#define LINE_CAP 32

/* "rate=" + 3 -> "rate=3", written into buf and returned. */
static const char *msg_kv(char *buf, size_t cap, const char *prefix, long n) {
    snprintf(buf, cap, "%s%ld", prefix, n);
    return buf;
}

/* A log buffer: up to LOG_CAP lines, each copied in. */
#define LOG_CAP 8
typedef struct {
    int count;
    char lines[LOG_CAP][LINE_CAP];
} LogBuf;

static LogBuf log_new(void) { return (LogBuf){ .count = 0 }; }

static void log_push(LogBuf *b, const char *msg) {
    if (b->count < LOG_CAP) {
        snprintf(b->lines[b->count], LINE_CAP, "%s", msg);
        b->count += 1;
    }
}
static int log_count(const LogBuf *b) { return b->count; }
static const char *log_line(const LogBuf *b, int i) {
    return i < b->count ? b->lines[i] : nullptr;
}

/* Null-safe comparisons for the checks: a missing line or reason is a
 * failed check, not a crash. */
static bool str_is(const char *p, const char *s) {
    return p != nullptr && strcmp(p, s) == 0;
}
static bool log_line_is(const LogBuf *b, int i, const char *s) {
    return str_is(log_line(b, i), s);
}

/* The one real output channel, used only by the production handlers. */
static int g_stdout_lines = 0;
static void stdout_line(const char *msg) {
    printf("  [prod] %s\n", msg);
    g_stdout_lines += 1;
}

/* --- 1. Effects as data, and an interpreter --- */
/* A request names an effect and carries its payload; the program never
 * performs it. Done is not an effect: it is how the program returns. */
typedef enum { EFF_ASK, EFF_LOG, EFF_FAIL, EFF_DONE } EffTag;
typedef struct {
    EffTag tag;
    union {
        const char *key;      /* Ask */
        const char *msg;      /* Log */
        const char *reason;   /* Fail */
        long value;           /* Done */
    };
} Eff;

static Eff Ask(const char *key) { return (Eff){ .tag = EFF_ASK, .key = key }; }
static Eff Log(const char *msg) { return (Eff){ .tag = EFF_LOG, .msg = msg }; }
static Eff Fail(const char *reason) { return (Eff){ .tag = EFF_FAIL, .reason = reason }; }
static Eff Done(long value) { return (Eff){ .tag = EFF_DONE, .value = value }; }

/* What running a program under a handler gives back. */
typedef enum { FINISHED, STOPPED } OutcomeTag;
typedef struct {
    OutcomeTag tag;
    union {
        long value;           /* Finished */
        const char *reason;   /* Stopped; nullptr when it carries none */
    };
} Outcome;

/* The program, as it would read with native handlers (OCaml 5, Koka):
 *   rate = perform Ask("rate")
 *   perform Log("rate=" ^ rate)
 *   if qty <= 0 then perform Fail("empty order")
 *   perform Log("total=" ^ qty * rate)
 *   return qty * rate
 * checkout_step is that program cut at each effect: it returns the next
 * request, and the next call resumes it with the answer. Its state struct
 * is the suspended rest of the program; `steps` counts how many times it
 * ran, so a check can see what a handler cut short. A Log message points
 * into st->msg, which the next step overwrites: a handler that keeps a
 * message must copy it (log_push does). */
typedef struct {
    int pc;
    long qty;
    long rate;
    int steps;
    char msg[LINE_CAP];
} Checkout;

static Checkout checkout_new(long qty) { return (Checkout){ .qty = qty }; }

static Eff checkout_step(void *self, long answer) {
    Checkout *st = self;
    st->steps += 1;
    switch (st->pc) {
    case 0:
        st->pc = 1;
        return Ask("rate");
    case 1:
        st->rate = answer;                     /* resumed with Ask's answer */
        st->pc = 2;
        return Log(msg_kv(st->msg, sizeof st->msg, "rate=", answer));
    case 2:
        st->pc = 3;
        if (st->qty <= 0) return Fail("empty order");
        return Log(msg_kv(st->msg, sizeof st->msg, "total=", st->qty * st->rate));
    default:
        st->pc = 4;
        return Done(st->qty * st->rate);
    }
}

/* A handler's answer: resume the program with a value, or stop it. */
typedef struct {
    bool resume;
    long answer;              /* fed to the next step when resume */
    const char *reason;       /* the stop's reason when not */
} Reply;

static Reply resume_with(long answer) { return (Reply){ .resume = true, .answer = answer }; }
static Reply stop(const char *reason) { return (Reply){ .resume = false, .reason = reason }; }

/* A handler is a closure by hand: the code takes its env first. */
typedef struct {
    Reply (*code)(void *env, Eff req);
    void *env;
} Handler;

/* The interpreter: run any step-function program under any handler. It
 * does not know what Ask, Log or Fail mean: the handler decides. */
static Outcome handle_with(Handler h, Eff (*step)(void *st, long answer), void *st) {
    long answer = 0;
    for (;;) {
        Eff req = step(st, answer);
        if (req.tag == EFF_DONE) return (Outcome){ .tag = FINISHED, .value = req.value };
        Reply r = h.code(h.env, req);
        if (!r.resume) return (Outcome){ .tag = STOPPED, .reason = r.reason };
        answer = r.answer;
    }
}

/* Production handler: Ask reads the process configuration, Log writes to
 * stdout, Fail is reported and stops the program. It captures nothing. */
static long g_config_rate = 4;
static Reply prod_code(void *env, Eff req) {
    (void)env;
    switch (req.tag) {
    case EFF_ASK:
        if (strcmp(req.key, "rate") == 0) return resume_with(g_config_rate);
        return stop("unknown key");
    case EFF_LOG:
        stdout_line(req.msg);
        return resume_with(0);
    case EFF_FAIL:
        stdout_line(req.reason);
        return stop(req.reason);
    default:
        return stop(nullptr);
    }
}
static Handler prod_handler(void) { return (Handler){ prod_code, nullptr }; }

/* Test handler: a fixed environment (the rate it answers) and a log buffer
 * it records into. The env struct is the closure's capture; the caller
 * owns it and keeps it alive for the whole run. No I/O, nothing global. */
typedef struct {
    long rate;
    LogBuf *log;
} TestEnv;

static Reply test_code(void *env, Eff req) {
    TestEnv *e = env;
    switch (req.tag) {
    case EFF_ASK:
        if (strcmp(req.key, "rate") == 0) return resume_with(e->rate);
        return stop("unknown key");
    case EFF_LOG:
        log_push(e->log, req.msg);
        return resume_with(0);
    case EFF_FAIL:
        return stop(req.reason);   /* do not resume: the failure is the result */
    default:
        return stop(nullptr);
    }
}
static Handler test_handler(TestEnv *env) { return (Handler){ test_code, env }; }

/* --- 2. Resumable handlers --- */
/* Ask is answered and the program RESUMES with the answer: handle_with
 * passes the handler's value to the next checkout_step call. Two handlers
 * that answer differently get different results from the same program.
 * (A native handler resumes a captured continuation, and OCaml 5's are
 * one-shot. Here the continuation is a plain struct, so a copy of it could
 * be resumed twice: C does not stop that.) */

/* --- 3. A non-resuming effect is an early exit --- */
/* The test handler answers Fail by NOT resuming, so the rest of the
 * program never runs: no "total=" line, and no further steps. That is an
 * exception built from a handler. The same mechanism is the gotcha when
 * it is an accident: a handler that forgets to resume after Log stops the
 * program just as silently. */
static Reply forgetful_code(void *env, Eff req) {
    TestEnv *e = env;
    switch (req.tag) {
    case EFF_ASK:
        return resume_with(e->rate);
    case EFF_LOG:
        log_push(e->log, req.msg);
        return stop(nullptr);      /* BUG: should be resume_with(0) */
    default:
        return stop(req.reason);
    }
}
static Handler forgetful_handler(TestEnv *env) { return (Handler){ forgetful_code, env }; }

/* --- 4. State as an effect --- */
/* step(state, input) -> (output, new_state). The state is a value the
 * caller threads through, not a hidden variable: tally_step takes it
 * through a pointer to const and builds a new one, so every earlier state
 * is still readable. (const stops a direct write in tally_step; a cast
 * could still defeat it, which the s0 checks below would catch.) A State
 * effect (Get / Put) interpreted by a handler comes down to exactly this
 * threading. The output is the running mean, total / count; C's integer
 * division truncates toward zero, which is the floor for these
 * non-negative totals. */
typedef struct {
    long count;
    long total;
} Tally;

typedef struct {
    long out;
    Tally next;
} TallyStep;

static TallyStep tally_step(const Tally *st, long x) {
    Tally next = { st->count + 1, st->total + x };
    return (TallyStep){ next.total / next.count, next };
}

/* --- 5. Capability passing --- */
/* session_check needs the time and a logger. It takes them as a
 * capability struct of {function pointer, env} pairs instead of reaching
 * for globals, so a test can pass a fake clock and a recording logger. */
typedef struct {
    long (*code)(void *env);
    void *env;
} ClockCap;

typedef struct {
    void (*code)(void *env, const char *msg);
    void *env;
} LogCap;

typedef struct {
    ClockCap now;
    LogCap log;
} Caps;

static Caps caps_new(ClockCap now, LogCap log) { return (Caps){ now, log }; }

static bool session_check(const Caps *caps, long expires_at) {
    long now = caps->now.code(caps->now.env);
    char line[LINE_CAP];
    if (now < expires_at) {
        caps->log.code(caps->log.env, msg_kv(line, sizeof line, "valid at ", now));
        return true;
    }
    caps->log.code(caps->log.env, msg_kv(line, sizeof line, "expired at ", now));
    return false;
}

/* Production capabilities. A real program would read
 * clock_gettime(CLOCK_REALTIME); this file stays deterministic, so the
 * "system clock" is a global that moves forward on every read. That global
 * is exactly the hidden state the capability keeps out of session_check. */
static long g_sys_time = 1000;
static int g_clock_reads = 0;
static long sys_clock_code(void *env) {
    (void)env;
    g_clock_reads += 1;
    long t = g_sys_time;
    g_sys_time += 1;
    return t;
}
static void sys_log_code(void *env, const char *msg) {
    (void)env;
    stdout_line(msg);
}
static ClockCap sys_clock(void) { return (ClockCap){ sys_clock_code, nullptr }; }
static LogCap sys_log(void) { return (LogCap){ sys_log_code, nullptr }; }

/* Test capabilities: a clock stopped at *t, and a logger into a buffer. */
static long fake_clock_code(void *env) { return *(const long *)env; }
static void fake_log_code(void *env, const char *msg) { log_push(env, msg); }
static ClockCap fake_clock(long *t) { return (ClockCap){ fake_clock_code, t }; }
static LogCap fake_logger(LogBuf *log) { return (LogCap){ fake_log_code, log }; }

/* --- 6. Functional core, imperative shell --- */
/* A thermostat. The core, decide(heater, temp) -> (new_heater, commands),
 * is pure: it reads only its arguments and returns the commands as data.
 * Hysteresis: heat on below 19, off above 21; an alarm at 15 or below.
 * The shell is the only code that touches the device.
 * C23 added effect annotations to standard C, [[reproducible]] and the
 * stricter [[unsequenced]]. [[reproducible]] promises gcc that decide
 * changes nothing outside itself and that a second call in a row with the
 * same arguments returns what the first did. gcc trusts the promise and
 * does not check it: a decide that wrote g_heater_pin would still compile
 * without a word. */
typedef enum { HEAT_ON = 1, HEAT_OFF = 2, ALARM = 3 } CmdTag;
typedef struct {
    CmdTag tag;
    long temp;
} Cmd;

#define CMDS_CAP 16
typedef struct {
    int count;
    Cmd items[CMDS_CAP];
} Cmds;

static void cmds_push(Cmds *c, CmdTag tag, long temp) {
    if (c->count < CMDS_CAP) {
        c->items[c->count] = (Cmd){ tag, temp };
        c->count += 1;
    }
}
static bool cmd_is(const Cmds *c, int i, CmdTag tag, long temp) {
    return i < c->count && c->items[i].tag == tag && c->items[i].temp == temp;
}

typedef struct {
    int heater;               /* 0 = off, 1 = on */
    Cmds cmds;
} Decision;

static Decision decide(int heater, long temp) [[reproducible]];
static Decision decide(int heater, long temp) {
    Decision d = { .heater = heater };
    if (heater == 0 && temp < 19) {
        d.heater = 1;
        cmds_push(&d.cmds, HEAT_ON, temp);
    }
    if (heater == 1 && temp > 21) {
        d.heater = 0;
        cmds_push(&d.cmds, HEAT_OFF, temp);
    }
    if (temp <= 15) cmds_push(&d.cmds, ALARM, temp);
    return d;
}

/* The core over a run of events: still pure (it only calls decide). */
static Decision core_run(const long *events, int n) {
    Decision all = { .heater = 0 };
    for (int i = 0; i < n; i++) {
        Decision d = decide(all.heater, events[i]);
        for (int k = 0; k < d.cmds.count; k++) {
            cmds_push(&all.cmds, d.cmds.items[k].tag, d.cmds.items[k].temp);
        }
        all.heater = d.heater;
    }
    return all;
}

/* The shell: the device registers it drives, and the loop that executes
 * each command the core returns. */
static int g_heater_pin = 0;
static int g_alarms_raised = 0;
static void shell_execute(const Cmds *cmds) {
    for (int k = 0; k < cmds->count; k++) {
        switch (cmds->items[k].tag) {
        case HEAT_ON: g_heater_pin = 1; break;
        case HEAT_OFF: g_heater_pin = 0; break;
        case ALARM: g_alarms_raised += 1; break;
        }
    }
}
static int shell_run(const long *events, int n) {
    int heater = 0;
    for (int i = 0; i < n; i++) {
        Decision d = decide(heater, events[i]);
        shell_execute(&d.cmds);
        heater = d.heater;
    }
    return heater;
}

/* === Tests === */

static void test_effects_as_data(void) {
    LogBuf log = log_new();
    TestEnv env = { 3, &log };
    Checkout st = checkout_new(10);
    Outcome o = handle_with(test_handler(&env), checkout_step, &st);
    check(o.tag == FINISHED, "test handler: checkout(10) finished");
    check(o.value == 30, "test handler: checkout(10) at rate 3 = 30");
    check(log_count(&log) == 2, "test handler captured 2 log lines");
    check(log_line_is(&log, 0, "rate=3"), "log line 0 is \"rate=3\"");
    check(log_line_is(&log, 1, "total=30"), "log line 1 is \"total=30\"");

    /* The same program under the production handler: real output. */
    int before = g_stdout_lines;
    Checkout pst = checkout_new(10);
    Outcome p = handle_with(prod_handler(), checkout_step, &pst);
    check(p.tag == FINISHED, "production handler: checkout(10) finished");
    check(p.value == 40, "production handler: config rate 4 gives 40");
    check(g_stdout_lines - before == 2, "production handler wrote its 2 log lines to stdout");
}

static void test_resumable(void) {
    LogBuf log3 = log_new();
    LogBuf log5 = log_new();
    TestEnv env3 = { 3, &log3 };
    TestEnv env5 = { 5, &log5 };
    Checkout st3 = checkout_new(10);
    Checkout st5 = checkout_new(10);
    long v3 = handle_with(test_handler(&env3), checkout_step, &st3).value;
    long v5 = handle_with(test_handler(&env5), checkout_step, &st5).value;
    check(v3 == 30, "resumed with 3: 10 * 3 = 30");
    check(v5 == 50, "resumed with 5: 10 * 5 = 50");
    check(v3 != v5, "the answer the handler supplies decides the result");
    check(log_line_is(&log5, 0, "rate=5"), "the resumed program logged the answer it got");
}

static void test_early_exit(void) {
    LogBuf log = log_new();
    TestEnv env = { 3, &log };
    Checkout st = checkout_new(0);
    Outcome o = handle_with(test_handler(&env), checkout_step, &st);
    check(o.tag == STOPPED, "Fail is not resumed: the run stops");
    check(str_is(o.reason, "empty order"), "the handler returns the failure, \"empty order\"");
    check(log_count(&log) == 1, "only \"rate=3\" was logged: the \"total=\" step never ran");
    check(st.steps == 3, "the program ran 3 steps (Ask, Log, Fail), not 4");

    /* The gotcha: a handler that forgets to resume after Log. */
    LogBuf flog = log_new();
    TestEnv fenv = { 3, &flog };
    Checkout fst = checkout_new(10);
    Outcome f = handle_with(forgetful_handler(&fenv), checkout_step, &fst);
    check(f.tag == STOPPED, "forgetful handler: the run stopped after the first Log");
    check(f.reason == nullptr, "forgetful handler: and the stop carries no reason at all");
    check(fst.steps == 2, "forgetful handler: 2 steps ran (Ask, Log), not 4");
}

static void test_state_threading(void) {
    const long inputs[3] = { 5, 10, 20 };
    long outs[3];
    Tally states[3];

    Tally s0 = { 0, 0 };
    const Tally *st = &s0;
    for (int i = 0; i < 3; i++) {
        TallyStep r = tally_step(st, inputs[i]);
        outs[i] = r.out;
        states[i] = r.next;
        st = &states[i];
    }
    check(outs[0] == 5, "running mean after 5: 5 / 1 = 5");
    check(outs[1] == 7, "running mean after 10: 15 / 2 = 7");
    check(outs[2] == 11, "running mean after 20: 35 / 3 = 11");
    check(st->count == 3, "final state: count 3");
    check(st->total == 35, "final state: total 35");
    check(s0.count == 0, "initial state unchanged: count still 0");
    check(s0.total == 0, "initial state unchanged: total still 0");

    /* Replaying from s0 gives the same final state: nothing hidden moved. */
    Tally again = s0;
    for (int i = 0; i < 3; i++) {
        again = tally_step(&again, inputs[i]).next;
    }
    check(again.total == st->total, "replaying from s0 reaches the same total");
}

static void test_capabilities(void) {
    int reads0 = g_clock_reads;
    int lines0 = g_stdout_lines;

    LogBuf log_a = log_new();
    long t100 = 100;
    Caps at100 = caps_new(fake_clock(&t100), fake_logger(&log_a));
    check(session_check(&at100, 150), "fake clock at 100, expiry 150: valid");
    check(log_line_is(&log_a, 0, "valid at 100"), "fake logger recorded \"valid at 100\"");

    LogBuf log_b = log_new();
    long t200 = 200;
    Caps at200 = caps_new(fake_clock(&t200), fake_logger(&log_b));
    check(!session_check(&at200, 150), "fake clock at 200, expiry 150: expired");
    check(log_line_is(&log_b, 0, "expired at 200"), "fake logger recorded \"expired at 200\"");

    check(g_clock_reads - reads0 == 0, "the fakes never read the system clock");
    check(g_stdout_lines - lines0 == 0, "the fakes never wrote to stdout");

    /* The same function with the production capabilities. */
    Caps prod = caps_new(sys_clock(), sys_log());
    check(!session_check(&prod, 150), "production clock at 1000, expiry 150: expired");
    check(g_clock_reads - reads0 == 1, "production read the system clock once");
}

static void test_functional_core(void) {
    /* Every threshold is hit exactly, so an off-by-one comparison fails:
     * 19 while off and 21 while on emit nothing (not below 19, not above
     * 21), 15 alarms and 16 does not. 17 arrives while the heater is on
     * and 23 while it is off, so a decide that ignores its state fails
     * too, and 14 alarms with the heater already on. */
    const long events[9] = { 19, 18, 17, 21, 22, 23, 15, 16, 14 };

    /* The pure core alone: no device, just the commands it returns. */
    Decision run = core_run(events, 9);
    check(run.cmds.count == 5, "core emitted 5 commands for 9 events");
    check(cmd_is(&run.cmds, 0, HEAT_ON, 18), "command 0 is HEAT_ON(18)");
    check(cmd_is(&run.cmds, 1, HEAT_OFF, 22), "command 1 is HEAT_OFF(22)");
    check(cmd_is(&run.cmds, 2, HEAT_ON, 15), "command 2 is HEAT_ON(15)");
    check(cmd_is(&run.cmds, 3, ALARM, 15), "command 3 is ALARM(15)");
    check(cmd_is(&run.cmds, 4, ALARM, 14), "command 4 is ALARM(14)");
    check(run.heater == 1, "core's final state: heater on");

    Decision none = decide(1, 20);
    check(none.cmds.count == 0, "decide(on, 20): inside the band, no commands");
    check(none.heater == 1, "decide(on, 20): the heater stays on");
    check(g_heater_pin + g_alarms_raised == 0, "the core never touched the device");

    /* The shell runs the same core and executes what it returns. The
     * first 6 events end just after HEAT_OFF(22): the pin must be off
     * there, which the final pin (on again) cannot show. */
    shell_run(events, 6);
    check(g_heater_pin == 0, "shell, first 6 events: HEAT_OFF(22) drove the pin off");
    check(shell_run(events, 9) == 1, "shell: final state heater on");
    check(g_heater_pin == 1, "shell drove the heater pin on");
    check(g_alarms_raised == 2, "shell raised the alarm twice");
}

int main(void) {
    test_effects_as_data();
    test_resumable();
    test_early_exit();
    test_state_threading();
    test_capabilities();
    test_functional_core();
    printf("All effect system examples passed.\n");
    return 0;
}
