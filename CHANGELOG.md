# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Core crate with types: `Concept`, `Topic`, `Example`, `BestPractice`, `Gotcha`, `PerformanceNote`
- `Language` enum supporting Rust, Python, C, Go, TypeScript, Shell, Zig
- `Registry` for in-memory concept storage with lookup and filtering
- `SearchQuery` and `search()` for full-text and tag-based search with relevance scoring
- `Comparison` and `compare()` for cross-language side-by-side views
- `ValidationResult` and `run_validation()` / `validate_all()` for compile/run verification
- Content loader (`loader` module) — reads `concept.toml` + language files into Registry
- TOML-based content format specification (`concept.toml`)
- Content: strings topic with Rust implementation
- Integration tests for loader and validation
- `scripts/validate-content.sh` — shell-based content validation
- `scripts/bench-history.sh` — benchmark tracking with git context
- GitHub Actions CI pipeline (stable + MSRV 1.89, content validation)
- Criterion benchmarks for search and registry operations
- `basic` example demonstrating the full API

### Fixed
- Search scoring bug: text+tags queries no longer return false positives when tags match but text doesn't
