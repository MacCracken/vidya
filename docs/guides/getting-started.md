# Getting Started with Vidya

This guide takes you from a clean clone to a working `vidya` CLI in under five minutes.

## Prerequisites

- **Cyrius toolchain** — install per [cyrius/README.md](https://github.com/MacCracken/cyrius#installation). The pinned version is read from `cyrius.cyml` at build time.
- **Linux x86_64** — the default platform. Aarch64 cross-build is available (best-effort) via `cyrius build --aarch64`; see `.github/workflows/release.yml`.

That's it. No Python, no Node, no Rust toolchain required to build or use vidya. (Those are only needed if you want to run the full content-validation suite — see [Validating Content](#validating-content) below.)

## Build

```bash
cd vidya
cyrius update                          # rehydrate lib/ from the pinned toolchain
cyrius build src/main.cyr build/vidya
```

The build produces a ~1.1 MB static ELF at `build/vidya`. No runtime dependencies.

## First Run

```bash
./build/vidya stats
```

Expected output:

```
=== Vidya Corpus Stats ===
  Topics:     74
  Complete:   74 (all 11 languages)
  Examples:   814
  Languages:  11
```

## Common Tasks

```bash
./build/vidya list                              # browse all 74 topics
./build/vidya search "memory"                   # text search across the corpus
./build/vidya info strings                      # full record for a topic
./build/vidya code quantum_computing rust       # ANSI-colored source via vyakarana
./build/vidya compare strings rust python       # side-by-side cross-language view
./build/vidya gaps                              # coverage gaps (currently zero)
./build/vidya serve 8080                        # HTTP service for programmatic consumers
```

Full command surface and HTTP route table: [`docs/usage.md`](../usage.md).

## Validating Content

Vidya validates every code example by compiling and running it in its native toolchain. For local single-language spot-checks, the CLI is enough (`vidya validate <topic>`). For the full 11-language matrix, use the script:

```bash
./scripts/validate-content.sh
```

The script gracefully skips languages whose toolchain isn't installed. CI (`.github/workflows/ci.yml`) installs the full set — zig 0.16.0, aarch64 binutils, qemu-user-static, tsx, qiskit, cyrius, plus what ubuntu-latest already ships (rustc / python3 / gcc / go / node / bash).

## Adding Content

See [`CONTRIBUTING.md`](../../CONTRIBUTING.md). The recipe in short:

1. `content/<topic>/concept.toml` with required fields and at least one each of `[[best_practices]]`, `[[gotchas]]`, `[[performance_notes]]`.
2. One implementation per language. All 11 required for "complete" status: `rust.rs`, `python.py`, `c.c`, `go.go`, `typescript.ts`, `shell.sh`, `zig.zig`, `asm_x86_64.s`, `asm_aarch64.s`, `openqasm.qasm`, `cyrius.cyr`.
3. Every implementation must compile and run successfully. `vidya gaps` to verify.

Full content-format spec: [`development/content-format.md`](../development/content-format.md).

## Where Next

- **Browse the docs index** — [`doc-health.md`](../doc-health.md) (whole-tree ledger) and the [`development/`](../development/) subdir.
- **Understand the architecture** — [`architecture/overview.md`](../architecture/overview.md).
- **Read past decisions** — [`adr/README.md`](../adr/README.md).
- **Track the roadmap** — [`development/roadmap.md`](../development/roadmap.md).
