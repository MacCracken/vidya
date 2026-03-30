// Vidya — Input/Output in Go
//
// Go I/O is built on the io.Reader and io.Writer interfaces — two of
// the most important interfaces in Go. bufio adds buffering. os.File,
// bytes.Buffer, strings.Reader all satisfy these interfaces.

package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"os"
	"strings"
)

func main() {
	// ── Writing to a buffer ────────────────────────────────────────
	var buf bytes.Buffer
	fmt.Fprint(&buf, "hello ")
	fmt.Fprint(&buf, "world")
	assert(buf.String() == "hello world", "buffer write")

	// ── io.Reader: reading from strings ────────────────────────────
	reader := strings.NewReader("hello world")
	data, err := io.ReadAll(reader)
	assertNoErr(err)
	assert(string(data) == "hello world", "ReadAll")

	// ── Buffered reading: line by line ──────────────────────────────
	input := "line1\nline2\nline3\n"
	scanner := bufio.NewScanner(strings.NewReader(input))
	var lines []string
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	assert(len(lines) == 3, "scanner lines")
	assert(lines[0] == "line1", "first line")

	// ── io.Copy: connect reader to writer ──────────────────────────
	var dest bytes.Buffer
	src := strings.NewReader("copy this")
	n, err := io.Copy(&dest, src)
	assertNoErr(err)
	assert(n == 9, "copy bytes")
	assert(dest.String() == "copy this", "copy content")

	// ── MultiReader: concatenate streams ───────────────────────────
	r1 := strings.NewReader("hello ")
	r2 := strings.NewReader("world")
	multi := io.MultiReader(r1, r2)
	combined, _ := io.ReadAll(multi)
	assert(string(combined) == "hello world", "MultiReader")

	// ── MultiWriter: tee to multiple destinations ──────────────────
	var dest1, dest2 bytes.Buffer
	tee := io.MultiWriter(&dest1, &dest2)
	fmt.Fprint(tee, "shared")
	assert(dest1.String() == "shared", "tee dest1")
	assert(dest2.String() == "shared", "tee dest2")

	// ── TeeReader: read and copy simultaneously ────────────────────
	var logged bytes.Buffer
	teeReader := io.TeeReader(strings.NewReader("data"), &logged)
	result, _ := io.ReadAll(teeReader)
	assert(string(result) == "data", "tee read")
	assert(logged.String() == "data", "tee log")

	// ── LimitReader: cap bytes read ────────────────────────────────
	limited := io.LimitReader(strings.NewReader("hello world"), 5)
	first5, _ := io.ReadAll(limited)
	assert(string(first5) == "hello", "LimitReader")

	// ── Buffered writer ────────────────────────────────────────────
	var backing bytes.Buffer
	bw := bufio.NewWriter(&backing)
	for i := 0; i < 100; i++ {
		fmt.Fprintf(bw, "line %d\n", i)
	}
	bw.Flush() // must flush!
	assert(strings.Contains(backing.String(), "line 99"), "buffered writer")

	// ── File I/O with temp file ────────────────────────────────────
	tmpfile, err := os.CreateTemp("", "vidya-*.txt")
	assertNoErr(err)
	defer os.Remove(tmpfile.Name())

	_, err = tmpfile.WriteString("file content\n")
	assertNoErr(err)
	tmpfile.Close()

	// Read back
	content, err := os.ReadFile(tmpfile.Name())
	assertNoErr(err)
	assert(string(content) == "file content\n", "file roundtrip")

	// ── Seek ───────────────────────────────────────────────────────
	f, _ := os.Open(tmpfile.Name())
	defer f.Close()
	f.Seek(5, io.SeekStart) // skip "file "
	rest, _ := io.ReadAll(f)
	assert(string(rest) == "content\n", "seek+read")

	// ── Pipe: connected reader/writer ──────────────────────────────
	pr, pw := io.Pipe()
	go func() {
		fmt.Fprint(pw, "piped data")
		pw.Close()
	}()
	piped, _ := io.ReadAll(pr)
	assert(string(piped) == "piped data", "pipe")

	fmt.Println("All input/output examples passed.")
}

func assert(cond bool, msg string) {
	if !cond { panic("assertion failed: " + msg) }
}

func assertNoErr(err error) {
	if err != nil { panic("unexpected error: " + err.Error()) }
}
