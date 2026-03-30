// Vidya — Testing in Go
//
// Go has built-in testing via the testing package and `go test`.
// Test functions are named TestXxx and take *testing.T. Table-driven
// tests are the standard pattern. Benchmarks use *testing.B.
// This file demonstrates patterns as runnable assertions since it's
// not a _test.go file.

package main

import (
	"fmt"
	"strings"
)

// ── Code under test ────────────────────────────────────────────────

func ParseKV(line string) (string, string, error) {
	idx := strings.Index(line, "=")
	if idx < 0 {
		return "", "", fmt.Errorf("no '=' found in: %s", line)
	}
	key := strings.TrimSpace(line[:idx])
	value := strings.TrimSpace(line[idx+1:])
	if key == "" {
		return "", "", fmt.Errorf("empty key")
	}
	return key, value, nil
}

func Clamp(value, min, max int) int {
	if min > max {
		panic(fmt.Sprintf("min (%d) must be <= max (%d)", min, max))
	}
	if value < min {
		return min
	}
	if value > max {
		return max
	}
	return value
}

type Counter struct {
	count int
	max   int
}

func NewCounter(max int) *Counter {
	return &Counter{count: 0, max: max}
}

func (c *Counter) Increment() bool {
	if c.count < c.max {
		c.count++
		return true
	}
	return false
}

func (c *Counter) Value() int {
	return c.count
}

func main() {
	// ── Basic assertions ───────────────────────────────────────────
	k, v, err := ParseKV("host=localhost")
	assert(err == nil, "valid parse")
	assert(k == "host" && v == "localhost", "parse values")

	// ── Whitespace trimming ────────────────────────────────────────
	k, v, err = ParseKV("  port = 3000  ")
	assert(err == nil, "trimmed parse")
	assert(k == "port" && v == "3000", "trimmed values")

	// ── Empty value is ok ──────────────────────────────────────────
	k, v, err = ParseKV("key=")
	assert(err == nil, "empty value parse")
	assert(k == "key" && v == "", "empty value")

	// ── Error cases ────────────────────────────────────────────────
	_, _, err = ParseKV("no_equals")
	assert(err != nil, "should error without equals")
	assert(strings.Contains(err.Error(), "no '='"), "error message")

	_, _, err = ParseKV("=value")
	assert(err != nil, "should error on empty key")

	// ── Table-driven tests ─────────────────────────────────────────
	// The standard Go pattern: define test cases as a slice of structs
	clampCases := []struct {
		name     string
		value    int
		min, max int
		expected int
	}{
		{"in range", 5, 0, 10, 5},
		{"below min", -1, 0, 10, 0},
		{"above max", 100, 0, 10, 10},
		{"at min", 0, 0, 10, 0},
		{"at max", 10, 0, 10, 10},
		{"min equals max", 5, 5, 5, 5},
	}

	for _, tc := range clampCases {
		got := Clamp(tc.value, tc.min, tc.max)
		assert(got == tc.expected,
			fmt.Sprintf("Clamp(%d, %d, %d) = %d, want %d [%s]",
				tc.value, tc.min, tc.max, got, tc.expected, tc.name))
	}

	// ── Panic testing ──────────────────────────────────────────────
	panicked := false
	func() {
		defer func() {
			if r := recover(); r != nil {
				panicked = true
				msg := fmt.Sprintf("%v", r)
				assert(strings.Contains(msg, "min (10) must be <= max (5)"), "panic message")
			}
		}()
		Clamp(7, 10, 5) // min > max should panic
	}()
	assert(panicked, "should have panicked")

	// ── Stateful testing ───────────────────────────────────────────
	c := NewCounter(3)
	assert(c.Value() == 0, "initial value")
	assert(c.Increment(), "inc 1")
	assert(c.Increment(), "inc 2")
	assert(c.Increment(), "inc 3")
	assert(!c.Increment(), "inc at max")
	assert(c.Value() == 3, "final value")

	// ── Zero-max counter ───────────────────────────────────────────
	c = NewCounter(0)
	assert(!c.Increment(), "zero max increment")
	assert(c.Value() == 0, "zero max value")

	// ── Subtests pattern (in real Go tests) ────────────────────────
	// In a _test.go file, you'd write:
	//
	// func TestClamp(t *testing.T) {
	//     for _, tc := range cases {
	//         t.Run(tc.name, func(t *testing.T) {
	//             got := Clamp(tc.value, tc.min, tc.max)
	//             if got != tc.expected {
	//                 t.Errorf("got %d, want %d", got, tc.expected)
	//             }
	//         })
	//     }
	// }
	//
	// Run with: go test -run TestClamp/below_min -v

	fmt.Println("All testing examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
