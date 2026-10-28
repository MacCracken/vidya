# Getting Started with Vidya

This guide takes you from a clean clone to a working `vidya` CLI in under five minutes.

## Prerequisites

- **Cyrius toolchain** — install per [cyrius/README.md](https://github.com/MacCracken/cyrius#installation). The pinned version is read from `cyrius.cyml` at build time.
- **Linux x86_64** — the default platform. Aarch64 cross-build is available (best-effort) via `cyrius build --aarch64`; see `.github/workflows/release.yml`.

That's it. No Python, no Node, no Rust toolchain required to build or use vidya. (Those are only needed if you want to run the full content-validation suite — see [Validating Content](#validating-content) below.)

## Build

```bash
cd vidya
cyrius lib sync                        # vendor the pinned stdlib into lib/
cyrius deps                            # resolve the [deps.*] git deps
cyrius build src/main.cyr build/vidya
```

The build produces a static ELF at `build/vidya` (current size in [`../development/state.md`](../development/state.md)). No runtime dependencies.

## First Run

```bash
./build/vidya stats
```

Expected output:

```
=== Vidya Corpus Stats ===
  Groups:     14
  Topics:     80
  Complete:   80 (all 11 languages)
  Examples:   880
  Languages:  11
```

## Common Tasks

```bash
./build/vidya list                              # all 80 topics, by group
./build/vidya list compilers                    # one group's topics
./build/vidya search "memory"                   # text search across the corpus
./build/vidya info fundamentals/strings         # full record for a topic
./build/vidya code quantum/fundamentals rust    # ANSI-colored source via vyakarana
./build/vidya compare fundamentals/strings rust python  # side-by-side cross-language view
./build/vidya gaps                              # coverage gaps (currently zero)
./build/vidya serve 8080                        # HTTP service for programmatic consumers
```

A topic id is its path under `content/`: `<group>/<topic>`. A bare 2.x name such as `strings` is not found, and the error names the topic it probably meant.

Full command surface and HTTP route table: [`docs/usage.md`](../usage.md).

## Validating Content

Vidya validates every code example by compiling and running it in its native toolchain. For local single-language spot-checks, the CLI is enough (`vidya validate <group>/<topic>`, or a whole group with `vidya validate <group>`). For the full 11-language matrix, use the script:

```bash
./scripts/validate-content.sh
```

The script skips languages whose toolchain isn't installed; `VIDYA_STRICT=1` makes any skip a failure. CI (`.github/workflows/ci.yml`) runs it strict in an Arch Linux container with the full set: Zig, the aarch64 binutils and qemu-user, rustup stable, Python 3.15 (uv), tsc + tsx + `@types/node`, qiskit in `.venv`, and cyrius.

## Adding Content

See [`CONTRIBUTING.md`](../../CONTRIBUTING.md). The recipe in short:

1. `content/<group>/<topic>/concept.toml`, whose `id` is `<group>/<topic>`, with the required fields and at least one each of `[[best_practices]]`, `[[gotchas]]`, `[[performance_notes]]`.
2. One implementation per language. All 11 required for "complete" status: `rust.rs`, `python.py`, `c.c`, `go.go`, `typescript.ts`, `shell.sh`, `zig.zig`, `asm_x86_64.s`, `asm_aarch64.s`, `openqasm.qasm`, `cyrius.cyr`.
3. Every implementation must compile and run successfully. `vidya gaps` to verify.

Full content-format spec: [`development/content-format.md`](../development/content-format.md).

## Where Next

- **Browse the docs index** — [`doc-health.md`](../doc-health.md) (whole-tree ledger) and the [`development/`](../development/) subdir.
- **Understand the architecture** — [`architecture/overview.md`](../architecture/overview.md).
- **Read past decisions** — [`adr/README.md`](../adr/README.md).
- **Track the roadmap** — [`development/roadmap.md`](../development/roadmap.md).
