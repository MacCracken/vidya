// Vidya — Macro Systems in Go
//
// Go has no macros. This is a deliberate design choice — Go values
// readability and simplicity over metaprogramming power. Instead of
// macros, Go provides:
//
//   1. go:generate — run code generators before compilation
//   2. Build tags  — conditional compilation
//   3. //go:embed   — embed files at compile time
//   4. //go:linkname — link to unexported symbols (unsafe escape hatch;
//                      restricted for the standard library since Go 1.23)
//   5. text/template — runtime code/text generation
//   6. reflect — runtime metaprogramming (with performance cost)
//
// Compare to Rust's macro system:
//   Rust macro_rules!  → Go has nothing (use go:generate)
//   Rust proc macros   → Go has nothing (use code generators)
//   Rust #[derive(...)] → Go has nothing (use go:generate + stringer)
//   Rust cfg!(...)      → Go build tags
//   Rust include_bytes! → //go:embed

package main

import (
	"bytes"
	_ "embed"
	"fmt"
	"reflect"
	"strings"
	"text/template"
)

func main() {
	testBuildTags()
	testGoEmbed()
	testTemplateCodeGen()
	testReflectMetaprogramming()
	testGeneratePatterns()
	testCompilerDirectives()

	fmt.Println("All macro system examples passed.")
}

// ── Build Tags (Conditional Compilation) ────────────────────────────
// Go's equivalent of Rust's #[cfg(...)]. Build tags select which
// files to include at compile time.
//
// File-level constraint (Go 1.17+):
//   //go:build linux && amd64
//
// Old syntax (still works):
//   // +build linux,amd64
//
// Custom tags:
//   //go:build debug
//   → enabled with: go build -tags debug
//
// Common patterns:
//   //go:build !windows        — everything except Windows
//   //go:build cgo             — only when CGo is enabled
//   //go:build ignore          — never compiled (documentation only)
//   //go:build integration     — integration tests via -tags integration

func testBuildTags() {
	// We can't test build tags at runtime (they're compile-time).
	// Instead, model what they do:

	type BuildConstraint struct {
		Expression string
		Matches    func(os, arch string, tags []string) bool
	}

	constraints := []BuildConstraint{
		{
			Expression: "linux && amd64",
			Matches: func(os, arch string, tags []string) bool {
				return os == "linux" && arch == "amd64"
			},
		},
		{
			Expression: "!windows",
			Matches: func(os, arch string, tags []string) bool {
				return os != "windows"
			},
		},
		{
			Expression: "linux || darwin",
			Matches: func(os, arch string, tags []string) bool {
				return os == "linux" || os == "darwin"
			},
		},
	}

	// Test linux/amd64
	assert(constraints[0].Matches("linux", "amd64", nil), "linux && amd64")
	assert(!constraints[0].Matches("linux", "arm64", nil), "not amd64")
	assert(constraints[1].Matches("linux", "amd64", nil), "!windows on linux")
	assert(!constraints[1].Matches("windows", "amd64", nil), "!windows on windows")
	assert(constraints[2].Matches("darwin", "arm64", nil), "darwin matches")
}

// ── go:embed (Compile-Time File Embedding) ──────────────────────────
// Rust: include_str!("file.txt"), include_bytes!("file.bin")
// Go:   //go:embed file.txt     (requires import "embed")
//
// //go:embed works in a single-file `go run` too: patterns are relative
// to the source file's directory, so this file can embed itself. (It goes
// on a package-level var; the corpus always names this file go.go.)

//go:embed go.go
var thisFile string

func testGoEmbed() {
	// In a real Go project:
	//   //go:embed version.txt
	//   var version string
	//
	//   //go:embed static/*
	//   var staticFS embed.FS
	//
	//   //go:embed schema.sql
	//   var schema []byte

	// The real thing: the compiler copied this source file into thisFile.
	assert(strings.HasPrefix(thisFile, "// Vidya — Macro Systems in Go"), "embedded own header")
	assert(strings.Contains(thisFile, "//go:embed go.go"), "embedded own directive")

	// Key differences from Rust:
	//   - Go embeds at compile time but into runtime variables
	//   - Rust's include_bytes! produces &'static [u8] (zero-cost)
	//   - Go's embed.FS supports directory trees (Rust needs include_dir crate)
}

// ── text/template (Runtime Code Generation) ─────────────────────────
// Since Go has no macros, code generation often happens at build
// time using go:generate + text/template. This is the runtime
// template engine that generators use.

func testTemplateCodeGen() {
	// Template for generating a Go enum with String() method
	const enumTemplate = `type {{.Name}} int

const (
{{- range $i, $v := .Variants}}
	{{$v}} {{if eq $i 0}}{{$.Name}} = iota{{end}}
{{- end}}
)

func (e {{.Name}}) String() string {
	switch e {
{{- range .Variants}}
	case {{.}}:
		return "{{.}}"
{{- end}}
	default:
		return "unknown"
	}
}`

	type EnumDef struct {
		Name     string
		Variants []string
	}

	tmpl, err := template.New("enum").Parse(enumTemplate)
	assert(err == nil, "template parses")

	var buf bytes.Buffer
	err = tmpl.Execute(&buf, EnumDef{
		Name:     "Color",
		Variants: []string{"Red", "Green", "Blue"},
	})
	assert(err == nil, "template executes")

	output := buf.String()
	assert(strings.Contains(output, "type Color int"), "generated type")
	assert(strings.Contains(output, "Red Color = iota"), "generated iota")
	assert(strings.Contains(output, "case Blue:"), "generated switch")

	// In Rust, this would be a proc macro:
	//   #[derive(Debug, Display)]
	//   enum Color { Red, Green, Blue }
	//
	// Go requires an external tool (stringer, enumer) + go:generate
}

// ── reflect (Runtime Metaprogramming) ───────────────────────────────
// Go's reflect package provides runtime type inspection. It's the
// closest thing to compile-time metaprogramming, but with a runtime
// cost. Rust uses proc macros for the same purpose (at compile time).

func testReflectMetaprogramming() {
	type Config struct {
		Host  string `json:"host" env:"APP_HOST"`
		Port  int    `json:"port" env:"APP_PORT"`
		Debug bool   `json:"debug" env:"APP_DEBUG"`
	}

	// Inspect struct tags at runtime (like Rust's #[derive] at compile time)
	t := reflect.TypeOf(Config{})
	assert(t.NumField() == 3, "three fields")

	hostField, _ := t.FieldByName("Host")
	assert(hostField.Tag.Get("json") == "host", "json tag")
	assert(hostField.Tag.Get("env") == "APP_HOST", "env tag")

	portField, _ := t.FieldByName("Port")
	assert(portField.Type.Kind() == reflect.Int, "port is int")

	// Build a map from struct tags
	envVars := map[string]string{}
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		envKey := field.Tag.Get("env")
		if envKey != "" {
			envVars[envKey] = field.Name
		}
	}
	assert(envVars["APP_HOST"] == "Host", "env mapping")
	assert(envVars["APP_PORT"] == "Port", "env mapping port")
	assert(len(envVars) == 3, "all env vars mapped")

	// Performance note: reflect is 10-100x slower than direct field access.
	// Rust proc macros generate direct code — zero runtime cost.
}

// ── go:generate Patterns ────────────────────────────────────────────
// go:generate runs arbitrary commands before compilation.
// Common tools:
//   stringer   — generates String() for int enums
//   mockgen    — generates mock implementations of interfaces
//   protoc     — generates code from .proto files
//   sqlc       — generates type-safe Go from SQL queries
//   enumer     — generates JSON/text marshaling for enums

func testGeneratePatterns() {
	// Model what go:generate + stringer would produce:
	//
	// Source file:
	//   //go:generate stringer -type=Direction
	//   type Direction int
	//   const ( North Direction = iota; South; East; West )
	//
	// Generated file (direction_string.go):
	//   func (d Direction) String() string { ... }

	type Direction int
	const (
		North Direction = iota
		South
		East
		West
	)

	// Simulating what stringer generates:
	dirNames := [...]string{"North", "South", "East", "West"}
	dirString := func(d Direction) string {
		if int(d) < len(dirNames) {
			return dirNames[d]
		}
		return fmt.Sprintf("Direction(%d)", d)
	}

	assert(dirString(North) == "North", "stringer North")
	assert(dirString(West) == "West", "stringer West")
	assert(dirString(Direction(99)) == "Direction(99)", "stringer unknown")

	// Model what mockgen would produce (see MockLogger below):
	mock := &MockLogger{}
	mock.Log("test")
	assert(len(mock.calls) == 1, "mock recorded call")
	assert(mock.calls[0] == "test", "mock recorded message")
}

// MockLogger — simulates what mockgen would generate for a Logger interface.
// In real code, `go:generate mockgen` creates these automatically.
type MockLogger struct {
	calls []string
}

func (m *MockLogger) Log(msg string) { m.calls = append(m.calls, msg) }

// ── Compiler Directives ─────────────────────────────────────────────
// Go has several //go: directives that control compiler behavior.
// These are the closest thing to Rust's #[...] attributes.

func testCompilerDirectives() {
	// Model the directives and what they do:
	type Directive struct {
		Name      string
		Purpose   string
		RustEquiv string
	}

	directives := []Directive{
		{
			Name:      "//go:noinline",
			Purpose:   "Prevent function inlining",
			RustEquiv: "#[inline(never)]",
		},
		{
			Name:      "//go:nosplit",
			Purpose:   "Don't insert stack-growth check",
			RustEquiv: "N/A (Rust doesn't have goroutine stacks)",
		},
		{
			Name:      "//go:noescape",
			Purpose:   "Promise that pointer args don't escape",
			RustEquiv: "N/A (Rust has lifetimes)",
		},
		{
			Name:      "//go:linkname localname pkg.remotename",
			Purpose:   "Bind to another package's unexported symbol (std: only symbols marked for it, Go 1.23+)",
			RustEquiv: "N/A (unsafe, no Rust equivalent)",
		},
		{
			Name:      "//go:generate command args...",
			Purpose:   "Run command during 'go generate'",
			RustEquiv: "build.rs (build scripts)",
		},
		{
			Name:      "//go:embed pattern",
			Purpose:   "Embed file contents at compile time",
			RustEquiv: "include_str! / include_bytes!",
		},
		{
			Name:      "//go:build constraint",
			Purpose:   "Conditional compilation",
			RustEquiv: "#[cfg(...)]",
		},
	}

	assert(len(directives) == 7, "seven directives")

	// Verify all have Rust equivalents documented
	for _, d := range directives {
		assert(d.RustEquiv != "", fmt.Sprintf("directive %s has Rust equiv", d.Name))
		assert(d.Purpose != "", fmt.Sprintf("directive %s has purpose", d.Name))
	}

	// //go:linkname is the most dangerous — it breaks encapsulation.
	// In practice, it's used by the Go runtime and stdlib internals.
	// Since Go 1.23 the linker enforces that for the standard library: a
	// "pull" linkname to an internal symbol not marked with its own
	// //go:linkname fails to link ("invalid reference to runtime.gcount");
	// only a grandfathered set of widely-used ones still resolves.
	// Regular Go code should never use it.
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
