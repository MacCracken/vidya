// Vidya — Error Handling in Go
//
// Go uses explicit error return values — no exceptions. Functions return
// (result, error) pairs. The caller checks err != nil. Custom error types
// implement the error interface. errors.Is and errors.As handle wrapping.

package main

import (
	"errors"
	"fmt"
	"strconv"
)

// ── Custom error types ─────────────────────────────────────────────

type MissingKeyError struct {
	Key string
}

func (e *MissingKeyError) Error() string {
	return fmt.Sprintf("missing key: %s", e.Key)
}

type ParseError struct {
	Key    string
	Value  string
	Reason error
}

func (e *ParseError) Error() string {
	return fmt.Sprintf("cannot parse '%s=%s': %v", e.Key, e.Value, e.Reason)
}

func (e *ParseError) Unwrap() error {
	return e.Reason
}

// ── Functions returning errors ─────────────────────────────────────

func readPort(configText string) (int, error) {
	lines := splitLines(configText)
	for _, line := range lines {
		if len(line) > 5 && line[:5] == "port=" {
			value := line[5:]
			port, err := strconv.Atoi(value)
			if err != nil {
				return 0, &ParseError{Key: "port", Value: value, Reason: err}
			}
			return port, nil
		}
	}
	return 0, &MissingKeyError{Key: "port"}
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			line := s[start:i]
			if len(line) > 0 {
				lines = append(lines, line)
			}
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

// ── Wrapping errors with context ───────────────────────────────────

func processConfig(text string) (int, error) {
	port, err := readPort(text)
	if err != nil {
		return 0, fmt.Errorf("processing config: %w", err)
	}
	return port, nil
}

// ── Sentinel errors ────────────────────────────────────────────────

var ErrNotFound = errors.New("not found")

func findUser(id int) (string, error) {
	users := map[int]string{1: "alice", 2: "bob"}
	name, ok := users[id]
	if !ok {
		return "", fmt.Errorf("user %d: %w", id, ErrNotFound)
	}
	return name, nil
}

func main() {
	// ── Basic error handling ───────────────────────────────────────
	port, err := readPort("host=localhost\nport=3000\n")
	assert(err == nil, "should parse")
	assert(port == 3000, "port value")

	// ── Missing key error ──────────────────────────────────────────
	_, err = readPort("host=localhost\n")
	assert(err != nil, "should error on missing port")
	var missingErr *MissingKeyError
	assert(errors.As(err, &missingErr), "should be MissingKeyError")
	assert(missingErr.Key == "port", "key should be port")

	// ── Parse error with wrapping ──────────────────────────────────
	_, err = readPort("port=abc\n")
	assert(err != nil, "should error on bad port")
	var parseErr *ParseError
	assert(errors.As(err, &parseErr), "should be ParseError")
	assert(parseErr.Key == "port", "parse error key")

	// Unwrap to get the underlying strconv error
	var numErr *strconv.NumError
	assert(errors.As(err, &numErr), "should unwrap to NumError")

	// ── fmt.Errorf with %w wraps the error ─────────────────────────
	_, err = processConfig("port=abc\n")
	assert(err != nil, "processConfig should error")
	// errors.As traverses the wrap chain
	assert(errors.As(err, &parseErr), "wrapped ParseError")

	// ── Sentinel errors with errors.Is ─────────────────────────────
	name, err := findUser(1)
	assert(err == nil, "alice exists")
	assert(name == "alice", "alice name")

	_, err = findUser(999)
	assert(errors.Is(err, ErrNotFound), "should be ErrNotFound")

	// ── The comma-ok pattern (not an error, just absence) ──────────
	m := map[string]int{"a": 1}
	val, ok := m["b"]
	assert(!ok, "key not present")
	assert(val == 0, "zero value on miss")

	// ── defer for cleanup ──────────────────────────────────────────
	cleaned := false
	func() {
		defer func() { cleaned = true }()
		// work happens here
	}()
	assert(cleaned, "defer ran")

	// ── recover from panics ────────────────────────────────────────
	recovered := false
	func() {
		defer func() {
			if r := recover(); r != nil {
				recovered = true
			}
		}()
		panic("test panic")
	}()
	assert(recovered, "recovered from panic")

	fmt.Println("All error handling examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
