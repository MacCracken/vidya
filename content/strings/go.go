// Vidya — Strings in Go
//
// Go strings are immutable byte slices, always UTF-8 by convention.
// The string type is a read-only slice of bytes. For mutable string
// building, use strings.Builder. Rune iteration handles Unicode correctly.

package main

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

func main() {
	// ── Creation ────────────────────────────────────────────────────
	literal := "hello"
	fromFmt := fmt.Sprintf("%s world", literal)
	multiline := `line one
line two`
	assert(fromFmt == "hello world", "sprintf")
	assert(strings.Count(multiline, "\n") == 1, "multiline")

	// ── Strings are immutable byte slices ──────────────────────────
	s := "hello"
	// s[0] = 'H'  // ← compile error! strings are immutable
	s = "H" + s[1:] // creates a new string
	assert(s == "Hello", "immutable concat")

	// ── Byte length vs rune count ──────────────────────────────────
	cafe := "café"
	assert(len(cafe) == 5, "byte length")                    // 5 bytes (é is 2 bytes)
	assert(utf8.RuneCountInString(cafe) == 4, "rune count")  // 4 runes

	// ── Iterating runes (characters), not bytes ────────────────────
	runes := []rune(cafe)
	assert(runes[3] == 'é', "rune indexing")

	// range iterates by rune automatically
	count := 0
	for range cafe {
		count++
	}
	assert(count == 4, "range rune iteration")

	// ── strings.Builder: efficient concatenation ───────────────────
	// GOOD: Builder pre-allocates, O(n) total
	var b strings.Builder
	b.Grow(64) // pre-allocate
	for i := 0; i < 10; i++ {
		fmt.Fprintf(&b, "%d ", i)
	}
	result := strings.TrimSpace(b.String())
	assert(result == "0 1 2 3 4 5 6 7 8 9", "builder")

	// BAD: += in a loop is O(n²)
	// s := ""; for i := 0; i < 10; i++ { s += fmt.Sprintf("%d ", i) }

	// ── strings.Join: the idiomatic way ────────────────────────────
	words := []string{"hello", "world", "from", "go"}
	joined := strings.Join(words, " ")
	assert(joined == "hello world from go", "join")

	// ── Common operations ──────────────────────────────────────────
	assert(strings.Contains("hello world", "world"), "contains")
	assert(strings.HasPrefix("hello", "hel"), "prefix")
	assert(strings.HasSuffix("hello", "llo"), "suffix")
	assert(strings.ToUpper("hello") == "HELLO", "upper")
	assert(strings.ToLower("HELLO") == "hello", "lower")
	assert(strings.TrimSpace("  hello  ") == "hello", "trim")
	assert(strings.Replace("hello world", "world", "go", 1) == "hello go", "replace")
	assert(strings.Index("hello world", "world") == 6, "index")

	// ── Splitting ──────────────────────────────────────────────────
	parts := strings.Split("a,b,c", ",")
	assert(len(parts) == 3, "split len")
	assert(parts[1] == "b", "split value")

	fields := strings.Fields("  hello   world  ")
	assert(len(fields) == 2, "fields len")

	// ── String conversion ──────────────────────────────────────────
	num := fmt.Sprintf("%d", 42)
	assert(num == "42", "int to string")

	// ── Byte slice conversion ──────────────────────────────────────
	bytes := []byte("hello")
	bytes[0] = 'H'                          // mutable!
	assert(string(bytes) == "Hello", "byte slice mutation")

	// ── String comparison ──────────────────────────────────────────
	assert("hello" == "hello", "equality")
	assert(strings.EqualFold("Hello", "hello"), "case insensitive")

	fmt.Println("All string examples passed.")
}

func assert(cond bool, msg string) {
	if !cond {
		panic("assertion failed: " + msg)
	}
}
