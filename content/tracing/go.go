// Vidya — Tracing & Structured Logging in Go
//
// Go has strong built-in support for observability:
//   - log         — basic unstructured logging (stdlib)
//   - log/slog    — structured logging (stdlib, Go 1.21+)
//   - runtime/trace — execution tracing (goroutine scheduling, GC, syscalls)
//   - context     — propagation of deadlines, cancellation, and trace IDs
//
// For production: OpenTelemetry Go SDK provides distributed tracing
// with spans, baggage, and export to backends (Jaeger, OTLP, etc).
//
// Compare to Rust:
//   Go log/slog  → Rust tracing crate (structured events + spans)
//   Go runtime/trace → Rust doesn't have a built-in equivalent
//   Go context   → Rust doesn't have implicit propagation (explicit params)

package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"log/slog"
	"strings"
	"sync"
	"time"
)

func main() {
	testBasicLog()
	testSlogStructured()
	testSlogLevels()
	testSlogGroups()
	testContextPropagation()
	testSpanModel()
	testTraceIdPropagation()
	testFilterByLevel()
	testCustomHandler()
	testOpenTelemetryPattern()

	fmt.Println("All tracing examples passed.")
}

// ── Basic log Package ───────────────────────────────────────────────
// The stdlib log package is unstructured — just text lines with a
// timestamp prefix. Fine for scripts, inadequate for production.

func testBasicLog() {
	var buf bytes.Buffer
	logger := log.New(&buf, "APP: ", log.Ltime|log.Lmsgprefix)

	logger.Print("server starting")
	logger.Printf("listening on port %d", 8080)

	output := buf.String()
	assert(strings.Contains(output, "APP: server starting"), "log prefix")
	assert(strings.Contains(output, "port 8080"), "log format")

	// log.SetFlags controls what prefix each line gets:
	//   log.Ldate     — 2024/01/15
	//   log.Ltime     — 15:04:05
	//   log.Lmicroseconds — 15:04:05.000000
	//   log.Llongfile — /full/path/file.go:42
	//   log.Lshortfile — file.go:42
	//   log.Lmsgprefix — prefix after flags, before message
}

// ── log/slog: Structured Logging ────────────────────────────────────
// slog (Go 1.21+) provides key-value structured logging with levels.
// This is Go's answer to Rust's tracing crate.

func testSlogStructured() {
	var buf bytes.Buffer
	handler := slog.NewJSONHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	})
	logger := slog.New(handler)

	logger.Info("request handled",
		"method", "GET",
		"path", "/api/users",
		"status", 200,
		"duration_ms", 42,
	)

	output := buf.String()
	// Output is JSON: {"time":"...","level":"INFO","msg":"request handled","method":"GET",...}
	assert(strings.Contains(output, `"level":"INFO"`), "slog level")
	assert(strings.Contains(output, `"method":"GET"`), "slog key-value")
	assert(strings.Contains(output, `"status":200`), "slog int value")
	assert(strings.Contains(output, `"duration_ms":42`), "slog duration")
}

// ── slog Levels ─────────────────────────────────────────────────────
// slog has four built-in levels: Debug, Info, Warn, Error.
// Custom levels are just integers (like Rust tracing's Level).

func testSlogLevels() {
	var buf bytes.Buffer

	// Set minimum level to Warn — Debug and Info are suppressed
	handler := slog.NewTextHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelWarn,
	})
	logger := slog.New(handler)

	logger.Debug("this is suppressed") // below Warn
	logger.Info("this is suppressed")  // below Warn
	logger.Warn("this is logged")      // at Warn
	logger.Error("this is logged")     // above Warn

	output := buf.String()
	assert(!strings.Contains(output, "suppressed"), "debug/info filtered")
	assert(strings.Contains(output, "WARN"), "warn logged")
	assert(strings.Contains(output, "ERROR"), "error logged")

	// Level values: Debug=-4, Info=0, Warn=4, Error=8
	// Custom levels: slog.Level(2) is between Info and Warn
	assert(slog.LevelDebug < slog.LevelInfo, "debug < info")
	assert(slog.LevelInfo < slog.LevelWarn, "info < warn")
	assert(slog.LevelWarn < slog.LevelError, "warn < error")
}

// ── slog Groups (Namespaced Attributes) ─────────────────────────────
// Groups create nested attribute namespaces. In JSON output,
// groups become nested objects. Like Rust tracing's span fields.

func testSlogGroups() {
	var buf bytes.Buffer
	handler := slog.NewJSONHandler(&buf, nil)
	logger := slog.New(handler)

	// WithGroup creates a namespace
	reqLogger := logger.WithGroup("request")
	reqLogger.Info("handled",
		"method", "POST",
		"path", "/api/data",
	)

	output := buf.String()
	// JSON output: {"request":{"method":"POST","path":"/api/data"}}
	assert(strings.Contains(output, "request"), "group name present")
	assert(strings.Contains(output, "POST"), "group field present")

	// With() adds default attributes to every log call
	buf.Reset()
	serviceLogger := logger.With("service", "auth", "version", "1.5.0")
	serviceLogger.Info("started")
	output = buf.String()
	assert(strings.Contains(output, "auth"), "with attribute")
	assert(strings.Contains(output, "1.5.0"), "with version")
}

// ── Context Propagation ─────────────────────────────────────────────
// Go's context.Context carries deadlines, cancellation signals,
// and request-scoped values (like trace IDs). It's passed explicitly
// as the first parameter — Go convention, not compiler-enforced.
//
// Rust has no equivalent — you pass trace context as explicit params
// or use thread-local storage (tracing crate does this).

type contextKey string

const traceIDKey contextKey = "trace-id"

func testContextPropagation() {
	// Create a context with a trace ID
	ctx := context.WithValue(context.Background(), traceIDKey, "abc-123")

	// Pass through call chain
	result := handleRequest(ctx, "/api/users")
	assert(strings.Contains(result, "abc-123"), "trace ID propagated")

	// Context with timeout
	ctx2, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	// Check if context is still valid
	select {
	case <-ctx2.Done():
		panic("context should not be done yet")
	default:
		// good — still valid
	}

	assert(ctx2.Err() == nil, "context not expired yet")
}

func handleRequest(ctx context.Context, path string) string {
	traceID := ctx.Value(traceIDKey).(string)
	return fmt.Sprintf("[%s] handling %s", traceID, path)
}

// ── Span Model ──────────────────────────────────────────────────────
// Model tracing spans — a span represents a unit of work with a
// start time, end time, and attributes. This is what OpenTelemetry
// provides; we model it to show the pattern.

type Span struct {
	Name       string
	TraceID    string
	SpanID     string
	ParentID   string // empty for root span
	StartTime  time.Time
	EndTime    time.Time
	Attributes map[string]any
	Events     []SpanEvent
	Status     SpanStatus
}

type SpanEvent struct {
	Name string
	Time time.Time
	Attrs map[string]any
}

type SpanStatus int

const (
	StatusUnset SpanStatus = iota
	StatusOK
	StatusError
)

func (s *Span) End() {
	s.EndTime = time.Now()
}

func (s *Span) SetAttribute(key string, value any) {
	if s.Attributes == nil {
		s.Attributes = make(map[string]any)
	}
	s.Attributes[key] = value
}

func (s *Span) AddEvent(name string) {
	s.Events = append(s.Events, SpanEvent{
		Name: name,
		Time: time.Now(),
	})
}

func (s *Span) Duration() time.Duration {
	if s.EndTime.IsZero() {
		return 0
	}
	return s.EndTime.Sub(s.StartTime)
}

func testSpanModel() {
	root := &Span{
		Name:      "HTTP GET /api/users",
		TraceID:   "trace-001",
		SpanID:    "span-001",
		StartTime: time.Now(),
	}
	root.SetAttribute("http.method", "GET")
	root.SetAttribute("http.url", "/api/users")

	// Child span
	child := &Span{
		Name:      "DB query",
		TraceID:   "trace-001",
		SpanID:    "span-002",
		ParentID:  "span-001",
		StartTime: time.Now(),
	}
	child.SetAttribute("db.system", "postgresql")
	child.SetAttribute("db.statement", "SELECT * FROM users")
	child.AddEvent("query_started")
	child.End()
	child.Status = StatusOK

	root.AddEvent("db_complete")
	root.End()
	root.Status = StatusOK

	assert(root.TraceID == child.TraceID, "same trace")
	assert(child.ParentID == root.SpanID, "parent-child link")
	assert(root.Attributes["http.method"] == "GET", "root attribute")
	assert(child.Attributes["db.system"] == "postgresql", "child attribute")
	assert(len(child.Events) == 1, "child has event")
	assert(child.Status == StatusOK, "child OK")
	assert(root.Duration() >= 0, "root has duration")
}

// ── Trace ID Propagation ────────────────────────────────────────────
// In distributed systems, trace IDs propagate through context.
// This simulates a request flowing through multiple services.

type Service struct {
	Name string
	Log  []string
	mu   sync.Mutex
}

func (s *Service) Handle(ctx context.Context, operation string) context.Context {
	traceID, _ := ctx.Value(traceIDKey).(string)
	s.mu.Lock()
	s.Log = append(s.Log, fmt.Sprintf("[%s] %s: %s", traceID, s.Name, operation))
	s.mu.Unlock()
	return ctx // pass context through
}

func testTraceIdPropagation() {
	gateway := &Service{Name: "gateway"}
	auth := &Service{Name: "auth"}
	users := &Service{Name: "users"}

	// Simulate request flowing through services
	ctx := context.WithValue(context.Background(), traceIDKey, "req-42")

	ctx = gateway.Handle(ctx, "received request")
	ctx = auth.Handle(ctx, "validated token")
	_ = users.Handle(ctx, "fetched user list")

	// All services logged with the same trace ID
	assert(strings.Contains(gateway.Log[0], "req-42"), "gateway traced")
	assert(strings.Contains(auth.Log[0], "req-42"), "auth traced")
	assert(strings.Contains(users.Log[0], "req-42"), "users traced")
}

// ── Filter by Level (Performance) ───────────────────────────────────
// Best practice: check level BEFORE formatting. A filtered-out log
// call should cost one comparison, not a full format cycle.

func testFilterByLevel() {
	formatCalled := false

	var buf bytes.Buffer
	handler := slog.NewTextHandler(&buf, &slog.HandlerOptions{
		Level: slog.LevelWarn, // only Warn and above
	})
	logger := slog.New(handler)

	// slog checks level before evaluating LogAttrs arguments
	// but regular key-value args are always evaluated.
	// Use LogAttrs for performance-critical paths:
	logger.LogAttrs(context.Background(), slog.LevelDebug, "debug msg",
		slog.String("expensive", func() string {
			formatCalled = true
			return "computed"
		}()),
	)

	// Note: the string was still computed because Go evaluates function
	// arguments before the call. For truly lazy evaluation, use Enabled():
	formatCalled = false
	if logger.Enabled(context.Background(), slog.LevelDebug) {
		// This block is skipped entirely when debug is disabled
		formatCalled = true
		logger.Debug("expensive operation")
	}
	assert(!formatCalled, "debug block skipped")

	// Rust tracing does this automatically with the event! macro:
	//   debug!("value: {}", expensive_fn());  // macro short-circuits
}

// ── Custom slog Handler ─────────────────────────────────────────────
// slog's Handler interface lets you write custom log backends.
// This is like Rust's tracing Subscriber.

type CountingHandler struct {
	inner  slog.Handler
	counts map[slog.Level]int
	mu     sync.Mutex
}

func NewCountingHandler(inner slog.Handler) *CountingHandler {
	return &CountingHandler{
		inner:  inner,
		counts: make(map[slog.Level]int),
	}
}

func (h *CountingHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.inner.Enabled(ctx, level)
}

func (h *CountingHandler) Handle(ctx context.Context, r slog.Record) error {
	h.mu.Lock()
	h.counts[r.Level]++
	h.mu.Unlock()
	return h.inner.Handle(ctx, r)
}

func (h *CountingHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &CountingHandler{inner: h.inner.WithAttrs(attrs), counts: h.counts}
}

func (h *CountingHandler) WithGroup(name string) slog.Handler {
	return &CountingHandler{inner: h.inner.WithGroup(name), counts: h.counts}
}

func testCustomHandler() {
	var buf bytes.Buffer
	inner := slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelDebug})
	counting := NewCountingHandler(inner)
	logger := slog.New(counting)

	logger.Info("one")
	logger.Info("two")
	logger.Warn("warning")
	logger.Error("error")

	assert(counting.counts[slog.LevelInfo] == 2, "two info logs")
	assert(counting.counts[slog.LevelWarn] == 1, "one warn log")
	assert(counting.counts[slog.LevelError] == 1, "one error log")
}

// ── OpenTelemetry Pattern ───────────────────────────────────────────
// Model the OpenTelemetry Go SDK pattern. In production, you'd use
// go.opentelemetry.io/otel. We model the core concepts here.

type Tracer struct {
	name  string
	spans []*Span
}

func NewTracer(name string) *Tracer {
	return &Tracer{name: name}
}

func (t *Tracer) Start(ctx context.Context, name string) (context.Context, *Span) {
	span := &Span{
		Name:      name,
		TraceID:   fmt.Sprintf("trace-%d", len(t.spans)),
		SpanID:    fmt.Sprintf("span-%d", len(t.spans)),
		StartTime: time.Now(),
	}

	// Check for parent span in context
	if parent, ok := ctx.Value(contextKey("span")).(*Span); ok {
		span.TraceID = parent.TraceID
		span.ParentID = parent.SpanID
	}

	t.spans = append(t.spans, span)
	return context.WithValue(ctx, contextKey("span"), span), span
}

func testOpenTelemetryPattern() {
	tracer := NewTracer("my-service")

	// Start root span
	ctx, rootSpan := tracer.Start(context.Background(), "handleRequest")
	rootSpan.SetAttribute("http.method", "GET")

	// Start child span (inherits trace ID from context)
	_, dbSpan := tracer.Start(ctx, "queryDatabase")
	dbSpan.SetAttribute("db.system", "postgres")
	dbSpan.End()

	rootSpan.End()

	assert(len(tracer.spans) == 2, "two spans recorded")
	assert(tracer.spans[0].Name == "handleRequest", "root span")
	assert(tracer.spans[1].Name == "queryDatabase", "child span")
	assert(tracer.spans[1].TraceID == tracer.spans[0].TraceID, "same trace")
	assert(tracer.spans[1].ParentID == tracer.spans[0].SpanID, "parent link")
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
