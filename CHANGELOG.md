# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.0] — 2026-04-14

### Changed
- **HTTP server now uses `lib/http_server.cyr`** (cyrius 4.5.0 stdlib).
  Dropped ~270 LOC of hand-rolled plumbing from `src/main.cyr`
  (`make_crlf`, `http_respond`, `http_ok/not_found/bad_request`,
  `http_parse_path`, local `http_get_param`/`http_path_segment`, and
  the bind/listen/accept loop in `cmd_serve`). Routes now go through
  `http_send_response` + `http_server_run`. Behaviour preserved;
  `/info/{topic}` now also benefits from stdlib URL-decoding on
  query strings.
- CI/release workflows bumped to Cyrius 4.5.0 (from 2.7.1).
- Vendored stdlib: added `lib/http_server.cyr`, refreshed
  `lib/fnptr.cyr` to expose `fncall3..fncall6` (needed for the
  `http_server_run` handler callback).

### Verified
- Self-build with cc3 4.5.0: 114KB ELF, clean.
- `vidya serve` end-to-end against `/stats`, `/`, `/list`, `/languages`,
  `/search?q=...`, `/info/{topic}`, plus 400/404 paths — all return
  identical JSON shape to 2.1.0.

## [2.1.0] — 2026-04-09

### Added
- **HTTP service layer** — `vidya serve [port]` starts a localhost JSON API (default port 8390)
  - Endpoints: `/stats`, `/list`, `/search?q=...`, `/info/{topic}`, `/languages`, `/`
  - All responses are JSON, `Connection: close`, proper HTTP/1.1 headers
  - Memory-resident: loads corpus once, serves from RAM
  - 92KB static ELF — no framework, no runtime, no dependencies
- `lib/tagged.cyr`, `lib/json.cyr`, `lib/net.cyr` added to vendored stdlib

### Changed
- CI/release workflows updated to Cyrius 2.7.1 (from 2.2.2)
- Tooling renamed: `cyrb` → `cyrius`, `cyrb.toml` → `cyrius.toml`
- `cyrius.toml` updated to `[package]`/`[build]` section format
- Sakshi re-vendored (v0.7.0)
- CI content validation skips `content/cyrius/` (language reference, not a topic)
- Added `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE` (missing after port)
- All doc references updated from `cyrb`/`cc2` to `cyrius` CLI

## [2.0.0] — 2026-04-08

Major version bump: vidya is no longer a Rust crate. It is a Cyrius program with a complete
11-language corpus. The Rust implementation is preserved in `rust-old/` but is no longer the
primary interface. This is a breaking change for anyone importing `vidya` as a Rust dependency.

### Breaking
- **Implementation language changed from Rust to Cyrius** — `Cargo.toml`, `src/*.rs` moved to `rust-old/`
- **Binary interface changed** — vidya is now a standalone CLI tool (`build/vidya`, 85KB ELF), not a library crate
- **11th language added** — `Language::Cyrius` variant changes the `Language` enum (was 10 variants, now 11)

### Added — Cyrius Port
- **Ported vidya from Rust to Cyrius** — 85KB static ELF binary, 600 lines of Cyrius replacing 2,396 lines of Rust
- Cyrius CLI tool (`src/main.cyr`) with commands: `list`, `search`, `info`, `compare`, `validate`, `gaps`, `stats`, `languages`, `help`
- TOML content loader, hashmap registry, full-text search, cross-language comparison — all in Cyrius
- **Sakshi integration** — structured tracing and error handling via vendored `lib/sakshi.cyr` (stderr-only profile)
- `cyrb.toml` project manifest for Cyrius build tooling
- Vendored 29 Cyrius stdlib modules in `lib/`
- Rust source preserved in `rust-old/` for reference

### Added — Language: Cyrius
- **Cyrius as 11th language** — `Language::Cyrius` variant with `.cyr` extension, `#` comment prefix
- Cyrius validation command: pipes through `cc2` from `$CYRIUS_HOME`
- 20 Cyrius content implementations across topics (pattern-focused, documenting actual Cyrius/AGNOS patterns)

### Added — Content Expansion (193 → 396 examples)
- **203 new language implementations** across all 36 topics
- All 36 topics now complete (11/11 languages each) — up from 15 complete
- New implementations by language:
  - **Go**: 16 new topics (compiler, OS, language design, tracing)
  - **Zig**: 20 new topics (compiler, OS, language design, tracing)
  - **TypeScript**: 20 new topics (compiler, OS concepts, language design, tracing)
  - **Shell**: 21 new topics (scripting patterns for every domain)
  - **x86_64 Assembly**: 19 new topics (real machine-level demonstrations)
  - **AArch64 Assembly**: 20 new topics (ARM64 cross-platform coverage)
  - **OpenQASM**: 21 new topics (quantum analogies for classical concepts)
  - **Python**: 20 new topics (compiler, OS, language design)
  - **C**: 20 new topics (compiler, OS, systems)
  - **Cyrius**: 20 new topics (AGNOS patterns, cc2 internals)
  - **Rust**: 1 new topic (tracing)

### Added — Testing & Benchmarks
- `tests/vidya.tcyr` — 37 Cyrius-native tests (language enum, TOML loading, registry, file discovery, content scanning)
- `tests/vidya.bcyr` — 6 benchmarks (load_concept: 28μs, load_all: 2.35ms, reg_get: 493ns, search: 4μs)
- `BENCHMARKS.md` — Cyrius vs Rust comparison with charts (`docs/benchmarks.png`, `docs/benchmarks-tiers.png`)
- Benchmark history: `bench-history.csv` (Cyrius), `bench-history-rust.csv` (Rust baseline)

### Added — Documentation & Infrastructure
- `docs/sources.md` — source citations for language specs, algorithms, standards
- `docs/usage.md` — complete CLI usage guide
- `docs/development/learning-paths.md` — 5 ordered learning paths (Compiler, OS, Systems, Language Design, Quantum)
- `docs/development/content-grouping.md` — future subdirectory plan for 50+ topics
- `related_topics` field added to all 36 `concept.toml` files — cross-references between topics
- `vidya gaps` command — reports missing language implementations per topic
- `.gitignore` updated: `*.rlib`, `rust-old/target/`
- Documented `qelib1.inc` location in content-format.md

### Changed
- Version bump from 1.5.0 to 2.0.0 — breaking: implementation language changed from Rust to Cyrius
- Binary: Rust crate (~800KB release) → Cyrius binary (85KB static ELF)
- Dependencies: 8 Rust crates → 0 external deps (vendored Cyrius stdlib)
- Total: **36 topics**, **396 examples** across **11 languages**

### Performance — Cyrius vs Rust
| Benchmark | Cyrius | Rust | Winner |
|-----------|--------|------|--------|
| load_all (35 topics) | 2.35ms | 3.83ms | Cyrius 1.6x |
| load_concept | 28μs | 123μs | Cyrius 4.4x |
| search_text | 4μs | 30μs | Cyrius 7.6x |
| reg_get_hit | 493ns | 17ns | Rust 30x |
| Binary size | 85KB | 800KB | Cyrius 9.4x |

## [1.5.0] — 2026-04-04

### Added
- **18 new topics** covering compiler internals, systems programming, language design, and low-level fundamentals:
  - Compiler internals: `lexing_and_parsing`, `code_generation`, `intermediate_representations`, `linking_and_loading`, `optimization_passes`
  - Systems programming: `syscalls_and_abi`, `virtual_memory`, `interrupt_handling`, `process_and_scheduling`, `filesystems`
  - Language design: `ownership_and_borrowing`, `trait_and_typeclass_systems`, `macro_systems`, `module_systems`
  - High-value additions: `instruction_encoding`, `elf_and_executable_formats`, `allocators`, `boot_and_startup`
- 18 new `Topic` enum variants with Display implementations
- Rust implementations for all 18 new topics (concept.toml + rust.rs each)
- Total: **33 topics**, 173+ content examples across 10 languages

## [1.0.0] — 2026-03-30

### Added
- **Design Patterns** topic: builder, strategy, observer, state machine, RAII/cleanup, dependency injection, factory — all 10 languages
- Total: **150 content examples** across 15 topics and 10 languages
- Native OpenQASM 2.0 validation via `openqasm` crate (feature: `openqasm`) — no Python/qiskit dependency needed
- `openqasm` added to `full` feature set
- `test_qasm` example for standalone QASM validation
- 4 new benchmarks: `search_quantum`, `search_multi_tag`, `compare_all_languages` + fixed `search_text_miss`

### Changed
- Updated `basic.rs` example to demonstrate full 15-topic corpus (load, search, compare, browse)
- Updated README.md with 15 topics, 10 languages, feature flags, validation instructions
- Updated architecture docs and content format spec for all languages
- `validate.rs`: OpenQASM uses native Rust parser when `openqasm` feature is enabled, falls back to Python/qiskit otherwise
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
