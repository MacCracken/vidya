// Vidya — Design Patterns in Go
//
// Go patterns: builder via functional options, strategy via interfaces
// and first-class functions, observer via channels or callbacks,
// defer for cleanup, and interface-based dependency injection.
// No inheritance — composition via embedding and interfaces.

package main

import (
	"fmt"
	"math"
	"strings"
)

func main() {
	testBuilderPattern()
	testStrategyPattern()
	testObserverPattern()
	testStateMachine()
	testDeferCleanup()
	testDependencyInjection()
	testFactoryPattern()

	fmt.Println("All design patterns examples passed.")
}

// ── Builder (functional options) ──────────────────────────────────────
type Server struct {
	Host           string
	Port           int
	MaxConnections int
	TimeoutMs      int
}

type ServerOption func(*Server)

func WithHost(h string) ServerOption       { return func(s *Server) { s.Host = h } }
func WithPort(p int) ServerOption          { return func(s *Server) { s.Port = p } }
func WithMaxConns(n int) ServerOption      { return func(s *Server) { s.MaxConnections = n } }
func WithTimeout(ms int) ServerOption      { return func(s *Server) { s.TimeoutMs = ms } }

func NewServer(opts ...ServerOption) (*Server, error) {
	s := &Server{MaxConnections: 100, TimeoutMs: 5000}
	for _, opt := range opts {
		opt(s)
	}
	if s.Host == "" {
		return nil, fmt.Errorf("host is required")
	}
	if s.Port == 0 {
		return nil, fmt.Errorf("port is required")
	}
	return s, nil
}

func testBuilderPattern() {
	s, err := NewServer(WithHost("localhost"), WithPort(8080), WithTimeout(3000))
	assertNoErr(err)
	assert(s.Host == "localhost", "host")
	assert(s.Port == 8080, "port")
	assert(s.MaxConnections == 100, "default max conns")
	assert(s.TimeoutMs == 3000, "timeout")

	_, err = NewServer(WithHost("localhost"))
	assert(err != nil, "missing port")
}

// ── Strategy (interface + functions) ──────────────────────────────────
type DiscountStrategy func(float64) float64

func applyDiscount(price float64, strategy DiscountStrategy) float64 {
	return strategy(price)
}

func testStrategyPattern() {
	noDiscount := func(p float64) float64 { return p }
	tenPct := func(p float64) float64 { return p * 0.9 }
	flatFive := func(p float64) float64 {
		if p-5 < 0 {
			return 0
		}
		return p - 5
	}

	assert(applyDiscount(100, noDiscount) == 100, "no discount")
	assert(applyDiscount(100, tenPct) == 90, "10%")
	assert(applyDiscount(100, flatFive) == 95, "$5 off")
	assert(applyDiscount(3, flatFive) == 0, "floor at 0")
}

// ── Observer ──────────────────────────────────────────────────────────
type EventEmitter struct {
	listeners []func(string)
}

func (e *EventEmitter) On(cb func(string)) {
	e.listeners = append(e.listeners, cb)
}

func (e *EventEmitter) Emit(event string) {
	for _, cb := range e.listeners {
		cb(event)
	}
}

func testObserverPattern() {
	var log []string
	em := &EventEmitter{}
	em.On(func(e string) { log = append(log, "A:"+e) })
	em.On(func(e string) { log = append(log, "B:"+e) })

	em.Emit("click")
	em.Emit("hover")

	assert(len(log) == 4, "4 events")
	assert(log[0] == "A:click", "first")
	assert(log[3] == "B:hover", "last")
}

// ── State machine ─────────────────────────────────────────────────────
type DoorState int

const (
	DoorLocked DoorState = iota
	DoorClosed
	DoorOpen
)

func (d DoorState) Unlock() (DoorState, error) {
	if d == DoorLocked {
		return DoorClosed, nil
	}
	return d, fmt.Errorf("cannot unlock")
}

func (d DoorState) Open() (DoorState, error) {
	if d == DoorClosed {
		return DoorOpen, nil
	}
	return d, fmt.Errorf("cannot open")
}

func (d DoorState) Close() (DoorState, error) {
	if d == DoorOpen {
		return DoorClosed, nil
	}
	return d, fmt.Errorf("cannot close")
}

func (d DoorState) Lock() (DoorState, error) {
	if d == DoorClosed {
		return DoorLocked, nil
	}
	return d, fmt.Errorf("cannot lock")
}

func testStateMachine() {
	door := DoorLocked
	var err error
	door, err = door.Unlock()
	assertNoErr(err)
	assert(door == DoorClosed, "unlocked")
	door, err = door.Open()
	assertNoErr(err)
	door, err = door.Close()
	assertNoErr(err)
	door, err = door.Lock()
	assertNoErr(err)
	assert(door == DoorLocked, "relocked")

	_, err = DoorLocked.Open()
	assert(err != nil, "invalid transition")
}

// ── Defer cleanup (Go's RAII) ─────────────────────────────────────────
func testDeferCleanup() {
	var log []string
	func() {
		log = append(log, "acquire:db")
		defer func() { log = append(log, "release:db") }()
		log = append(log, "acquire:file")
		defer func() { log = append(log, "release:file") }()
	}()

	assert(len(log) == 4, "4 entries")
	assert(log[0] == "acquire:db", "first acquire")
	assert(log[2] == "release:file", "defer reversal")
	assert(log[3] == "release:db", "last release")
}

// ── Dependency injection (interfaces) ─────────────────────────────────
type Logger interface {
	Log(msg string) string
}

type StdoutLogger struct{}

func (StdoutLogger) Log(msg string) string { return "[stdout] " + msg }

type TestLogger struct {
	Entries []string
}

func (t *TestLogger) Log(msg string) string {
	entry := "[test] " + msg
	t.Entries = append(t.Entries, entry)
	return entry
}

type Service struct {
	logger Logger
}

func (s *Service) Process(item string) string {
	return s.logger.Log("processing " + item)
}

func testDependencyInjection() {
	svc := &Service{logger: StdoutLogger{}}
	assert(svc.Process("order") == "[stdout] processing order", "prod logger")

	tl := &TestLogger{}
	svc = &Service{logger: tl}
	svc.Process("order-1")
	svc.Process("order-2")
	assert(len(tl.Entries) == 2, "test logger")
	assert(tl.Entries[0] == "[test] processing order-1", "first entry")
}

// ── Factory ───────────────────────────────────────────────────────────
type Shape interface {
	Area() float64
}

type Circle struct{ Radius float64 }
type Rectangle struct{ Width, Height float64 }
type Triangle struct{ Base, Height float64 }

func (c Circle) Area() float64    { return math.Pi * c.Radius * c.Radius }
func (r Rectangle) Area() float64 { return r.Width * r.Height }
func (t Triangle) Area() float64  { return 0.5 * t.Base * t.Height }

func ShapeFactory(name string, params []float64) (Shape, error) {
	switch strings.ToLower(name) {
	case "circle":
		return Circle{params[0]}, nil
	case "rectangle":
		return Rectangle{params[0], params[1]}, nil
	case "triangle":
		return Triangle{params[0], params[1]}, nil
	default:
		return nil, fmt.Errorf("unknown shape: %s", name)
	}
}

func testFactoryPattern() {
	c, err := ShapeFactory("circle", []float64{5})
	assertNoErr(err)
	assert(math.Abs(c.Area()-78.539) < 0.001, "circle area")

	r, _ := ShapeFactory("rectangle", []float64{3, 4})
	assert(r.Area() == 12, "rect area")

	_, err = ShapeFactory("hexagon", nil)
	assert(err != nil, "unknown shape")
}

// ── Helpers ───────────────────────────────────────────────────────────
func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
func assertNoErr(err error) {
	if err != nil {
		panic("unexpected error: " + err.Error())
	}
}
