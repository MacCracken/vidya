# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Design Patterns** topic: builder, strategy, observer, state machine, RAII/cleanup, dependency injection, factory — all 10 languages
- Total: **150 content examples** across 15 topics and 10 languages
- 4 new benchmarks: `search_quantum`, `search_multi_tag`, `compare_all_languages` + fixed `search_text_miss` to use truly nonexistent term

## [1.0.0] — 2026-03-30

### Added
- **140 content examples** across 14 topics and 10 languages
- 4 new topics: **Security**, **Algorithms**, **Kernel Topics**, **Quantum Computing**
  - Security: input validation, injection prevention, constant-time comparison, secret zeroing, path traversal, parameterized queries, XSS prevention, safe deserialization
  - Algorithms: binary search, insertion sort, merge sort, BFS/DFS graph traversal, dynamic programming (Fibonacci, LCS), two-sum hash map, GCD
  - Kernel Topics: page table entries (x86_64 4-level), virtual address decomposition, MMIO volatile registers, interrupt descriptor tables, GDT entries, ABI/calling conventions (SysV AMD64, AAPCS64), struct packing, ELF parsing, quantum error correction
  - Quantum Computing: state vector simulation, Hadamard/CNOT/CZ gates, Bell states, GHZ states, Grover's search (2-qubit and 3-qubit), quantum phase estimation, VQE ansatz, Shor's period-finding, noise channels (depolarizing, amplitude damping, dephasing), dynamical decoupling
- `Topic::KernelTopics` and `Topic::QuantumComputing` variants in the crate
- OpenQASM quantum content for all 14 topics — validated via qiskit
- Full quantum simulator in Rust, Python, Go, C, TypeScript, and Zig (complex arithmetic, gate matrices, measurement probabilities)

### Changed
- Version bump from 0.1.0 to 1.0.0 — stable API and content corpus
- `validate-content.sh`: shell scripts now fully execute (was `bash -n` syntax-only)
- `validate-content.sh`: C compilation upgraded to `-std=c17 -lm -lpthread`
- `validate.rs`: C validation now uses `-std=c17 -lm -lpthread` (matching script)
- `validate.rs`: Shell validation now runs `bash` (not `bash -n`)

### Fixed
- Broken rustdoc intra-doc link in `language.rs` (`extension()` → `Self::extension()`)

## [0.1.0] — 2026-03-27

### Added
- Core crate with types: `Concept`, `Topic`, `Example`, `BestPractice`, `Gotcha`, `PerformanceNote`
- `Language` enum supporting Rust, Python, C, Go, TypeScript, Shell, Zig, x86_64 ASM, AArch64 ASM, OpenQASM
- `Registry` for in-memory concept storage with lookup and filtering
- `SearchQuery` and `search()` for full-text and tag-based search with relevance scoring
- `SearchQuery` builder methods: `with_language()`, `with_limit()`, `with_tags()`
- `Comparison` and `compare()` for cross-language side-by-side views
- `ValidationResult` and `run_validation()` / `validate_all()` for compile/run verification
- Content loader (`loader` module) — reads `concept.toml` + language files into Registry
- TOML-based content format specification (`concept.toml`)
- MCP tool integration via `bote` (feature: `mcp`) — search, get, compare, list tools
- Content: 10 topics with all 10 language implementations
  - strings, error_handling, iterators, memory_management, pattern_matching,
    type_systems, concurrency, testing, performance, input_output
- Integration tests for loader, validation, and MCP dispatch
- `scripts/validate-content.sh` — shell-based content validation
- `scripts/bench-history.sh` — benchmark tracking with git context
- GitHub Actions CI pipeline (stable + MSRV 1.89, content validation)
- Criterion benchmarks: 12 benchmarks covering registry, search, compare, and loader
- `basic` example demonstrating the full API
- Architecture documentation in `docs/`

### Improved
- Search relevance scoring: exact ID/title/tag matches now score higher than substring matches
- Benchmarks use real loaded content instead of empty registries

### Fixed
- Search scoring bug: text+tags queries no longer return false positives when tags match but text doesn't
- Validation temp file collisions: each run uses unique per-process temp paths
