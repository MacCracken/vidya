// Vidya — Module Systems in Go
//
// Go modules (introduced Go 1.11, default since 1.16) manage
// dependencies and define import paths. Key concepts:
//
//   go.mod        — declares module path, Go version, dependencies
//   go.sum        — cryptographic checksums for reproducible builds
//   Capitalization — exported (public) vs unexported (private)
//   internal/     — package visible only to parent module
//   replace       — redirect imports (local development, forks)
//   vendor/       — vendored dependencies for hermetic builds
//
// Compare to Rust's module system:
//   Rust crate   → Go module (go.mod)
//   Rust mod      → Go package (directory)
//   Rust pub      → Go Capitalized names
//   Rust pub(crate) → Go unexported (lowercase) within module
//   Rust Cargo.toml → Go go.mod
//   Rust Cargo.lock → Go go.sum

package main

import (
	"fmt"
	"strings"
)

func main() {
	testGoModStructure()
	testVisibilityRules()
	testImportPaths()
	testInternalPackages()
	testReplaceDirectives()
	testVendoring()
	testPackageOrganization()
	testInitFunctions()
	testWorkspaces()

	fmt.Println("All module system examples passed.")
}

// ── go.mod Structure ────────────────────────────────────────────────
// A go.mod file has four directives: module, go, require, replace.
// Unlike Cargo.toml, go.mod is minimal — no [features], no [profile].

type GoMod struct {
	Module  string            // module path (e.g., github.com/user/repo)
	Go      string            // minimum Go version
	Require []Dependency
	Replace []ReplaceRule
	Exclude []string          // rarely used — exclude specific versions
}

type Dependency struct {
	Path    string
	Version string
	Indirect bool // transitive dependency (not directly imported)
}

type ReplaceRule struct {
	Old     string
	New     string // can be a version or a local path
}

func testGoModStructure() {
	mod := GoMod{
		Module: "github.com/example/myapp",
		Go:     "1.22",
		Require: []Dependency{
			{Path: "github.com/gorilla/mux", Version: "v1.8.1"},
			{Path: "golang.org/x/sync", Version: "v0.6.0"},
			{Path: "golang.org/x/text", Version: "v0.14.0", Indirect: true},
		},
		Replace: []ReplaceRule{
			{Old: "github.com/broken/pkg", New: "../local/pkg"},
		},
	}

	assert(mod.Module == "github.com/example/myapp", "module path")
	assert(len(mod.Require) == 3, "three deps")
	assert(mod.Require[2].Indirect, "indirect dep")
	assert(mod.Replace[0].New == "../local/pkg", "local replace")

	// Version format: Go uses semver with 'v' prefix
	// v1.8.1 — standard release
	// v0.0.0-20240101000000-abcdef123456 — pseudo-version (commit hash)
	// v2.0.0 — major version (import path changes: github.com/user/repo/v2)
}

// ── Visibility Rules ────────────────────────────────────────────────
// Go's visibility is dead simple: Capitalized = exported, lowercase = unexported.
// This applies to types, functions, methods, fields, and constants.
//
// Rust has pub, pub(crate), pub(super), pub(in path) — more granular.
// Go has just two levels: exported or not.

type PublicStruct struct {
	ExportedField   int    // visible outside package
	unexportedField string // visible only within package
}

// Since we're in package main, everything is "within package"

func testVisibilityRules() {
	s := PublicStruct{
		ExportedField:   42,
		unexportedField: "hidden",
	}
	assert(s.ExportedField == 42, "exported field accessible")
	assert(s.unexportedField == "hidden", "unexported accessible within package")

	// Model visibility rules
	type Symbol struct {
		Name     string
		Exported bool
	}

	symbols := []Symbol{
		{"Handler", true},     // starts with uppercase → exported
		{"handler", false},    // starts with lowercase → unexported
		{"HTTPClient", true},  // acronyms: all caps (Go convention)
		{"xmlParser", false},  // unexported
		{"X", true},           // single letter, uppercase → exported
		{"x", false},          // single letter, lowercase → unexported
	}

	for _, sym := range symbols {
		firstChar := sym.Name[0]
		isUpper := firstChar >= 'A' && firstChar <= 'Z'
		assert(isUpper == sym.Exported,
			fmt.Sprintf("%s: exported=%v", sym.Name, sym.Exported))
	}
}

// ── Import Paths ────────────────────────────────────────────────────
// Go import paths are URL-like strings that identify packages.
// Unlike Rust (crate names in Cargo.toml), Go uses the full VCS path.

func testImportPaths() {
	type ImportPath struct {
		Path    string
		Kind    string // stdlib, external, internal
		Example string
	}

	paths := []ImportPath{
		// Standard library — no domain prefix
		{Path: "fmt", Kind: "stdlib", Example: "fmt.Println"},
		{Path: "net/http", Kind: "stdlib", Example: "http.ListenAndServe"},
		{Path: "encoding/json", Kind: "stdlib", Example: "json.Marshal"},

		// External — domain prefix
		{Path: "github.com/gorilla/mux", Kind: "external", Example: "mux.NewRouter"},
		{Path: "golang.org/x/sync/errgroup", Kind: "external", Example: "errgroup.Group"},

		// Internal — restricted visibility
		{Path: "myapp/internal/db", Kind: "internal", Example: "db.Connect"},
	}

	// Standard library has no dots in first path element
	for _, p := range paths {
		firstElem := strings.Split(p.Path, "/")[0]
		hasDot := strings.Contains(firstElem, ".")
		if p.Kind == "stdlib" {
			assert(!hasDot, fmt.Sprintf("%s is stdlib (no dot)", p.Path))
		} else {
			assert(hasDot || strings.Contains(p.Path, "internal"),
				fmt.Sprintf("%s is external/internal", p.Path))
		}
	}

	assert(len(paths) == 6, "six import examples")
}

// ── Internal Packages ───────────────────────────────────────────────
// Any package whose path contains "internal" can only be imported
// by code in the parent of the internal directory. This is Go's
// version of Rust's pub(crate) — module-private visibility.
//
// Example layout:
//   myapp/
//     internal/         ← only myapp can import
//       db/             ← myapp/internal/db
//       auth/           ← myapp/internal/auth
//     cmd/
//       server/         ← can import myapp/internal/db
//     pkg/
//       api/            ← can import myapp/internal/db (same module)
//
// External packages CANNOT import myapp/internal/db.

func testInternalPackages() {
	type ImportRule struct {
		Importer string
		Target   string
		Allowed  bool
	}

	rules := []ImportRule{
		// Same module — allowed
		{"myapp/cmd/server", "myapp/internal/db", true},
		{"myapp/pkg/api", "myapp/internal/auth", true},

		// Parent of internal — allowed
		{"myapp", "myapp/internal/db", true},

		// External — blocked by compiler
		{"github.com/other/pkg", "myapp/internal/db", false},
		// myapp/cmd/internal/util is still under myapp, so it can import myapp/internal/db
		{"other-module/pkg", "myapp/internal/db", false}, // different module entirely
	}

	for _, rule := range rules {
		canImport := isInternalImportAllowed(rule.Importer, rule.Target)
		assert(canImport == rule.Allowed,
			fmt.Sprintf("%s → %s: allowed=%v", rule.Importer, rule.Target, rule.Allowed))
	}
}

func isInternalImportAllowed(importer, target string) bool {
	// Find "internal" in the target path
	idx := strings.Index(target, "/internal")
	if idx == -1 {
		return true // no "internal" in path — always allowed
	}
	// Importer must share the parent prefix
	parent := target[:idx]
	return strings.HasPrefix(importer, parent)
}

// ── Replace Directives ──────────────────────────────────────────────
// go.mod replace redirects imports. Used for:
//   1. Local development (point to local checkout)
//   2. Forks (use your fork instead of upstream)
//   3. Monorepo modules (relative paths)
//
// Rust equivalent: Cargo.toml [patch] section

func testReplaceDirectives() {
	type ReplaceEntry struct {
		From    string
		To      string
		UseCase string
	}

	replaces := []ReplaceEntry{
		{
			From:    "github.com/upstream/lib v1.2.3",
			To:      "../local/lib",
			UseCase: "local development",
		},
		{
			From:    "github.com/upstream/lib v1.2.3",
			To:      "github.com/myfork/lib v1.2.4-patch",
			UseCase: "use fork",
		},
		{
			From:    "example.com/mymodule/subpkg",
			To:      "./subpkg",
			UseCase: "monorepo relative path",
		},
	}

	assert(len(replaces) == 3, "three replace examples")

	// Local replacements use relative/absolute paths
	assert(!strings.Contains(replaces[0].To, "github.com"), "local path")

	// Fork replacements point to different VCS paths
	assert(strings.Contains(replaces[1].To, "myfork"), "fork redirect")
}

// ── Vendoring ───────────────────────────────────────────────────────
// `go mod vendor` copies all dependencies into vendor/ directory.
// Builds with -mod=vendor use vendored code. This gives hermetic
// builds without network access — important for CI and air-gapped
// environments.
//
// Rust equivalent: cargo vendor (similar concept)

func testVendoring() {
	type VendorFile struct {
		Path    string
		Purpose string
	}

	vendorLayout := []VendorFile{
		{Path: "vendor/modules.txt", Purpose: "index of vendored modules"},
		{Path: "vendor/github.com/gorilla/mux/mux.go", Purpose: "vendored source"},
		{Path: "vendor/golang.org/x/sync/errgroup/errgroup.go", Purpose: "vendored source"},
	}

	assert(len(vendorLayout) == 3, "vendor layout")

	// Key commands:
	// go mod vendor     — create/update vendor directory
	// go build -mod=vendor — build using vendored deps
	// go mod verify     — verify go.sum checksums

	// vendor/modules.txt lists all vendored modules with versions
	assert(vendorLayout[0].Path == "vendor/modules.txt", "modules.txt exists")
}

// ── Package Organization ────────────────────────────────────────────
// Go convention: one package per directory. The package name matches
// the directory name. Unlike Rust where mod.rs or lib.rs defines
// module structure, Go uses the filesystem directly.

func testPackageOrganization() {
	type DirPackage struct {
		Dir      string
		Package  string
		Purpose  string
	}

	// Standard project layout (not enforced, but conventional)
	layout := []DirPackage{
		{Dir: "cmd/server/", Package: "main", Purpose: "entry point"},
		{Dir: "cmd/cli/", Package: "main", Purpose: "CLI entry point"},
		{Dir: "internal/db/", Package: "db", Purpose: "private database logic"},
		{Dir: "internal/auth/", Package: "auth", Purpose: "private auth logic"},
		{Dir: "pkg/api/", Package: "api", Purpose: "public API types"},
		{Dir: "pkg/client/", Package: "client", Purpose: "public client library"},
	}

	// Package name = last element of directory path
	for _, dp := range layout {
		if dp.Package != "main" {
			parts := strings.Split(strings.TrimSuffix(dp.Dir, "/"), "/")
			lastDir := parts[len(parts)-1]
			assert(lastDir == dp.Package,
				fmt.Sprintf("dir %s → package %s", dp.Dir, dp.Package))
		}
	}

	// cmd/ directories always use package main
	for _, dp := range layout {
		if strings.HasPrefix(dp.Dir, "cmd/") {
			assert(dp.Package == "main",
				fmt.Sprintf("cmd dir %s must be package main", dp.Dir))
		}
	}
}

// ── init() Functions ────────────────────────────────────────────────
// Go packages can have init() functions that run automatically when
// the package is imported. Order: imported packages first, then this
// package's init(), then main(). Multiple init() per file allowed.
//
// Rust has no init — use lazy_static! or std::sync::OnceLock.

var initOrder []string

func init() {
	initOrder = append(initOrder, "first")
}

func init() {
	initOrder = append(initOrder, "second")
}

func testInitFunctions() {
	// Both init() functions ran before main()
	assert(len(initOrder) == 2, "two init functions ran")
	assert(initOrder[0] == "first", "first init ran first")
	assert(initOrder[1] == "second", "second init ran second")

	// Gotcha: init() functions run on import, which can cause
	// surprising side effects. Prefer explicit initialization:
	//   Bad:  func init() { db = connectDB() }
	//   Good: func SetupDB() (*DB, error) { ... }
}

// ── Go Workspaces ───────────────────────────────────────────────────
// Go 1.18+ workspaces (go.work) let you develop multiple modules
// together. Like Cargo workspaces in Rust.

func testWorkspaces() {
	type GoWork struct {
		Go   string
		Use  []string // module directories
	}

	workspace := GoWork{
		Go:  "1.22",
		Use: []string{
			"./cmd/server",
			"./pkg/lib",
			"./internal/shared",
		},
	}

	assert(workspace.Go == "1.22", "workspace Go version")
	assert(len(workspace.Use) == 3, "three modules in workspace")

	// go.work file format:
	//   go 1.22
	//   use (
	//       ./cmd/server
	//       ./pkg/lib
	//       ./internal/shared
	//   )
	//
	// Key difference from Cargo workspace:
	//   Cargo: single Cargo.lock for all workspace members
	//   Go:    each module has its own go.sum (go.work.sum for workspace)
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
