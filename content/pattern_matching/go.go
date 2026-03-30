// Vidya — Pattern Matching in Go
//
// Go doesn't have Rust-style pattern matching or match expressions.
// Instead it uses: switch statements (including type switches),
// if-else chains, and comma-ok idioms. Go's switch is more powerful
// than C's — cases don't fall through by default, and you can switch
// on any comparable expression.

package main

import (
	"fmt"
	"strings"
)

// ── Interface + type switch: Go's closest to pattern matching ──────

type Shape interface {
	Area() float64
}

type Circle struct{ Radius float64 }
type Rectangle struct{ Width, Height float64 }
type Triangle struct{ Base, Height float64 }

func (c Circle) Area() float64    { return 3.14159265 * c.Radius * c.Radius }
func (r Rectangle) Area() float64 { return r.Width * r.Height }
func (t Triangle) Area() float64  { return 0.5 * t.Base * t.Height }

func describe(s Shape) string {
	switch v := s.(type) {
	case Circle:
		return fmt.Sprintf("circle r=%.1f", v.Radius)
	case Rectangle:
		return fmt.Sprintf("rect %gx%g", v.Width, v.Height)
	case Triangle:
		return fmt.Sprintf("tri base=%g", v.Base)
	default:
		return "unknown"
	}
}

func main() {
	// ── Type switch ────────────────────────────────────────────────
	assert(describe(Circle{1.0}) == "circle r=1.0", "circle describe")
	assert(describe(Rectangle{3, 4}) == "rect 3x4", "rect describe")

	// ── Expression switch (no tag) ─────────────────────────────────
	classify := func(n int) string {
		switch {
		case n < 0:
			return "negative"
		case n == 0:
			return "zero"
		case n <= 10:
			return "small"
		default:
			return "large"
		}
	}

	assert(classify(-5) == "negative", "negative")
	assert(classify(0) == "zero", "zero")
	assert(classify(7) == "small", "small")
	assert(classify(100) == "large", "large")

	// ── Value switch ───────────────────────────────────────────────
	statusText := func(code int) string {
		switch code {
		case 200:
			return "ok"
		case 301, 302: // multiple values per case
			return "redirect"
		case 404:
			return "not found"
		case 500:
			return "server error"
		default:
			return "unknown"
		}
	}

	assert(statusText(200) == "ok", "200")
	assert(statusText(301) == "redirect", "301")
	assert(statusText(999) == "unknown", "999")

	// ── Comma-ok pattern: Go's Option equivalent ───────────────────
	m := map[string]int{"port": 3000}

	// Checking existence
	val, ok := m["port"]
	assert(ok && val == 3000, "key present")

	_, ok = m["missing"]
	assert(!ok, "key absent")

	// ── Type assertion with comma-ok ───────────────────────────────
	var s Shape = Circle{5.0}

	if c, ok := s.(Circle); ok {
		assert(c.Radius == 5.0, "type assertion circle")
	}

	if _, ok := s.(Rectangle); ok {
		panic("should not be rectangle")
	}

	// ── Destructuring: multiple return values ──────────────────────
	quot, rem := divmod(17, 5)
	assert(quot == 3 && rem == 2, "divmod")

	// ── If with initialization (Go's if-let equivalent) ────────────
	text := "port=3000"
	if idx := strings.Index(text, "="); idx >= 0 {
		key := text[:idx]
		value := text[idx+1:]
		assert(key == "port", "if-init key")
		assert(value == "3000", "if-init value")
	}

	// ── Fallthrough (explicit, unlike C) ───────────────────────────
	result := ""
	switch 1 {
	case 1:
		result += "one"
		fallthrough // explicitly fall through to next case
	case 2:
		result += "+two"
	case 3:
		result += "+three"
	}
	assert(result == "one+two", "fallthrough")

	// ── Select for channel pattern matching ────────────────────────
	ch1 := make(chan string, 1)
	ch2 := make(chan string, 1)
	ch1 <- "hello"

	var received string
	select {
	case msg := <-ch1:
		received = msg
	case msg := <-ch2:
		received = msg
	default:
		received = "nothing"
	}
	assert(received == "hello", "select")

	fmt.Println("All pattern matching examples passed.")
}

func divmod(a, b int) (int, int) {
	return a / b, a % b
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
