// Vidya — Type Systems in Go
//
// Go has a static type system with interfaces for polymorphism.
// Interfaces are satisfied implicitly (structural typing). Generics
// (Go 1.18+) enable type-safe reusable code. Go favors composition
// over inheritance — there are no classes.

package main

import (
	"fmt"
	"strings"
)

// ── Interfaces: implicit satisfaction ──────────────────────────────

type Stringer interface {
	String() string
}

type Point struct{ X, Y int }

func (p Point) String() string {
	return fmt.Sprintf("(%d, %d)", p.X, p.Y)
}

// Point satisfies Stringer without declaring it — structural typing

// ── Multiple interfaces ────────────────────────────────────────────

type Reader interface {
	Read() string
}

type Writer interface {
	Write(s string)
}

type ReadWriter interface {
	Reader
	Writer
}

type Buffer struct {
	data string
}

func (b *Buffer) Read() string    { return b.data }
func (b *Buffer) Write(s string)  { b.data += s }

// ── Generics (Go 1.18+) ───────────────────────────────────────────

func Max[T int | float64 | string](a, b T) T {
	if a > b {
		return a
	}
	return b
}

// Type constraint interface
type Number interface {
	int | int32 | int64 | float64
}

func Sum[T Number](nums []T) T {
	var total T
	for _, n := range nums {
		total += n
	}
	return total
}

// ── Generic data structure ─────────────────────────────────────────

type Stack[T any] struct {
	items []T
}

func (s *Stack[T]) Push(item T) {
	s.items = append(s.items, item)
}

func (s *Stack[T]) Pop() (T, bool) {
	if len(s.items) == 0 {
		var zero T
		return zero, false
	}
	last := s.items[len(s.items)-1]
	s.items = s.items[:len(s.items)-1]
	return last, true
}

func (s *Stack[T]) Len() int {
	return len(s.items)
}

// ── Embedding: composition over inheritance ─────────────────────────

type Animal struct {
	Name string
}

func (a Animal) Speak() string {
	return a.Name + " speaks"
}

type Dog struct {
	Animal // embedded — Dog "inherits" Speak()
	Breed  string
}

// Dog can override
func (d Dog) Fetch() string {
	return d.Name + " fetches"
}

// ── Named types (newtype pattern) ──────────────────────────────────

type Celsius float64
type Fahrenheit float64

func (c Celsius) ToFahrenheit() Fahrenheit {
	return Fahrenheit(c*9/5 + 32)
}

func main() {
	// ── Interface satisfaction ──────────────────────────────────────
	var s Stringer = Point{3, 4}
	assert(s.String() == "(3, 4)", "stringer")

	// ── Interface as parameter ─────────────────────────────────────
	printStr := func(s Stringer) string { return s.String() }
	assert(printStr(Point{1, 2}) == "(1, 2)", "interface param")

	// ── ReadWriter interface ───────────────────────────────────────
	var rw ReadWriter = &Buffer{}
	rw.Write("hello")
	assert(rw.Read() == "hello", "readwriter")

	// ── Empty interface: any ───────────────────────────────────────
	var anything any = 42
	assert(anything.(int) == 42, "any int")
	anything = "hello"
	assert(anything.(string) == "hello", "any string")

	// ── Generics ───────────────────────────────────────────────────
	assert(Max(3, 5) == 5, "max int")
	assert(Max(3.14, 2.71) == 3.14, "max float")
	assert(Max("b", "a") == "b", "max string")

	ints := []int{1, 2, 3, 4, 5}
	assert(Sum(ints) == 15, "sum ints")

	floats := []float64{1.1, 2.2, 3.3}
	assertFloat(Sum(floats), 6.6, "sum floats")

	// ── Generic data structure ─────────────────────────────────────
	stack := &Stack[int]{}
	stack.Push(1)
	stack.Push(2)
	stack.Push(3)

	val, ok := stack.Pop()
	assert(ok && val == 3, "stack pop")
	assert(stack.Len() == 2, "stack len")

	// ── Embedding (composition) ────────────────────────────────────
	dog := Dog{
		Animal: Animal{Name: "Rex"},
		Breed:  "Labrador",
	}
	assert(dog.Speak() == "Rex speaks", "embedded method")
	assert(dog.Fetch() == "Rex fetches", "own method")
	assert(dog.Name == "Rex", "promoted field")

	// ── Named types ────────────────────────────────────────────────
	boiling := Celsius(100)
	f := boiling.ToFahrenheit()
	assertFloat(float64(f), 212.0, "celsius to fahrenheit")

	// Can't mix types without explicit conversion
	// var bad Fahrenheit = boiling  // ← compile error!

	// ── Type assertions and switches ───────────────────────────────
	values := []any{42, "hello", 3.14, true}
	types := []string{}
	for _, v := range values {
		switch v.(type) {
		case int:
			types = append(types, "int")
		case string:
			types = append(types, "string")
		case float64:
			types = append(types, "float")
		case bool:
			types = append(types, "bool")
		}
	}
	assert(strings.Join(types, ",") == "int,string,float,bool", "type switch")

	fmt.Println("All type system examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}

func assertFloat(got, want float64, msg string) {
	if got-want > 0.001 || want-got > 0.001 {
		panic(fmt.Sprintf("assertion failed (%s): got %f, want %f", msg, got, want))
	}
}
