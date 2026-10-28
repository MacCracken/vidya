// Vidya — Effect Systems — Go port.
//
// Side effects made explicit: a program that returns effect requests
// (Ask, Log, Fail), handlers that decide what each one means (resume with
// an answer, or stop), state threaded through step(state, input),
// capabilities passed as parameters, and a pure core behind a thin shell.
//
// OCaml 5, Koka, Unison and Eff have native effect handlers; Go does not.
// A goroutine blocked on a channel (or Go 1.23's iter.Pull) could suspend
// a direct-style program at each effect, but the hand-offs would hide in
// the runtime. Here an explicit step function and a handler loop make
// every resume deterministic and visible. Capabilities are interfaces.

package main

import (
	"fmt"
	"os"
)

var passCount, failCount int

func check(cond bool, name string) {
	if cond {
		passCount++
	} else {
		failCount++
		fmt.Println("  FAIL:", name)
	}
}

// --- Shared helpers: a log buffer and the one real output channel ---

// logBuf records lines. It is the test handlers' buffer and, through its
// Log method, the fake logger of section 5.
type logBuf struct{ lines []string }

func (b *logBuf) push(msg string) { b.lines = append(b.lines, msg) }

// lineIs is null-safe: a missing line is a failed check, not a panic.
func (b *logBuf) lineIs(i int, s string) bool { return i < len(b.lines) && b.lines[i] == s }

// Counted beside the write, so a check can see who printed.
var stdoutLines = 0

func stdoutLine(msg string) {
	fmt.Println("  [prod] " + msg)
	stdoutLines++
}

// --- 1. Effects as data, and an interpreter ---

// A request names an effect and carries its payload; the program never
// performs it. Done is not an effect: it is how the program returns.
type Tag int

const (
	Ask Tag = iota
	Log
	Fail
	Done
)

type Eff struct {
	Tag Tag
	Str string // Ask's key, Log's message or Fail's reason
	N   int    // Done's value
}

// Reply is a handler's answer: resume the program with Value, or stop
// it, with a Reason or without one ("").
type Reply struct {
	Resume bool
	Value  int
	Reason string
}

type Handler func(Eff) Reply

// Program is any step-function program: each call runs it up to its
// next request, resumed with the answer to the previous one.
type Program interface {
	Step(answer int) Eff
}

// Outcome is what running a program under a handler gives back.
type OutTag int

const (
	Finished OutTag = iota
	Stopped
)

type Outcome struct {
	Tag    OutTag
	Value  int
	Reason string
}

// The program, as it would read with native handlers (OCaml 5, Koka):
//
//	rate = perform Ask("rate")
//	perform Log("rate=" ^ rate)
//	if qty <= 0 then perform Fail("empty order")
//	perform Log("total=" ^ qty * rate)
//	return qty * rate
//
// checkout is that program cut at each effect. Its fields are the
// suspended rest of the program; steps counts how many times it ran, so
// a check can see what a handler cut short.
type checkout struct {
	pc, qty, rate, steps int
}

func checkoutNew(qty int) *checkout { return &checkout{qty: qty} }

func (p *checkout) Step(answer int) Eff {
	p.steps++
	switch p.pc {
	case 0:
		p.pc = 1
		return Eff{Tag: Ask, Str: "rate"}
	case 1:
		p.rate = answer // resumed with Ask's answer
		p.pc = 2
		return Eff{Tag: Log, Str: fmt.Sprintf("rate=%d", answer)}
	case 2:
		p.pc = 3
		if p.qty <= 0 {
			return Eff{Tag: Fail, Str: "empty order"}
		}
		return Eff{Tag: Log, Str: fmt.Sprintf("total=%d", p.qty*p.rate)}
	}
	p.pc = 4
	return Eff{Tag: Done, N: p.qty * p.rate}
}

// handleWith runs any program under any handler. It does not know what
// Ask, Log or Fail mean: the handler decides.
func handleWith(h Handler, p Program) Outcome {
	answer := 0
	for {
		req := p.Step(answer)
		if req.Tag == Done {
			return Outcome{Tag: Finished, Value: req.N}
		}
		r := h(req)
		if !r.Resume {
			return Outcome{Tag: Stopped, Reason: r.Reason}
		}
		answer = r.Value
	}
}

// Production handler: Ask reads the process configuration, Log writes to
// stdout, Fail is reported and stops the program.
var config = map[string]int{"rate": 4}

func prodHandler(req Eff) Reply {
	switch req.Tag {
	case Ask:
		if v, ok := config[req.Str]; ok {
			return Reply{Resume: true, Value: v}
		}
		return Reply{Reason: "unknown key"}
	case Log:
		stdoutLine(req.Str)
		return Reply{Resume: true}
	case Fail:
		stdoutLine(req.Str)
		return Reply{Reason: req.Str}
	}
	return Reply{}
}

// testHandler has a fixed environment (the rate it answers) and a log
// buffer it records into. No I/O, nothing global.
func testHandler(rate int, log *logBuf) Handler {
	return func(req Eff) Reply {
		switch req.Tag {
		case Ask:
			if req.Str == "rate" {
				return Reply{Resume: true, Value: rate}
			}
			return Reply{Reason: "unknown key"}
		case Log:
			log.push(req.Str)
			return Reply{Resume: true}
		case Fail:
			return Reply{Reason: req.Str} // do not resume: the failure is the result
		}
		return Reply{}
	}
}

// --- 2. Resumable handlers ---
// Ask is answered and the program RESUMES with the answer: handleWith
// passes the handler's Value to the next Step call. Two handlers that
// answer differently get different results from the same program. (A
// native handler resumes a captured continuation; OCaml 5's are
// one-shot: a second `continue` raises Effect.Continuation_already_resumed.)

// --- 3. A non-resuming effect is an early exit ---
// The test handler answers Fail by NOT resuming, so the rest of the
// program never runs: no "total=" line, and no further steps. That is an
// exception built from a handler, and the same mechanism is the gotcha
// when it is an accident: a handler that forgets to resume after Log
// stops the program just as silently.
func forgetfulHandler(rate int, log *logBuf) Handler {
	return func(req Eff) Reply {
		switch req.Tag {
		case Ask:
			return Reply{Resume: true, Value: rate}
		case Log:
			log.push(req.Str)
			return Reply{} // BUG: should be Reply{Resume: true}
		}
		return Reply{Reason: req.Str}
	}
}

// --- 4. State as an effect ---
// step(state, input) -> (output, newState). The state is a value the
// caller threads through, not a hidden variable: tallyStep builds a new
// record and never writes the one it was given, so every earlier state
// is still readable. A State effect (Get / Put) interpreted by a handler
// comes down to exactly this threading. The output is the running mean,
// Total / Count (Go's int division truncates, which is floor here:
// nothing is negative). tallyStep takes a pointer, as a large state
// would be passed, so only discipline stops a write through it; the
// check that s0 is unchanged is what catches one. Passed by value, a
// Tally would be copied and a write could not reach the caller.
type Tally struct{ Count, Total int }

func tallyStep(st *Tally, x int) (int, *Tally) {
	next := &Tally{Count: st.Count + 1, Total: st.Total + x}
	return next.Total / next.Count, next
}

// --- 5. Capability passing ---
// sessionCheck needs the time and a logger. It takes them as a
// capability record instead of calling time.Now() and fmt.Println, so a
// test can pass a fake clock and a recording logger. A call through an
// interface is an indirect call unless the compiler sees the concrete
// type and devirtualizes it.
type Clock interface{ Now() int }

type Logger interface{ Log(msg string) }

type Caps struct {
	Clock  Clock
	Logger Logger
}

func sessionCheck(caps Caps, expiresAt int) bool {
	now := caps.Clock.Now()
	if now < expiresAt {
		caps.Logger.Log(fmt.Sprintf("valid at %d", now))
		return true
	}
	caps.Logger.Log(fmt.Sprintf("expired at %d", now))
	return false
}

// Production capabilities. A real program would read time.Now(); this
// file stays deterministic, so the "system clock" is a global that moves
// forward on every read. That global is exactly the hidden state the
// capability keeps out of sessionCheck.
var sysTime = 1000
var clockReads = 0

type sysClock struct{}

func (sysClock) Now() int {
	clockReads++
	t := sysTime
	sysTime++
	return t
}

type sysLog struct{}

func (sysLog) Log(msg string) { stdoutLine(msg) }

// Test capabilities: a clock stopped at t, and a logger into a buffer.
type fakeClock int

func (c fakeClock) Now() int { return int(c) }

func (b *logBuf) Log(msg string) { b.push(msg) }

// --- 6. Functional core, imperative shell ---
// A thermostat. The core, decide(heater, temp) -> (newHeater, commands),
// is pure: it reads only its arguments and returns the commands as data.
// Hysteresis: heat on below 19, off above 21; an alarm at 15 or below.
// The heater is a bool (false = off). The shell is the only code that
// touches the device.
type CmdTag int

const (
	HeatOn CmdTag = iota + 1
	HeatOff
	Alarm
)

type Cmd struct {
	Tag  CmdTag
	Temp int
}

func cmdIs(cmds []Cmd, i int, tag CmdTag, temp int) bool {
	return i < len(cmds) && cmds[i] == Cmd{Tag: tag, Temp: temp}
}

func decide(heater bool, temp int) (bool, []Cmd) {
	var out []Cmd
	next := heater
	if !heater && temp < 19 {
		next = true
		out = append(out, Cmd{Tag: HeatOn, Temp: temp})
	}
	if heater && temp > 21 {
		next = false
		out = append(out, Cmd{Tag: HeatOff, Temp: temp})
	}
	if temp <= 15 {
		out = append(out, Cmd{Tag: Alarm, Temp: temp})
	}
	return next, out
}

// coreRun is the core over a run of events: still pure (it only calls
// decide).
func coreRun(events []int) (bool, []Cmd) {
	heater := false
	var all []Cmd
	for _, temp := range events {
		next, cmds := decide(heater, temp)
		all = append(all, cmds...)
		heater = next
	}
	return heater, all
}

// The shell: the device registers it drives, and the loop that executes
// each command the core returns.
var heaterPin, alarmsRaised int

func shellExecute(cmds []Cmd) {
	for _, c := range cmds {
		switch c.Tag {
		case HeatOn:
			heaterPin = 1
		case HeatOff:
			heaterPin = 0
		case Alarm:
			alarmsRaised++
		}
	}
}

func shellRun(events []int) bool {
	heater := false
	for _, temp := range events {
		next, cmds := decide(heater, temp)
		shellExecute(cmds)
		heater = next
	}
	return heater
}

// === Tests ===

func testEffectsAsData() {
	log := &logBuf{}
	o := handleWith(testHandler(3, log), checkoutNew(10))
	check(o.Tag == Finished, "test handler: checkout(10) finished")
	check(o.Value == 30, "test handler: checkout(10) at rate 3 = 30")
	check(len(log.lines) == 2, "test handler captured 2 log lines")
	check(log.lineIs(0, "rate=3"), `log line 0 is "rate=3"`)
	check(log.lineIs(1, "total=30"), `log line 1 is "total=30"`)

	// The same program under the production handler: real output.
	before := stdoutLines
	p := handleWith(prodHandler, checkoutNew(10))
	check(p.Tag == Finished, "production handler: checkout(10) finished")
	check(p.Value == 40, "production handler: config rate 4 gives 40")
	check(stdoutLines-before == 2, "production handler wrote its 2 log lines to stdout")
}

func testResumable() {
	log3, log5 := &logBuf{}, &logBuf{}
	o3 := handleWith(testHandler(3, log3), checkoutNew(10))
	o5 := handleWith(testHandler(5, log5), checkoutNew(10))
	check(o3.Value == 30, "resumed with 3: 10 * 3 = 30")
	check(o5.Value == 50, "resumed with 5: 10 * 5 = 50")
	check(o3.Value != o5.Value, "the answer the handler supplies decides the result")
	check(log5.lineIs(0, "rate=5"), "the resumed program logged the answer it got")
}

func testEarlyExit() {
	log := &logBuf{}
	prog := checkoutNew(0)
	o := handleWith(testHandler(3, log), prog)
	check(o.Tag == Stopped, "Fail is not resumed: the run stops")
	check(o.Reason == "empty order", `the handler returns the failure, "empty order"`)
	check(len(log.lines) == 1, `only "rate=3" was logged: the "total=" step never ran`)
	check(prog.steps == 3, "the program ran 3 steps (Ask, Log, Fail), not 4")

	// The gotcha: a handler that forgets to resume after Log.
	flog := &logBuf{}
	fprog := checkoutNew(10)
	f := handleWith(forgetfulHandler(3, flog), fprog)
	check(f.Tag == Stopped, "forgetful handler: the run stopped after the first Log")
	check(f.Reason == "", "forgetful handler: and the stop carries no reason at all")
	check(fprog.steps == 2, "forgetful handler: 2 steps ran (Ask, Log), not 4")
}

func testStateThreading() {
	inputs := []int{5, 10, 20}
	var outs []int
	s0 := &Tally{}
	st := s0
	for _, x := range inputs {
		out, next := tallyStep(st, x)
		outs = append(outs, out)
		st = next
	}
	check(len(outs) == 3 && outs[0] == 5, "running mean after 5: 5 / 1 = 5")
	check(len(outs) == 3 && outs[1] == 7, "running mean after 10: 15 / 2 = 7")
	check(len(outs) == 3 && outs[2] == 11, "running mean after 20: 35 / 3 = 11")
	check(st.Count == 3, "final state: count 3")
	check(st.Total == 35, "final state: total 35")
	check(s0.Count == 0, "initial state unchanged: count still 0")
	check(s0.Total == 0, "initial state unchanged: total still 0")

	// Replaying from s0 gives the same final state: nothing hidden moved.
	again := s0
	for _, x := range inputs {
		_, again = tallyStep(again, x)
	}
	check(again.Total == st.Total, "replaying from s0 reaches the same total")
}

func testCapabilities() {
	reads0 := clockReads
	lines0 := stdoutLines

	logA := &logBuf{}
	check(sessionCheck(Caps{Clock: fakeClock(100), Logger: logA}, 150), "fake clock at 100, expiry 150: valid")
	check(logA.lineIs(0, "valid at 100"), `fake logger recorded "valid at 100"`)

	logB := &logBuf{}
	check(!sessionCheck(Caps{Clock: fakeClock(200), Logger: logB}, 150), "fake clock at 200, expiry 150: expired")
	check(logB.lineIs(0, "expired at 200"), `fake logger recorded "expired at 200"`)

	check(clockReads-reads0 == 0, "the fakes never read the system clock")
	check(stdoutLines-lines0 == 0, "the fakes never wrote to stdout")

	// The same function with the production capabilities.
	check(!sessionCheck(Caps{Clock: sysClock{}, Logger: sysLog{}}, 150), "production clock at 1000, expiry 150: expired")
	check(clockReads-reads0 == 1, "production read the system clock once")
}

func testFunctionalCore() {
	// Every threshold is hit exactly, so an off-by-one comparison fails:
	// 19 while off and 21 while on emit nothing (not below 19, not above
	// 21), 15 alarms and 16 does not. 17 arrives while the heater is on
	// and 23 while it is off, so a decide that ignores its state fails
	// too, and 14 alarms with the heater already on.
	events := []int{19, 18, 17, 21, 22, 23, 15, 16, 14}

	// The pure core alone: no device, just the commands it returns.
	heater, cmds := coreRun(events)
	check(len(cmds) == 5, "core emitted 5 commands for 9 events")
	check(cmdIs(cmds, 0, HeatOn, 18), "command 0 is HEAT_ON(18)")
	check(cmdIs(cmds, 1, HeatOff, 22), "command 1 is HEAT_OFF(22)")
	check(cmdIs(cmds, 2, HeatOn, 15), "command 2 is HEAT_ON(15)")
	check(cmdIs(cmds, 3, Alarm, 15), "command 3 is ALARM(15)")
	check(cmdIs(cmds, 4, Alarm, 14), "command 4 is ALARM(14)")
	check(heater, "core's final state: heater on")

	stillOn, none := decide(true, 20)
	check(len(none) == 0, "decide(on, 20): inside the band, no commands")
	check(stillOn, "decide(on, 20): the heater stays on")
	check(heaterPin+alarmsRaised == 0, "the core never touched the device")

	// The shell runs the same core and executes what it returns. The
	// first 6 events end just after HEAT_OFF(22): the pin must be off
	// there, which the final pin (on again) cannot show.
	shellRun(events[:6])
	check(heaterPin == 0, "shell, first 6 events: HEAT_OFF(22) drove the pin off")
	check(shellRun(events), "shell: final state heater on")
	check(heaterPin == 1, "shell drove the heater pin on")
	check(alarmsRaised == 2, "shell raised the alarm twice")
}

func main() {
	testEffectsAsData()
	testResumable()
	testEarlyExit()
	testStateThreading()
	testCapabilities()
	testFunctionalCore()
	if failCount > 0 {
		fmt.Printf("%d passed, %d failed\n", passCount, failCount)
		os.Exit(1)
	}
	fmt.Println("All effect system examples passed.")
}
