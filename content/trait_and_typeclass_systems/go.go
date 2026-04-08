// Vidya — Trait and Typeclass Systems in Go
//
// Go has interfaces, not traits. The key difference: Go interfaces
// are satisfied implicitly (structural typing). You never write
// "implements Foo" — if your type has the right methods, it satisfies
// the interface. This enables decoupled design but loses some of
// Rust's compile-time guarantees (associated types, default methods,
// trait bounds on generics).
//
// Key contrasts with Rust traits:
//   Go:   implicit satisfaction, no generics on interfaces (until 1.18)
//   Rust: explicit `impl Trait for Type`, associated types, trait bounds
//   Go:   embedding for composition (not inheritance)
//   Rust: supertraits for composition

package main

import (
	"fmt"
	"math"
	"strings"
)

func main() {
	testImplicitSatisfaction()
	testEmptyInterface()
	testTypeAssertions()
	testTypeSwitches()
	testEmbeddingComposition()
	testInterfaceComposition()
	testMethodSets()
	testStringerInterface()
	testErrorInterface()
	testFunctionalInterfaces()

	fmt.Println("All trait and typeclass system examples passed.")
}

// ── Implicit Interface Satisfaction ─────────────────────────────────
// In Rust: impl Shape for Circle { ... }  — explicit
// In Go: Circle has Area() float64         — that's enough

type Shape interface {
	Area() float64
	Perimeter() float64
}

type Circle struct{ Radius float64 }

func (c Circle) Area() float64      { return math.Pi * c.Radius * c.Radius }
func (c Circle) Perimeter() float64 { return 2 * math.Pi * c.Radius }

type Rectangle struct{ Width, Height float64 }

func (r Rectangle) Area() float64      { return r.Width * r.Height }
func (r Rectangle) Perimeter() float64 { return 2 * (r.Width + r.Height) }

// No "impl Shape for Circle" — the compiler checks structurally
func totalArea(shapes []Shape) float64 {
	sum := 0.0
	for _, s := range shapes {
		sum += s.Area()
	}
	return sum
}

func testImplicitSatisfaction() {
	shapes := []Shape{
		Circle{Radius: 5},
		Rectangle{Width: 3, Height: 4},
	}
	area := totalArea(shapes)
	expected := math.Pi*25 + 12
	assert(math.Abs(area-expected) < 0.001, "total area")
}

// ── Empty Interface (any) ───────────────────────────────────────────
// `any` (alias for `interface{}`) accepts any type. Like Rust's
// `dyn Any` but used much more broadly in Go.

func testEmptyInterface() {
	var box any

	box = 42
	assert(box.(int) == 42, "any holds int")

	box = "hello"
	assert(box.(string) == "hello", "any holds string")

	box = Circle{Radius: 3}
	c := box.(Circle)
	assert(c.Radius == 3, "any holds struct")
}

// ── Type Assertions ─────────────────────────────────────────────────
// Type assertions recover the concrete type from an interface.
// Like Rust's downcast on dyn Any, but more ergonomic.

func testTypeAssertions() {
	var s Shape = Circle{Radius: 10}

	// Checked assertion (safe — returns ok bool)
	c, ok := s.(Circle)
	assert(ok, "is a Circle")
	assert(c.Radius == 10, "extracted radius")

	// Failed assertion
	_, ok = s.(Rectangle)
	assert(!ok, "not a Rectangle")

	// Unchecked assertion panics on failure:
	//   r := s.(Rectangle)  // panic: interface conversion
	// In Rust, downcast_ref returns Option — same idea, different syntax
}

// ── Type Switches ───────────────────────────────────────────────────
// Go's type switch is pattern matching on the concrete type behind
// an interface. Like Rust's match on enum variants, but for interfaces.

func describe(s Shape) string {
	switch v := s.(type) {
	case Circle:
		return fmt.Sprintf("circle r=%.1f", v.Radius)
	case Rectangle:
		return fmt.Sprintf("rect %gx%g", v.Width, v.Height)
	default:
		return "unknown shape"
	}
}

func testTypeSwitches() {
	assert(describe(Circle{Radius: 5}) == "circle r=5.0", "type switch circle")
	assert(describe(Rectangle{Width: 3, Height: 4}) == "rect 3x4", "type switch rect")
}

// ── Embedding for Composition ───────────────────────────────────────
// Go uses struct embedding instead of trait inheritance. Embedded
// types promote their methods, giving the outer type their interface
// for free. Like Rust's supertraits, but at the struct level.

type Named struct {
	Name string
}

func (n Named) String() string { return n.Name }

type Animal struct {
	Named      // embedded — Animal gets String() for free
	Legs  int
}

type Vehicle struct {
	Named
	Wheels int
}

func testEmbeddingComposition() {
	a := Animal{Named: Named{Name: "dog"}, Legs: 4}
	assert(a.String() == "dog", "promoted method")  // calls Named.String()
	assert(a.Name == "dog", "promoted field")        // direct field access

	v := Vehicle{Named: Named{Name: "car"}, Wheels: 4}
	assert(v.String() == "car", "vehicle string")

	// Both satisfy fmt.Stringer through embedding
	var s fmt.Stringer = a
	assert(s.String() == "dog", "animal is Stringer")
	s = v
	assert(s.String() == "car", "vehicle is Stringer")
}

// ── Interface Composition ───────────────────────────────────────────
// Go composes interfaces by embedding, like Rust's supertraits.
//   Rust: trait ReadWrite: Read + Write {}
//   Go:   type ReadWriter interface { Reader; Writer }

type Reader interface {
	Read(p []byte) (int, error)
}

type Writer interface {
	Write(p []byte) (int, error)
}

type ReadWriter interface {
	Reader
	Writer
}

// A buffer that satisfies ReadWriter
type Buffer struct {
	data []byte
	pos  int
}

func (b *Buffer) Read(p []byte) (int, error) {
	n := copy(p, b.data[b.pos:])
	b.pos += n
	return n, nil
}

func (b *Buffer) Write(p []byte) (int, error) {
	b.data = append(b.data, p...)
	return len(p), nil
}

func testInterfaceComposition() {
	buf := &Buffer{}

	// Satisfies Writer
	var w Writer = buf
	n, _ := w.Write([]byte("hello"))
	assert(n == 5, "wrote 5 bytes")

	// Satisfies Reader
	var r Reader = buf
	out := make([]byte, 5)
	n, _ = r.Read(out)
	assert(n == 5, "read 5 bytes")
	assert(string(out) == "hello", "read content")

	// Satisfies ReadWriter (composite interface)
	var rw ReadWriter = buf
	rw.Write([]byte(" world"))
	assert(len(buf.data) == 11, "composite interface works")
}

// ── Method Sets and Pointer Receivers ───────────────────────────────
// A subtle rule: *T satisfies interfaces requiring pointer receivers,
// but T does not. This is Go's version of &self vs &mut self in Rust.

type Counter struct{ count int }

func (c *Counter) Increment() { c.count++ }
func (c Counter) Value() int   { return c.count }

type Incrementable interface {
	Increment()
	Value() int
}

func testMethodSets() {
	c := &Counter{}  // pointer — satisfies Incrementable
	var inc Incrementable = c
	inc.Increment()
	inc.Increment()
	assert(inc.Value() == 2, "pointer receiver interface")

	// var inc2 Incrementable = Counter{}  // compile error!
	// Counter value doesn't have Increment() in its method set.
	// Only *Counter does, because Increment takes a pointer receiver.
	//
	// In Rust terms: &self methods are on both T and &T,
	// but &mut self methods require &mut T.
}

// ── Stringer Interface ──────────────────────────────────────────────
// fmt.Stringer is Go's equivalent of Rust's Display trait.
//   Rust: impl fmt::Display for T { fn fmt(...) -> fmt::Result }
//   Go:   func (t T) String() string

type Color struct{ R, G, B uint8 }

func (c Color) String() string {
	return fmt.Sprintf("#%02X%02X%02X", c.R, c.G, c.B)
}

func testStringerInterface() {
	red := Color{255, 0, 0}
	assert(red.String() == "#FF0000", "stringer")

	// fmt.Sprintf automatically calls String() for %s and %v
	s := fmt.Sprintf("%v", red)
	assert(s == "#FF0000", "sprintf uses Stringer")
}

// ── Error Interface ─────────────────────────────────────────────────
// Go's error is a single-method interface: Error() string
// This is simpler than Rust's std::error::Error trait (which has
// source(), Display, Debug). Go's simplicity means less boilerplate
// but also less structured error chains.

type ValidationError struct {
	Field   string
	Message string
}

func (e *ValidationError) Error() string {
	return fmt.Sprintf("validation: %s — %s", e.Field, e.Message)
}

func validate(name string) error {
	if strings.TrimSpace(name) == "" {
		return &ValidationError{Field: "name", Message: "cannot be empty"}
	}
	return nil
}

func testErrorInterface() {
	err := validate("")
	assert(err != nil, "validation failed")
	assert(strings.Contains(err.Error(), "cannot be empty"), "error message")

	// Type assertion to get structured error
	ve, ok := err.(*ValidationError)
	assert(ok, "is ValidationError")
	assert(ve.Field == "name", "error field")

	assert(validate("Alice") == nil, "valid input")
}

// ── Functional Interfaces ───────────────────────────────────────────
// Go interfaces with a single method are like Rust's Fn traits.
// You can also use function types directly.

type Predicate func(int) bool

type Filterable interface {
	Filter(Predicate) []int
}

type IntSlice []int

func (s IntSlice) Filter(p Predicate) []int {
	var result []int
	for _, v := range s {
		if p(v) {
			result = append(result, v)
		}
	}
	return result
}

func testFunctionalInterfaces() {
	nums := IntSlice{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

	evens := nums.Filter(func(n int) bool { return n%2 == 0 })
	assert(len(evens) == 5, "filtered evens")
	assert(evens[0] == 2, "first even")

	// In Rust: iter().filter(|n| n % 2 == 0).collect::<Vec<_>>()
	// Same idea, different syntax. Rust's Fn/FnMut/FnOnce gives
	// more control over capture semantics.

	big := nums.Filter(func(n int) bool { return n > 7 })
	assert(len(big) == 3, "filtered >7")
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
