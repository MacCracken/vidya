# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.9.6] — 2026-10-28

P5, the roadmap's last 2.9.x item: three topics on functional programming
and type theory, so the corpus is **80 topics / 880 examples**, all 11/11.
Also two loader fixes: 141 existing examples had no explanation, and 27
had one that ran into their first section.

### Added — P5: `functional_patterns`, `effect_systems`, `dependent_types`

The Cyrius reference for each topic was written first. The other ten ports
mirror its checks with the same expected values. Every port was
mutation-tested: one behaviour per section was broken in a copy, and the
file had to fail. Each topic was then reviewed after its gate went green.
The three reviews found 32 defects, all fixed. Most were false or
overstated claims in comments, and headers over 12 lines. Four were
checks that could not fail:
- the thermostat thresholds (below);
- TypeScript's empty `vecHead`;
- a forged-Percent check in both assembly ports.

- **`functional_patterns`.** Covers:
  - pure functions and memoization keyed on every argument;
  - compose and pipe on a pair that does not commute;
  - closures and partial application;
  - what a closure captures;
  - a persistent cons list that shares structure (cons is O(1);
    update-at-i copies i + 1 nodes, and the check counts them);
  - folds (`foldl(-)` is −6 and `foldr(-)` is 2 over `[1, 2, 3]`);
  - tail calls.

  The capture section checks each language's real behaviour: Python
  lambdas give `[2, 2, 2]`, a JavaScript `var` gives `[3, 3, 3]`, `let`
  and Go ≥ 1.22 give `[0, 1, 2]`, Rust shows late binding only through
  a shared `Cell`, and Cyrius copies the value. Tail calls also differ by
  language:
  - Cyrius compiles a `return f(..)` to a jump, and runs 10,000,000 deep.
  - Zig guarantees `@call(.always_tail)`, but 0.17's self-hosted x86_64
    backend refuses it, so the gate runs that check only under LLVM.
  - Python raises `RecursionError` at depth 999.
  - Go's goroutine stacks grow to 1 GB, so its naive 100,000-deep
    recursion works.

  OpenQASM has no functions, so its port treats gates as reversible
  functions: composition order, `inv @`, and uncomputing a scratch
  register.
- **`effect_systems`.** Effects as data, interpreted by handlers. One
  `checkout` program asks for a rate, logs, and may fail. A test handler
  and a production handler give it different meanings. The topic covers:
  - resuming with an answer;
  - `Fail` as a handler that does not resume (the rest provably never
    runs);
  - state threaded through `step(state, input)`;
  - capability passing with a fake clock;
  - a pure thermostat core behind a thin shell.

  Python and TypeScript use generators. The other languages use a step
  function and a handler loop, and each header names the languages with
  native handlers (OCaml 5, Koka, Unison, Eff). The OCaml figures are the
  PLDI 2021 paper's §6.3: 5 ns to perform, 11 ns to resume, and 23 ns to
  allocate and switch fibers. OpenQASM's port is the deferred-measurement
  principle, pinned by `@expect`. The review found that the thermostat's
  events never landed on a threshold, so an off-by-one comparison passed
  every check. The events are now `[19, 18, 17, 21, 22, 23, 15, 16, 14]`,
  and all eight comparison and shell mutants fail in all ten ports that
  have the thermostat.
- **`dependent_types`.** The roadmap asked for its scope to be settled
  first. It teaches what dependent types are (`Vec n a`, `Fin n`, Σ),
  the nearest honest encoding at each language's real strength, and
  refinement at the boundary ("parse, don't validate"). None of the 11
  languages has full dependent types. Each header places its language:
  - **Zig** is strongest: `Vec(n + m)` is a real type.
  - **Rust** has const generics, but `N + M` is unstable on stable.
  - **Cyrius** has one struct type per length, with
    `#assert sizeof(Vec5) == sizeof(Vec2) + sizeof(Vec3)`.
  - **C** has `static_assert` and `[static N]`.
  - **TypeScript** has tuple lengths and brands, erased at run time.
  - **Python, Go, Shell and assembly** check at run time.

  Every "does not compile" comment quotes an error the toolchain on this
  host produced. Each file names its escape hatch and what keeps it
  honest: TypeScript `as`, a C cast, Rust `transmute`, a Zig or Go struct
  literal. Two claims were corrected by measurement before they shipped:
  - rustc 1.99 `-O` **keeps** the bounds check for a plain `Fin<N>`;
  - qiskit's importer rejects `const`, so OpenQASM register sizes are
    literal expressions.

### Fixed — 141 examples had no explanation

The loader takes an example's explanation from its leading line comments.
For AArch64 it looked for `#`, but every AArch64 example is written with
`//`, the comment GNU `as` uses there. So **all 77 AArch64 examples**
had an empty explanation, and `vidya compare` showed nothing for them.
The marker is now `//`.

The same was true of 64 more examples whose header the loader cannot read:
- 22 Python files with a module docstring;
- 36 C files with a `/* … */` block;
- 6 C files with a `#define _GNU_SOURCE` above the comment.

Each header is now a run of line comments, with the `#define` moved below
it. The text of every header is unchanged, and all 64 files pass the gate.

`cyrius test` now fails if any example's explanation is empty. That test
found the same defect in two new P5 files before they shipped.
`content-format.md` spells out the rule and each language's marker.

### Fixed — 27 explanations ran into the first section

The loader read on through blank lines. So when a header was followed by
a blank line and the first section's banner comment, the explanation took
in the banner and the comments under it. For example,
`instruction_encoding/typescript.ts` ended its explanation with
"── Register encoding ──" and the next line. Now the first blank line ends
the header, which is the "consecutive comment lines" rule
`content-format.md` always stated.

- Across all 880 examples, `compare` output changes only by removing
  lines: 54 swallowed banner and comment lines in the 27 examples, and
  the blank line every shebang file (shell, some Python) printed ahead of
  its explanation.
- Two of the 27 lost a second paragraph rather than a banner: the
  armv8.1-a LSE note in `concurrency/asm_aarch64.s` and the
  `_GNU_SOURCE` note in `syscalls_and_abi/c.c`. Both sit next to the code
  they describe.
- A new `explanation` test group pins the rules: a blank line ends the
  header, a shebang adds nothing, and a block comment yields nothing.

### Changed

- `build_systems/cyrius.cyr`: the array comment no longer describes the
  bare `var x[N]` that 2.9.5 replaced.
- `learning-paths.md` puts every topic on a path, 80 of 80. Ten topics
  had no path since 2.7.1. The new paths are Language Fundamentals,
  Build & Release, and Functional Programming & Type Theory.
- The `stats` blocks in `usage.md` and `getting-started.md` still showed
  74 topics from 2.7.1.

### Gates and numbers

- `cyrius test` **163/0** (158 + 5: the corpus explanation check, its
  non-vacuity guard, and the three `explanation` rules). Content gate **880/880** under `VIDYA_STRICT=1`.
  The binary is 2,945,472 B.
- Benchmarks (`target/bench-history/20261028-065631-675ee61.txt`
  against `20261028-033533-f1ed86a.txt`) move only with corpus size:
  - `load_all`: 7.97 → 8.25 ms for 77 → 80 topics, which is 103.5 →
    103.1 µs per topic;
  - `json_search_response`: +4.5 %;
  - `json_list_response`: +2.0 %.

  No code path got faster or slower, and none is claimed.

## [2.9.5] — 2026-10-28

The three follow-ups the 2.9.4 review left on the roadmap. No vidya source
change. The content changes in 40 files.

### Fixed — 129 Cyrius arrays declared 8× too large

A top-level bare `var x[N]` reserves N i64 **slots**, but 129 declarations
in 29 Cyrius ports were written as byte counts (`var node_term[24]; # 3 ×
i64`). Each was 8× too big. That was safe, but wasteful, and it taught the
rule backwards. Each one is now typed at its intended size: `i64[N/8]` for
slot access, `u8[N]` for byte access. Across those 29 programs the arrays
reserve **104 KB instead of 830 KB** (−710 KB; `networking_fundamentals`
alone −475 KB).

Shrinking an array can turn a latent overrun into real corruption. Cyrius's
bounds-checked mode checks only `a[i]` subscripts, and these ports use
`store64(&a + i*8, …)`. So each conversion was verified with a canary
instead. A guard word placed right after every shrunken array, which is
contiguous in declaration order, was set before `main` and checked at exit,
in a scratch copy of each program. No guard was hit in any of the 29
programs. A deliberate mutant that shrank `node_term` below its use
corrupted the guard and failed the example's own tests. A bare and a typed
array read the same through their name, so no expression changed meaning.
All 77 Cyrius examples pass the gate.

### Fixed — three OpenQASM claims without a source

The 2.9.4 review left three OpenQASM claims PLAUSIBLE. Each now cites its
source, and one is reworded to match it:

- `maze_generation`: the claim now matches Aharonov, Ambainis, Kempe and
  Vazirani's abstract ("Quantum Walks On Graphs", arXiv:quant-ph/0012090).
  The walk on the cycle mixes almost quadratically faster (O(n log n)
  against Θ(n²)), and in general a quantum walk is at most *polynomially*
  faster. The file had said "at most quadratic on bounded-degree graphs",
  which is stronger than the paper's abstract claims. MNRS 2007 is cited
  as arXiv:quant-ph/0608026.
- `explicit_gpu_synchronization`: the teleportation analogy cites Bennett
  et al. 1993. It also says why the classical bits are the "signal":
  without them the consumer's qubit is maximally mixed.
- `projectile_physics`: Hamiltonian simulation (Lloyd 1996) and variational
  time evolution (Li and Benjamin 2017) are cited for the evolve-then-sample
  shape.

### Changed — Python asserts that could only check literals

The review's PY-77 flagged asserts that cannot fail. A Python `ast` pass
then found every assert whose inputs are all literals, or names bound once
to a literal. The pass skipped `assert False` after a call that must raise,
and checks of the language's own behaviour. 34 such sites in 8 files were
changed:

- A constant re-checked against the literal it was defined as
  (`CR0_PE == 0x0000_0001`, the PE and Mach-O magics, the SysV register
  tables) became a comment carrying the assert's message.
- `len()` of a list written just above, and arithmetic on literals, were
  removed.
- Two-literal comparisons (`prev_regs.rsp != next_regs.rsp`, dict values
  set just above) were removed.
- `kernel_topics`' `test_abi_calling_convention`, which checked nothing,
  became comments on the register tables, and its call was removed.
- `strings`' `"hello" == "hello"  # case-sensitive` became
  `"hello" != "Hello"`, which actually shows case-sensitivity.

The rule is now in `content-format.md`: every check must be able to fail
when the code it demonstrates is wrong.

## [2.9.4] — 2026-10-28

The roadmap's content review, on the latest version of every content
language. **OpenQASM 2.0 → 3.1** (all 77 circuits, each proven equivalent to
its original) and **Python 3.15** are the two language moves. CI's content
gate now runs the same current toolchains as the dev host, in an Arch Linux
container. The full-corpus review findings are listed below.

### Changed — content languages on their latest versions

| Language | Was | Now |
|---|---|---|
| OpenQASM | 2.0 (`qelib1.inc`, qiskit `qasm2`) | **3.1** (`stdgates.inc`, qiskit `qasm3`) |
| Python | 3.14 (host) / 3.12 (CI's Ubuntu image) | **3.15** (3.15.2) |
| Rust | 1.97.1 | **1.99.1**, edition 2024 |
| tsx, `@types/node` | 4.22.4, 26.2.0 | **4.23.15, 26.6.5** (TypeScript 7.0.2 was already current) |
| qiskit / qiskit-aer | 2.4.1 / 0.17.2 | **2.6.1 / 0.18.2**, plus qiskit-qasm3-import 0.6.0 |

Already current, checked against each project's release index: Go 1.27.3,
GCC 16.2, Node 26.12.1, TypeScript 7.0.2 (whose newest named target is
ES2025, so `--target es2025` stays), Bash 5.3, Zig 0.17.0, binutils 2.47,
QEMU 11.1.2, Cyrius 6.7.18. The C standard stays C23, the newest published;
the Rust edition stays 2024. The strict gate passed 847/847 on the new Rust,
Python, tsx and qiskit before any content changed.

- **OpenQASM 3.1.** The circuits were converted mechanically
  (`qreg`/`creg` → `qubit[n]`/`bit[n]`, `measure a -> b` → `b = measure a`,
  `cu1` → `cp`, `cu3` → `cu(θ, φ, λ, 0)`, `u1` → `p`, `u3` → `U`, `if (c==n)`
  with braces). The review later replaced every `cu` with `cry`, because
  `cu`'s phase convention differs between qiskit and the reference
  `stdgates.inc`. Every circuit was **proven to be the same circuit** as its
  2.0 original. The proof checked three things: the same registers; equal
  unitaries, compared per group of qubits that gates connect, in the 72
  circuits with nothing non-unitary before their final measurements; and
  identical per-register outcome distributions from seeded aer runs at 8,192
  shots (worst gap 0.0000). Five registers had names that OpenQASM 3
  reserves or that `stdgates.inc` defines, so they were renamed:
  `input` (×2), `in`, `inv`, `phase`. `content/qelib1.inc` is gone, because
  OpenQASM 3's `stdgates.inc` is built into the importer. vyakarana's grammar
  already colours 3.x (`qubit`, `bit`).
- **The OpenQASM gate now simulates.** `scripts/qasm_check.py` loads each
  circuit with qiskit's OpenQASM 3 importer, then runs every `// @expect`
  line in a seeded qiskit-aer simulation. `@expect <reg> == <int>` means
  every shot reads that value; `@expect <reg> in {…}` means every shot is in
  the set and each value occurs. Through 2.9.3 a circuit's prose ("result
  will always be 101") was never checked, which was one of the blind spots
  CLAUDE.md names. Both validators call the script.
- **Python 3.15.** `VIDYA_PYTHON` picks the interpreter in both validators
  (default `python3`). The gate prints the version it used, and under
  `VIDYA_STRICT=1` it refuses an interpreter older than 3.15. On the dev
  host, 3.15 is uv-managed (`~/.local/bin/python3.15`), because Arch still
  packages 3.14.
- **CI's content job runs in `archlinux:latest`.** ubuntu-latest is Ubuntu
  24.04, whose stock GCC 13 and Python 3.12 are far behind, and GCC 16 has
  no apt build for it. pacman now provides GCC, Go, Node, Zig, binutils and
  QEMU at the dev host's versions. Rust comes from rustup stable, Python
  3.15 from uv, and qiskit with its OpenQASM 3 importer and aer from a
  venv. A new step prints every toolchain's version, so a break caused by a
  new upstream release can be attributed. Zig moved from the
  sha256-checked tarball to Arch's signed package. The container's first
  run failed two Shell examples that had leaned on Ubuntu's image:
  - `code_generation/shell.sh` called `xxd`, which ships with vim, and Arch's
    base image has no vim (exit 127). It now uses `od`, which coreutils
    guarantees, the way `binary_formats/shell.sh` already did.
  - `interrupt_handling/shell.sh` failed when `/proc/interrupts` reads empty,
    as it does in GitHub Actions' job container. It now runs those checks
    when the file has a header line, and otherwise prints why it skipped.

  Both failures reproduced in a local `archlinux:latest` container, and the
  fixed scripts pass there.
- **The authoring rules for OpenQASM changed.** `content-format.md` used to
  say "Use OPENQASM 2.0 (not 3.0)" and "do not use `swap` or `cp`". The
  second rule was a limitation of qiskit's 2.0 parser, not of the language.
  The notes now cover 3.1, reserved names, and `@expect`.

### Fixed — the full-corpus review: 1,134 findings behind a green gate

Eleven reviewers ran in parallel, one per language, over all 77 examples and
the `concept.toml` entries for their language. Every finding had to be
verified by a probe, a mutant or a spec citation before it was fixed: 1,126
were CONFIRMED and 8 PLAUSIBLE. Afterwards each language's 77 examples were
re-run against that language's gate (plus ASan/UBSan and a `-DNDEBUG` build
for C, `-race` for Go, and the simulator for OpenQASM). Before any of it, the
gate read 847/847. The last review, at 2.8.3, found 80.

| Language | Findings | High | Files changed |
|---|---|---|---|
| Cyrius | 136 | 15 | 69 |
| TypeScript | 130 | 5 | 67 |
| C | 127 | 5 | 67 |
| Go | 118 | 5 | 66 |
| x86_64 | 109 | 10 | 58 |
| Rust | 108 | 4 | 59 |
| Zig | 90 | 4 | 57 |
| AArch64 | 87 | 8 | 63 |
| Python | 84 | 2 | 55 |
| Shell | 79 | 1 | 52 |
| OpenQASM | 66 | 4 | 77 |
| **Total** | **1,134** | **63** | **716 files under `content/`** |

Bugs one reviewer found were often in other ports too. So a cross-port
sweep then checked 87 more ports for 20 such bugs, and fixed 30 of them. A
closeout pass fixed 5 more in 12 files. One owner applied the `concept.toml`
findings: 40 proposals, each checked against the fixed code and a probe,
across 26 files. Five of them were partly wrong as proposed and were
corrected. The worst, by kind:

- **Untrusted-input decoders that read or write out of bounds.** The
  compression decoder never checked a back-reference offset (C, Zig, Rust,
  both assembly ports, Cyrius). serialization's `decode_frame` checked the
  1024-byte limit but not the 64-byte destination. The SQL tokenizers had no
  bound, and the HTTP parsers ignored `Content-Length`, so a pipelined
  request was swallowed into the body (Python, Shell, Zig, x86_64). The
  assembly ports bounds-checked with signed compares, so `dispatch(-1)` jumped
  ~32 GB away and `gem_destroy(-31)` zeroed a `.data` global.
- **Security examples that did not secure.** "Safe path" helpers passed a
  symlink escape (Shell, C, Zig, TypeScript), Rust's passed an absolute path
  through `Path::join`, and Go's lexical check lost to a symlink (it now uses
  `os.Root`). A permission check could never match, so mode 777 passed. A
  TLS example handed back unverified plaintext.
- **Algorithms that were wrong in every port**, because they were ported
  from one another:
  - `reproducible_builds` stamped `min(now, SOURCE_DATE_EPOCH)`, so a slow
    clock leaked into the build (all ten classical ports).
  - top-k masked dropped logits to 0 instead of −∞ (every port).
  - render-graph culling left culled passes in the schedule.
  - a "PCG" generator was an LCG.
  - `^0.2.3` accepted `0.9.0`.
  - transactions past the read-set cap committed stale reads.
  - DNS answered NXDOMAIN for NODATA, and ignored the CNAME chain's minimum
    TTL.
  - the CFS model collapsed task weights, so a high-priority task got 100 %
    of the CPU.
  - the sine table was out of phase over half the circle.
- **Optimizers and linkers that never worked.** Constant propagation
  reported changes it never made, so the pass loop never terminated (C,
  Python, Rust). Strength reduction turned `7*8` into `7<<8` (Go). Every
  object's `.text` sat at 0x400000, and PC32 subtracted 4 twice (Go, TS).
  Rust's generated ELF printed garbage, and the TS code generator emitted
  the topic's own misaligned-call bad example.
- **Quantum circuits whose prose the simulator contradicted.** The QPE
  inverse QFT read a phase of 1/4 as 50/25/25. The "Shor oracle" was two
  CNOTs, so its output was noise. The "Ψ±" Bell states were Φ∓. "Completes
  only when both are ready" was an XOR, and "2-of-3 majority" was one
  Toffoli on two voters. All 66 OpenQASM findings came from reading the
  circuits against their own words, which `@expect` now checks: 205 lines on
  205 of the 213 classical registers.
- **Cyrius memory taught wrong.** A fn-local `var x[N]` is N **bytes**, and
  five lessons wrote 8-byte slots past it; in `security` that defeated the
  bounds-check lesson. Five lessons taught that every local has a fixed
  static address. Three files said traits, modules and macros do not exist.
- **Tests that could not fail**, in every language: an assert on the literal
  just written, a "PASS: scaled blit 2x" for a 1:1 blit, an HTTP test
  comparing the test data with itself, AI decision code never called. C put
  the operation under test inside `assert()` 134 times in 23 files, so
  `-DNDEBUG` compiled it away (ipc still printed 18/18 ok). Those calls now
  happen first, and the assert checks the saved result. Printed "N/N ok"
  tallies were often wrong; Go and C now count their checks at run time.
- **Outdated for the target version.** On Python 3.15, an unguarded `Pool`
  now hangs instead of raising. Zig 0.17 deprecates `@intFromEnum`
  (`@backingInt`; 26 lines). Linux's scheduler has been EEVDF, not CFS, since
  6.6. Go 1.24–1.27 brought `errors.AsType`, `wg.Go` and `os.Root`. C's GNU
  `__int128` became C23's `_BitInt(128)`, and small-int caching on Python 3.15
  is −5..1024.

### Verified

Strict content gate **847/847**, zero skips, on Python 3.15 and OpenQASM 3.1
(76 circuits run their `@expect` lines). `cyrius test` 158/0. `vidya stats`:
77 topics, 77 complete, 847 examples, 0 gaps. The vidya source changed only
in `validate_command`'s Python and OpenQASM strings, so the benchmarks
measure content. `load_concept` reads ~19 % slower (59.3 µs) because
`content/strings/concept.toml`, the file it parses, grew 34 % in the review.
The 2.9.3 bench binary reads the same 59.3 µs on the new content. The other
rows are flat.

Also: literal U+FFFD bytes, committed in March, were repaired in the
comment dividers of nine files (4 `.qasm`, 2 `rust.rs`, 3 `shell.sh`). And six
`concept.toml` sentences were reworded to say concretely what they meant.

## [2.9.3] — 2026-10-28

`serve` longevity, the roadmap's next 2.9.x item. A long-running `serve`
kept everything it ever allocated: 81 MB at startup, ~77 MB more per hot
reload, and every response it built. Now it starts at 13.4 MB and adds
~9.4 MB per reload. Requests add nothing, except `/code`'s tokenizer
stream. It also recalibrates sakshi's clock hourly. Output is
byte-identical to 2.9.2 in every command and endpoint (954 dumps compared).
`cyrius test` **158/0** (+18), 12 benchmarks.

### Fixed — memory a long-running `serve` never gave back

Resident memory of one `serve` process, measured from `/proc` on the same
corpus:

| | 2.9.2 | 2.9.3 |
|---|---|---|
| after startup | 80.9 MB | **13.4 MB** |
| per hot reload | +77.2 MB | **+9.4 MB** |
| 500 × `/code/lexing_and_parsing/c` | +336 MB | **+59.5 MB** |
| 500 × `/list` | +22.5 MB | **0** |

- **The loader read every file into a fixed-size buffer.** Each
  `concept.toml` got 256 KiB and each example 64 KiB, whatever its size:
  ~75 MB of heap for a 6.4 MB corpus, paid again on every hot reload,
  because the bump heap never frees. `read_file_exact` now reads through
  one buffer kept across files (`file_read_whole_into`) and keeps an
  exact-size copy. An example over 65,535 bytes was also **cut short with
  no error**. It now loads whole, up to 1 MiB (`LOAD_FILE_MAX`); beyond
  that it is refused and shows up as a gap. New tests `load_sized` and
  `load_big_example` both fail on 2.9.2, which returned the 70,000-byte
  example as 65,535 bytes.
  - The first cut made a cold load **slower**: 35 ms against 19 ms. Two
    causes. Each file started a fresh 4 KiB buffer and doubled it, and the
    copy went through `lib/string.cyr`'s `memcpy`, which moves one byte per
    iteration (6.3 MB per load, ~8 ms). With one kept buffer and an
    8-byte copy (`copy_bytes8`), a cold load is 18.7–18.8 ms against
    2.9.2's 19.1–19.2 ms (two interleaved rounds of seven).
- **Every response stayed on the bump heap.** `handle_request` now wraps
  each request in `rq_enter` / `rq_leave` (`src/vidya_core.cyr`): the JSON
  builders, `search`, the escaper, sandhi's request parsing and the
  response itself allocate from a growable arena, which is reset
  afterwards. Outside `serve`, `rq_alloc()` is the default allocator, so
  the CLI, the tests and the benches allocate exactly as before. The
  reload, the registry and every library cache stay on the default heap.
  Measured global-heap growth per request, before and after:
  `/stats` 0.5 KB → 0, `/list` 44 KB → 0, `/info` 3.6 KB → 0, `/search`
  0.8–8 KB → 0, `/compare` 1.6 KB → 0, `/code` 154–688 KB → **29–119 KB**.
  - What `/code` still leaves is vyakarana's stream: a fresh one per
    render, with no reuse or allocator API. The token buffer is now
    reused (`render_tokenbuf`), which removed ~45 % of what was left.
    `tokenbuf_drop_front`, which the reuse needs, is exported but not on
    vyakarana's public-API list. The `rq_arena_code` test renders twice,
    so a rename would fail there.
  - New tests: `rq_arena_flat` (20 rounds of every non-`/code` response
    leave the global heap at exactly 0 bytes of growth) and
    `rq_arena_code` (a second `/code` render stays under 40 KB).
- **`sandhi_json_escape_a` ignores its allocator** (sandhi 1.13.7, also
  current upstream). It builds its result with a plain `str_builder_new()`,
  so it leaks on the global heap whatever arena it is handed: ~19 KB per
  `/list` under the request arena. vidya now escapes with its own
  `json_escape_a`, which sizes the output and fills one allocation from
  the arena. Because the 2.8.2 injection fix rests on those rules, the
  new `json_escape_matches_sandhi` test requires byte-identical output
  to sandhi's escaper for every byte value 1–255, a string mixing every
  escaped class, and all 847 examples. With sandhi's escaper put back,
  `rq_arena_flat` fails: 493,440 B over 20 rounds.
- **Not fixed: the replaced registry on a hot reload (~9.4 MB, 6.3 MB of
  it the corpus files).** Freeing it means building each registry on an
  arena, and bayan's `toml_parse` hard-codes `default_alloc()`, so the
  parse trees the registry points into cannot move there. On the roadmap
  under "Waiting on a trigger", with the vyakarana stream.

### Added — hourly clock recalibration in `serve`

sakshi stamps spans and log lines from a calibrated cycle counter, and
recommends recalibrating hourly in a long-running process (the counter
drifts up to ~0.1 s an hour on x86_64). `cmd_serve` never did. After each
request, once an hour has passed (`CLOCK_RECAL_NS`), `serve_recalibrate`
runs `sakshi_clock_recalibrate()` and logs `clock recalibrated: <Hz> Hz`.
The call pauses ~10–80 ms, so it runs after the response has gone out and
outside the logged latency. An idle server makes no timestamps, so it
recalibrates on the first request after the hour. Checked end to end with
the period cut to 1 s: no recalibration inside the second, one after the
request that crossed it, and a hot reload in the same run served normally.
New test `clock_recal` covers the due-check.

### Performance

Interleaved A/B of the two bench binaries, three rounds:

| Bench | 2.9.2 | 2.9.3 | Δ mean | per-round Δ |
|---|---|---|---|---|
| load_concept | 48.871 µs | 50.467 µs | +3.3 % | +0 / +1 / +9 % |
| load_all | 7.857 ms | 7.901 ms | +0.6 % | +0 / −0 / +2 % |
| reg_get_hit | 129 ns | 104 ns | (−19.1 %) | +1 / −47 / +4 % |
| reg_get_miss | 100 ns | 239 ns | (+139.3 %) | −73 / +1055 / −2 % |
| search_text | 5.709 µs | 6.017 µs | **+5.4 %** | +5 / +6 / +5 % |
| search_text_exact | 11.135 µs | 11.256 µs | +1.1 % | +1 / +0 / +2 % |
| toml_sections | 2.140 µs | 2.199 µs | +2.8 % | +6 / +1 / +1 % |
| json_info_response | 9.118 µs | 7.500 µs | **−17.7 %** | −17 / −19 / −18 % |
| json_search_response | 252.384 µs | 246.588 µs | −2.3 % | −2 / −4 / −1 % |
| json_list_response | 112.001 µs | 94.115 µs | **−16.0 %** | −17 / −14 / −16 % |
| field_escaped | 3.311 µs | 2.721 µs | **−17.8 %** | −17 / −18 / −18 % |
| field_raw_splice | 560 ns | 560 ns | +0.0 % | +0 / −1 / +0 % |

- **The escape-heavy rows are 16–18 % faster**, every round. The cause is
  `json_escape_a`, which sizes the output once and fills one allocation,
  where sandhi appended one byte at a time to a builder.
- **`search_text` is 5.4 % slower**, every round. The bench makes one
  `cstr_lower` call, which now allocates through `rq_alloc()` and the
  Allocator vtable, so that `/search` stays flat under the arena. It is
  ~0.3 µs per search, and the end-to-end `json_search_response` row is
  net −2.3 %. `to_cstr` went the same way at first (`search_text_exact`
  +4.9 %). Nothing on the request path needs it, so it keeps its direct
  `alloc`, and that row is flat.
- **The load rows are flat** in this warm, in-process bench. The cold
  load figure is under Fixed.
- `reg_get_*` remain the per-process hash-seed lottery (see 2.9.0).

`serve` latency, server-side from the access log, median of 20 at 77
topics: `/stats` 45 → 39 µs, `/compare` 48 → 43 µs, `/info` 53 → 49 µs,
`/list` 208 → 183 µs, `/search` 418 → 430 µs, `/code` 911 → 852 µs. Hot
reload median 26 → 22 ms (seven reloads each).

## [2.9.2] — 2026-10-28

Hygiene patch, the roadmap's first 2.9.x item. No dependency, behaviour or
output change: the binary is byte-identical to 2.9.1 (the one source edit is
a comment). `cyrius test` 140/0, 12 benchmarks, and content gate 847/847,
strict, zero skips.

### Added — field note: a git dep on a stdlib-folded module

`compiler/gotchas.cyml` gains a CLASS entry,
`a_git_dep_on_a_stdlib_folded_module_downgraded_silently_now_it_pins_nothing_v6718`,
promoted under CLAUDE.md's three-port rule. Five repos hit it: sit, patra,
sigil, kavach and vidya (2.8.1). It was written from a re-run at 6.7.18
rather than from the old records, and that changed what it says:

- **Through 6.5.38** the git block overlaid the snapshot's copy on every
  build. That was a silent downgrade, and `deps --verify` could not see it,
  because the lock is hashed from disk.
- **Since 6.5.39** the overwrite is refused, on every `deps` and `build`:
  `warning: refusing to overwrite stdlib leaf 'sakshi'`. Re-running vidya's
  own 2.8.0 block (`[deps.sakshi]` tag 2.4.4) over 6.7.18's sakshi 2.5.10
  builds a binary byte-identical to the tree without the block. The pin is
  inert, but `cyrius.lock` still carries a `sakshi … 2.4.4` commit row and
  `deps --verify` passes, so the manifest and lock name a version the build
  never uses.
- The warning's advice ("declare it in [deps] stdlib OR depend on the
  package") does not rescue the pin either. With `sakshi` also removed from
  `[deps] stdlib`, another stdlib module still vendored it, and the git
  artifact was refused the same way.

### Changed — field-notes index

- `field_notes/index.cyml` claimed "Verified on Cyrius 2.2 → 6.6.19". It now
  says what the stamp means: entries span 2.2 → 6.7.18, each was verified on
  the version it names, and none is re-verified when the pin moves. Bumping
  the old stamp would have claimed a re-verification that never happened.
- Its counts were re-derived with the `grep -c` the file prescribes. They had
  drifted again: language/ read 81 against 166, compiler/ 257 against 336,
  and nine per-file lines were stale (gotchas 139 → 209, platform_abi 16 →
  41, semantics_runtime 33 → 64, …). `compiler/index.cyml` had kept up with
  its own counts, apart from its gotchas section line (205 → 209); it also
  lists the new entry.

### Changed — docs

- **`docs/architecture/overview.md`'s serve figures, re-measured at 77
  topics.** They had been taken at 60. Each comes from vidya's own sakshi log
  lines, running the 2.9.1 binary:
  - `load_all` is **~19 ms** per process start (18.5–20.3 ms over 7 runs).
    The old figure was ~2.4 ms. The bench's `load_all` (~7.8 ms) is a
    repeated load inside one warm process, which is not the same
    measurement.
  - Reload is **22–27 ms** (median 26 ms over 7 reloads), up from 17–22 ms,
    in line with 77 / 60 topics.
  - Per-request latency is still sub-millisecond at the median on every
    endpoint: `/stats` 45 µs, `/compare` 48 µs, `/info` 53 µs, `/list`
    208 µs, `/search` 418 µs, `/code` 911 µs. `/code` tokenizes, and one of
    its 20 runs took 2.7 ms.
- **Stale renderer comments** in `src/vidya_core.cyr`. They still said
  OpenQASM has no vyakarana grammar, which was true of 2.2.1; vyakarana has
  shipped one since 2.3.5. The section header also still described the
  pre-2.7.0 plan ("vidya does not currently render source code anywhere").
  Comment-only; the `has_grammar` fallback stays.

## [2.9.1] — 2026-10-27

Dependency patch. **cyrius 6.7.15 → 6.7.18** and **vyakarana 2.9.1 →
2.10.0**, the newest tag of each. The folded stdlib leaves move with the
snapshot: bayan 1.9.0 → 1.11.1, sandhi 1.13.1 → 1.13.7, sigil 3.13.12 →
3.13.15. sakshi stays at 2.5.10, byte-identical. No content added (77 topics
/ 847 examples, 0 gaps). `cyrius test` **140/0**, 12 benchmarks, and content
gate **847/847**, strict, zero skips.

The only source change is an API rename. bayan 1.11.0 deprecated the bare
TOML lookups (see Changed). The CLI and `serve` output is byte-identical to
2.9.0. Only `code` colouring moves, from vyakarana's token fixes.

### Verified — output-neutral apart from `code` colour

Every observable output was dumped from the 2.9.0 and 2.9.1 binaries and
byte-compared: `list` / `stats` / `gaps` / `languages` / `help`, five
searches, `info` for all 77 topics, `code` for every example, a `compare`,
and 12 `serve` endpoints (including two 404s).

- **Identical:** everything except `code`, all 12 `serve` endpoints included.
- **`code`:** 78 of 847 examples differ (rust 37, typescript 22, c 18,
  python 1). With the colour codes stripped, the text is byte-identical in
  every one. Two vyakarana changes account for every differing span:
  - **2.9.7, type suffixes (874 spans).** A literal and its suffix are now one
    `number` token: `0u64`, `0usize`, `0x…ULL`, `0j`, `0x40_0078n`. The
    suffix used to be plain text.
  - **2.9.3, block comments (26 spans).** The typescript grammar had no
    `/* … */` rule, so a `/** … */` doc comment came back as operators. It is
    now a comment. That hit 26 doc comments in 7 TypeScript files.

### Changed — cyrius 6.7.15 → 6.7.18

**`toml_get` / `toml_get_sections` → `bayan_toml_get_by_cstr` /
`bayan_toml_get_sections_by_cstr`.** bayan 1.11.0 (cyrius 6.7.17) made the
flat lookups name their key type, and the 13 bare names now warn on every
call. vidya had 35 such calls: 20 in `src/vidya_core.cyr` (the loader), 11 in
`tests/vidya.tcyr`, and 4 in `tests/vidya.bcyr`. Each key is a C-string
literal, so `_by_cstr` is the right form. The old names are one-line
pass-throughs to the new ones, so behaviour and binary size are unchanged
(the two aliases become dead code: unreachable fns 3,662 → 3,664). The build
now prints no deprecation warnings. `toml_parse` and `toml_section_pairs` are
plain aliases and stay. bayan 1.11.1's other new refusals cannot reach vidya:
duplicate JSON keys, malformed JSON numbers, and non-canonical base64. vidya
parses only TOML; its JSON is built, never parsed.

The migration guide says a hand-written include list needs `lib/slice.cyr`
and `lib/hashseed.cyr` ahead of `lib/bayan.cyr`, and `lib/slice.cyr` ahead of
`lib/sandhi.cyr`. vidya builds through the manifest's `[deps] stdlib`, which
resolves them, so `src/main.cyr`'s include lines needed nothing. The rest of
the 6.7.16–6.7.18 guide covers networking deadlines, WebSocket and TLS
hardening, crypto lanes and X.509 nameConstraints. None of it touches a path
vidya runs: `serve` is plaintext, synchronous, and localhost.

**Binary 2,762,208 → 2,937,144 B (+174,936, +6.3 %).** Split with two
scratch builds:

| Build | Size | Δ |
|---|---|---|
| 2.9.0 (cyrius 6.7.15, 6.7.15 lib, vyakarana 2.9.1) | 2,762,208 B | — |
| 6.7.18 compiler over the 6.7.15 lib | 2,762,208 B | **compiler 0** (15 bytes differ) |
| 6.7.18 snapshot, vyakarana 2.9.1 | 2,863,424 B | **stdlib +101,216** |
| 6.7.18 snapshot, vyakarana 2.10.0 (2.9.1) | 2,937,144 B | **vyakarana +73,720** |

The stdlib growth is spread more widely than at 2.9.0. By source size: bayan
+81,966 B, sigil +45,117, sandhi +42,200, and the two TLS handshake files
+22,909. `lib/` keeps the same 75 entries: 39 files changed and 42 are
byte-identical. Static data 135,696 → 136,336 B. Unreachable code (cyrius
does not DCE by default) 3,502 → 3,664 fns, 1,270,715 → 1,354,583 B. A
`CYRIUS_DCE=1` build is 1,585,464 B (1,550,416 at 2.9.0). A second build of
the same tree in a scratch copy is byte-identical to `build/vidya`.

The pin bump used the clean rehydrate (`rm -rf lib cyrius.lock && cyrius lib
sync && cyrius deps`), and `cyrius deps --verify` reports 81 verified. The
`hashmap_fast.cyr` footprint note still prints, and every `cyrius run` /
`build` still moves `lib/vyakarana.cyr` aside while it re-resolves (absent
in 31 polls of one build), so the one-cyrius-command-per-tree rule stands.
The clean rehydrate matters for the git dep too. In a scratch tree, changing
the vyakarana tag in place and running `cyrius deps` left the old tag's commit
line in `cyrius.lock` next to the new one. Every resolve after that printed
"cyrius.lock keeps vyakarana@2.9.1's pin … fail-closed", even though the
vendored file was the new tag's. The main tree's lock, rehydrated clean, has
the one 2.10.0 line.

### Changed — vyakarana 2.9.1 → 2.10.0

Eleven patch tags and one minor, all pinned to cyrius 6.7.18 (2.9.2 onward).
**No token kind, `Token` layout or public-API change**, so no call site
moved. 2.9.11 adds a document API (`tokenize_doc_*`, incremental
retokenization), which vidya does not call. `render_code` still makes one
`tokenize_stream_feed` per file, so the streaming fixes in 2.9.10–2.9.12 are
inert here. The visible effect is the colour change above. The bundle grew
362,193 → 473,365 B of source (+111,172) for new grammars, number shapes and
the document API, and vidya's binary grew by 73,720 B.

### Benchmarks — one row slower, attributed

Interleaved A/B of the two bench binaries on one machine, three rounds. The
harness `lib/bench.cyr` is unchanged across these pins.

| Bench | 2.9.0 | 2.9.1 | Δ mean | per-round Δ |
|---|---|---|---|---|
| load_concept | 49.974 µs | 49.094 µs | −1.8 % | −2 / −1 / −2 % |
| load_all | 8.048 ms | 7.861 ms | −2.3 % | −2 / −3 / −2 % |
| reg_get_hit | 105 ns | 117 ns | (+10.8 %) | +0 / +30 / −5 % |
| reg_get_miss | 232 ns | 131 ns | (−43.5 %) | −72 / −23 / +176 % |
| search_text | 5.865 µs | 5.699 µs | −2.8 % | −3 / −3 / −3 % |
| search_text_exact | 11.048 µs | 11.102 µs | +0.5 % | +1 / +1 / +0 % |
| toml_sections | 1.955 µs | 2.122 µs | **+8.5 %** | +9 / +9 / +8 % |
| json_info_response | 9.161 µs | 9.079 µs | −0.9 % | −2 / +0 / −1 % |
| json_search_response | 257.784 µs | 251.514 µs | −2.4 % | −3 / −2 / −3 % |
| json_list_response | 113.028 µs | 111.561 µs | −1.3 % | −0 / −1 / −2 % |
| field_escaped | 3.320 µs | 3.309 µs | −0.3 % | −0 / −0 / −0 % |
| field_raw_splice | 562 ns | 560 ns | −0.4 % | −0 / +0 / −1 % |

- **`toml_sections` +8.5 % is real, and it is bayan's code.** bayan 1.9.0's
  `get_sections` called `str_eq_cstr` on each section name directly. 1.11.x
  goes through `_toml_find_sections` → `_toml_key_eq` → `str_eq_cstr`, one
  more call per section. A scratch bench timed the 1.9.0 body against the
  1.11.1 path in **one** 6.7.18 binary, with the same fixture
  (`content/strings/concept.toml`, 14 sections × 3 lookups) over three
  processes. The old body ran 1.77–1.86 µs and the new path 1.93–1.99 µs
  (+9 %), with no overlap between the ranges. That is about 4 ns per section
  compared, roughly 0.15 µs per topic load. `load_concept` is net faster
  anyway.
- **The 1–3 % improvements are not claimed.** At 2.9.0, a `toml_sections`
  delta of −5.7 % that held in every round turned out to be code layout
  between two binaries. These deltas have no mechanism behind them yet.
- **`reg_get_hit` / `reg_get_miss` remain a per-process hash-seed lottery**
  (see 2.9.0). They are not a signal in either direction.

### Docs

- `cyrius.cyml`: a 6.7.18 block (folds, the size split, the TOML rename, the
  include-list note) and a vyakarana 2.10.0 block.
- `docs/architecture/overview.md` point 5 and the
  `stdlib_str_to_cstr_key_migration` field note: the typed lookup names.
- `docs/development/state.md`, `roadmap.md`, `docs/sources.md`,
  `docs/doc-health.md`: pins, sizes and posture for 2.9.1.

## [2.9.0] — 2026-10-23

Toolchain minor. **cyrius 6.6.20 → 6.7.15**, the move onto cyrius's 6.7
language line, and **vyakarana 2.4.3 → 2.9.1**, the newest tag on that pin.
The folded stdlib leaves move with the snapshot: bayan 1.5.12 → 1.9.0,
sandhi 1.10.8 → 1.13.1, sigil 3.13.10 → 3.13.12, sakshi 2.5.7 → 2.5.10. No
content added (77 topics / 847 examples, 0 gaps). `cyrius test` **140/0**
(+1, a regression test), 12 benchmarks, and content gate **847/847**, strict,
zero skips.

vidya's own source needed **no change for 6.7**. It built and passed its tests
first time, despite 6.7's reserved words (`trait`, `const`, `true`, `false`,
`do`, `dyn`), `!` as an operator, and arity-checked forward calls. A separate
audit read the migration guide's 6.7.0–6.7.15 sections against every line of
vidya's Cyrius and found no silent semantic change either: vidya uses no typed
pointers, structs, generics or f64. Of the 316 stdlib functions it calls,
those that changed did so in ways it cannot observe: `exec_cmd` children now
start with default signal dispositions, and sandhi's server internals moved
while its return contract held. The source edits in this release are **four
pre-existing bugs** that the bump's verification surfaced (see Fixed). The
worst is a segfault that took down `serve`.

### Verified — the toolchain move is output-neutral; vyakarana changes colour only

Every observable output was dumped from three builds and byte-compared: `info`
for all 77 topics, `code` for all 847 examples, `list` / `stats` / `gaps` /
`languages`, five searches, and 11 `serve` endpoints.

| Build | vs previous | Result |
|---|---|---|
| cyrius 6.6.20 + vyakarana 2.4.3 (2.8.7) | — | baseline |
| cyrius **6.7.15** + vyakarana 2.4.3 | baseline | **byte-identical everywhere** |
| cyrius 6.7.15 + vyakarana **2.9.1** (2.9.0) | middle build | CLI and `serve` identical. `code` differs in **287 of 847** examples, all in colour; plain text is byte-identical in every one |

The colour changes are vyakarana's intended token fixes. 2.7.0 makes a decimal
one `number` token (`2.0`, not `2` `.` `0`), which reaches all 77 OpenQASM
files and every float literal elsewhere. 2.7.1 makes byte strings one token
(`b"…"`), and 2.6.0 does the same for shell positionals (`$1`). By language:
openqasm 77, shell 63, python 52, rust 35, typescript 17, zig 16, go 15, c 10,
cyrius 2.

### Changed — cyrius 6.6.20 → 6.7.15

**Binary 2,683,032 → 2,820,176 B (+137,144, +5.1 %) from the dependencies
alone.** The shipped 2.9.0 binary is 2,762,208 B, after the array fix under
Fixed. Split with two scratch
builds: the 6.7.15 compiler over the *6.6.20* lib is 2,674,840 B (**compiler
−8,192**); the 6.7.15 snapshot with vyakarana 2.4.3 is 2,897,752 B (**stdlib
+222,912**); and vyakarana 2.9.1 takes **77,576** back (see below). The
stdlib growth is again mostly `bayan` (+180,407 B of source). bayan now also
pulls in `lib/math.cyr` and a `lib/unicode/` directory of casefold, category
and normalisation tables (353 KB of source), so `lib/` went **73 → 75
entries**. Static data went the other way, **515,728 → 193,664 B**: sigil's
256 KiB crypto-bank buffer is no longer in `.bss`, and its build warning is
gone.

**`lib/math.cyr` broke one content example.** It defines `gcd`, and `cyrius run`
prepends this manifest's stdlib to every content example, so
`algorithms/cyrius.cyr`'s own `fn gcd` became a duplicate-fn shadow. The gate
fails on that since 2.8.3, and it was the gate's only failure. The shadow was
real. That `gcd` returns −6 for `gcd(48, -18)` (verified), where the stdlib's
makes signs positive first. Last-definition-wins would have handed the wrong
one to the stdlib's own `lcm`. Renamed to `gcd_euclid`, with a comment saying
why.

A new resolve note now prints on every resolve: `lib/hashmap_fast.cyr` "is
outside the declared footprint". `cyrius lib sync` still copies it as a
declared-subset sibling, but `cyrius deps` no longer resolves it. It is
harmless, because `lib/` is gitignored and CI recreates the same state.

**Never run two cyrius commands in one tree.** Every `cyrius run` / `build`
re-resolves the vyakarana git dep and moves `lib/vyakarana.cyr` out and back
(absent in 486 of the polls taken during one `cyrius run`, then back on the
same inode). A `cyrius build` alongside the content gate failed with "cannot
hash lib/vyakarana.cyr (errno 2)". Recorded in `CLAUDE.md` and `cyrius.cyml`.

### Changed — vyakarana 2.4.3 → 2.9.1

Five minors. The public API is unchanged throughout (`tokenize_stream_*`,
`tokenbuf_*`, `kind_name`, `has_grammar`), so no call site moved. The minors
are earned by token-boundary fixes: 2.6.0 (shell), 2.7.0 (number literals),
2.7.1 (12 grammars), and 2.9.1 (markdown fences, closeout audit). The effect
on vidya is the colour-only `code` difference above. 2.9.0 compacted the
embedded grammars, so the bundle is 38,978 B smaller as source and vidya's
binary 77,576 B smaller. 2.8.0's chunk-invariance work is inert here, as
2.4.0's was, because `render_code` feeds each file in one
`tokenize_stream_feed`. 2.5.2 also fixed a segfault in
`has_grammar(0)` / `tokenize_stream_new(0)` (an unknown language). vidya
was never exposed: `render_code` passes a fixed per-language stem from
`lang_stem`, never 0, and asks `has_grammar` before it opens a stream.

### Fixed

- **A `concept.toml` without an `id` crashed every command, and `serve` on hot
  reload.** `load_concept` joins each example's file name onto the topic id,
  and with no `id` it passed 0 to `path_join`, which dereferenced it: exit
  139. That covers a file truncated mid-save, a typo'd key, or junk. Under
  `serve` the hot reloader fires on exactly that mid-save state. The reload
  path was *designed* to refuse a bad topic and keep the live registry, but
  it never got the chance. Verified on the 6.6.20 build: one bad file killed
  `serve` on its next request. Now `load_concept` refuses a topic without an
  `id` (return 0), so `load_all` skips the topic and a reload keeps the live
  registry. That was checked by breaking a file under a running `serve`: it
  stays up, `/stats` still reports 77 topics, and `/info/strings` still
  answers 200. A crash matrix also ran 8 CLI commands and 7 endpoints against
  four broken files (no `id`, `id` only, an empty table, junk), with no
  crash. The new `missing_id` test group (`tests/fixtures/missing_id/`: no
  `id`, one example file) **segfaults on the old source** and passes on the
  new. A defensive `sections == 0` check was added beside it, because
  `toml_parse` returns 0 on an allocation failure. The audit that surfaced
  this misattributed it to `toml_parse` returning 0 on malformed input. It
  does not: it returned a vec for every input tried, junk included.
- **Two top-level arrays were 8× their intended size.** A bare `var x[N]` is
  N *bytes* inside a fn but N *i64 slots* at top level (cyrius documents the
  trap in `content/cyrius/language/agents.cyml`). `_tool_probe[88]`, whose
  comment said "`var buf[N]` is N BYTES — LANG_COUNT × 8 B", reserved 704 B
  for 88 B of use. `_inotify_buf[8192]` reserved 64 KiB for an 8,192-byte
  read. Both now use the position-independent typed form, `i64[11]` and
  `u8[8192]`, sizes measured at 6.7.15. This is harmless over-reservation,
  not an overflow, but it sat in the file's static data: **the binary is
  57,968 B smaller** for it (2,820,176 → 2,762,208), with static data at
  193,664 → 135,696 B.
- **`vidya search` dropped the space after the em dash** on every result line
  (`networking_fundamentals —TCP and UDP…`). `src/main.cyr` wrote `" — "` with
  length 4, but the em dash is 3 bytes of UTF-8, so the literal is 5. The bug
  dates from 2026-04-08. It was invisible to the tests, because the CLI
  printer lives in `main.cyr`, outside the `vidya_core.cyr` layer the tests
  include. 6.7.15's `cyrius lint` found it ("write length 4, but its literal
  is 5 bytes"). The other 49 literal writes in `src/` and `tests/` were
  checked by script and are exact. `serve`'s JSON was never affected.
- **The "no content found" log line dropped its last byte.**
  `sakshi_error("no content found in content/", 27)` wrote 27 bytes of a
  28-byte literal, so the log read `content` instead of `content/`. This is
  the same class as the em dash, but in a call the lint does not check. A
  wider scan of every `"literal", N` call in `src/` and `tests/` (70) found no
  others.

### Benchmarks — no real change

The harness is byte-identical across these pins (`lib/bench.cyr`), so unlike
2.8.6 the rows compare directly. Interleaved A/B on one machine, three
rounds. This measures the dependency bump on its own, before the Fixed items.
Of those, only the `id` check touches a benchmarked path (one comparison per
`load_concept`):

| Bench | 6.6.20 | 6.7.15 | Δ mean | per-round Δ |
|---|---|---|---|---|
| load_concept | 51.196 µs | 50.476 µs | −1.4 % | −1 / −1 / −2 % |
| load_all | 8.045 ms | 8.143 ms | +1.2 % | +1 / +1 / +1 % |
| reg_get_hit | 91 ns | 162 ns | (+77.0 %) | −1 / +91 / +142 % |
| reg_get_miss | 165 ns | 120 ns | (−27.5 %) | −73 / +151 / +23 % |
| search_text | 5.693 µs | 5.689 µs | −0.1 % | +0 / −0 / −0 % |
| search_text_exact | 11.236 µs | 11.228 µs | −0.1 % | +0 / +0 / −1 % |
| toml_sections | 2.095 µs | 1.975 µs | −5.7 % | −6 / −6 / −5 % |
| json_info_response | 9.236 µs | 9.297 µs | +0.7 % | −1 / +1 / +2 % |
| json_search_response | 249.155 µs | 250.488 µs | +0.5 % | +0 / +1 / +1 % |
| json_list_response | 113.070 µs | 114.797 µs | +1.5 % | +3 / +1 / +1 % |
| field_escaped | 3.429 µs | 3.364 µs | −1.9 % | −6 / −0 / +0 % |
| field_raw_splice | 581 ns | 572 ns | −1.6 % | −7 / +1 / +2 % |

Three rows looked like they moved, and a harness-free loop (six processes per
pin) settles each:

- **`reg_get_hit` / `reg_get_miss` are a seed lottery at both pins.**
  `hashmap.cyr` and `hashseed.cyr` differ between the pins *only in comments*.
  A hit sits at ~87–88 ns, but with outliers at both pins (130 ns at 6.6.20;
  394 and 183 ns at 6.7.15), and misses range 50–726 ns. **Correction to
  2.8.6**, which said a hit "holds at ~85–87 ns … as expected for a hit on
  the first probe". That is only true when the seed puts no collision on the
  key's probe path. Both rows carry the per-process `getrandom` seed, and
  neither is a regression signal.
- **`toml_sections` is flat.** Harness-free, it reads 1.93–1.95 µs vs
  1.95–1.99 µs, +1–2 %, the opposite sign to the bench's −5.7 %. The
  consistent bench delta is code-layout variance between two different
  binaries, not a bayan speed-up.

## [2.8.7] — 2026-10-23

Content toolchain cut: **Zig 0.16.0 → 0.17.0**, for the corpus and the CI pin
together. It was forced, not chosen. pacman upgraded the dev host's Zig to
0.17.0 on 2026-10-21, after which 37 of the 77 Zig examples no longer
compiled (2.8.6 "Known"). No other language and no project source changed.
`cyrius test`, benchmarks and the binary are untouched.

**45 `zig.zig` files changed, and every one prints exactly what its 0.16
version printed.** Checked by building each file's HEAD source with Zig 0.16.0
and the new source with 0.17.0, then diffing stdout. The only difference is
two lines of `ownership_and_borrowing` output, reworded on purpose (GPA →
SafeAllocator). Zig **77/77** under 0.17.0, and the strict content gate is
**847/847** on this host.

### Changed — the two 0.17 removals that broke compilation

- **`**` array repetition is gone, replaced by `@splat` (111 lines, 34 files).**
  0.17's tokenizer no longer has a `**` token. `[_]u8{0} ** N` now lexes as two
  `*` and fails with "binary operator '*' has whitespace on one side, but not
  the other", which does not point at the real cause. Every
  `[_]T{v} ** N` became `@splat(v)`, and the nested `[_][M]T{[_]T{0} ** M} ** N`
  became `@splat(@splat(0))`. `@splat` takes its length from the result type,
  so the 13 untyped locals (`var ident = [_]u8{0} ** 16;`) gained an
  explicit `[N]T` annotation. 107 lines were rewritten by a pattern rewrite and
  4 by hand. The two string repeats are written out: `strings` now *teaches*
  repetition as `const dashes: [5]u8 = @splat('-');` plus `&dashes` for the
  slice, and `security` builds its oversized inputs the same way.
- **Struct reflection is struct-of-arrays (3 files).** `@typeInfo(T).@"struct"`
  no longer has a `fields` slice of records. It has parallel `field_names` /
  `field_types` / `field_attrs` slices, and `std.meta.fields` is now a
  `@compileError`. `macro_systems` iterates
  `inline for (names, types, 0..) |name, FieldType, i|`, and its tuple walker
  reads `field_names` directly. `type_systems` and
  `trait_and_typeclass_systems` count `field_names.len`, and the former now
  also asserts a field's type.

### Fixed — a semantic change the compiler only half-caught

- **`@hasDecl` sees only `pub` declarations.** Before 0.17 it also returned
  true for a private declaration when the check sat in the same file.
  `trait_and_typeclass_systems` checked its shapes' private `area()` /
  `name()` that way, and the example's own comment taught the old rule ("checks
  both public and private declarations"). Under 0.17 the comptime constraint
  rejected `Circle`. That was a compile error *here* only because the check
  feeds a `@compileError`. A `hasMethod` used as a plain boolean would just
  have flipped. The six interface methods are now `pub`, and the comment
  states the rule, including why the old one was a trap: a constraint could
  pass in its own file and fail for every other caller.

### Changed — off 0.17-deprecated API (compiled, but taught the old spelling)

- `std.heap.DebugAllocator` → **`std.heap.SafeAllocator`** (11 sites, 10 files):
  `var gpa: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});`.
  `deinit` now returns a leak *count* rather than `.ok` / `.leak`, so
  `ownership_and_borrowing` asserts `leaks == 0`. Its history note now reads
  GeneralPurposeAllocator (≤0.15) → DebugAllocator (0.16) → SafeAllocator
  (0.17).
- `std.fmt.allocPrint` → **`allocator.print`**, and `std.fmt.bufPrint` →
  **`std.mem.print`** (`strings`, `code_generation`).
- `@import("builtin").os` → **`@import("builtin").target.os`**
  (`module_systems`). The old form is slated for removal in 0.18.

**How the deprecations were found**: the 0.17 std was scanned for every public
name under a `/// Deprecated` doc comment (221 names), and the corpus was
grepped for each one. That turned up the five real uses above, plus false
positives on local names (`ElfConst.ELFCLASS64`, a `resolve` method, a
`b.path` comment). The release notes' other silent changes do not apply here.
Every `@bitCast` in the corpus is scalar ↔ scalar or packed struct ↔ integer,
which 0.17 leaves unchanged. No example bitcasts an `extern struct`, and none
calls `containsAtLeastScalar`.

### Changed — CI

- `ZIG_VER` **0.16.0 → 0.17.0**, and the download is now **sha256-verified**
  against the checksum `ziglang.org/download/index.json` publishes. Before,
  the step ran whatever the URL returned, and a bad download would surface as
  unrelated compile errors 77 files later. The step's comment records what
  0.17 changed.
- Version stamps: `README.md`, `docs/sources.md`,
  `docs/development/content-format.md`, `docs/guides/getting-started.md`,
  and the roadmap's pin-maintenance row and header.

## [2.8.6] — 2026-10-23

Dependency cut. **cyrius 6.6.2 → 6.6.20** and **vyakarana 2.4.0 → 2.4.3**, the
last vyakarana tag on the 6.6.20 pin. The folded stdlib leaves move with the
snapshot: sakshi 2.5.1 → 2.5.7, bayan 1.5.5 → 1.5.12, sandhi 1.9.16 → 1.10.8,
sigil 3.12.16 → 3.13.10. No content added (77 topics / 847 examples, 0 gaps)
and no source change: `cyrius test` **139/0**, 12 benchmarks green,
`cyrius lint` / `cyrius fmt --check` output identical to 6.6.2 on both
`src/` files.

**Output is byte-identical to the 2.8.5 build.** Two checks against the 6.6.2
binary: 8.6 MB of CLI output (`info` × 77, `code` × 847, which covers every
example through vyakarana, plus `list` / `stats` / `gaps` / `languages` and five
searches) and 11 `serve` endpoints, including the escaped-query and 404 paths.

### Changed — cyrius 6.6.2 → 6.6.20

The declared stdlib set is unchanged (25 modules). The snapshot under it is
not: every declared module except `ct` changed content, and 59 of the 65
previously vendored files moved. Largest source growth: `sigil` +211,769 B,
`tls` +51,743, `bayan` +42,110, `process` +35,709, `net` +35,493, `io`
+34,300, `sandhi` +32,822.

**Binary 2,457,488 → 2,683,032 B (+225,544, +9.2 %).** To attribute it, we
built the 6.6.20 compiler against the **6.6.2** lib through a synthetic
`CYRIUS_HOME`. That build is 2,449,288 B, so the compiler made the binary
**8,200 B smaller** and the snapshot added **233,744 B**. Most of the snapshot
growth is code vidya never reaches. Unreachable bytes went 979,196 →
1,075,594 and a `CYRIUS_DCE=1` build is 1,605,784 B. Accepted for the same
reason as 2.8.4's `bayan` growth: DCE is a build-wide switch, not a per-module
opt-out.

`lib/` went **65 → 73 files**, all transitive: `async` plus its `_agnos` /
`_macos` / `_win` variants (via sandhi), `random` and `sys` (via sigil),
`tls_hostid` (via tls), and `alloc_cx` and `poison` (via alloc). `assert.cyr`,
the test-assertion library 2.8.4 noted entering the binary, is no longer
vendored. One visible side effect: the **five long-expected
`undefined function` warnings** (`random_bytes`, `async_new_in`,
`async_spawn`, `async_run`, `async_await_readable`) no longer fire. Their
definers are now vendored. Nothing calls them, so they are DCE-dead. The 6.6.2
note about an oversized array local is now a warning located at
`lib/sigil.cyr:28046`, a 256 KiB crypto-bank buffer that `serve` never
reaches.

**The pin bump now requires a clean rehydrate.** Done in place, `cyrius lib sync`
refreshes only the declared subset and re-locks at the new pin. `cyrius deps`
then **refuses** the 15 transitive leaves still holding 6.6.2 content
(`atomic`, `hashseed`, `result`, `boxed`, `slice`, `freelist`, `mmap`, the
`thread*` and `sync*` families): "cyrius.lock and the pinned stdlib snapshot
DISAGREE". `cyrius deps --relock` gets past the refusal but leaves the
orphaned 6.6.2 `assert.cyr` vendored and locked. The sequence that works is
`rm -rf lib cyrius.lock && cyrius lib sync && cyrius deps`. CLAUDE.md's
toolchain table had called this belt-and-braces since 2.8.1, and now says it
is required. Overwriting a stale *declared* module still works as before:
`fmt.cyr` was re-verified at 6.6.20.

### Changed — vyakarana 2.4.0 → 2.4.3

2.5.0 moves vyakarana to cyrius 6.7.9, so 2.4.3 is the newest tag on this pin.
Two of the three steps are vyakarana's own toolchain bumps (2.4.1 → 6.6.2,
2.4.3 → 6.6.20) with no source change. 2.4.2 renames the private
`_stream_grow` to `_vyk_stream_grow` because it collided with sankoch's. vidya
does not vendor sankoch, so that collision never reached it. At 2.4.3 the
bundle gains a `# Requires` block, and its `.deps` sidecar now lists 4 leaves
instead of 11, dropping `args`, `assert`, `fs` and `hashmap`. vidya declares
the three of those it uses itself, so nothing depended on the sidecar. The
public API is unchanged, with no call-site edits, and `code` output is
byte-identical across all 847 examples (see above).

### Benchmarks — two rows moved, and neither is real

Interleaved A/B on one machine: three alternating rounds per pin, each pin
built from its own tree.

| Bench | 6.6.2 mean | 6.6.20 mean | Δ mean | per-round Δ |
|---|---|---|---|---|
| load_concept | 51.478 µs | 51.724 µs | +0.5 % | +3 / +1 / −2 % |
| load_all | 8.313 ms | 8.051 ms | −3.2 % | −4 / −3 / −3 % |
| reg_get_hit | 93 ns | 91 ns | −2.5 % | −3 / −1 / −3 % |
| reg_get_miss | 241 ns | 87 ns | **−64.0 %** | −64 / −65 / −63 % |
| search_text | 5.933 µs | 5.727 µs | −3.5 % | −4 / −1 / −5 % |
| search_text_exact | 11.436 µs | 11.175 µs | −2.3 % | −2 / −3 / −3 % |
| toml_sections | 1.883 µs | 2.082 µs | **+10.6 %** | +10 / +12 / +10 % |
| json_info_response | 9.319 µs | 9.241 µs | −0.8 % | −1 / −1 / −0 % |
| json_search_response | 255.195 µs | 249.278 µs | −2.3 % | −2 / −2 / −3 % |
| json_list_response | 114.790 µs | 113.365 µs | −1.2 % | −2 / −2 / −0 % |
| field_escaped | 3.399 µs | 3.379 µs | −0.6 % | −2 / −1 / +1 % |
| field_raw_splice | 597 ns | 567 ns | −5.0 % | −5 / −5 / −5 % |

Both outliers held their direction in all three rounds, which made them look
real. A harness-free loop showed they are not. It timed 10⁶ `map_get` misses,
10⁶ hits and 10⁵ × 3 `toml_get_sections` calls with `clock_now_ns`, taking the
best of five, across **five separate processes per pin**:

- **`toml_sections` is ~3 % *faster* at 6.6.20**, not 10 % slower: 1.99–2.01 µs
  at 6.6.2 vs 1.93–1.95 µs at 6.6.20, with no overlap. The +10.6 % comes from the
  harness. `lib/bench.cyr` was rewritten between the pins (20,668 → 55,545 B).
  The 6.6.2 version subtracted a scalar timer floor from every per-sample
  minimum, which the 6.6.20 file's own 6.6.5 entry calls "a mean subtracted
  from a minimum" and shows is biased. On a ~2 µs op, a misplaced 1.3 µs floor
  is a 10 % error.
- **`reg_get_miss` has no pin effect.** Under the harness-free loop it ranged
  from **49 to 611 ns per process at *both* pins**. `lib/hashmap.cyr` has seeded
  its hash from `getrandom` on every process since cyrius 6.5.39 (the
  hash-flooding fix), so the probe-chain length for one fixed missing key
  changes with the seed. This bench row measures which seed was drawn, and
  three short chains in a row produced the −64 %. The 6.6.2 harness was
  bimodal on the same row too: 98 ns in one run, 484 ns in the next.
- `reg_get_hit` holds at ~85–87 ns under both harnesses, as expected for a hit
  on the first probe.

**Consequence: `target/bench-history` snapshots from 2.8.5 and earlier are not
comparable with 2.8.6 onward.** The measuring instrument changed, separately
from anything it measures. A fresh baseline is recorded at
`target/bench-history/20261023-171301-9745d59.txt`.

### Known — host Zig 0.17.0 fails 37 of 77 Zig examples (CI unaffected)

With this host's Zig (0.17.0, upgraded by pacman on 2026-10-21), the strict
content gate ran **810 passed / 37 failed / 0 skipped**, and every failure is
a `zig.zig` file. The corpus and CI pin **Zig 0.16.0** (`ZIG_VER` in `ci.yml`).
Re-run under 0.16.0, taken from the pacman package cache, all **77/77** Zig
examples pass, so the gate is **847/847** on the CI toolchain set. All 77
Cyrius examples pass under 6.6.20. The 0.17.0 errors are 34 × "binary
operator '*' has whitespace on one side, but not the other" and 6 × std
`no field named` renames, plus two one-offs: a `@typeInfo` deprecation and a
comptime interface check. Porting the
corpus to 0.17 is separate content work, not part of this dependency cut.

## [2.8.5] — 2026-09-11

### Changed

- **Toolchain `6.5.35` → `6.6.2`.** No source change; the value form needed none.
  Build, tests, and any bench/fuzz/distlib target the repo ships re-verified at the new pin.


## [2.8.4] — 2026-08-22

Dependency cut. **cyrius 6.5.31 → 6.5.35**, **vyakarana 2.3.2 → 2.4.0**, sakshi
unchanged at 2.4.11. No content added — the corpus stays 77 topics / 847
examples, 0 gaps — and no source change was required: `cyrius test`
**139/0**, 12 benchmarks green, content gate **847/847 with zero skips**
under `VIDYA_STRICT=1`.

The whole cut is one number: **the binary grew 2,564,472 → 2,772,568 B
(+208,096, +8.1 %)**, and all of it is a stdlib module vidya barely uses.

### Changed — cyrius 6.5.31 → 6.5.35

The snapshot's module **list** is identical either side (102 modules), and
exactly **three files tree-wide** changed content: `bayan`, `patra`, `vani`.
Only `bayan` is one of the 25 modules vidya declares; every other declared
module is byte-identical, sha256-verified per module.

`bayan` is not a small change. It nearly **tripled** — 215,533 → 641,083 B,
+368 functions — absorbing a PDF subsystem (`_pdfc_*`, `_pdfe_*`, `_pdff_*`,
`_pdfg_*`). vidya reaches bayan only for TOML and JSON, so every byte of that
is unreachable from `main()`. **cyrius does not run DCE by default, so it
ships anyway**: unreachable functions 2,546 → 2,931, unreachable bytes
721,478 → 869,883.

Attributed by building the 6.5.35 compiler against the **6.5.31** lib tree:
**2,548,088 B**. So 6.5.35's band F register-allocator work made the binary
**16,384 B smaller**, and the stdlib growth added 224,480 B on top of that.
Accepted rather than worked around — `CYRIUS_DCE=1` is a build-wide behaviour
change, not a per-module opt-out, and the corpus loader is not the place to
run that experiment for the first time in a release. Still **−81.1 %** against
2.8.0's 14.66 MB.

`lib/` also went **62 → 63 files**: `assert.cyr` is now vendored. Nothing was
declared to cause it and neither `sakshi` nor `alloc` changed content — the
transitive resolver simply started chasing `sakshi`'s `panic()` and `alloc`'s
`fail_after_n_allocs()` into it. Worth noting what it is: a **test assertion
library**, now linked into the shipped binary. Harmless — DCE-dead, and
`panic` is a real fatal path — but it is the arc reaching further on its own.

6.5.35's headline is codegen (the register allocator finally time-shares
registers, via loop-aware liveness). vidya's evidence that this is safe here
is the gate, not the upstream release notes: 139 assertions, 12 benchmarks,
847 examples, all unchanged.

### Changed — vyakarana 2.3.2 → 2.4.0

A **minor**, and the minor is earned: 2.4.0 changes streaming token
*boundaries*. It fixed five independent root causes that made a chunk-fed
consumer disagree with a whole-buffer consumer on **13 of 20** corpus files —
a divergence the pre-existing `fuzz/streaming.fcyr` never caught because its
inputs were short synthetic strings. 15 of 20 grammars are now chunk-invariant
at every chunk size tested, up from 7.

**None of it reaches vidya, by construction.** `render_code`
(`src/vidya_core.cyr:942`) makes exactly one `tokenize_stream_feed` call with
the entire file and then `_finish` — that is the whole-buffer path 2.4.0
corrects the chunked path *against*. The public API
(`tokenize_stream_new` / `_feed` / `_finish` / `_free`, `tokenbuf_*`,
`kind_name`) is unchanged, so no call site moved. Verified live: `vidya code`
still colours through the vyakarana path.

### Changed — CI action majors, 3–4 versions behind

`actions/checkout` **v4 → v7**, `actions/upload-artifact` **v4 → v7**,
`actions/download-artifact` **v4 → v8**, `softprops/action-gh-release`
**v2 → v3**. Every one of those majors is fundamentally a Node 20 → Node 24
runtime move requiring Actions Runner ≥ 2.327.1, which GitHub-hosted
`ubuntu-latest` satisfies.

The two candidate breakages were checked rather than assumed, and neither
applies:

- **`download-artifact` v5's breaking path change is by-ID only.** It fixed
  `artifact-ids:` downloads extracting to `path/<name>/` instead of `path/`.
  `release.yml` downloads by `name:`, which upstream's own migration guide
  lists explicitly under *"no action needed"*.
- **`upload-artifact` v7's new `archive:` input is opt-in**, and multi-file
  globs with an explicit `name:` — what `release.yml` does — are unchanged.

⚠ **This was ecosystem-wide staleness, not a vidya oversight.** sit, hoosh,
vyakarana, sakshi and sandhi were all still on the identical `v4`/`v2` pins as
of 2026-08-22, so vidya is now deliberately ahead rather than accidentally
divergent. What the others need is written up in
[`docs/development/ecosystem-action-pins.md`](docs/development/ecosystem-action-pins.md).
cyrius itself pins actions by full commit SHA, which is the stronger pattern
if this ever needs security hardening rather than currency.

The Zig content pin was checked in the same sweep and is **already current** —
CI installs 0.16.0 and 0.16.0 is the latest release.

### Fixed — two recorded numbers that were wrong

- **The 2.8.3 binary size in `docs/development/state.md` was wrong by 168 B.**
  It recorded 2,564,304; HEAD at the 6.5.31 pin actually builds **2,564,472**,
  verified byte-for-byte against the committed `build/vidya`. The 2.8.4 delta
  above is measured against the real number.

- **The field-notes index had rotted badly.** `content/cyrius/field_notes/index.cyml`
  claimed the `compiler/` set held **46 entries** with `gotchas.cyml` at
  **12**. The real counts are **180** and **123**, and six retro files were
  missing from the listing entirely. Re-derived, with the derivation command
  recorded inline so the next reader regenerates rather than restates. The
  verification range also moved 6.4.10 → **6.5.35**.

### Benchmarks — flat, and a stored-baseline trap worth recording

Against the stored 2026-08-20 baseline, `load_all` appeared to regress
**+29 %** (5.937 → 7.68 ms) and `reg_get_miss` **+30 %**. Neither is real.
Swapping only `bayan.cyr` back to its 6.5.31 copy reproduced the same 7.69 ms,
and an **interleaved A/B of the two compilers on the same box** — two rounds,
alternating — put them on top of each other:

| | load_all | reg_get_miss |
|---|---|---|
| 6.5.31 compiler | 7.684 / 7.713 ms | 524 / 523 ns |
| 6.5.35 compiler | 7.624 / 7.726 ms | 511 / 514 ns |

The pre-bump configuration is exactly as slow on this box today, so the delta
belongs to the measurement environment, not the release. This is the failure
mode cyrius 6.5.35's own CHANGELOG documents against itself — **A/B the two
binaries interleaved rather than comparing against a stored number.** The
first run here was additionally taken while the 847-example content gate was
saturating the box, which is how it got noticed.


## [2.8.3] — 2026-08-20

Toolchain bump, a corpus-wide example review, and four new gate checks. No
content added — the corpus stays 77 topics / 847 examples, 0 gaps — but a
large share of it changed, because a 96-agent review found **80 verified
defects sitting behind a green gate**.

- **Cyrius 6.5.29 → 6.5.31**, and the C standard C17 → **C23**.
- **Example review, Tiers 1–4**: memory-safety bugs, tests that could not
  fail, and code that taught the opposite of its own subject. Each was
  reproduced as a failure, fixed, then re-reproduced against the fix.
- **Four gate checks added**, each closing a class rather than a defect.
- Binary 2,563,160 → 2,564,304 B. `cyrius test` 139/0, 12 benchmarks,
  content gate **847/847 with zero skips**.

**The headline is not the count of fixes — it is what the gate could not
see.** `847/847 green` was true throughout, and simultaneously: a C parser
had six unbounded `memcpy`s, three security suites could not fail, an
OpenQASM reset never fired in 2059 of 4000 shots, and the file teaching
position-independent code emitted 12 absolute relocations while claiming
they were RIP-relative. Compiling and exiting 0 is a much weaker guarantee
than it appears.

### Fixed — CI

- **The C23 move broke CI for eight commits while passing locally.** I measured
  "77/77 compile and run under `-std=c23`" on **gcc 16.2.1** and generalised it
  to the corpus, without ever checking the compiler CI uses. `ubuntu-latest`
  ships **gcc 13.2**, which rejects `-std=c23` outright:
  `unrecognized command-line option '-std=c23'; did you mean '-std=c2x'?`
  Every Content Validation run from the first example-review commit onward
  failed on the first C file.

  The corpus itself was fine — reproduced in a `gcc:13.2` container, all
  **77 C examples compile and run under `-std=c2x`**, which selects the same
  standard (`__STDC_VERSION__` is 202311 for both spellings). Only the flag
  name was wrong. Both validators now **probe**: `-std=c23` where the compiler
  accepts it, `-std=c2x` otherwise. Verified selecting `c23` locally and `c2x`
  in the gcc 13.2 container, compiling a real example in each.

- **The TypeScript gate resolved `tsc` once instead of 77 times.** The first
  form was `npx -y -p typescript@latest tsc` *per file* — 77 npx resolutions,
  each able to reach the registry. It now prefers an installed binary
  (`$(npm root -g)/typescript/bin/tsc`, or `VIDYA_TSC`) and only falls back to
  npx when none exists: 0.03s vs 0.44s per file, and no network dependency in
  the common case.

### Added — four gate checks

Every one of these had already let a real defect through, and each is
mirrored in **both** validators (`scripts/validate-content.sh` and
`validate_command` in `src/vidya_core.cyr`), which had themselves drifted
twice this cycle.

- **Rust: an additive `--test` pass** for files carrying `#[test]` /
  `#[cfg(test)]`. Without it, 116 of 201 lines in `testing/rust.rs` were
  never compiled — a deliberate type error *and* a false assertion both
  printed "All testing examples passed".
- **Go: `gofmt -l` then `go vet` before `go run`.** Seven files shipped a
  redundant-newline `Println` past the gate; 47 were unformatted.
- **TypeScript: `tsc --noEmit --strict` before running.** `tsx` strips types
  and never checks them, so the corpus had never been type-checked. Two real
  defects surfaced (`TS2367`, comparisons the checker proves impossible).
- **Python: `-X warn_default_encoding -W error::EncodingWarning`.** An
  encoding-less `open()` is a portability bug the corpus's own concept.toml
  warns about, and a plain run cannot see it.
- **Cyrius: any `duplicate fn` now fails.** Not cosmetic —
  `gpu_memory_pooling` shadowed the stdlib `alloc` and segfaulted the moment
  a stdlib allocation was added. Nine further shadows of `chan_send`,
  `is_digit`, `sock_bind`, `_scan_ident` and friends were renamed.

⚠ **What the gate still cannot see**: comment-level falsehoods, semantics it
never executes (no OpenQASM circuit is simulated), and anything a language's
own tooling does not flag. That boundary is now written into `CLAUDE.md`.


### Fixed

Tier 4 of the example review — the tail, 27 findings across seven language
groups. Each was reproduced before being fixed. Highlights:

- **C**: six `p = realloc(p, n)` self-assignments across three files leaked the
  original block on failure — `gcc -fanalyzer` traced CWE-401 in each, one of
  them in `memory_management/c.c`, whose subject *is* leak avoidance. Also
  `boot_and_startup/c.c`'s `1 << 31` (the corpus's only UBSan hit) and ~12
  unchecked fallible I/O returns in `input_output` / `page_management` —
  captured into variables rather than wrapped in `assert()`, which `-DNDEBUG`
  would delete along with the call.
- **Rust**: `type_systems/rust.rs` byte-sliced a `String` at a fixed offset —
  byte 50 lands inside a 🦀 — while `strings/rust.rs:48` warns against exactly
  that. `concurrency/rust.rs` used `Arc` inside `thread::scope`, against its own
  concept.toml. The `atomic::fence` label was corrected: measured with
  `--emit asm`, `fence` emits `lock orl $0, -64(%rsp)` (a hardware barrier)
  while `compiler_fence` emits only `#MEMBARRIER` — it was mislabelled as the
  latter.
- **Go**: `iterators/go.go` advertised `iter.Seq` and never imported `iter`;
  `bloom_and_glow` shadowed the 1.21 `clear` builtin; `tracing:191` panicked on
  any caller-supplied context while two sibling sites used comma-ok. Two
  performance claims were **measured and found wrong**: index-vs-range loops
  compile to *byte-identical* machine code (both 27 bytes, same instruction
  sequence), and the "~50 element" slice/map crossover measures ≈14 on a miss
  and ≈37 on a hit.
- **Zig**: `allocators/zig.zig`'s bump allocator aligned the *offset*, not the
  *address* — its `%8==0` assertion passed only because the backing array
  happened to sit favourably; with a deliberately odd base the old code returns
  `addr%8==1`. `performance/zig.zig` claimed sentinel slices "avoid bounds
  checks"; indexing past the sentinel panics with
  `index out of bounds: index 12, len 11`.
- **Shell**: unquoted expansions in trap/xargs strings — under a `TMPDIR` with
  a space, `concurrency/shell.sh` failed outright and two others leaked a temp
  directory every run while exiting 0. Fixed and verified against a
  from-source **bash 3.2.57** that the files needing ≥ 4.0 features are now
  annotated as such.
- **Assembly**: `filesystems/asm_x86_64.s` wrote 13 bytes of a 14-byte literal
  and then read 13 back, so the dropped newline was invisible; the AArch64
  sibling said 14, which showed the intent.

### Fixed — Cyrius `&local` is not a dangling pointer, and that is worse

Four files described a returned `&local` as a "dangling stack pointer". It is
not: Cyrius gives every local a **fixed address**, so the pointer never faults.
An initial correction swung too far the other way — "the pointer stays readable
forever, so nothing crashes" — which is also wrong, and would send a reader
after the wrong workaround. Measured, there are **two** silent hazards:

1. **Aliasing** — every call returns the same address, so a second call
   overwrites the first call's object.
2. **Frame reuse** — the compiler overlays frames, so an *unrelated* function's
   local can occupy that address. A helper returning `&local` read back `4242`,
   then `999888` after a single call to an unrelated function.

All five files now say this, consistently: `projectile_physics`,
`sprite_rendering`, `state_machines`, `game_ai_decisions`, and
`ownership_and_borrowing` — the last of which was untouched by the tier and had
drifted out of agreement with the other four. The two heap-allocating
constructors that were dead code now have tests asserting that two calls return
**distinct** objects, so the fix is exercised rather than merely present.

Also fixed: `input_output/cyrius.cyr` told `file_read_all` a 16-byte buffer held
128 (`var buf[N]` reserves N **bytes** — measured `&b - &a` = −16 for `[16]`);
`strings/cyrius.cyr:57` documented a `str_replace` call shape that compiles,
exits 0, and silently returns the string unchanged.

Tier 3 of the example review (crypto naming + error propagation).

- **The stubbed "AEAD" was named as if it were real, in all 10 ports.**
  `aeadSeal` / `aeadOpen` / `computeTag` sit in `tls_and_encryption` next to
  `TLS_AES_256_GCM_SHA384` and a `concept.toml` that says *"Use AEAD ciphers
  exclusively… don't compose your own"*. The tag is a byte **sum**, so it is
  permutation-invariant: swapping bytes 9 and 12 of `"transfer 10 usd"` gives
  `"transfer u0 1sd"` with an **identical tag** (sum 1362 → tag 1407 with the
  file's key=42/nonce=7), and the "authenticated" open accepts the forgery.
  Only the Cyrius port disclaimed the stub at all, and its disclaimer was
  itself wrong — it claimed "any byte flip in ciphertext or AAD changes the
  tag", which holds for a flip but not for a permutation.

  Renamed across all ten to `demoSeal` / `demoOpen` / `weakChecksum` (native
  casing per language; the two assembly ports also renamed their `.ct_*`
  local labels, and shell's `AEAD_OK` → `DEMO_OK`). Each port now carries a
  disclaimer naming the exact weakness and pointing at AES-GCM /
  ChaCha20-Poly1305. **The algorithm is deliberately unchanged** — the eleven
  ports mirror one scenario and most have no crypto available under the
  validator (Rust links no crates, C has no `-lcrypto`, the assembly ports
  have nothing), so making one port real would break the mirror. Naming and
  disclaiming was the fix. Verified: zero remaining occurrences of the old
  identifiers anywhere including comments, printed strings and asm labels;
  every surviving mention of "AEAD" is contrast prose; and filtering comments
  out of the diff leaves only rename lines — no arithmetic, signature or
  assertion changed. 10/10 ports green.
- **`content/error_handling/c.c` discarded the error it was propagating.**
  The `goto cleanup` label ended `return ERR_NOT_FOUND` unconditionally, so a
  config with a host but an unparseable port produced `ERR_PARSE` inside
  `parse_port` and handed the caller `ERR_NOT_FOUND` — in the topic that
  exists to teach error propagation, on the one path that lost it. The cause
  now travels in `rc`; two assertions pin it (`ERR_PARSE` for `port=abc`,
  `ERR_INVALID` for `port=99999`). The Rust and Go siblings already did this.
- **`content/error_handling/shell.sh` taught a false `set -e` exemption and
  shipped an inert trap section.** It listed subshells as a case `set -e`
  misses "depending on shell version" — measured on bash 5.3,
  `set -e; ( false ); echo reached` exits 1 **without printing** — and then
  contradicted itself 55 lines later by relying on `|| parent_ok=caught`.
  Separately, none of `cleanup_ran` / `error_trapped` / `parent_ok` was ever
  asserted, and `trap - EXIT ERR` disarmed the EXIT trap before the script
  ended, so `cleanup` never ran at all. The claim is corrected and the traps
  are now observable: the ERR trap is triggered and asserted, and the EXIT
  trap is demonstrated from a spawned shell — the only place it can be seen,
  since it fires as its own process exits.

Tier 3 of the example review (cross-language).

- **Three C files taught the subtraction `qsort` comparator.**
  `return *(const int *)a - *(const int *)b` overflows when the operands are
  far apart, producing a comparator that contradicts itself. Measured at `-O2`
  on `{2000000000, -2000000000, 0, 1000000, -1000000}`: the array comes back
  **NOT SORTED**, with `-2000000000` last. Replaced with the three-way
  `(x > y) - (x < y)` in `algorithms`, `iterators` and `type_systems` — the
  same overflow class `algorithms/concept.toml` already warns about for
  binary-search midpoints.
- **`content/algorithms/cyrius.cyr` used its own topic's `bad_example`.**
  Line 69 was `var mid = (lo + hi) / 2;` — character-for-character the
  `bad_example` in `algorithms/concept.toml`, whose `good_example` is
  `lo + (hi - lo) / 2`. Every other classical port already used the safe form.
- **`content/linking_and_loading/go.go` was the corpus's only genuinely
  nondeterministic example.** It assigned section base addresses while ranging
  a map, and Go randomises map iteration — 6 runs produced 2 distinct outputs.
  Now iterates a canonical link order (`.text`, `.rodata`, `.data`, `.bss`,
  then the rest alphabetically). Sorting alphabetically would have put `.data`
  before `.text` and taught ELF layout backwards. Two symbol-table loops were
  sorted for the same reason. 10 runs now produce one output.
- **`content/ownership_and_borrowing/go.go` taught a pre-1.22 workaround as
  current idiom.** It used `i := i` with the comment "(Go idiom)" and the
  assertion message "loop var shadowed correctly". Go 1.22 (Feb 2024) gives
  each iteration a fresh variable for both 3-clause and range loops — verified
  on this toolchain, closures capture correctly with no shadow. Removed; the
  history is kept, because *why* the idiom existed is the interesting part.
- **Four stale Zig API references.** `concurrency/zig.zig` opened with "No
  async/await runtime in the standard library (removed in 0.14+)" — but 0.16's
  `std.Io` documents "async, await, concurrent, and cancel", and the file
  itself uses `std.Io.Threaded` on line 81. Also corrected:
  `std.time.nanoTimestamp` (gone; `std.time` is duration constants and the
  clock moved to `std.Io.Clock.Timestamp.now`), `GeneralPurposeAllocator`
  (renamed `DebugAllocator`), and `std.crypto.utils` (now
  `std.crypto.timing_safe`). All three were in comments, which is why they
  compiled.
- **`content/ownership_and_borrowing/zig.zig`'s errdefer section had no
  errdefer.** `buildResource` returned `?Resource` — an optional, so `errdefer`
  could not apply even in principle — contained none, faked the cleanup with a
  manual assignment, and printed "errdefer cleaned up". Now returns `!Resource`
  with a real `errdefer` whose effect is observable through a counter the
  caller asserts on both paths. Neutering the errdefer body now aborts.
- **`content/pattern_matching/cyrius.cyr` defined `classify` twice.** The
  compiler warns "last definition wins", but resolution is **positional**: the
  body a call site gets depends on where it sits relative to the second
  definition. Moving a test function below it turned 20 passed / 0 failed into
  17 passed / 3 failed with no assertion edited. Second one renamed
  `classify_match`.

### Changed

- **Go: `gofmt` sweep (47 files) and `go vet` clean (7 files).** Seven
  `fmt.Println("…\n")` calls tripped vet's redundant-newline check; rewritten
  as `fmt.Printf` so the output stays byte-identical. All 77 Go examples now
  pass `gofmt -l` and `go vet`. Verified by capturing stdout for all 77 before
  and after: **76 byte-identical**, the one difference being
  `syscalls_and_abi`, which prints a live PID by design.

Tier 3 of the example review (quantum + validator lockstep). OpenQASM files
parse cleanly and the gate never **simulates** them, so semantic defects here
shipped green. Everything below was measured on a simulator.

- **`content/kernel_topics/openqasm.qasm`: the qubit reset never fired.** In
  OpenQASM 2.0 `if(creg==N)` compares the **whole register** as an integer.
  With a 2-bit `mem_check` and an entangled `(|00⟩+|11⟩)/√2` state the
  measurement is only ever `00` or `11`, so `if(mem_check==1)` — binary `01` —
  was never true. Simulated: **2059 of 4000 shots** came back with both qubits
  still `|1⟩` while the section claimed they had been reset to `|0⟩`. Split
  into per-qubit 1-bit registers so each comparison is a real bit test:
  **4000/4000** now reset correctly.
- **`content/qelib1.inc` is never read, and said so nowhere.** `qasm2.load`
  special-cases that filename and substitutes its own built-in table.
  Verified: replacing the file with invalid QASM, or deleting it, changes
  nothing — every example still loads. So its 42 gate definitions were
  documentation being mistaken for the resolution set. The practical
  consequence is a real trap: `swap` is defined on line 61 and yet
  `'swap' is not defined in this scope` at load time. Both validators now
  pass `custom_instructions=qasm2.LEGACY_CUSTOM_INSTRUCTIONS`, which restores
  the legacy set so the file and the loader agree (77/77 still load under
  `strict=True`), and the file carries a banner explaining the substitution.
- **Two files propagated the wrong reason for it.**
  `projectile_physics` blamed `qelib1.inc` for omitting `swap` (it defines
  it); `package_resolution` claimed there is no `cz` — measured, **`cz` is
  accepted by default**. Both comments corrected.

### Fixed — validator lockstep

`scripts/validate-content.sh` and `src/vidya_core.cyr`'s `validate_command`
must stay in step; they had diverged for two languages, and in both cases the
shipped `vidya validate` CLI silently skipped work the shell gate ran.

- **AArch64**: the CLI probed only `qemu-aarch64` while the shell accepts
  `qemu-aarch64-static` too — so on a `qemu-user-static` host the CLI skipped
  all 77 AArch64 examples. It now accepts either.
- **OpenQASM**: the CLI hardcoded bare `python3` while the shell prefers
  `.venv/bin/python3`. With qiskit installed in the venv, the CLI reported
  "toolchain not installed" and skipped. It now prefers the venv too.
  `vidya validate quantum_computing` goes from **10 passed / 1 skipped** to
  **11 passed / 0 skipped**.

### Verified rather than assumed — no change made

- **Both Grover implementations are correct.** Simulated: `quantum_computing`
  finds `|101⟩` with probability **0.948** (theory for 2 iterations at N=8 is
  ≈0.945) and `algorithms` finds `|11⟩` with probability **1.000**. A reported
  "tops out at 0.625" did not reproduce, so neither file was touched.

Tier 3 of the example review (assembly) — code that taught something false.
Every claim below was measured with `readelf`, `objdump` or a live probe,
not argued from the source comments.

- **`content/linking_and_loading/asm_x86_64.s` had position-independent code
  exactly backwards.** It taught that "`[symbol]` in Intel syntax defaults to
  RIP-relative" and "emits a R_X86_64_PC32 relocation". `readelf -r` on the
  shipped file: **12 `R_X86_64_32S`, zero `PC32`**. In GAS Intel syntax a bare
  `[symbol]` is an *absolute* reference; `[rip + symbol]` is required. This is
  the PIC topic, so the file was teaching the opposite of its subject. Now 11
  `PC32` and exactly one `32S` — that one deliberately kept and labelled, so
  `readelf -r` shows the contrast the prose describes.
- **`content/instruction_encoding/asm_x86_64.s` documented an encoding it did
  not emit.** The comment gives `mov rax, [rip+disp32] → 48 8B 05 …` with
  `ModR/M: 05`, then writes `mov rax, [value]`, which assembles to
  `48 8B 04 25 …` — ModR/M `04` (SIB follows) plus SIB `25`, two extra bytes
  and an absolute address. Corrected; `objdump -d` now shows the documented
  `48 8b 05`, and the difference is explained rather than papered over.
- **Three files claimed the wrong stack alignment at `_start`.** The System V
  psABI guarantees **16-byte** alignment at process entry; the files said 8.
  Measured with `mov rax, rsp; and rax, 15` → 0. Worse, `syscalls_and_abi`
  then did `push rax  # align stack (now 16-byte aligned)`, which takes rsp to
  8 mod 16 and **breaks** alignment for the following `call` — a callee
  spilling with `movaps` would fault. The push/pop pair was wrong in both
  directions and cancelled out. All three now state the rule correctly and
  *assert* the alignment; `kernel_topics` and `memory_management` had computed
  `rsp & 0xF` and then thrown the answer away.
- **Callee-saved registers clobbered across `bl` (AAPCS64).**
  `framebuffer_rendering`'s `draw_hline`/`draw_vline` kept a loop counter in
  x23 across a call while saving only x19-x22 — and shipped the abandoned
  reasoning as comments: *"wait, fb_set IS called. Need i in callee-saved."*
  and *"fall through — we already accidentally use x4. Fix: use x23 above +
  add stp."* `consensus`'s `run_election` used x21/x22 unsaved beneath a
  comment calling x21 **"caller-saved"** — it is callee-saved.
  `reproducible_builds`'s `build_digest` kept three arguments in x24-x26
  across a `bl` (correct technique) without saving them (the bug). All fixed
  with correct frames; the dead `mov x0, x21` in `draw_hline` is gone.
- **Documented, not "fixed": `grid_pathfinding`'s shared x22.** `bfs_relax`
  and `astar_relax` update x22 as a caller-owned queue cursor. That is a
  deliberate local convention rather than a slip, so it is now stated as one,
  with a warning that these helpers cannot be lifted into a library unchanged.

Tier 2 of the example review — tests that could not fail. Every item was
proven by sabotage: break the thing the test exists to check, confirm the
suite still reported success, fix, then confirm the same sabotage now fails.

- **`content/testing/rust.rs`: 116 of 201 lines were never compiled.**
  Everything behind `#[cfg(test)]` — 11 `#[test]` functions — is invisible to
  a plain `rustc` build. A deliberate type error *and* a false assertion
  inside `mod tests` both compiled clean and printed "All testing examples
  passed". Both validators now make an **additive** `--test` pass for files
  matching `#[test]` / `#[cfg(test)]`; the type error surfaces as `E0308` and
  the false assertion as a failing test. Additive matters: `--test` replaces
  `main()`, so it cannot simply supersede the normal build.
- **`content/testing/typescript.ts`: `assertThrows` passed when nothing
  threw.** It threw its sentinel *inside* the `try`, so its own `catch` ate
  it — and worse, any `expectedMsg` that was a substring of that sentinel
  ("throw", "to throw") then matched, making the assertion succeed precisely
  when the function did not throw. Rewritten to record whether the call threw
  outside the catch. Sabotage now yields `expected function to throw, but it
  returned normally`.
- **`content/testing/python.py`: `python3 -O` deleted the whole suite.** 25
  bare `assert`s inside `unittest.TestCase` plus an assert-based runner gate.
  With a deliberately broken `clamp`, `python3 -O` printed *both* `FAILED
  (failures=1)` and "All testing examples passed", exiting 0. Asserts are now
  `self.assertEqual` / `assertTrue` / `assertIn`, and the gate raises
  `SystemExit`. Sabotage now exits 1 under both `python3` and `python3 -O`.
- **`content/binary_formats/asm_x86_64.s` and
  `content/compiler_bootstrapping/asm_x86_64.s` asserted nothing.** The first
  printed "ELF!" and exited; the second computed 10+32 and printed the result
  without ever checking it was 42. Both now build a structure and assert it,
  mirroring their AArch64 siblings (which had 16 and 8 checks to the x86_64
  files' zero — so this was never a constraint of assembly). Corrupting a
  magic byte, `e_machine`, the ELF class, an instruction length, an operand,
  or an opcode now exits 1; every one of those was silently green before.
- **Six tautological AArch64 assertions.** `mov wN, #imm` followed by
  `cmp wN, #imm` cannot fail. Each now checks what its own comment claims:
  `optimization_passes` performs the `sub w2, w0, w0` instead of asserting a
  constant; `kernel_topics` derives the EL encodings from the documented
  `EL << 2` rule; `compiler_bootstrapping` computes the forward-reference
  offset as `3 - 2`; and `instruction_encoding` reads back the words the
  assembler actually emitted and compares them to the documented
  `0xD2800540` / `0x52800021` — turning the bit-field comments into checked
  claims. (Two further candidates were **not** defects: `concurrency`
  round-trips through `stlr`/`ldar`, and `explicit_gpu_synchronization`
  spans a `ret` into a separate entry point. Both left alone.)
- **`content/memory_management/asm_aarch64.s` asserted the clobber, not the
  restore.** The STP/LDP block saved a pair, overwrote it, asserted the
  *overwrite*, then restored — so deleting the very `ldp` the block exists to
  demonstrate left it passing. Now seeds known values, clobbers, restores and
  compares against the originals; deleting the `ldp` exits 1.
- **Five shell examples shipped false test summaries.** `compression` claimed
  `9/11`, `serialization` `18/19`, `http_and_web_protocols` `16/24`,
  `tls_and_encryption` `15/16`, `concurrent_file_access` `14/12` — a
  hardcoded denominator that had drifted from the number of checks actually
  run. The gate reads only the exit status, so every one shipped green. Each
  denominator is corrected and now guarded: the file asserts `PASS ==
  EXPECTED` and exits 1 on mismatch, so the claim cannot drift silently again.

Tier 1 of a corpus-wide example review — five defects where the corpus was
teaching something unsafe or wrong. Each was reproduced as a failure first,
then fixed, then re-reproduced against the fix.

- **`content/http_and_web_protocols/c.c`: six unbounded `memcpy`s from
  attacker-controlled lengths.** The request-line and header fields copied
  parsed lengths into fixed buffers with no bounds check. Reproduced:
  `AddressSanitizer: stack-buffer-overflow, WRITE of size 15001` past the
  9,652-byte `Request` — and at smaller sizes it corrupted the struct silently
  (`path_len` came back as `0x41414141`). The `body` copy was already clamped,
  so the omission was an oversight, not a design. **The Rust and Go ports of the
  same topic have no such bug.** Now validates every length against its
  destination *before* committing anything, so a rejected request leaves the
  struct as `memset` left it. All 24 of the file's assertions still pass.
- **`content/security/python.py` and `content/security/typescript.ts`: the
  path-traversal guards were lexical-only.** `os.path.normpath` and
  `path.resolve` are pure string operations that never touch the filesystem, so
  a symlink *inside* the base pointing outside it never contains `..` and sails
  through. Reproduced: with `escape` a symlink to `/etc`, the corpus's own
  `safe_resolve` accepted `escape/passwd` and the process read the real
  `/etc/passwd`. Both now resolve symlinks (`Path.resolve` / `fs.realpathSync`)
  before an exact containment check, and the Python suite gained a symlink case
  — the one a lexical check cannot see.
- **`content/security/typescript.ts`: all three security suites were
  unfalsifiable.** Each is `try { …; assert(false) } catch {}`, and a bare
  `catch` cannot distinguish the expected rejection from the assertion that
  fires when no rejection came. `assert` now throws a distinct `AssertionFailed`
  that every catch rethrows. Proven both ways: disabling the containment check
  in a copy previously printed "All security examples passed" and now fails with
  `AssertionFailed: should reject: ../../etc/passwd`.
- **`content/gpu_memory_pooling/cyrius.cyr` redefined the stdlib `alloc`.** The
  file includes `lib/alloc.cyr` and then defines its own `alloc`, which wins
  ("last definition wins", warned on every compile). Every stdlib call that
  allocates internally — `vec_push`, `map_set`, `str_builder` — was routed into
  a 4 KB bump pool that returns *offsets*, not addresses. Adding one `vec_push`
  to the old shape exits **139 (SIGSEGV)** before printing a line; renamed to
  `pool_alloc`, the same probe passes 16/16.
- **`content/fixed_point_arithmetic/cyrius.cyr`: `fx_mul` used a logical shift
  on a signed product.** In Cyrius `>>` is logical and `>>>` is arithmetic — the
  opposite of C/Java, which is why the file already defines an `asr()` helper
  and already handles sign correctly in `fx_to_int` and `fx_to_int_round`.
  `fx_mul(-3.0, 2.5)` returned **281474976219136** instead of −491520. This is
  the exact defect `content/cyrius/`'s own field note records as the DOOM
  black-screen bug. The roundtrip test multiplied only positives, where the two
  shifts are indistinguishable — three negative-operand assertions now close
  that detection gap (121/121).

### Changed

- **C standard C17 → C23** (`ISO/IEC 9899:2024`). gcc 16.2.1 already defaults
  to `gnu23`, so the corpus was pinned one revision behind its own compiler.
  Moved at all six config/doc sites plus four in-example prose mentions;
  `scripts/validate-content.sh` and `src/vidya_core.cyr`'s `validate_command`
  were changed together to keep the two validators byte-identical. Verified
  before and after: all **77 C examples compile *and run*** under
  `-std=c23 -Wall -Werror`, identical to c17 — zero source changes were
  needed for the standard move itself.
- **Zig: two deprecated stdlib names retired.** `std.ArrayListUnmanaged` →
  `std.ArrayList` (6 files) and `mem.indexOf` → `mem.find` (4 files, 11 sites).
  Both are bare aliases the installed 0.16.0 stdlib marks `/// Deprecated`
  (`std.zig:58`, `mem.zig:1413`). Established by cross-referencing **all 192**
  `/// Deprecated` names in the installed stdlib against the corpus — those two
  were the only genuine hits; the ELF-constant and `path` matches were
  corpus-local identifiers, not stdlib uses. All 77 Zig examples rebuild, rerun,
  and produce **byte-identical output**.
- **`docs/sources.md` version table corrected.** TypeScript was listed as
  "ES2024 / TS 5.x"; npm `dist-tags.latest` is **7.0.2**, and the installed
  compiler's own `TS6046` error names **es2025** as its highest target — so the
  row is now "TS 7.0.2 / ES2025". (A first pass had this as ES2026; the compiler
  rejects that target, which is why the number came from `tsc` rather than from
  release notes.) The Cyrius row still read "Pinned at 6.4.2" — now 6.5.31.
- **Cyrius toolchain 6.5.29 → 6.5.31.** A pure compiler-side bump: diffing
  the two snapshots' `lib/` sets shows **no module added, none removed, and
  none of the 25 modules vidya declares changed content** (verified by
  sha256 over each declared module). So there was no stdlib surface to
  migrate and no source change was needed. Binary 2,563,160 B →
  2,563,264 B (+104 B); `cyrius test` 139/0; `cyrius lint` unchanged.

## [2.8.2] — 2026-08-20

Correctness cut over the 2.8.1 infra base — no content change (corpus stays
77 topics / 847 examples, 0 gaps). Five user-visible defects fixed, three of
them in surfaces the two documented consumers (agnoshi, hoosh) read directly,
plus the `src/vidya_core.cyr` extraction that made the last three findable at
all. Binary 2,562,008 B → 2,563,160 B (+1,152 B).

**Tests 41 → 139. Benchmarks 6 → 12.** Each entry below quotes the delta it
was measured at against the shared 2.8.1 baseline of 41 assertions, so those
per-entry numbers (41 → 74, 41 → 96, 41 → 51) do not sum — they overlap. 139
and 12 are the verified totals for this release, from a clean-room
`rm -rf lib && cyrius lib sync && cyrius deps && cyrius build`.

Every defect here shares one root cause: **nothing tested the code that had
them.** `tests/vidya.tcyr` exercised zero functions from `src/main.cyr` — it
re-implemented helpers locally and asserted on stdlib primitives — so the JSON
builders, the search path, and the validate subprocess layer had no coverage
between them. The extraction is the structural half of the fix; the 98 new
assertions are the other half.

### Fixed

- **`search` is case-insensitive again.** Matching was a byte-exact `memeq`
  scan with no case folding at any layer, so `vidya search tcp` returned
  "No results." while `vidya search TCP` returned 2 topics. Queries now
  ASCII-fold on both sides: `tcp`, `TCP`, and `Tcp` are one query. Folding is
  ASCII-only by design — bytes ≥ 0x80 pass through untouched, so UTF-8
  sequences are never mangled and non-ASCII queries keep their previous
  byte-exact behavior. The narrowing dates to the v2.0 Rust→Cyrius port and
  was never documented. Both `search()` callers are covered, so the CLI and
  the HTTP `/search?q=` endpoint (and with them both documented consumers,
  agnoshi and hoosh) are fixed together.

- **`search` searches tags again.** The tag branch was commented out —
  `# Tags search disabled pending Str null-termination fix` — directly under
  a section header claiming tags were searched, and
  [`docs/development/content-format.md`](docs/development/content-format.md)
  specifies `tags` to content authors as "Search tags". That contract was
  unmet across all 77 topics: `content/strings/concept.toml` declares the tag
  `interpolation`, which appears in no id, title, or description, so
  `vidya search interpolation` could never match. The blocking rationale was
  obsolete — tag `Str`s point into the raw TOML buffer with no terminator,
  and the new scanner reads `str_data`/`str_len` directly rather than
  requiring one.

- **`/info/{topic}` reported `1` for every section count.** The HTTP
  builder emitted `str_builder_add_int(sb, bps != 0 && vec_len(bps))`
  for `best_practices`, `gotchas` and `performance_notes`. Cyrius `&&`
  is a logical operator yielding `0`/`1`, so the null-vec guard silently
  became the value and every topic reported `1`. `/info/strings` said
  `"best_practices":1,"gotchas":1,"performance_notes":1` where the
  concept actually holds 5 / 4 / 4. The CLI path was never affected — it
  uses the same `&&` as a *guard* (`bps != 0 && vec_len(bps) > 0`), never
  as the value. Counts now go through a `vec_count()` helper that branches
  explicitly. **This was consumer-visible**: agnoshi and hoosh read these
  three fields.

- **`/search?q=` allowed JSON structure injection.** The query was spliced
  into the response body with `str_builder_add_cstr` and no escaping, and
  sandhi percent-decodes params before the builder sees them
  (`sandhi_server_get_param_a` → `sandhi_server_url_decode_a`), so `%22`,
  `%5C` and `%0A` arrived as raw bytes. `?q=a%22b` produced unparseable
  output; a crafted query produced a *parseable* document carrying
  attacker-chosen keys alongside a duplicated `count`/`results` pair.
  Every user- and content-derived string in every `json_*_response` now
  goes through `sandhi_json_escape` (already vendored, and already used
  correctly for `source` in `json_code_response` — it was simply unapplied
  everywhere else). Concept ids, titles, descriptions, tags and example
  paths were spliced unescaped too; latent only because no concept in
  `content/` currently contains a quote or a backslash.

- **`vidya validate` reported 462 false FAILs out of 847 examples.** On a host
  with every toolchain installed the subcommand printed `308 passed, 462
  failed, 77 skipped` while `scripts/validate-content.sh` — the authoritative
  gate, and what CI runs — was green on the same tree. The corpus was never
  broken; the diagnostic was. Three independent bugs in `validate_one`'s
  hand-rolled fork/exec (`src/main.cyr`):
  - **The child got an empty environment.** `sys_execve(..., 0)` passed a NULL
    `envp`. `/bin/sh` synthesises a default `PATH` for its *own* command
    lookups but exports nothing, so every failure message was an unset-env
    symptom: `rustc: command not found` (rustup lives outside the default
    PATH), `gcc: fatal error: cannot execute 'cc1'`, `GOCACHE is not defined
    and neither $XDG_CACHE_HOME nor $HOME are defined`, `zig: unable to
    resolve zig cache directory`, `sh: tsx: command not found`, and `cd:
    /Repos/cyrius: No such file or directory` (that template's `$HOME`
    expanded to `""`). Only Python and Shell — the two commands that need
    nothing from the environment — passed, which is exactly the 308.
  - **Two under-reserved stack buffers.** `var sh_argv[4]` and `var
    status_buf[1]`: `var buf[N]` reserves N **bytes**, so a 4-pointer argv
    needs 32 and a wait status needs 4. Both wrote past their reservation into
    neighbouring stack slots on every call — the same class of bug as the
    cyrius stdlib's own v5.11.60 `_exec3` fix.
  - **The assembly templates masked their exit status.** Both ended
    `... ; rm -f {out}.o`, so `sh` exited with `rm`'s status — a *failing*
    x86_64 or AArch64 example reported PASS. False green, opposite direction,
    same function.

  Exec now runs through the stdlib's `exec_cmd` (`lib/process.cyr`), which
  sizes its buffers correctly and forwards `/proc/self/environ` to the child.
  Temp-file cleanup moved out of the templates into `validate_one`, which
  unlinks both `{out}` and `{out}.o`, so no template can ever end in a status-
  clobbering verb again. A signal-killed child (`exec_cmd` returns -1 —
  SIGSEGV/SIGABRT are ordinary outcomes for a broken C or asm example) is now
  counted as a FAIL; passed through unmapped it would have aliased the -1 skip
  sentinel and been silently counted as skipped.

  **After: `770 passed, 0 failed, 77 skipped`** on the same tree, exit 0. The
  77 skips are OpenQASM (no qiskit on that host) — precisely what the shell
  gate skips there. Cross-checked topic-for-topic: `vidya validate compression`
  and `scripts/validate-content.sh` on the same topic now both report 10 passed
  / 0 failed / 1 skipped.

### Changed

- `tests/vidya.bcyr` no longer inlines its own copies of `to_cstr` and
  `cstr_contains`; it includes `src/vidya_core.cyr` like the test suite.

- **Search no longer allocates per field.** `str_has` copied every field into
  a fresh null-terminated buffer via `to_cstr` before scanning; `str_has_ci`
  folds the query once per search and scans the field's bytes in place. On the
  like-for-like benchmark this is **12.04 μs → 6.49 μs (−46.1%)** for one probe
  across all 77 topic ids, with non-overlapping distributions over 4 runs of
  1,000 iterations — the removed allocation more than pays for the added
  per-byte fold. It also stops `serve` leaking: each `/search?q=` request made
  up to 4 `to_cstr` allocations per concept (~308 corpus-wide) from a bump
  allocator that never frees. `cstr_contains` is no longer on the search
  path but is kept in `src/vidya_core.cyr`: the JSON golden tests use it as
  a general substring helper.

- **Benchmarks**: added `search_text_exact`, which measures the former
  copy-then-byte-exact path so the case-folding delta is measured against what
  `search()` actually cost. `search_text` now walks the production path over
  `Str` fields; through 2.8.1 it probed the registry's already-null-terminated
  hashmap keys and so never paid the copy production paid, making its 9.52 μs
  not comparable to the current 6.49 μs. See [`BENCHMARKS.md`](BENCHMARKS.md).

- **Tests**: `cyrius test` 41 → 74 assertions *for this change alone*, adding `search_case_fold` and
  `search_tags` groups covering both regressions, the ASCII-only fold boundary
  (`@`/`[`/digits/UTF-8 lead bytes untouched), and the leading-byte fast path's
  false-start cases.

- **`vidya validate` mirrors `scripts/validate-content.sh` command for
  command.** The two had drifted, and every divergence produced a wrong
  answer rather than a different one:
  - **A missing toolchain is now a SKIP, not a FAIL.** Each language gets a
    one-shot `command -v` probe (qiskit gets an import probe), cached per
    process, and skips print `SKIP: <topic>/<Lang> (toolchain not installed)`
    instead of vanishing silently. This is the gate's contract; the CLI had no
    probe at all, so on any host missing one toolchain it would have reported
    77 false FAILs for that language.
  - **OpenQASM is validated instead of blanket-skipped.** There was no command
    template, so all 77 `.qasm` files fell through to the skip sentinel — the
    whole of the old `77 skipped`. Now runs the gate's
    `qasm2.load(..., include_path=[<content dir>])`, via a new `{content}`
    substitution alongside `{file}` and `{out}`.
  - **Cyrius examples run through `cyrius run`.** The template built the
    example by piping it through `./build/cc2` inside
    `${CYRIUS_HOME:-$HOME/Repos/cyrius}` — a compiler-development path that
    does not exist on a normal install, so all 77 would have failed even with
    the environment fixed.
  - **Python runs the file, not `python3 -c "exec(open(f).read())"`.** The
    wrapper left `__file__` undefined, so any example reaching for it would
    have failed under the CLI and passed under the gate.
  - The summary now prints `note: authoritative content gate is
    scripts/validate-content.sh`, so the diagnostic cannot be mistaken for it.

- **sakshi 2.4.10 → 2.4.11, with no manifest change** — the cyrius 6.5.29
  stdlib snapshot was refreshed in place and `cyrius lib sync` picked it up.
  This is the 2.8.1 stdlib-leaf decision working as designed: that entry
  predicted the newer sakshi "arrives here when a later cyrius patch folds
  it", and it did, without vidya touching a pin. Under the old
  `[deps.sakshi]` git block the repo would still be holding 2.4.4 and
  shadow-overriding the snapshot. 2.4.11 adds drop accounting to
  `sakshi_span_enter` (non-zero return on a saturated 16-deep stack, plus a
  one-shot warn); vidya's single `load_all` span is balanced with no early
  return, so it cannot leak a slot.
- **`process` is declared in `cyrius.cyml` `[deps] stdlib`.** It was already
  vendored as another module's transitive; an undeclared module of that class
  fails at **runtime**, not at build time. Vendored file count is unchanged
  (62); binary 2,562,008 B → 2,563,184 B (**+1,176 B**, the reachable part of
  `exec_cmd`). The six benchmarks are flat against 2.8.1 (`load_all` 5.82–5.87 ms
  vs 5.63 ms, `load_concept` 43.8 μs vs 42.4 μs, `reg_get_hit` 133–139 ns vs
  136 ns — all inside run-to-run spread; no benchmarked path was touched).

### Added

- **`src/vidya_core.cyr`** — the domain + JSON layer split out of
  `src/main.cyr` (types, registry, TOML loader, hot-reload, search,
  compare, code, validate, and the `json_*_response` builders). Included
  by `main.cyr`, `tests/vidya.tcyr` and `tests/vidya.bcyr`, so tests and
  benchmarks now run the same code the binary serves. This is the trigger
  named in decision 4 of [`docs/architecture/overview.md`](docs/architecture/overview.md)
  finally firing: `tcyr` cannot bind a port and could not reach into a
  file whose only entry point is `main()`.

- **55 new tests (41 → 96 *for this change alone*), all against the real builders.** Golden bodies
  for `/info`, `/stats`, `/list`, `/compare`, `/gaps` and `/search` against
  a fixture concept whose section counts are 3 / 2 / 4 — distinct from each
  other and none equal to `1`, so a boolean collapse fails loudly. Plus:
  escaping unit tests (quote, backslash, newline, tab, `\u0001` control
  byte, null and length-borrowed `Str`), injection round-trip tests
  asserting a hostile query comes back verbatim as a *value* with no
  attacker key at structure level, a content-derived hostile fixture
  (bare `"` and `\` reaching the builder from TOML), and a corpus sweep
  that checks all 77 `/info` bodies are structurally sound and report
  counts equal to the registry's real vector lengths.

- **Test fixtures under `tests/fixtures/`** (`json_golden`, `json_hostile`).
  Outside `content/` on purpose — `load_all` and the content gate never
  see them.

- **5 new benchmarks (6 → 11)** over the real builders:
  `json_info_response` 10.0µs, `json_search_response` 300.0µs (dominated by
  the 77-concept scan, not by escaping), `json_list_response` 120.1µs. The
  escaping cost is isolated by a paired micro-benchmark on one real
  130-byte description: `field_escaped` 3.59µs vs `field_raw_splice` 620ns,
  i.e. **+3.0µs per escaped field** — the price of the injection fix. In
  context: a whole `/info` body costs 10µs against an ~84µs request. The
  six pre-existing benchmarks are unchanged and within noise
  (`load_all` 6.03ms → 5.97ms, `reg_get_hit` 31ns → 32ns).

- **`tests/vidya.tcyr` — `validate_exec` group (41 → 51 assertions *for this change alone*).** Pins the
  subprocess contract behind `vidya validate`, since every false-FAIL bug lived
  in that layer and none of it was covered: exit status is the child's exit
  code (0 / 1 / 42), a signal-killed child reports -1 (the case that must not
  alias the skip sentinel), the child inherits the parent's environment
  (asserted via `$HOME`, which no shell synthesises — guarded on the parent
  actually having one so a HOME-less runner cannot fail it spuriously), a
  trailing `rm` swallows a non-zero status while a bare command does not, the
  toolchain-probe shape returns 0 for a present tool and non-zero for an absent
  one, and `{out}` substitution replaces *all* occurrences.

## [2.8.1] — 2026-08-20

Infra-only cut — no content change (corpus stays 77 topics / 847 examples,
0 gaps). Cyrius pin **6.4.2 → 6.5.29**, sakshi reshaped from a git dep into a
stdlib leaf, vyakarana **2.2.3 → 2.3.2**. Headline: **the binary shrank
14.66 MB → 2.56 MB (−82.5%)** — 2.8.0's sigil-crypto static-data regression is
gone at 6.5.x.

### Changed

- **Cyrius toolchain 6.4.2 → 6.5.29.** No stdlib module was removed across the
  jump (verified by diffing the `lib/` module sets of both snapshots — three
  additions only: `async_macos`, `async_win`, `thread_macos`, none of which
  vidya declares). The build required no source change beyond the sakshi work
  below.
  - **Binary 14,661,488 B → 2,562,008 B (−82.5%).** The compiler's report of
    large static data fell from **13,119,032 B → 862,168 B**. 2.8.0 documented
    the ~13 MB as the unavoidable cost of a sandhi consumer — sigil's
    `SIGIL_CRYPTO_BANKS = 64` parallel-crypto banks linked as *reachable static
    data* via the `tls` → `sha384_init_into` transitive, explicitly "not
    DCE-eliminable". That is no longer true at 6.5.x: the constant is still 64
    in both snapshots, so the change is in how the toolchain places and reaches
    those banks, not in sigil's own configuration. vidya's `serve` is still
    plaintext localhost and still never executes the crypto at runtime.
  - **`cyrius bench` rediscovers `tests/*.bcyr`.** The 6.4.x discovery
    regression that 2.8.0 worked around is fixed — no-arg `cyrius bench` finds
    the suite again. CI and `scripts/bench-history.sh` keep passing the
    explicit `tests/vidya.bcyr` path anyway: it is unambiguous and works on
    both sides of the fix.
- **sakshi is now a stdlib leaf, not a git dep — and this fixes a silent
  downgrade.** cyrius folded sakshi into its stdlib snapshot at **6.5.24**, so
  `lib/sakshi.cyr` ships with the toolchain. vidya nonetheless still carried
  `[deps.sakshi]` pinned at tag **2.4.4**, and `cyrius deps` overlays a git
  dep's resolution *on top of* the folded snapshot on every build — so the
  2.4.4 file was **replacing the toolchain's 2.4.10**. Effects, all now gone:
  - The build emitted `duplicate fn 'sakshi_span_enter' / 'sakshi_span_exit'
    (last definition wins)` on every compile.
  - `cyrius deps --verify` could not catch it: the lock is written **from
    disk**, so it recorded the hash of the downgraded file and reported clean.
  - The stale copy was pushed at anything reaching vidya transitively.

  `[deps.sakshi]` is removed and `"sakshi"` added to `[deps] stdlib`, matching
  the shape sit settled on after hitting the same trap. ⚠ Do not re-add the git
  block — pinning sakshi means pinning the toolchain, and the `cyrius` pin in
  `[package]` is that lever. Net version movement: sakshi **2.4.4 → 2.4.10**.
- **vyakarana 2.2.3 → 2.3.2** (still a real git dep — vyakarana is *not* folded
  into the snapshot). 2.3.0 moved vyakarana's own pin 6.1.24 → 6.5.4 and re-cut
  its vendored `lib/`; 2.3.1–2.3.2 are tokenizer-correctness patches (`TK_ERROR`
  adjudication across 37 grammars). No token-kind, `Token`-layout, or public-API
  change, so vidya's `code` command gains highlighting accuracy with no call-site
  change.

### Fixed

- **`load_all` span tracing had been dead code.** `src/main.cyr` defined local
  no-op stubs `fn sakshi_span_enter(...) { return 0; }` / `fn sakshi_span_exit()
  { return 0; }` immediately after `include "lib/sakshi.cyr"`, which overrode the
  real implementations ("last definition wins"). The comment above them cited
  **sakshi v0.5.0**, whose stderr-only profile genuinely omitted the span stack —
  four major versions stale. So vidya's one instrumented span recorded nothing.
  Stubs removed; `load_all` now emits real `[ENTER]` / `[EXIT]` records with
  elapsed time to stderr, stdout unchanged. The pair is balanced with no early
  return between enter and exit, so it cannot leak a slot from sakshi's 16-deep
  span stack — the failure mode sakshi 2.4.11 documents.

### Fixed — CI and release gates

A status audit run against this cut found that several gates had been reporting
green on work they never did. All are one- to six-line repairs and all are in
this cut; none change the shipped program.

- **The release aarch64 cross-build has been silently skipped since the 6.1.x
  pin.** `.github/workflows/release.yml` guarded on
  `$HOME/.cyrius/bin/cc5_aarch64`. That binary was renamed `cycc_aarch64` at
  cyrius **6.0.0** and the back-compat symlink was dropped at **6.1.0**, so the
  `if` was permanently false: the step emitted `::warning::cc5_aarch64 not
  shipped`, the job went green, and the release shipped x86_64-only. **2.7.1
  shipped an aarch64 artifact; 2.7.3 and 2.8.0 did not.** The probe now tries
  `cycc_aarch64`, `cycc-native-aarch64`, then `cc5_aarch64`. Verified before
  changing it: `cyrius build --aarch64` at 6.5.29 produces a working 3,049,200 B
  static aarch64 ELF that runs the full corpus under `qemu-aarch64`.

  The roadmap entry for this said "no vidya-side action — just monitor the CI
  warning". The warning being emitted *was* the bug; that entry is corrected.

- **The content gate has been skipping all 77 AArch64 examples on every CI
  run.** `scripts/validate-content.sh` probed for `qemu-aarch64`, but CI
  installs `qemu-user-static --no-install-recommends`, which on noble ships
  **only** `qemu-aarch64-static`. So `HAS_QEMU_AA64=false` and every AArch64
  example took the skip branch — while the banner printed
  `aarch64=$HAS_AARCH64_AS` (the *assembler*, which was present), reporting
  true. CI has been green on **770/847**. The probe now accepts either binary
  name and the banner reports what it actually gates on.

- **A skipped example could never fail the content gate.** The exit check
  considered only `$FAIL`; `$SKIP` was printed and discarded, so Zig, AArch64,
  OpenQASM and Cyrius — 308 of 847 — could all vanish silently behind a broken
  probe. `VIDYA_STRICT=1` (now set on the CI step, where the full toolchain is
  installed by construction) makes any skip exit 1. Local runs are unaffected:
  not every developer has zig, an aarch64 cross-toolchain and qiskit.

- **`cyrius test` was `continue-on-error: true`, and `release.yml` gates on
  that workflow** via `needs: [ci]` without re-running tests — so a fully red
  41-test suite could still tag a release. `cyrius test` does exit non-zero on
  a failed assertion. Flag removed. It is deliberately kept on the *bench* step,
  which asserts nothing and flakes on shared runners. Neither sit nor hoosh
  suppresses a test gate anywhere.

- **The lint gate could pass on a file that does not parse.** It matched only
  `^\s*warn `, so `error: does not parse, so lint checks were NOT run` scored
  zero warnings and passed. Now matches `error` too.

- **CI staged `lib/` with `cp -rL "$HOME/.cyrius/lib/"*`** — the flat symlink
  dir, i.e. whatever the wrapper currently points at, and the whole 101-module
  snapshot. Replaced with `cyrius lib sync` (pin-aware, declared subset) +
  `cyrius deps`, so CI now produces the same 62-module `lib/` a developer does.

- **`scripts/validate-content.sh` probed `cargo run --example test_qasm`** —
  banned tooling (vidya migrated off Rust at v2.0; that example survives only
  in `rust-old/`) *and* a latent false-green: the branch it guarded printed
  `✓ OpenQASM (native)` and incremented `PASS` without validating anything.
  Both the probe and the branch are gone; qiskit is the only OpenQASM path.

- **`tests/test.sh` deleted.** It piped `src/main.cyr` into `./build/cc2` — a
  binary gone since the 2.0 port — and stdin piping cannot resolve the file's
  17 relative `include`s regardless. Referenced by nothing; its exit status was
  always `rm`'s 0.

- **`build/vidya` was a tracked 14.6 MB binary**, and `release.yml`'s
  `git archive HEAD` packed it into every checksummed `*-src.tar.gz` — the
  tarball zugot's recipe pins. A 2.8.1 source tarball would have shipped a
  stale executable 5.7× larger than the one that tag builds. `build/` is now
  gitignored (with a `.gitkeep`, hoosh's convention). ⚠ The ignore rule does
  not untrack it — `git rm --cached build/vidya` is still needed.

- **A false-positive lint deferral** in `src/main.cyr`: a comment describing
  allocation lifetime used the phrase "go out of scope", which cyrlint reads as
  an untracked deferral marker. Reworded; `cyrius lint src/main.cyr` is now
  clean apart from the three `exceeds 120 characters` warnings CI tolerates.

### Documentation

- **Swept ten user-facing docs that had frozen at v2.7.1** — `README.md`,
  `docs/usage.md`, `docs/guides/getting-started.md`, `docs/examples/README.md`,
  `docs/development/{content-format,learning-paths,roadmap}.md`,
  `docs/architecture/overview.md`, `BENCHMARKS.md`, `CLAUDE.md`. They variously
  claimed 74 topics / 814 examples (actual: 77 / 847), a `~1.1 MB` binary, and
  `cyrius update` as the rehydration command — which ignores the manifest pin
  under wrapper drift and is the exact 2.7.2 incident. `overview.md` was two
  generations behind at "60 topics" / "~600KB", still described sakshi as a git
  dep, and still listed the `json`/`toml` modules 6.1.x folded into `bayan`.
  Volatile figures now point at `docs/development/state.md` rather than being
  restated. `roadmap.md` contradicted itself — header pin 6.4.2 vs `5.11.55`
  further down, 77 topics in one line and 74 in another, release history
  stopping at 2.6.x. CHANGELOG and ADR figures were left alone: those are
  correct history.
- **`docs/doc-health.md` had itself gone stale** — the ledger built to catch
  exactly this drift last swept 2026-05-16 and marked `README.md`,
  `BENCHMARKS.md` and `docs/usage.md` "✅ Fresh" while all three were wrong.
  Updated, with the outstanding items (uncited sources, and a
  CLAUDE.md-vs-`content-format.md` contradiction over whether best practices /
  gotchas / performance notes are required) recorded rather than quietly closed.
- **`CLAUDE.md` toolchain table corrected**: `cyrius deps --verify` now carries
  the ⚠ that it cannot detect a shadowed stdlib module (the lock is written
  from disk); the `cyrius bench` note records that 6.5.x fixed the 6.4.x
  discovery regression; `~600KB` and `sakshi 2.0.0` replaced with a pointer to
  `state.md`; `cyrius lib sync` documented as its own step.

### Fixed — benchmark harness

- **Four of six benchmarks had been measuring empty inputs since 2026-04-08.**
  `toml_get` / `toml_get_sections` take **cstr** keys, not `Str`; passing
  `str_from("id")` silently returns 0 rather than erroring. `tests/vidya.bcyr`
  did exactly that at four sites, so the bench registry was never populated
  (`map_set` was unreachable) and `reg_get_hit`, `reg_get_miss`, `search_text`
  and `toml_sections` all probed a **zero-entry** map. The tell was visible in
  the published numbers and went unread for four months: `reg_get_hit` was
  benchmarking *faster* than `reg_get_miss`, which is impossible for a
  populated open-addressed map. `tests/vidya.tcyr` documents this precise trap
  in a comment on its `toml_loader` group while the sibling `.bcyr` kept doing
  it. Keys are now cstr literals and the same NB is recorded in the `.bcyr`.
  Product code was never affected — all 20 `toml_get*` call sites in
  `src/main.cyr` already used cstr literals.

  Scale of the correction, at the 6.5.29 pin:

  | benchmark | empty input (as published) | real corpus |
  |---|---|---|
  | `reg_get_hit` | 33 ns | **136 ns** |
  | `reg_get_miss` | 51 ns | **398 ns** |
  | `search_text` | 72 ns | **9.52 µs** (132×) |
  | `toml_sections` | 1.29 µs | **1.93 µs** |

### Performance

Measured on this box, same corpus, same day, **4 runs at each pin**, medians
below — and **with the harness fix above in place at both pins**, so this is
the first A/B in vidya's history that compares real work. `load_concept` and
`load_all` were always measuring real input and are unaffected by the fix.

| benchmark | 6.4.2 | 6.5.29 | delta | verdict |
|---|---|---|---|---|
| `reg_get_miss` | 504 ns | 398 ns | **−21.0%** | **real** — distributions do not overlap (6.4.2 min 502 ns > 6.5.29 max 411 ns) |
| `load_all` | 5.933 ms | 5.633 ms | −5.1% | modest — 3 of 4 runs below the whole 6.4.2 range |
| `load_concept` | 44.44 µs | 42.39 µs | −4.6% | modest — one overlapping outlier |
| `reg_get_hit` | 138.5 ns | 136.5 ns | −1.4% | noise — full overlap |
| `search_text` | 9.650 µs | 9.520 µs | −1.3% | noise — full overlap |
| `toml_sections` | 1.834 µs | **1.927 µs** | **+5.1%** | **real regression** — distributions do not overlap (6.4.2 max 1.891 µs < 6.5.29 min 1.917 µs) |

The hashmap miss path is meaningfully faster; TOML section extraction is
meaningfully *slower*. The regression is small in absolute terms (~93 ns per
call) and `toml_sections` runs only during corpus load, which improved overall
— but it is real and is recorded here rather than averaged away. No claim is
made for the two noise rows in either direction.

⚠ These numbers are **not comparable to `BENCHMARKS.md`**, which is still
stamped v2.7.1 / cyrius 5.11.55 and derives from the empty-input harness. That
file needs a regeneration pass it has not had yet.

### Verified rather than assumed

Every claim below was measured on this box at the 6.5.29 pin, from a clean
`rm -rf lib && cyrius lib sync && cyrius deps`, not inferred:

- **Zero stdlib module removals** 6.4.2 → 6.5.29 across the whole snapshot
  (diffed both `lib/` sets: three additions only — `async_macos`, `async_win`,
  `thread_macos` — none declared here).
- **Clean-room reproducible**: 62 modules vendored, `build/vidya` 2,562,008 B,
  `cyrius test` **41 passed / 0 failed**, `cyrius lint src/main.cyr` clean apart
  from the three `exceeds 120 characters` warnings CI tolerates.
- **Content gate 847/847, zero skipped** under `VIDYA_STRICT=1` — the first run
  in which a skip would have been a failure. (The machine used has the
  unsuffixed `qemu-aarch64`, so its AArch64 coverage was already real; CI's was
  not, which is what the probe fix above addresses.)
- **aarch64 cross-build works at 6.5.29**: 3,049,200 B static ELF, runs the
  full corpus under `qemu-aarch64`. Verified *before* changing release.yml's
  probe, so the fix restores a working artifact rather than converting a silent
  skip into a loud failure.
- **All 10 CLI commands dispatch** on the rebuilt binary.
- **`cyrius lib sync` and `cyrius deps` do overwrite a stale `lib/<mod>.cyr`**
  at 6.5.29 — staged a 6.4.2 `fmt.cyr` into a 6.5.29 tree and watched each
  command restore it. The older "treats an existing file as satisfied and never
  refreshes" behavior (vyakarana's 2.3.0 entry, observed at 6.5.4) no longer
  applies, so `rm -rf lib` before a pin bump is belt-and-braces, not required.
  This is also *why* a git-dep overlay is the dangerous case and plain staleness
  is not: the overlay is reapplied on every build by design.
- **`ct`, `keccak`, `sigil` are now redundant declarations.** Dropping all three
  from `[deps] stdlib` still vendors the same 62 modules and still builds clean
  (binary 4,080 B smaller) — 6.5.x's transitive arc chases them. `chrono` and
  `dynlib` remain hard requirements; removing either is a build error. All five
  are kept anyway: an undeclared module of this class fails at **runtime**, not
  at build time (sit's missing `random` made `sit key generate` SIGILL exactly
  this way), and 4 KB does not buy that exposure.
- The five `undefined function` warnings (`random_bytes`, `async_new_in`,
  `async_spawn`, `async_run`, `async_await_readable`) are unchanged from 2.8.0
  and remain dead-path placeholders — traced with `CYRIUS_DCE_VERBOSE=1` to
  `_sigil_random_fill` and `sandhi_server_run_async`. `random_bytes` is
  referenced only by `lib/sigil.cyr` and the agnos/windows syscall shims, none
  reachable from a Linux-hosted plaintext `serve`.
- **`CYRIUS_HOME` takes the install root** (`~/.cyrius`), not the versioned
  directory. Pointing it at `~/.cyrius/versions/<pin>` makes the resolver look
  for `<pin>/versions/<pin>/lib` and fail. Recorded in `state.md`.

## [2.8.0] — 2026-07-04

### Changed

- **Cyrius toolchain 6.1.41 → 6.4.2** (infra-only cut — no new content
  topics; corpus stays at 77 topics / 847 examples). A three-minor-series
  jump — the bulk was internal cycc / self-host churn (growable-region
  migration, codegen), so consumer impact was small and mechanical:
  - **stdlib link surface grew.** The 6.2.x→6.4.x sandhi / TLS refolds
    added follow-through references the cyrius transitive resolver doesn't
    chase, so five modules were added to `[deps] stdlib` in `cyrius.cyml`:
    `chrono` (`clock_now_ns`/`clock_now_ms`), `dynlib` (`dynlib_auxv_*`),
    and `sigil` + `ct` + `keccak` (`sha384_init_into`). Without them the
    build failed with 5 reachable-undefined functions.
  - **Binary grew ~2.1 MB → ~14.7 MB.** Linking `sigil` (pulled via the
    `tls` → `sha384_init_into` transitive that sandhi's server path now
    references) brings in its parallel-crypto banks — ~13 MB of reachable
    static data (`SIGIL_CRYPTO_BANKS=64`). Not DCE-eliminable. This is the
    baseline cost of a sandhi consumer on 6.4.2 (sit is ~14.9 MB); vidya's
    `serve` is plaintext localhost and never runs the crypto at runtime.
- **sakshi 2.2.10 → 2.4.4** — 2.2.10 was a 6.1.x-era artifact. 2.4.4 adds
  128-bit W3C trace-id support; purely additive, no behavior change for
  existing callers. (vyakarana held at 2.2.3 — still the latest tag; its
  6.1.x `dist` compiles and runs clean under 6.4.2.)

### Fixed

- **`cyrius bench` discovery.** cyrius 6.4.x dropped `tests/*.bcyr` from the
  no-arg `cyrius bench` (it now looks only in `benches/` and `tests/bcyr/`),
  which had been silently finding zero benchmarks. CI (`.github/workflows/ci.yml`)
  and `scripts/bench-history.sh` now pass the explicit path
  `cyrius bench tests/vidya.bcyr`. `bench-history.sh` had also been calling a
  dead `cargo bench` (Rust-era debt removed at v2.0) — replaced in the same edit.
- **Flaky content-gate assertion in `content/process_and_scheduling/shell.sh`.**
  It asserted the live process nice `== 0`, but nice is *inherited* — under a
  renice'd ancestor (CI/batch runners) the read returns non-zero (tripped the
  gate at `got '5'`). Now asserts the live nice is a valid level `[-20, 19]`;
  the default-of-0 concept stays in the `NICE_DEFAULT` constant. Also more
  accurate pedagogically (nice is inherited, not reset per process).

## [2.7.3] — 2026-06-12

### Added

- **P4 build-tooling cluster complete — 3 new topics, 77 topics / 847
  examples, all 11/11.** `build_systems`, `package_resolution`, and
  `reproducible_builds` close P4. Each was designed Cyrius-first and
  ported to the other 10 languages (rust / python / c / go / typescript
  / shell / zig 0.16 / x86_64 asm / aarch64 asm + an OpenQASM thematic
  analog), with a fixed scenario contract asserted identically in every
  port. Validator: 847/847 green.
- **New topic: `build_systems` — DAG + topological order + incremental rebuild.**
  A minimal build-system core across all 11 languages: a DAG of build
  targets, Kahn topological ordering, content-signature dirty-tracking
  (input signature = source mixed with dependencies' output signatures,
  `HB=131`/`HM=1000003` polynomial), ninja-style incremental rebuild
  (only dirty targets run; content-addressed outputs let unchanged
  rebuilds cut off downstream), and cycle detection. The Cyrius
  reference (`content/build_systems/cyrius.cyr`) was designed first,
  then ported to rust / python / c / go / typescript / shell / zig 0.16
  / x86_64 asm / aarch64 asm, plus an OpenQASM thematic analog (the
  dependency DAG as a topologically-ordered CNOT cascade with X-driven
  dirty propagation). The same six-scenario contract holds in every
  port: topo orders all 3 targets (app after both deps); cold build
  rebuilds 3; a no-edit build rebuilds 0; editing one leaf rebuilds it
  + the root (2) while the sibling stays untouched; a 2-node mutual
  dependency is detected as a cycle. `concept.toml` carries 4 best
  practices, 4 gotchas (bad/good), and 2 performance notes (ninja null
  build, content-addressed caching).
- **New topic: `package_resolution` — semver + constraint solving.**
  Semantic versions encoded as a comparable integer triple, caret
  (`^x.y.z`) constraint ranges, range intersection for diamond
  dependencies, highest-compatible-version selection, bounded
  backtracking (the highest version of one package can force an
  impossible constraint on another — step down and re-solve), and
  dependency-cycle detection. Contract per port: semver ordering and
  major extraction; caret bounds + satisfaction; `^1.0.0 ∩ ^2.0.0` is
  empty; highest match in `^1.0.0` is 1.5.0; a diamond on a shared dep
  resolves to 1.5.0; conflicting carets are unresolvable; backtracking
  picks A 1.0.0 (not 1.1.0) with C 1.5.0; A↔B is a cycle, a diamond is
  acyclic. `concept.toml`: 4 best practices, 4 gotchas (incl. the 0.x
  caret special case and lexicographic-compare bug), 2 perf notes
  (pubgrub/conflict-learning, lockfiles).
- **New topic: `reproducible_builds` — deterministic, bit-for-bit output.**
  The three classic non-determinism leaks and their fixes: wall-clock
  timestamps → clamp to `SOURCE_DATE_EPOCH`; unstable readdir/hash-map
  order → sort before emitting; non-deterministic artifact names →
  content-addressing. Modeled as a build that folds a (normalized)
  timestamp and a sorted file set into one digest; the contract proves
  a deterministic pipeline (sort + normalize) yields byte-identical
  digests across runs that differ in BOTH input order and wall-clock
  time, while the naive pipeline drifts, and that timestamp
  normalization alone removes clock dependence. `concept.toml`: 4 best
  practices, 4 gotchas (incl. embedded build paths, parallel-write
  ordering), 2 perf notes (Debian reproducible-builds, `-trimpath` /
  go.sum). Validator across the cluster: 847/847 green.

## [2.7.2] — 2026-06-12

### Changed

- **Cyrius pin: 5.11.55 → 6.1.41.** Crosses the 6.0.x line into the
  6.1.x series the rest of the ecosystem now rides (sandhi 6.1.21,
  sakshi 6.1.17, vyakarana 6.1.24, sit 6.1.30, hoosh 6.1.31).
  Rehydration is `cyrius lib sync` (syncs vendored `lib/` to the
  manifest pin — 88 `.cyr` files from
  `~/.cyrius/versions/6.1.41/lib/`) rather than `cyrius update`, which
  re-resolves to the *wrapper's* version and would have pulled 6.2.0.
  Build with the pinned toolchain
  (`CYRIUS_HOME=~/.cyrius/versions/6.1.41 cyrius build --strict-pin …`)
  so cycc matches the pin; the default wrapper is 6.2.0 and
  `--strict-pin` rejects that drift. `cyrius.lock` is now populated
  (89 deps locked) where it had been empty.
- **Stdlib `json` + `toml` + `base64` → bundled `bayan` module.** 6.1.x
  stopped shipping the standalone `lib/{json,toml,base64}.cyr`; they now
  live in the `bayan` distlib (matching sit / hoosh on 6.1.x). Updated
  `cyrius.cyml` `[deps] stdlib` and the `include "lib/…"` lines in
  `src/main.cyr`, `tests/vidya.tcyr`, `tests/vidya.bcyr` (deduped — one
  `bayan` include replaces the separate json/toml includes). Without
  this, a clean `cyrius lib sync` (no stale standalone copies) fails
  with `cannot read ./lib/json.cyr` (and toml/base64) — the dirty mixed
  `lib/` only masked it.
- **sakshi: 2.2.4 → 2.2.10.** Latest tracing release.
- **vyakarana: 2.2.1 → 2.2.3.** Latest streaming-tokenizer release.
- **Binary size: ~1.1 MB → ~2.1 MB static ELF.** The 6.1.x stdlib is
  larger; the build flags ~1934 unreachable fns (DCE-eliminable via
  `CYRIUS_DCE=1`). `cyrius test` green (41 passed, 0 failed); corpus
  holds at 74 topics × 11 languages = 814 examples.
- **Zig content pin: 0.15.2 → 0.16.0** (latest language release; CI
  `ZIG_VER`, `docs/sources.md`, `README.md`, `content-format.md`,
  `getting-started.md`, roadmap all follow). All 14 `content/*/zig.zig`
  examples migrated to the 0.16 API — `std.heap.GeneralPurposeAllocator`
  → `std.heap.DebugAllocator`, and the 0.16 `std.Io` interface
  (`std.Io.Threaded` backend) now threads through the filesystem
  (`std.Io.Dir.cwd`, positional `read/writePositionalAll`), `std.Io.Mutex`,
  `io.random`, and the rewritten `std.Io.Writer` ("Writergate":
  `std.Io.Writer.Allocating`, `.fixed`, `PriorityQueue` unmanaged
  `push`/`pop`). Each rebuilt + run green under Zig 0.16.

### Added

- **Kernel field notes brought current through agnos 1.41.x** —
  `content/cyrius/field_notes/kernel.cyml` grew from 5 to 9 entries,
  closing the gap from the 1.31.x storage trio (where it had stalled)
  through the shell-separation arc. Each entry was mined from the agnos
  CHANGELOG + agnosticos iron-nuc-zen-log + kernel source, then
  adversarially fact-checked against those sources (every version
  number, byte-size, date, and the QEMU-vs-iron honesty bar
  re-derived, not taken from the draft):
  - `the_unicast_that_couldnt_arrive` — agnos 1.32.x networking. The
    ~14-burn chase of a phantom RTL8168H/8111H L2 accept-filter that
    ended at an RX descriptor ring 16→64 deepening; the
    audit-re-derive-don't-validate-comments lesson. Iron-validated
    2026-05-25.
  - `learning_to_write` — the two write arcs: 1.33.x ext2 indirect
    write (demo→base exit, iron-proven 2026-05-25) and the 1.41.x
    `VFS_SEC_WFILE` FAT/exFAT write-fd (software-complete, iron burn
    pending). Buffer lifecycle under an alloc-only heap; why
    iron-validation is per-arc and never transfers.
  - `exec_from_disk_the_four_in_one_burn` — agnos 1.40.x exec-from-disk.
    Loading a static ELF64 off ext2 into ring 3; the iron-only fault
    chain (gnoboot's ≥4 GB `boot_info` read, the scheduler dead-proc
    reset, the boot-stack `.rodata` stomp, the mount-routing lie) and
    the single `14013` burn that iron-validated four cuts at once
    (2026-05-31). The 1.40.14 teardown closeout shipped QEMU-only.
  - `the_shell_leaves_the_kernel` — agnos 1.37.5 + 1.41.x. The console
    font extracted to the `kashi` library (and the build-prepend
    footgun that left `bench.sh` latently broken), then the interactive
    shell walked out of ring 0 into a userland `agnsh` while a recovery
    REPL stays behind — the permanent kernel↔userland boundary.
    Software-complete and QEMU-green; **iron burn pending** (staged at
    1.41.11 behind the `#tracker-141x-cycle` A1–A4 rubric).

### Fixed

- **4 Cyrius examples broke under the 6.x toolchain** (surfaced by the
  pin bump; `scripts/validate-content.sh` is the gate):
  - `type_systems`, `design_patterns` — Cyrius 6.x dropped struct
    *field-access sugar* (`v.x` read/write silently resolved to 0).
    `Struct { … }` value-literals and `v.method()` dispatch still work;
    field access is now explicit pointer ops — `load64(&v + off)` /
    `store64(&v + off, …)` for inline value structs, `load64(ptr + off)`
    for heap records — the idiom vidya's own `Concept` type already used.
  - `distributed_systems` — single-letter uppercase globals `W`/`R`
    collided with reserved identifiers in 6.x (`W` silently read as 0,
    breaking the quorum gate); renamed to `W_QUORUM`/`R_QUORUM`.
  - `tracing` — `include "sakshi.cyr"` → `include "lib/sakshi.cyr"`
    (sakshi now vendors into `lib/`).
- `content/allocators/c.c` — unused-but-set `count` under gcc 16's
  stricter `-Werror`; folded into the fill-loop status print.
- `content/cyrius/field_notes/index.cyml` Kernel section was stale —
  it claimed "3 entries," listed only 2, and the file already held 5.
  Now lists all 9 (registering the previously-unlisted
  `the_mvp_gate_at_attempt_68` and `the_storage_trio_iron_debut`) with
  the count and subtitle corrected.

## [2.7.1] — 2026-05-16

### Changed

- **Cyrius pin: 5.9.43 → 5.11.55.** Absorbs the 5.10.x and 5.11.x
  cycles in one bump. Rehydration is now `cyrius update` (copies
  stdlib from `~/.cyrius/versions/<ver>/lib/` into `lib/` and
  re-resolves git deps); `cyrius deps` alone only handles
  `[deps.NAME]` git entries.
- **sakshi: 2.0.0 → 2.2.4.** Picks up cycle-counter timestamps
  (`_sk_now_ns` no longer goes through the kernel; ~22 ns on
  x86_64 via `rdtsc`+Q32 mul-shift, instant on aarch64 via
  `mrs cntvct_el0`), opt-in `sakshi_clock_recalibrate()`,
  aarch64 portability with arch-dispatched syscalls, and the
  v5.11.x `: i64` annotation pass. Public API surface
  unchanged.
- **vyakarana: 1.11.1 → 2.2.1.** Major bump; only scheduled
  API break in the roadmap. `tokenize_source(src, lang)`
  removed in favor of the push-based streaming API
  (`tokenize_stream_new` / `_feed` / `_finish` / `_free`) per
  vyakarana ADR 0017. Vidya's two consumers — `vidya code`
  CLI (`src/main.cyr:877`) and `GET /code/{topic}/{lang}`
  (`src/main.cyr:1569`) — migrated in place; observable
  output is byte-identical (rust track of
  `content/lexing_and_parsing/` re-verified at 2187 tokens
  on 8829 source bytes, same as 2.7.0). Also gets the
  compose-rule prefix-buffering streaming fix (2.2.1
  FINDING-011).
- `cyrius.cyml` `[deps] stdlib` extended with `tls`, `base64`,
  `fdlopen` — sandhi pulls `TLS_EARLY_DATA_*`, `fdlopen_*`,
  `base64_encode` via transitives that cyrius v5.10.x SLOT 19
  doesn't follow through enum/constant references. Mirrors sit's
  documented gap-list. Other undefined-symbol notes from sandhi
  (`hashmap_*`, `cyr_munmap`, `dynlib_*`, `clock_now_*`) land in
  DCE-eliminated paths and don't gate the build.
- `lib/` and `cyrius.lock` are now build artifacts under the
  5.11.x model — `lib/` is gitignored; lockfile defaults to empty
  on resolve.
- **CI/release workflows refreshed** for the 5.11.x model
  (mirrors sit / sigil / sandhi):
  - Cyrius install: hand-rolled tarball extract → upstream
    `install.sh` pipe (lays out `$HOME/.cyrius/versions/$VER/`
    + flat symlinks + `current` pointer correctly).
  - Dep resolution: two-step — `cp -rL $HOME/.cyrius/lib/* lib/`
    then `cyrius deps`. The pre-5.11 `cyrius deps --verify` step
    is gone (lockfile is empty under 5.11.x and gitignored).
  - `cyrius lint src/main.cyr` added as a CI gate (per-file in
    5.7+; cosmetic 120-char warnings tolerated, everything else
    hard-fails).
  - Release tarball no longer ships `lib/` (binary is statically
    linked) or `cyrius.lock` (gitignored).
- **`scripts/version-bump.sh` rewritten** — pre-2.0 cargo-era
  references (`Cargo.toml`, `cargo generate-lockfile`, the
  CLAUDE.md `**Version**` sed that no longer matches anything)
  are gone. Bump now writes `VERSION` and stamps
  `CHANGELOG.md`; cyrius.cyml inherits via `${file:VERSION}`.

### Added

- **`scripts/validate-content.sh` is now a CI gate.** The
  Content Validation job installs every language toolchain
  (zig 0.13.0, aarch64 binutils, qemu-user-static, tsx, qiskit,
  cyrius) and runs the full 814-example × 11-language sweep on
  every push/PR. Per CLAUDE.md Content Standards: every example
  MUST compile/run; ~10 min wallclock.
- **aarch64 release artifact (best-effort).** `release.yml`
  cross-builds `vidya-<tag>-aarch64-linux` via
  `cyrius build --aarch64` when `cc5_aarch64` is shipped with
  the pinned cyrius. Mirrors sit's pattern; ships x86_64 alone
  if cross-build fails or the cross-compiler isn't bundled.

## [2.7.0] — 2026-05-08

**Minor opens P4 (build systems) — infra bump turn before topic
work.** No new topic content; surface area is toolchain alignment,
new dependency wiring, and spec/doc cleanup ahead of the
2.7.x topic batch (build_systems, package_resolution,
reproducible_builds).

### Changed

- **Cyrius pin: 5.8.34 → 5.9.43.** Entire 5.9.x cycle absorbed
  in one bump (43 patches over 2 days, closed 2026-05-08).
  Highlights: niyama 1.0.1 fold (.0, 8th sibling distfile,
  6,664 lines, 5 regex engines), sovereignty pass kickoff (.1,
  743 LOC of bash audit-dispatcher → `programs/check.cyr` +
  `lib/audit_walk.cyr` 78th stdlib module),
  agnosys `#derive(Serialize)` cascade incl. Mach-O ARM64 fnptr
  ASLR fix (.33–.39), cx Phase 2c parity (.40), tls-live gate
  conversion + `.sh-conversion arc CLOSED (.41),
  `lib/regression.cyr` 79th stdlib testing-stdlib carve-out
  (.42, 22 verbs across display/buffer-scan/process/network/SSH).
  Self-host byte-identical at 751,744 B.
- `content/cyrius/language/index.cyml` verified-on bumped to
  5.9.42; `content/cyrius/language/stdlib_modules.cyml` adds
  16th entry documenting `regression_module`.
- `docs/development/content-format.md` extended to document the
  two non-topic entries under `content/`: the `cyrius/`
  language-reference subtree and `qelib1.inc` (load-bearing
  shared OpenQASM include — qiskit `include_path=[content/]`).
  Resolves the long-standing 76-vs-74 entry-count confusion in
  `ls content/` output.

### Added

- `[deps.vyakarana]` in `cyrius.cyml` pinned at **1.11.1**;
  `lib/vyakarana.cyr` vendored via `cyrius deps` (2547 lines;
  inlines all 38 grammars via `_grammar_blob_data` so consumers
  don't need `grammars/*.cyml` at runtime cwd).
- **`vidya code <topic> <lang>` CLI** — prints source with
  vyakarana token coloring (ANSI: keyword=blue, string=green,
  number=cyan, comment=dim, operator=magenta, preprocessor=
  yellow, error=red-bg). Falls back to plain source for
  languages without a vyakarana grammar (OpenQASM in 1.11.x).
- **`GET /code/{topic}/{lang}` HTTP route** — JSON response
  `{topic, language, path, source, tokens:[{kind, start, len}]}`.
  Theme contract per vyakarana ADR 0004: consumers index palettes
  by `kind` string, never by integer. Smoke-verified end-to-end:
  2187 tokens on the rust track of `content/lexing_and_parsing/`
  (8829 source bytes); OpenQASM gracefully returns `tokens:[]`.

### Fixed

- Repo hygiene: removed 7× `qemu_*.core` debris (~57 MB) from
  repo root left behind by 2026-05-02 aarch64 cross-test runs.
  Already gitignored (`*.core` + `qemu_*.core`); was a working-
  tree leak only.

## [2.6.4] — 2026-05-03

**P3 complete — `embeddings` shipped at 11/11 languages.**
Closes the Audio + AI/ML minor (5 topics × 11 langs over
2.6.0–2.6.4).

Three vector-search primitives in Q15 fixed-point:
- **Cosine similarity** as a plain dot product over pre-normalized
  unit vectors (the production trick — normalize once at insert,
  cosine is sqrt-free at query time)
- **Brute-force nearest-neighbour** scan
- **Top-k neighbours** via repeated argmax-on-unmarked

Hand-designed 4-vector unit-length corpus (axis-aligned + diagonal +
opposite) demonstrates: self-similarity ≈ 1.0, orthogonal = 0,
opposite ≈ -1.0, ranking by alignment, all bit-identical across
ports.

11 new source files; validator 803/803 → **814/814**. **🎉 P3
Audio + AI/ML complete — 5/5 topics × 11 langs landed.**

### Added

- `content/embeddings/` — vector-search primitives across 11
  languages: cyrius (13 tests / 23 asserts), HLLs (13 tests /
  16–17 asserts each), asm pair (9 tests / 9 asserts focused on
  dot + brute-force nearest; top-k mark/scan/zero in cyrius.cyr —
  too verbose for asm), OpenQASM (inner-product-as-overlap: SWAP
  test with cswap decomposed as cx + ccx + cx since qiskit
  qasm2's standard set excludes cswap).

## [2.6.3] — 2026-05-03

**P3 batch 4 — `inference` shipped at 11/11 languages.**
Three decode-time primitives in pure integer arithmetic: greedy
decoding (argmax over logits), top-k filtering (zero out all but
the K highest), and an autoregressive bigram decode loop with
EOS termination + max_length cap.

Hand-designed bigram table demonstrates greedy decode from
"hello" → "world" → "the" → "end" → EOS, deterministic across
all ports.

Skipped intentionally: temperature scaling, softmax, random
sampling — those need either exp() or a portable PRNG, both of
which fight cross-port portability (especially asm + shell).
concept.toml covers them as best practices and gotchas.

11 new source files; validator 792/792 → **803/803**. P3 is 4/5
topics in flight; `embeddings` (2.6.4) closes P3.

### Added

- `content/inference/` — inference decode primitives across 11
  languages: cyrius (10 tests / 29 asserts), HLLs (10 tests /
  17–21 asserts each — variations from per-element vs array
  comparisons), asm pair (5 tests / 9 asserts focused on argmax
  + bigram lookup + decode loop; top-k's triple-nested
  mark/scan/zero pattern lives in cyrius.cyr — too verbose for
  asm), OpenQASM (measurement-as-greedy-decode: ry encodes
  logits as amplitudes, measurement collapses to argmax, top-k
  modeled as amplitude amplification).

## [2.6.2] — 2026-05-03

**P3 batch 3 — `neural_networks` shipped at 11/11 languages.**
Tiny 2 → 3 → 2 MLP forward pass in Q15 fixed-point. Three
primitives (dense layer, ReLU, argmax) composed into a binary
classifier on hand-designed weights — predicts which input
feature is larger.

Skips softmax intentionally: argmax preserves order, and
production inference does the same (softmax is a training-time
construct for cross-entropy loss). This keeps the example pure
integer arithmetic across all 11 ports — no exp() approximation
needed.

11 new source files; validator 781/781 → **792/792**. P3 is 3/5
topics in flight; `inference` + `embeddings` slated for
2.6.3–2.6.4.

### Added

- `content/neural_networks/` — Q15 MLP forward pass across 11
  languages: cyrius (12 tests / 21 asserts), HLLs (12 tests / 16
  asserts each — HLLs collapse the per-element ReLU checks into
  array-equality), asm pair (8 tests / 8 asserts focused on full
  forward pass through dense + ReLU + argmax with hardcoded layer
  sizes), OpenQASM (rotation-as-weighted-sum: ry encodes inputs as
  amplitudes, cu3 applies controlled rotations as weights, reset
  models ReLU, measurement models argmax). One AArch64 gotcha
  surfaced: `mov w0, #-N` zero-extends to a large positive i64
  before mul; use `mov x0, #-N` for negative immediates.

## [2.6.1] — 2026-05-03

**P3 batch 2 — `audio_synthesis` shipped at 11/11 languages.**
Q15 fixed-point synth primitives (oscillators, ADSR envelope,
voice). API surface mirrors the production AGNOS synth crate
`naad` (Waveform, Adsr, EnvelopeState, gate_on/off, Voice) so
the corpus example reads as a portable educational version of
the same algorithms — naad uses f32 + PolyBLEP for production;
this corpus uses Q15 + naive waveforms for clarity and bit-exact
cross-port portability.

Three primitives:
- **Oscillator** — 16-bit phase accumulator + 16-entry Q15 sine
  LUT, naive saw (linear ramp), naive square (sign-of-phase).
- **ADSR envelope** — 5-state machine (Idle → Attack → Decay →
  Sustain → Release → Idle). Linear segments, sample-counted
  phases. Captures `release_start` at gate_off so Release
  ramps from current level (the click-on-early-release fix).
- **Voice** — oscillator × envelope, sample by sample.

11 new source files; validator 770/770 → **781/781**. P3 is 2/5
topics in flight; `neural_networks`, `inference`, `embeddings`
slated for 2.6.2–2.6.4.

### Added

- `content/audio_synthesis/` — Q15 synth primitives across 11
  languages: cyrius (11 tests / 25 asserts), HLLs (11 tests / 25
  asserts each — naad-style API names), asm pair (8 tests / 13
  asserts focused on phase + sine LUT + square + ADSR full state
  machine; saw + Voice dispatch in cyrius.cyr — too verbose for
  asm), OpenQASM (rotation-as-oscillation: `ry` advances phase,
  H+Z prepares square, `ccx` gates voice on env × osc).

## [2.6.0] — 2026-05-03

**P3 kickoff — Audio + AI/ML (minor bump)** — `audio_dsp`
shipped at 11/11 languages. Q15 fixed-point throughout (matches
hardware PCM, bit-exact across language ports).

Three building blocks:
- **Biquad filter** — Direct Form I IIR with 5 coefs (b0,b1,b2,a1,a2)
  + 4 state slots; one topology, every filter shape. 1-pole lowpass
  helper demonstrated under tests (passes DC, attenuates Nyquist).
- **FIR convolution** — N-tap kernel with shifting history; identity
  + moving-average kernels under test.
- **Level metering** — peak (max abs) and mean-absolute over a
  sample buffer.

11 new source files; validator 759/759 → **770/770**. P3 is 1/5
topics in flight; `audio_synthesis`, `neural_networks`,
`inference`, `embeddings` slated for 2.6.1–2.6.4.

### Added

- `content/audio_dsp/` — Q15 fixed-point DSP across 11 languages:
  cyrius (9 tests / 17 asserts), HLLs (9 tests / 14 asserts each
  — collapse the q_mul-bounds-check pair into a single range),
  asm pair (8 tests / 10 asserts focused on biquad lowpass + peak
  + mean-absolute; FIR omitted — variable-size kernels too verbose
  for asm), OpenQASM (interference-as-filtering: ry rotation as
  filter coefficient, Hadamard interference as 2-tap moving-avg,
  Toffoli OR as peak-detection).

## [2.5.2] — 2026-05-03

**P2 complete — `distributed_systems` shipped at 11/11 languages.**
Closes the Distributed Systems minor (3 topics × 11 langs over
2.5.0–2.5.2).

The topic covers three foundational patterns not subsumed by
`transactions_and_acid` or `consensus`:

- **Vector clocks** — per-node logical counters with element-wise
  compare returning LESS / EQUAL / GREATER / **CONCURRENT** (the
  fourth outcome that integer compare doesn't have)
- **Quorum reads/writes** — Dynamo-style N=3, W=R=2, where R+W>N
  intersection guarantees every read quorum overlaps the latest
  write quorum
- **Partition handling** — partition / heal a node, demonstrate
  write-quorum failures on the minority side, and intersection-
  based stale-data avoidance after heal

11 new source files; validator 748/748 → **759/759**. P2 is
**3/3 done**; next minor (2.6.x) opens **P3 audio + AI/ML**.

### Added

- `content/distributed_systems/` — three foundations across 11
  languages: cyrius (12 tests, 26 asserts), HLLs (12 tests, 17
  asserts each — HLLs collapse repetitive vector-clock comparisons
  into single equality assertions), asm pair (5 tests, 11 asserts
  focused on the quorum-replication core; vector clocks live in
  cyrius.cyr — element-wise compare too verbose for asm),
  OpenQASM (entanglement-as-replication: CNOT fan-out for write
  quorum, measurement of read quorum demonstrates the intersection
  guarantee).

## [2.5.1] — 2026-05-03

**P2 batch 2 — `consensus` (Raft) shipped at 11/11 languages.**
3-node Raft cluster modelled as in-memory state machines.
Demonstrates the five Raft safety properties under tests:

- **Term monotonicity** — terms only increase; stale RPCs rejected
- **Election safety** — vote uniqueness (one vote per node per term)
- **Log matching** — replicate copies leader's log entry-by-entry
  with term-mismatch truncation
- **Leader completeness** — log up-to-date check on RequestVote
  denies candidates with shorter or stale logs
- **State machine safety** — `advance_commit` only commits entries
  from the leader's CURRENT term; prior-term entries are committed
  indirectly when a current-term entry above them commits
  (the Figure-8 rule)

11 new source files; validator 737/737 → **748/748**. P2 is 2/3
topics in flight; `distributed_systems` slated for 2.5.2.

### Added

- `content/consensus/` — 3-node Raft across 11 languages: cyrius
  (10 tests, 42 asserts), HLLs (10 tests, 41 asserts each — Cyrius's
  extra assert is a redundant log-match split that the HLLs do via
  tuple equality), asm pair (6 tests, 12 asserts focused on the
  election state machine — no log replication; see cyrius.cyr for
  that), OpenQASM (vote-as-measurement: voter qubits measured for
  uniqueness, Toffoli for majority detection, gate-depth for term
  monotonicity).

## [2.5.0] — 2026-05-03

**P2 kickoff — Distributed Systems (minor bump)** —
`transactions_and_acid` shipped at 11/11 languages. OCC store with
explicit read-set/write-set tracking; demonstrates the four ACID
properties under tests. Atomicity (commit installs all-or-nothing,
abort discards), Consistency (transfer preserves balance invariant),
Isolation (no dirty reads in HLLs; OCC version-snapshot detects
write-write conflicts in all 11 langs), Durability (committed state
survives "crash-recovery" wipe of tx scratch).

11 new source files; validator 726/726 → **737/737**. P2 is 1/3
topics in flight; `consensus` + `distributed_systems` slated for
2.5.1 / 2.5.2.

### Added

- `content/transactions_and_acid/` — OCC transaction store across
  11 languages: cyrius, rust, python, c, go, typescript, shell, zig,
  asm_x86_64, asm_aarch64, openqasm. The Cyrius reference tests 9
  scenarios with 23 assertions (full multi-tx with dirty-read
  prevention + conflict detection); HLL ports mirror that. The asm
  ports cover a focused single-tx subset (atomicity, consistency,
  durability, OCC validation — 12 asserts each). OpenQASM models
  entanglement-as-commit with a controlled-fan-out gate as the
  all-or-nothing primitive.

## [2.4.4] — 2026-05-03

**Cyrius pin bump 5.8.19 → 5.8.34** — patch-level alignment with
upstream cyrius. No source changes required: build clean, all 41
tests pass, validator 726/726 unchanged. CLI surface identical
across the bump (no verbs added/removed/renamed). Field-notes
verification range extended.

### Changed

- `cyrius.cyml` — `cyrius = "5.8.19"` → `cyrius = "5.8.34"`.
- `content/cyrius/field_notes/index.cyml` — verification range
  `Cyrius 2.2 → 5.8.19` → `Cyrius 2.2 → 5.8.34`.
- `cyrius.lock` refreshed via `cyrius deps`.

## [2.4.3] — 2026-05-02

**Cyrius reference closeout — content/cyrius/ now organized as
it should be, not as it accreted.** Two surfaces both retired
into purpose-built layouts in a single release: the 4144-line
monolithic `language.cyml` (73 entries) split into a
usage-organized `language/` subfolder, and the chronological
per-version `compiler/` field notes (8 files, 60 entries)
recast as topical (gotchas / methodology / patterns) plus a
`retros/` subfolder for chronological narrative.

This is the long-overdue closeout of the incremental cyrius
content cleanup that's been happening since v2.3.1 (field-notes
subfolder split). End state: humans and agents now get the
best docs for where the project is right now — surface-area
organized, current-state focused, no archaeology required.

Plus cyrius pin bump 5.8.18 → 5.8.19 (no source changes).

### Changed — content/cyrius/language/ (NEW subfolder, 6 files, 52 entries)

Retired `content/cyrius/language.cyml` (4144 lines, 73 entries).
Replaced with topical-by-surface-area subfolder:

- **`index.cyml`** — TOC + section markers.
- **`core.cyml`** (7 entries) — overview, syntax,
  compiler_architecture, development_loop, known_limitations,
  porting_guide, stdlib catalog. Version-specific noise trimmed
  from the prior overview.
- **`features.cyml`** (16 entries) — every "how to use this
  language feature" entry: multi_width_types, sizeof_operator,
  unions, bitfield_builtins, struct_field_widths,
  expression_type_propagation, defer_statement, ifplat_directive,
  enum_namespacing, ref_directive, ret2_rethi,
  continue_in_for_loops, derive_str_fields,
  secret_var_compound_ops, slice_type_v58x, relaxed_fn_ordering.
- **`stdlib_modules.cyml`** (12 entries) — per-module usage:
  atoi_stdlib, f64_atan_and_math_lib, base64_module,
  chrono_module, file_locking, csv_module, http_module,
  patra_stdlib_module, strstr_function, hashmap_str_keys,
  fncall_ceiling, identity_lookups_musl_pattern.
- **`tooling.cyml`** (14 entries) — compiler binaries + CLI
  driver + verbs + format files (.tcyr/.bcyr/.fcyr/.scyr/.smcyr)
  + cyml + cyrius.cyml manifest + object directive + env vars +
  flags + LSP plugins + helper scripts + release pipeline +
  audit/test/check pipeline + minimum compiler version pin.
- **`agents.cyml`** (3 entries) — cyrius_for_agents,
  tcyr_test_conventions, agent_anti_patterns.

### Changed — content/cyrius/field_notes/compiler/ (REORGANIZED, 9 files, 46 entries)

Retired the chronological per-version layout
(pre_v3 / v3 / v4 / v5_0_to_5_4 / v5_5 / v5_6 / v5_7 / v5_8.cyml,
60 entries) in favor of topical files for current-work lookups,
with chronological narrative preserved in a `retros/` subfolder.

- **`compiler/index.cyml`** — per-entry TOC for the new layout.
- **`compiler/patterns.cyml`** (7 entries) — reusable design +
  convention patterns. Earn their slot when an agent is making
  a structural decision: ship_now_swap_backend_later,
  dist_bundle_stdlib_dep_convention,
  heap_cap_growth_compiler_grows_to_fit_language,
  version_string_via_generated_source_not_hardcoded,
  stdlib_hook_surface_via_fn_pointer_not_callback_registry,
  object_mode_pic_codegen_no_textrel,
  research_first_optimizer_dce_cfg_lessons.
- **`compiler/methodology.cyml`** (8 entries) — how to debug,
  scope, verify slot premises, triage cross-repo bugs.
  premise_check_at_slot_entry,
  perf_test_dont_assume_correctness_isnt_perf,
  verify_outputs_not_just_exit_codes,
  verify_slot_premise_before_investing,
  triage_dep_boundary_per_row_checksum,
  ci_drift_detection_silent_skip_is_false_green,
  ci_drift_detection_orphaned_path_is_certain_drift,
  anticipated_gotcha_pre_flight_v55x.
- **`compiler/gotchas.cyml`** (12 entries) — non-obvious traps
  in cyrius internals: slice_fn_local_layout_flip,
  slice_high_half_regalloc_pin, tail_call_escape_addr_local,
  pointer_vs_inline_struct_dispatch, stale_fixed_cap_drift,
  stdlib_alloc_grow_step_must_cover_request,
  libssl_needs_fdlopen_not_dynlib_open,
  sysv_odd_stack_args_rsp_alignment,
  pp_pass_helpers_take_src_base,
  ts_lex_jsx_lookahead_terminators,
  fn_keyword_in_param_position,
  lsp_globals_before_fn_definitions.
- **`compiler/retros/`** subfolder — per-version chronological
  narrative preserved for backstory:
  - `pre_v3.cyml` (5 entries) — v0.9–v1.x feature lists +
    cyrius-x VM
  - `v3.cyml` (9 entries) — v3.0 retrospective + v3.3-3.6
    release arcs
  - `v4.cyml` (3 entries) — v4.0 reflections + v4.8.x handoff
  - `v5_chronicle.cyml` (1 entry) — per-cycle v5.x feature lists
  - `v58x_agent_perspective.cyml` (1 entry) — v5.8.x slices
    sub-arc agent's view

### Changed — pin + index

- **Cyrius pin 5.8.18 → 5.8.19** (`cyrius.cyml`). No source
  changes required. Field-notes verification range bumped to
  5.8.19.
- **`field_notes/index.cyml`** — compiler/ section rewritten
  end-to-end to point at the topical layout (`compiler/index.cyml`
  carries the per-entry TOC). The 60-line per-version enumeration
  collapsed to an 8-line per-file pointer.

### Removed

- **`content/cyrius/language.cyml`** — 4144 lines retired.
- **~19 resolved/duplicate entries** dropped from the old
  language.cyml (the fix is in the compiler now and no agent
  action is needed): findvar_last_match, include_path_fallback,
  gt6_args_fix, cyrb_to_cyrius_rename, gvar_expansion,
  p_minus_1_hardening, tail_call_gt6_fix, str_data_expansion,
  constant_fold_identity, patra_module (superseded by
  patra_stdlib_module), function_table_2048,
  nested_while_codegen_bug + …_documented (resolved
  v3.4.6-3.4.9), derive_integers_fix, platform_stubs (Mach-O + PE
  actually work now), cc3_rename (cc5 era), and a few others.
- **~14 entries** consolidated out of the chronological compiler/
  per-version files when reshaped into topical patterns/
  methodology/gotchas (60 → 46 entries via dedup of release-arc
  rollups whose durable lessons now live in the topical files).

### Verified

- `cyrius test` 41/41 passing.
- `scripts/validate-content.sh` 726/726 (no content topics
  changed; `cyrius/` is skipped by the loader anyway).
- `vidya stats`: Topics 66, Complete 66 (all 11 languages),
  Examples 726 — unchanged.

### Notes

- This release closes out the incremental cyrius content
  cleanup that's been happening since v2.3.1's field-notes
  subfolder split. Both `language/` and `compiler/` surfaces
  now follow the same per-surface-area split convention,
  with one TOC file per directory and topical files sized
  for actual lookup workflows (current work) rather than
  chronological accretion (release archaeology).
- VERSION 2.4.2 → 2.4.3.

## [2.4.2] — 2026-05-02

**P1 Networking & Infrastructure complete.** Final 2 topics ship
+ cyrius pin bump 5.8.14 → 5.8.18.

### Added
- **P1 batch 3 — final 2 new topics × 11 languages each, +22
  source files** (validator sweep 704/704 → 726/726):
  - **`ipc`** — new topic. In-memory simulation of three IPC
    primitives: shared memory (multi-region byte buffer with
    multi-reader visibility), bounded FIFO pipe with
    full/empty semantics + ring-buffer wrap-around, and
    named-endpoint message channel (Unix-socket-shaped) with
    per-endpoint queues. 18 assertions covering shm OOB
    rejection, pipe FIFO + full + post-drain wrap, channel
    send-to-closed rejection, channel FIFO recv. OpenQASM
    uses Bell-pair entanglement as the shared-memory analog
    + CNOT chains as the pipe transfer.
  - **`serialization`** — new topic. Varint (LEB128) encode/
    decode + length-prefix framing + stream parser. 19
    assertions covering: varint sizes (1 byte for <128, 2
    for <16384, 3 for <2^21), round-trip, MAX_VARINT_BYTES=10
    overflow guard (the DoS gotcha), frame round-trip, stream
    parse over 3 back-to-back frames, truncated-frame
    rejection, oversize-length rejection (the malloc-bomb
    guard). OpenQASM uses CNOT chains as the
    continuation-bit dependency analog.
- **Cyrius pin 5.8.14 → 5.8.18** (`cyrius.cyml`). No source
  changes required. Field-notes verification range bumped to
  5.8.18.

### Changed
- **VERSION** 2.4.1 → 2.4.2.
- **Topic coverage**: 66 topics, 64 → 66 fully covered. Per-
  language counts (each):
  - All 11 languages: 64 → 66.
  - Examples: 704 → 726 (+22 new source files; +3.1%).

### Notes (recurring patterns worth field-noting)
- **Bash nameref self-cycle warning** (`local: warning: buf:
  circular name reference`). Hit in `serialization/shell.sh`
  when `decode_frame()` had `local -n buf=$1` and then called
  `decode_varint buf $buf_len` — the inner function's
  `local -n buf=$1` saw `buf` as both its declared name and
  its target, producing a cycle. Fix: pass the original $1
  through (`decode_varint $buf_arg $buf_len`) so the inner
  function's nameref points at the caller's caller's variable
  directly. Worth a `bash_nameref_self_cycle` field-note
  entry — this is the second time it's bitten in vidya
  content (first was in compression/shell.sh's PORT_TO_SOCK).
- **Zig u6 shift overflow on 11-byte varint bomb** in
  `serialization/zig.zig`. Iterating MAX_VARINT_BYTES=10
  times with `shift += 7` reaches 63 at the end of iteration
  9; the 10th iteration's `shift += 7` overflows u6 (max 63)
  before the loop's bounds check returns null. Fix: widen
  the shift counter to u32 (or usize) and `@intCast` when
  used. Relevant for any varint decoder in Zig that uses
  bitshift typed too narrowly.
- **x86_64: 3-register addressing modes are illegal**. Hit
  in `serialization/asm_x86_64.s`: `[rbx + r9 + rcx]` and
  `[r13 + rcx + r9]` produced "not a valid base/index
  expression". x86_64 allows `[base + index*scale + disp]`
  (max 2 registers + scale + displacement). Fix: fold one
  pair into a temp register first
  (`mov r8, r9; add r8, rcx; ... [rbx + r8]`). Worth a
  field-note entry.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean (under
  cyrius 5.8.18).
- `cyrius test` — 41/41 passing (no regressions across the
  pin bump).
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **726/726 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 66, Complete: 66 (all 11
  languages), Examples: 726`.

### P1 complete (6 of 6) 🎉

| Topic | Status |
|---|---|
| networking_fundamentals | ✅ shipped 2.4.0 |
| http_and_web_protocols | ✅ shipped 2.4.0 |
| tls_and_encryption | ✅ shipped 2.4.1 |
| dns | ✅ shipped 2.4.1 |
| ipc | ✅ shipped 2.4.2 |
| serialization | ✅ shipped 2.4.2 |

P1 Networking & Infrastructure cluster fully landed. After
v2.4.2: 66 topics × 11 languages = **726 source files**, all
validated. P0 → P0C → P1 arc complete.

**Next minor (2.5.x): P2 — Distributed Systems.**
transactions_and_acid, consensus, distributed_systems.
Subsumes the original `database_fundamentals` (already
covered as `btree_indexing` + `write_ahead_logging` in
P0C-3); builds on `concurrent_file_access` (P0C-4).

## [2.4.1] — 2026-05-02

P1 Networking & Infrastructure — second batch (2 of the planned 6
new topics). 4/6 P1 topics shipped after this release.

### Added
- **P1 batch 2 — 2 new topics × 11 languages each, +22 source
  files** (validator sweep 682/682 → 704/704):
  - **`tls_and_encryption`** — new topic. Simulation of the four
    load-bearing TLS 1.3 primitives: handshake state machine
    (INIT → HELLO_SENT → SERVER_HELLO → CERT_VERIFIED →
    ESTABLISHED), cipher suite negotiation (TLS 1.3 only —
    rejects 0x002F legacy 1.2 ciphers), certificate chain
    validation (issuer/subject linkage to a trust root,
    rejecting self-signed leafs), AEAD seal/open with auth-tag
    verification (XOR + sum stub captures the structural
    property: any byte flip in ciphertext rejects). Hostname-
    mismatch path tested end-to-end. 16 assertions; 5 in the
    asm focused subset. OpenQASM uses Bell-pair entanglement
    as the ECDHE shared-secret + cert-chain analog.
  - **`dns`** — new topic. In-memory DNS resolver simulation:
    small zone (A/AAAA/CNAME/MX/TXT records), recursive lookup
    that follows CNAME chains with a 16-hop depth bound (per
    RFC convention; libcurl/BIND both use 16), TTL cache with
    monotonic logical clock + advance_time() for deterministic
    expiry tests, negative caching for NXDOMAIN. Tests cover:
    CNAME chain following, CNAME loop detection (depth-bounded),
    cache hit vs miss, post-expiry re-query, negative cache,
    coexisting record types for the same name. 15 assertions;
    5 in the asm focused subset. OpenQASM uses CNOT chaining
    as the recursive-resolution analog.

### Changed
- **VERSION** 2.4.0 → 2.4.1.
- **Topic coverage**: 64 topics, 62 → 64 fully covered. Per-
  language counts (each):
  - All 11 languages: 62 → 64.
  - Examples: 682 → 704 (+22 new source files; +3.2%).

### Notes (recurring patterns worth field-noting)
- **Cyrius `var name[N]` is N BYTES, not N elements** — bit
  again writing `tls_and_encryption/cyrius.cyr`. `var
  leaf_cert[2]` allocates 2 bytes (one byte each for subject
  and issuer), not 2 i64s; the chain pointer-array
  `var chain[8]` allocates 8 bytes (1 ptr) instead of 24 bytes
  (3 ptrs). Already documented in field-note
  `var_name_bracket_is_bytes_not_elements` — this is the 4th+
  time it's bitten in vidya content. Worth promoting to a
  more-prominent CLAUDE.md DO note.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **704/704 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 64, Complete: 64 (all 11
  languages), Examples: 704`.

### P1 progress (4 of 6)

| Topic | Status |
|---|---|
| networking_fundamentals | ✅ shipped 2.4.0 |
| http_and_web_protocols | ✅ shipped 2.4.0 |
| tls_and_encryption | ✅ shipped 2.4.1 |
| dns | ✅ shipped 2.4.1 |
| ipc | planned 2.4.2 |
| serialization | planned 2.4.2 |

## [2.4.0] — 2026-05-02

**Minor bump opening P1 — Networking & Infrastructure.** First
new thematic addition since v2.2. Two new topics added (the first
2 of the planned P1 set of 6); v2.4.0/2.4.1/2.4.2 will each ship
2 topics, mirroring the v2.3.x cadence.

### Added
- **P1 cluster — 2 new topics × 11 languages each, +24 source
  files** (validator sweep 660/660 → 682/682):
  - **`networking_fundamentals`** — new topic. In-memory TCP
    socket state machine + lifecycle (no real syscalls): bind,
    listen, connect, accept, send, recv, close. 6-state subset
    of RFC 793 (CLOSED, LISTEN, SYN_RCVD, ESTABLISHED, FIN_WAIT,
    CLOSED). 19 assertions covering: fresh socket starts CLOSED,
    bind+listen transition to LISTEN, two-way connect brings both
    ends to ESTABLISHED, send/recv echoes bytes through, close
    transitions to CLOSED, port reuse rejected while in-use,
    recv on CLOSED returns -1, port becomes available after
    close. OpenQASM uses Bell-pair entanglement as
    handshake-establishes-connection analog.
  - **`http_and_web_protocols`** — new topic. HTTP/1.1 request
    parser. Sequential parse: request line → headers → body
    (RFC 9112). Header names normalized to lowercase for
    case-insensitive lookup (RFC 9110 §5.1). Body framing via
    Content-Length. 24 assertions covering: simple GET parses,
    method/path/version extracted, case-insensitive header
    lookup (Host == host == HOST), multiple headers, POST
    with body, body containing CRLF preserved (the parser
    bug that truncates POST payloads is a real concept.toml
    gotcha), malformed request rejected, absent header lookup
    returns null. Asm ports verify the parsing primitive
    (find_crlf scan + memeq) on known-shape requests.

### Changed
- **VERSION** 2.3.10 → **2.4.0** (minor bump — opens P1).
- **Topic coverage**: 62 topics, 60 → 62 fully covered. Per-
  language counts (each):
  - All 11 languages: 60 → 62.
  - Examples: 660 → 682 (+22 new source files; +3.3%).

### Notes (recurring patterns worth field-noting)
- **Bash `unset 'arr[ARR[s]]'` doesn't expand the inner array
  reference.** Captured in `networking_fundamentals/shell.sh`
  during port: `unset 'PORT_TO_SOCK[PORT[s]]'` failed to
  remove the entry, leaving the port "in use" after close. Fix:
  capture to a scalar first — `local p=${PORT[s]}; unset
  "PORT_TO_SOCK[$p]"`. Worth a `bash_unset_inner_array_ref`
  field-note entry once it bites a third time.
- **Zig `@memset` on >100KB global arrays trips a codegen
  bug.** `var port_to_sock: [65536]usize = ...; @memset(&port_to_sock, 0);`
  produced "emit MIR failed: InvalidInstruction (Zig compiler
  bug)" on the current Zig version. Workaround: replace the
  large fixed-size global with a smaller indirect (linear-scan
  pmap with SOCK_CAP entries). Worth tracking — likely
  upstream-fixable but the workaround is also genuinely
  smaller-data.
- **Cyrius reserves `match` as a keyword.** Hit in
  `http_and_web_protocols/cyrius.cyr` writing the header-lookup
  comparison loop. Renamed to `is_match`. Add to the parser-
  syntax field-notes if it surfaces in another port.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **682/682 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 62, Complete: 62 (all 11
  languages), Examples: 682`.

### P1 progress (2 of 6)

| Topic | Status |
|---|---|
| networking_fundamentals | ✅ shipped 2.4.0 |
| http_and_web_protocols | ✅ shipped 2.4.0 |
| tls_and_encryption | planned 2.4.1 |
| dns | planned 2.4.1 |
| ipc | planned 2.4.2 |
| serialization | planned 2.4.2 |

## [2.3.10] — 2026-05-02

**P0C-2c — final P0C patch.** All 60 topics now at 11/11
languages. P0 → P0C arc complete: every programming concept
in vidya's reference shelf has a working, tested implementation
in all 11 supported languages.

### Added
- **P0C-2c cluster — 2 topics × 11 languages each, +22 source
  files** (validator sweep 638/638 → 660/660):
  - **`direct_drm_gpu_compute`** — 11 new lang files (concept-
    only topic; cyrius reference designed first). In-memory
    simulation of the GEM BO → VA-map → submit → syncobj-wait
    flow that AMDGPU compute-MVP code targets. Models the
    kernel-side state (BO table, per-process VA map,
    submission queue, syncobj timeline) so the test surface
    is byte-deterministic. 20 assertions covering: open
    render node returns a non-zero fd, gem_create returns
    sequential handles starting at 1, gem_va_map binds
    handles, va_lookup hits/misses, va_map rejects invalid
    handles, submit returns increasing seqs, syncobj_wait for
    past/current/future, gem_destroy invalidates the VA
    mapping, submit on a destroyed BO is rejected. OpenQASM
    uses qubit-as-BO + CNOT sync chain analog.
  - **`render_graph_architecture`** — 11 new lang files. Tiny
    DAG framework where each pass declares reads/writes as
    bitmasks; the graph derives execution order, barrier
    count, and dead-pass culling from those declarations.
    Mirrors the small load-bearing core that
    Frostbite/UE5/Granite all converged on. 14 assertions
    covering: linear A→B→C add_pass + topo sort, barrier
    count from write→read edges, dead-pass culling (writer
    with no readers gets zeroed), cycle detection (Kahn-style
    sort emits 0 passes when a cycle is present). OpenQASM
    uses qreg-as-resource + gate-as-pass analog (Qiskit's
    DAGCircuit is exactly this pattern).

### Changed
- **VERSION** 2.3.9 → 2.3.10.
- **Topic coverage**: 60 topics, **58 → 60 fully covered, 0
  partial**. Per-language counts (each):
  - All 11 languages: 58 → 60.
  - Examples: 638 → 660 (+22 new source files; +3.4%).

### Resolved
- **The lingering 47→48 discrepancy from v2.3.5**. Various
  CHANGELOG entries through v2.3.4–v2.3.9 carried slightly
  off-by-one historical accounting (e.g. v2.3.4 reported
  "44 → 47 fully covered" when the post-v2.3.3 baseline
  per its own count was 33, not 44). The discrepancy was
  legacy bookkeeping noise that accumulated as topics moved
  from "concept-only" to "fully covered" in batches. Now
  permanently moot: **all 60 topics are at 11/11; the loader
  reports 60/60; the on-disk count matches.** No further
  reconciliation needed.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings, no new issues.
- `scripts/validate-content.sh` — **660/660 green**, 0 failed,
  0 skipped (full toolchain locally available).
- `vidya stats` reports `Topics: 60, Complete: 60 (all 11
  languages), Examples: 660`.

### P0 → P0C complete

The original 36 P0 topics (v2.0) plus 24 added across v2.3.2–v2.3.10:
- v2.3.2 (1): fixed_point_arithmetic
- v2.3.3 P0C-1 (8): collision_detection_2d, game_ai_decisions,
  game_loop_architecture, grid_pathfinding, maze_generation,
  projectile_physics, sprite_rendering, state_machines
- v2.3.4 P0C-3 (3): btree_indexing, sql_parsing, write_ahead_logging
- v2.3.7 P0C-4 (4): compression, concurrent_file_access,
  jsonl_format, page_management
- v2.3.8 P0C-2a (3): framebuffer_rendering, line_rasterization,
  bloom_and_glow
- v2.3.9 P0C-2b (3): bindless_resources, gpu_memory_pooling,
  explicit_gpu_synchronization
- v2.3.10 P0C-2c (2): direct_drm_gpu_compute, render_graph_architecture

Total: 36 + 24 = 60 topics × 11 languages = 660 source files,
660/660 validated. **Next minor (2.4.0) opens P1 — Networking &
Infrastructure** (networking_fundamentals, http_and_web_protocols,
tls_and_encryption, dns, ipc, serialization).

## [2.3.9] — 2026-05-02

P0C-2b graphics batch 2 — 3 topics × 11 languages each (33 new
source files). Largest "first-try clean" run of the v2.3.x arc:
all 33 files passed validation on the first build, no asm or
language-specific debugging required.

### Added
- **P0C-2b cluster — 3 topics × 11 languages each, +33 source
  files** (validator sweep 605/605 → 638/638):
  - **`bindless_resources`** — 11 new lang files (concept-only
    topic; cyrius reference designed first). 64-slot global
    descriptor table with slot 0 reserved as null sentinel
    (matching the page_management pattern). LIFO free-list for
    reuse, sequential bump for fresh allocations. 15 assertions
    covering: sequential alloc returns 1/2/3, slot 0 reserved,
    lookup roundtrip, update preserves ID, free + reuse via
    free-list LIFO, exhaustion returns 0 (null sentinel).
    OpenQASM uses qubits-as-handle-slots analog with
    X/measure/reset for alloc/lookup/free.
  - **`gpu_memory_pooling`** — 11 new lang files. Bump
    allocator over a 1024-byte pool — the "transient per-frame,
    reset on frame boundary" shape from concept.toml's first
    BP. `alloc(size)` returns offsets, `-1` sentinel on
    exhaustion. `alloc_aligned(size, align)` rounds bump up
    to the requested boundary first. `reset()` recycles the
    entire pool atomically. 16 assertions covering initial
    state, sequential allocs, exhaustion, reset + reuse,
    alignment rounding, alloc(0) no-op, monotonic-sum
    invariant across many small allocs.
  - **`explicit_gpu_synchronization`** — 11 new lang files.
    Two timeline semaphores (compute + transfer queues) —
    concept.toml's "monotonic frame counter / timeline
    wait/signal" escape-hatch primitive. `signal(sem, value)`
    advances iff value strictly greater than current (rejects
    regression to enforce monotonicity); `wait_for(sem,
    target)` returns 0/1 reachability; `wait_all(c_target,
    t_target)` is the multi-queue render-graph integration
    pattern — only proceeds when BOTH queues are at or past
    their targets. 19 assertions covering init, signal
    advance, past/current/future wait reachability, regression
    rejection (both `<` and `==`), multi-sem wait_all matrix
    (4 cases), monotonic invariant across 10 sequential
    signals. OpenQASM uses CNOT entanglement chains as
    quantum-fence analog (producer broadcasts state to
    consumers via Bell-pair pattern).

### Changed
- **VERSION** 2.3.8 → 2.3.9.
- **Topic coverage**: 60 topics, 55 → 58 fully covered. Per-
  language counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 55 → 58
  - x86_64 ASM / AArch64 ASM: 55 → 58
  - Cyrius: 55 → 58 (all 3 topics designed cyrius.cyr first)
  - Examples: 605 → 638 (+33 new source files; +5.5%).

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings (lines 821/822/1141), no new issues.
- `scripts/validate-content.sh` — **638/638 green**, 0 failed,
  0 skipped (full toolchain locally available).
- All 33 new files passed first-build validation. The asm
  ports applied the v2.3.8 lessons (callee-saved register
  caching across `bl/call`, `shl` instead of `imul reg, sym`)
  by reflex; no asm rework needed.

## [2.3.8] — 2026-05-02

P0C-2a graphics batch 1 — 3 topics × 11 languages each (33 new
source files). Plus `bloom_and_glow/concept.toml` completed
(was a TODO stub before this release).

### Added
- **P0C-2a cluster — 3 topics × 11 languages each, +33 source
  files** (validator sweep 572/572 → 605/605):
  - **`framebuffer_rendering`** — 11 new lang files (concept-only
    topic; cyrius reference designed first). 16×16 BGRA8888
    framebuffer with `fb_clear` (memset), `fb_set`/`fb_get` with
    explicit bounds-check returning a 0/1 success flag (matching
    the encom-hits pattern in concept.toml), `draw_hline`/
    `draw_vline`, `count_lit_pixels`. 18 assertions covering
    byte-exact BGRA encoding, OOB rejection, line clipping at
    screen edge. Asm ports use a `.bss` arena with the same
    test surface; OpenQASM uses qubit-as-pixel encoding.
  - **`line_rasterization`** — 11 new lang files. All-octant
    integer Bresenham on a 16×16 byte framebuffer; pure
    integer math (no floats, no division). 27 assertions
    covering 7 line types: horizontal (dy=0), vertical
    (dx=0), positive 45° diagonal, negative 45° diagonal,
    steep slope (|dy|>|dx|, octant swap), single-point
    degenerate, reversed start/end produces same pixel set.
    Asm ports use callee-saved x19+/r12+ to cache loop state
    across `bl/call fb_set` (per the AArch64 ABI field-note).
  - **`bloom_and_glow`** — 11 new lang files. 1-pixel additive
    bloom on a 16×16 single-channel intensity buffer. Each
    pixel ≥ THRESHOLD=128 contributes `intensity / GLOW_FRAC`
    to its 4 cardinal neighbors with per-channel saturation
    clamp at 255 (the wrap-gotcha from concept.toml). 20
    assertions covering: empty input → empty output, single
    bright pixel, saturation clamp, threshold cutoff, edge-
    pixel in-bounds-only glow, two adjacent bright pixels
    summing at midpoint. OpenQASM uses controlled rotations
    as amplitude-leakage analog of light-bleed.
- **`bloom_and_glow/concept.toml` completed** — was a TODO stub.
  Now has 4 best practices (threshold-before-blur, separable
  blur, per-channel additive composite with clamp, small-
  radius retro), 3 gotchas (black-background bloom is just the
  blur, per-channel saturation never wrap, hard-threshold
  banding), and 2 performance notes (bandwidth-limited not
  compute-limited, radius=1 is essentially free).

### Changed
- **VERSION** 2.3.7 → 2.3.8.
- **Topic coverage**: 60 topics, 52 → 55 fully covered. Per-
  language counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 52 → 55
  - x86_64 ASM / AArch64 ASM: 52 → 55
  - Cyrius: 52 → 55 (all 3 topics designed cyrius.cyr first)
  - Examples: 572 → 605 (+33 new source files; +5.8%).

### Notes (recurring patterns worth field-noting later)
- **x86_64 caller-saved register clobber across helper calls.**
  `bloom_and_glow/asm_x86_64.s`'s `apply_bloom` cached `glow`
  in `r8` across 4 `call fb_add`. SysV ABI marks `r8` as
  caller-saved, and `fb_add`'s body uses `r8` as scratch — so
  the second `fb_add` saw garbage instead of the saved glow.
  Fix: cache in `rbp` (callee-saved) with explicit
  `push rbp`/`pop rbp` at function entry/exit. Direct sibling
  of the AArch64 cross-`bl` clobber field-note
  (`aarch64_callee_saved_and_imm_limits`). Worth a parallel
  x86_64 entry once it surfaces a third time.
- **GAS `imul reg, symbol` ambiguity.** `imul rax, FB_W` where
  `FB_W` is a `.equ` constant gets parsed as `IMUL r64, r/m64`
  (memory operand) instead of the immediate form, which would
  read 8 bytes from address `[FB_W]`. Initial cause of the
  bloom asm failure; fixed by switching to `shl rax, 4` (since
  FB_W=16). The `cmp r64, symbol` form parses correctly as
  immediate on GAS — this is `imul`-specific. Worth noting if
  the pattern shows up again in another asm port.

### Verified
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings (lines 821/822/1141), no new issues.
- `scripts/validate-content.sh` — **605/605 green**, 0 failed,
  0 skipped (full toolchain locally available).

## [2.3.7] — 2026-05-02

P0C-4 systems & misc cluster — all 4 topics backfilled to 11/11
languages (43 new files). Plus cyrius pin bump 5.8.3 → 5.8.14.

### Added
- **P0C-4 cluster — 4 topics × 11 languages each, +43 source files**
  (validator sweep 529/529 → 572/572):
  - **`page_management`** — 10 new lang files (cyrius reference
    already existed). Tests: header init/verify with magic
    `0x50415452`, page_count starts at 1, sequential alloc
    returns 1 then 2, write 42 to page 1 + read back, free + reuse
    via free-list stack. Layout matches the cyrius reference exactly:
    header at offset 0, page 0 reserved as null sentinel, data
    pages at `PAGE_SZ + num * PAGE_SZ`. Languages with first-class
    file I/O (Rust/Python/C/Go/TS/Zig) use real `open`+`lseek`+
    `read`+`write`; shell + asm use in-memory simulation matching
    the WAL convention; OpenQASM uses qubit-as-page-slot analog
    (allocate/measure/reset).
  - **`compression`** — 11 new lang files (concept-only topic;
    cyrius reference designed first). LZ77-shaped 2-byte token
    stream: `[0, BYTE]` = literal, `[OFFSET, LEN]` = match.
    Greedy O(n²) match-finder over a 255-byte window. Tests:
    round-trip on substring repeat (`ABCABCABC`), overlapping
    RLE match (`AAAAAAAA` with offset=1 length=7), mostly-literal
    text (`Hello, World!`), decompression bomb guard (single
    match claiming length 200 with cap=10 → -1), empty input.
    Asm ports decoder-only with hand-built test token streams
    from the cyrius greedy encoding. OpenQASM uses entanglement
    as state-overlap analog (one Hadamard + 3 CNOTs = "1 source +
    3 back-references").
  - **`concurrent_file_access`** — 11 new lang files. Single-
    process exercise of the file-lock state machine via two
    distinct OPENs of the same path (flock is per-OPEN, so the
    two fds have independent lock state and can contend in one
    process). Tests: LOCK_EX write, LOCK_SH read with roundtrip
    integrity, LOCK_NB exclusive contention (second fd fails
    while first holds), release + acquire, LOCK_SH coexistence
    (multiple shared holders). Real `flock` where available
    (Rust via libc, Python via `fcntl`, C via `<sys/file.h>`,
    Go via `syscall.Flock`, Zig via `linux.syscall2(.flock)`,
    Shell via `flock(1)`, asm via raw syscall 73/32). TypeScript
    in-process state-machine simulation (Node has no built-in
    flock binding); OpenQASM uses GHZ entanglement as shared-
    lock analog.
  - **`jsonl_format`** — 11 new lang files. In-memory JSONL
    primitives: append records to a flat byte buffer with `\n`
    separators, build a per-line index (handles the no-trailing-
    newline edge case from concept.toml's gotcha), extract by
    index, JSON string escape covering all 5 special chars
    (`" \ \n \t \r`) with a 2× expansion bounds check, escape ↔
    unescape roundtrip. Asm ports focus on the
    escape/unescape/bounds-check (the algorithmic piece);
    OpenQASM uses the no-entanglement register as
    independent-records analog.
- **Cyrius pin 5.8.3 → 5.8.14** (`cyrius.cyml`). No source
  changes required — the 5.8.x stdlib is API-compatible with
  the 5.8.3 surface vidya consumes (sandhi, sakshi, syscalls,
  string, alloc, str, fmt, vec, hashmap, io, fs, tagged, json,
  fnptr, args, toml). Verified: build clean, `cyrius test` 41/41,
  full content validator 572/572.
- **`content/cyrius/field_notes/index.cyml`** — verification
  range bumped: "Cyrius 2.2 → 5.8.14".

### Changed
- **VERSION** 2.3.6 → 2.3.7.
- **Topic coverage**: 60 topics, 48 → 52 fully covered. Per-
  language counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 48 → 52
  - x86_64 ASM / AArch64 ASM: 48 → 52
  - Cyrius: 48 → 52 (page_management already had it; the other
    3 topics designed cyrius.cyr first as the reference)
  - Examples: 529 → 572 (+43 new source files; +8%).

### Notes (recurring patterns worth field-noting later)
- **Rust 2024 edition: `extern "C"` blocks must be `unsafe`.**
  Caught by `concurrent_file_access/rust.rs` declaring `flock`/
  `unlink` libc bindings. Fix: `unsafe extern "C" { ... }`. This
  is a 2024 hardening that the older `extern "C"` form rejects
  outright now.
- **Rust LZ77 decoder: capture `out.len()` before the inner copy
  loop.** Using the moving `out.len()` inside the loop caused
  off-by-one corruption on substring matches (offset=3, len=6
  reading from position 4 instead of 3 after pushing one byte).
  Other languages' iteration patterns happen to dodge this; only
  Rust's bytes-pushed-grow-the-vec idiom surfaces it. Worth a
  field-note (`lz77_capture_start_position`) once the third
  surfacing happens.
- **Cyrius `else if` is `elif`.** Re-surfaced writing
  `jsonl_format/cyrius.cyr`. Already documented in CLAUDE.md /
  field-notes from v2.3.5 — flagged again here.
- **Zig `std.io.getStdOut()` removed.** Use `std.debug.print`
  instead (matches existing zig content ports). Surfaced in
  `page_management/zig.zig`. Worth a field-note about the Zig
  stdlib's print API churn (`zig_stdout_api_drift`).

### Verified
- `cyrius build src/main.cyr build/vidya` — clean (large-static-
  data warning at 375064 bytes, unchanged from v2.3.6).
- `cyrius test` — 41/41 passing.
- `cyrius lint src/main.cyr` — 3 pre-existing line-length
  warnings (lines 821/822/1141), no new issues.
- `scripts/validate-content.sh` — **572/572 green**, 0 failed,
  0 skipped (full toolchain locally available).

## [2.3.6] — 2026-05-02

P0B-4 content hot-reload. The deferred half of v2.3.5 promoted
to its own focus release. After this patch, P0B is fully done:
all four sub-tasks (B-1 through B-4) shipped.

### Added
- **Hot-reload on `serve`**. Inotify watches every topic dir
  under `content/`; per-request drain detects pending events
  and triggers an inline full-rebuild + atomic registry swap.
  No process restart needed when concepts change.
- **`inotify_init_watches()`** — opens an `IN_NONBLOCK` fd
  via `syscall(294, 2048)` (`inotify_init1`) and adds watches
  on `content/` root + every subdir that contains a
  `concept.toml` (filter matches `load_all`'s — skips
  `content/cyrius/` and other non-topic dirs). Mask = 970
  (`IN_MODIFY|IN_CLOSE_WRITE|IN_MOVED_FROM|IN_MOVED_TO|IN_CREATE|IN_DELETE`).
  Idempotent: closes any prior fd before opening a new one.
  Re-runs after every successful reload to pick up newly-added
  topic dirs.
- **`inotify_drain()`** — non-blocking read loop on the inotify
  fd. Sets `_reload_pending = 1` if any bytes were drained;
  exits on EAGAIN (returns immediately when no events queued).
- **`build_next_registry()` + `swap_registry()` + `do_reload()`**
  — staged registry build into `_reg_entries_next` /
  `_reg_index_next`, all-or-nothing semantics (a malformed
  `concept.toml` aborts the reload and leaves the live
  registry untouched), atomic two-pointer swap. Sakshi event
  per reload: `INFO reload OK: <n> topics in <ns>ns (reload #N)`
  on success, `WARN reload aborted: a concept failed to load`
  on partial failure.
- **`_reload_count` + `_reload_failures`** — module-level
  counters incremented per outcome, included in the sakshi
  events for ops visibility.

### Changed
- **VERSION** 2.3.5 → 2.3.6.
- **`handle_request`** — now calls `inotify_drain()` then
  conditional `do_reload()` at the top before touching the
  serve-status global. Per-request overhead on the no-events
  path is one `read(2)` returning EAGAIN (sub-µs).
- **`cmd_serve`** — calls `inotify_init_watches()` immediately
  before entering `sandhi_server_run`.
- **`docs/architecture/overview.md`** — replaced the prior
  "Future hot-reload (P0B-4) will change this contract" note
  with a fully-specified **Hot-reload contract** section
  covering detection, drain, build, swap, re-watch, and
  observability. Memory-resident contract section refined to
  reflect that the route handlers (`http_route` and the
  `json_*_response` builders) remain forbidden from filesystem
  I/O, while `handle_request` itself is allowed to call into
  `inotify_drain` / `do_reload` as the controlled mutation
  point. Known-limits section gained two entries: "reload is
  triggered by the next request, not immediately" and "no
  partial reload."

### Verified
- `cyrius build src/main.cyr build/vidya` — clean (large-static-data
  warning bumped 309480 → 375064 bytes from the new 8KB
  inotify drain buffer + reload-related str literals).
- `cyrius test` — 41/41 passing (no regressions).
- **End-to-end smoke** across five scenarios:
  1. Baseline: 60 topics.
  2. Add a topic dir (`mkdir + cat > concept.toml`):
     60 → 61, `INFO reload OK: 61 topics in 17.5ms (reload #1)`,
     `/info/<new_topic>` returns the full concept.
  3. Remove the new topic dir:
     61 → 60, `INFO reload OK: 60 topics in 21.6ms (reload #2)`.
  4. Corrupt `algorithms/concept.toml` to garbage:
     `WARN reload aborted: a concept failed to load (failure #1);
     live registry untouched`. `/stats` still reports 60 topics;
     `/info/algorithms` still serves the pre-corruption data.
  5. Restore `algorithms/concept.toml`: stays at 60,
     `INFO reload OK: 60 topics in 19.7ms (reload #3)`.
- Reload latency: 17–22ms for 60 topics, dominated by the
  per-topic TOML parse in `load_concept`. Within the budget
  for an interactive dev tool.

### Notes for follow-up
- **Bump allocator never frees** — each successful reload doubles
  registry memory permanently. Acceptable for sessions with a
  handful of reloads; for sustained edit cycles, restart
  periodically. Documented in overview.md "Known limits."
- **Reload triggered by next request** — drains run in
  `handle_request`, so an idle process won't reload until the
  next hit. Workaround: drive a periodic curl. A SIGHUP-driven
  or accept-loop-integrated trigger is future work.

## [2.3.5] — 2026-05-02

Service-layer polish + recurring-pattern field notes. Doc-heavy
release; no new content topics.

### Added
- **P0B-3: structured access log on `serve`** in `src/main.cyr`.
  New `_serve_log(path, plen, status, elapsed_ns)` helper
  formats one line per request:
  `GET <path> -> <status> (<elapsed_ns>ns)`, level-routed
  through sakshi (200s → INFO, 4xx → WARN, 5xx → ERROR). New
  module-level `_serve_status` global captured by each
  `send_*` leaf so `handle_request` can include the status in
  the access line. Latency captured from `_sk_now_ns()`
  delta around `http_route()`. Smoke-tested on every endpoint:
  ```
  [INFO] GET /stats -> 200 (56222ns)
  [INFO] GET /list -> 200 (138995ns)
  [INFO] GET /info/algorithms -> 200 (43150ns)
  [WARN] GET /nope -> 404 (20007ns)
  [WARN] GET /search -> 400 (20198ns)
  ```
- **`content/cyrius/field_notes/language/shell_runtime.cyml`**
  — new file, 3 entries, promoting recurring bash-port gotchas
  surfaced 4× across v2.3.2–v2.3.4 backfills:
  - `bash_subshell_clobbers_stateful_helpers` — `$(fn)` runs in
    a subshell; mutations don't propagate to the parent. Use
    a side-effect global. (Hit 4×: game_ai_decisions,
    maze_generation, btree_indexing, write_ahead_logging.)
  - `bash_pre_increment_set_e_zero_exit` — `(( i++ ))` returns
    OLD value; when `i=0`, exit code 1 → `set -e` aborts.
    Use `i=$((i+1))`. (Hit in sql_parsing.)
  - `bash_bc_not_posix_mandatory` — `bc` absent on default
    Arch / Alpine / minimal NixOS; use `awk` for fp math.
    (Hit in quantum_computing.)
- **AArch64 ABI gotcha entry** appended to
  `content/cyrius/field_notes/language/platform_abi.cyml`
  (4 → 5 entries): `aarch64_callee_saved_and_imm_limits`
  consolidates three encoding/calling-convention pitfalls
  surfaced repeatedly across v2.3.3–v2.3.4 asm ports —
  cross-`bl` clobber of x0–x18 (rescue: cache in x19–x28
  callee-saveds OR recompute), `cmp xN, #imm` 12-bit unsigned
  ceiling (rescue: `ldr x16, =imm` literal-pool form), and
  `mov xN, #imm` 16-bit ceiling (same rescue). Hit 4× across
  game_loop_architecture, grid_pathfinding, maze_generation,
  btree_indexing, sql_parsing.

### Changed
- **VERSION** 2.3.4 → 2.3.5.
- **`docs/architecture/overview.md` rewritten end-to-end.**
  Was stale from the pre-v2.0 Rust era (talked about
  `src/lib.rs`, MCP/bote, 33 topics × 10 langs, Rust feature
  flags). Now reflects current Cyrius reality: two-layer
  diagram (content + Cyrius CLI), startup vs per-command vs
  per-request data flow, six numbered design decisions, and a
  dedicated **Memory-resident corpus contract (P0B-2)**
  section covering what the contract guarantees, what it
  forbids on the request path, and how P0B-4 will change it.
- **`CLAUDE.md` rewritten end-to-end.** Same staleness as
  overview.md. Replaced the cargo/clippy/audit/deny work-loop
  steps with cyrius-toolchain steps (`cyrius lint / fmt /
  test / bench / build / run / deps`), added a "Toolchains —
  which tool for which surface" section with two tables
  (Surface 1 = vidya project Cyrius commands; Surface 2 =
  per-language content validators with exact invocations
  pulled from `scripts/validate-content.sh`). Explicit
  "never run cargo against the project" prohibition; Rust
  carve-out for content `.rs` files via `rustc`.
- **`content/cyrius/field_notes/index.cyml`** — Language
  Gotchas section count 29 → 33 (added 3 from
  shell_runtime.cyml + 1 from platform_abi.cyml); split count
  5 → 6 files; per-file lines added for shell_runtime.cyml
  and updated for platform_abi.cyml (4 → 5).

### Verified
- **P0B-2 audit**: `reg_init` + `load_all` run once at startup
  (lines 1425, 1433); `cmd_serve` enters `sandhi_server_run`
  blocking accept loop without re-loading; every JSON
  response builder reads only `reg_list()`/`reg_get()` (pure
  in-memory hashmap+vec). Zero file I/O on the request path,
  verified by grep over the
  `http_route` + `handle_request` line range. Contract now
  documented as a featured section in
  `docs/architecture/overview.md`.
- `cyrius build src/main.cyr build/vidya` — clean.
- `cyrius test` — 41/41 passing (10 test groups).
- End-to-end serve smoke (build/vidya serve 18390 + curl
  /stats /list /info/algorithms /nope /search) — all five
  responses correct, all five access-log lines emitted with
  matching status + latency.

### Deferred to a follow-up
- **P0B-4 — content hot-reload (inotify watch on `content/`,
  atomic `_reg_entries` / `_reg_index` swap).** Roadmap had
  this in 2.3.5; deferred because (a) it strictly blocks on
  P0B-2 audit results — landed here — but (b) the design
  needs more thought than the rest of v2.3.5 combined. The
  inotify driver, the swap barrier, the dual-registry memory
  cost, and the question of whether P0B-4 should also handle
  partial-failure (one bad concept.toml shouldn't kill the
  whole reload) all want their own release. Slotted into a
  future patch, likely 2.3.5a or as a prelude to 2.3.6.

## [2.3.4] — 2026-05-02

### Added
- **P0B-1: HTTP `/compare` and `/gaps` endpoints wired** in
  `src/main.cyr`. Two new JSON builders:
  - `json_compare_response(topic_id, lang1_str, lang2_str)` — returns
    `{topic, title, left:{language, present, path}, right:{...}}`.
    Returns 0 (→ HTTP 404) when topic missing; -1 sentinel (→ HTTP
    400) when either language is unknown; otherwise the JSON object.
  - `json_gaps_response()` — returns
    `{topics, languages, gaps:[{id, covered, of, missing:[...]}, ...],
    total_missing}`.
  Smoke-tested via `curl`: `GET /compare?topic=algorithms&left=rust&right=python`
  returns the comparison object; `GET /gaps` returns 60-topic
  coverage breakdown; bad lang → 400, bad topic → 404, missing
  params → 400. P0B is now 7-of-7 endpoints live.
- **P0C-3 database cluster — all 3 topics backfilled to 11/11**
  (31 new source files; validator sweep 498/498 → 529/529):
  - **`btree_indexing`** — 10 new lang files implementing a
    simplified B+ tree (order 8). Tests: insert/lookup, sorted
    iteration, split-on-overflow, descending-input handling.
    OpenQASM uses Grover-search-on-tree as the analog.
  - **`sql_parsing`** — 10 new lang files; tokenizer for
    `SELECT * FROM users WHERE id = 1`, case-insensitive keywords,
    integer literals, parens, validator that rejects malformed
    SELECTs. OpenQASM models the parse as a 4-qubit token stream
    walking the production tree.
  - **`write_ahead_logging`** — 11 new lang files (concept-only
    topic; cyrius reference designed first as part of this
    release). Tests: append + replay, log-before-data invariant,
    uncommitted-writes-lost-on-crash, delete replay, last-write-wins
    on overwrite, monotonic offsets, capacity bound.

### Fixed
- **`tests/vidya.tcyr` — pre-existing failures from the cyrius 5.x
  cstr-key migration**. The toml_loader/toml_sections/gotcha_fields
  groups were silently failing because `toml_get(pairs,
  str_from("id"))` returns 0 under cyrius 5.x stdlib (which expects
  cstr keys, not Str — captured in field-note
  `stdlib_str_to_cstr_key_migration` in v2.3.0). Replaced 6
  `str_from("...")` call sites with bare cstr literals; replaced
  `str_eq(a, str_from("..."))` with `str_eq_cstr(a, "...")`. The
  test file now reports **41/41 passing** (was failing on test 6
  before P0B-1 work began).

### Changed
- **VERSION** 2.3.3 → 2.3.4.
- **Topic coverage**: 60 topics, 44 → 47 fully covered. Per-language
  counts (each):
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 44 → 47
  - x86_64 ASM / AArch64 ASM: 44 → 47
  - Cyrius: 44 → 47 (`write_ahead_logging` cyrius.cyr designed in
    this release; `btree_indexing` and `sql_parsing` already had it)
  - Examples: 498 → 529 (+31 new source files; +6%)

### Notes (recurring patterns worth field-noting)
- **Bash `(( i++ )) + set -e` interaction**: `(( i++ ))` evaluates
  to the OLD value of `i`; when `i=0`, that's a 0 exit code, which
  `set -e` treats as failure and aborts the script. Fix:
  `i=$((i+1))`. Surfaced in sql_parsing/shell.sh.
- **AArch64 cross-`bl` register clobber (3rd time this release
  arc)**: caller-saved x0–x18 not preserved across `bl`. Cache
  loop state in callee-saved x19–x28 OR recompute after each call.
  Caught independently in btree_indexing/asm_aarch64.s and
  sql_parsing/asm_aarch64.s by their respective backfill agents.
- **Bash subshell + stateful PRNG (4th time)**: `$(fn)` runs in a
  subshell so global mutations don't propagate. Use side-effect
  global (`OUT=...`) for stateful helpers. Hit btree_indexing's
  `node_new_leaf` and write_ahead_logging's full WAL state.

These three patterns + the v2.3.3 AArch64 12-bit `cmp` immediate
limit are now repeated enough to warrant a dedicated
`content/cyrius/field_notes/language/shell_runtime.cyml` (bash
gotchas) and a follow-up entry in
`content/cyrius/field_notes/language/platform_abi.cyml` covering
the AArch64 callee-saved-register convention. Deferred to v2.3.5
or a follow-up doc release.

## [2.3.3] — 2026-05-02

### Added
- **P0C-1 game-engine cluster — all 8 topics backfilled to 11/11**
  (78 new source files; validator sweep 420/420 → 498/498):
  - **`state_machines`** — 9 new lang files mirroring the FSM test
    set (PlayerState/GameState enums, committed-state timers,
    transition detection, idle-shoot-tick-idle).
  - **`projectile_physics`** — 9 new lang files; 1000-frame energy
    decay with `|vy| < 2 * GRAVITY` threshold (matches the v2.3.2
    convergence calibration); semi-implicit Euler stability bounded
    at 1000 units rise.
  - **`sprite_rendering`** — 9 new lang files; framebuffer + blit
    + transparency + clipping + scaled-blit + depth-sort. Shell
    port uses a 16×16 logical FB to keep wall-clock reasonable
    (all 8 test scenarios still exercised).
  - **`game_ai_decisions`** — 9 new lang files; PCG PRNG, stat
    scoring, AI dispatch (high-dunk-stat at close range → DUNK).
  - **`collision_detection_2d`** — 9 new lang files; AABB-vs-AABB,
    circle-vs-circle (squared-distance), AABB-vs-circle clamp,
    point-in-shape, swept AABB time-of-impact.
  - **`game_loop_architecture`** — 11 new lang files (concept-only
    topic; full coverage from scratch, with cyrius.cyr designed
    first as the reference). Fixed-timestep accumulator, spiral-
    of-death cap (5 × dt), update/render separation, deterministic
    timestamps.
  - **`grid_pathfinding`** — 11 new lang files; BFS + A* on an
    8×8 4-connected grid with Manhattan heuristic. A* and BFS
    must agree on path length for uniform-cost grids — verified
    across all 11 ports.
  - **`maze_generation`** — 11 new lang files; iterative recursive
    backtracker on an 8×8 grid with PCG PRNG. **Cross-language byte
    parity confirmed for seed=42**: `cells[0]=13, cells[27]=12,
    cells[63]=6` across Rust/Python/C/Go/TS/Shell/Zig/x86_64/
    AArch64/Cyrius (the PCG output sequence agrees because every
    port uses signed-i64 wrapping arithmetic).

### Changed
- **VERSION** 2.3.2 → 2.3.3.
- **Topic coverage**: 60 topics, 25 → 33 fully covered (the
  original 36 + fixed_point_arithmetic + 8 P0C-1). Per-language
  counts:
  - Rust/Python/C/Go/TypeScript/Shell/Zig/OpenQASM: 36 → 44 each
  - x86_64 ASM: 36 → 44 (3 P0C-1 topics added asm_x86_64.s; 5
    already had it)
  - AArch64 ASM: 36 → 44 (all 8 P0C-1 topics added asm_aarch64.s)
  - Cyrius: 36 → 44 (3 P0C-1 topics added cyrius.cyr; 5 already had it)
  - Examples: 411 → 498 (78 new source files; +21%)

### Notes (worth promoting to field-notes in a follow-up)
- **AArch64 `cmp xN, #imm` 12-bit limit**: `cmp` accepts only
  0–4095 unsigned. Larger values (e.g. 4166 = DT_US/4) need
  `ldr xN, =imm` first, same as `mov` 16-bit limit. Surfaced in
  game_loop_architecture's port.
- **AArch64 register clobber across `bl`**: any helper called
  via `bl` clobbers caller-saved x0–x18. Functions that cache
  loop state in caller-saved regs across calls (e.g. `manhattan`
  in grid_pathfinding's A*, `idx` in maze_generation) must use
  callee-saved x19–x28 or recompute after each call. Caught
  cross-call clobber bugs in grid_pathfinding/asm_x86_64.s and
  maze_generation/asm_x86_64.s during port.
- **Bash subshell + stateful PRNG**: `$(rng_next)` runs the
  function in a subshell; `_rng_state` mutations don't propagate.
  Fix: stateful side-effect setter (`rng_next` writes a global
  `RNG_OUT`), callers read the global. Caught in
  game_ai_decisions/shell.sh.

## [2.3.2] — 2026-05-02

### Added
- **`fixed_point_arithmetic` backfilled to 11/11 languages** (P0C-1
  kickoff). Nine new files: `rust.rs`, `python.py`, `c.c`, `go.go`,
  `typescript.ts`, `shell.sh`, `zig.zig`, `asm_aarch64.s`,
  `openqasm.qasm`. All mirror the test set in `cyrius.cyr`
  (`fx_from_int`, `fx_to_int` truncate + round, `fx_mul`,
  `fx_mul_safe`, `fx_div`, sine table peak/trough/zero, roundtrip).
  Each leads with a short comment on the language-specific idiom
  (Rust's `wrapping_*` / `i128`, Python's bigint, C's `__int128`,
  TypeScript's bigint requirement, Bash's `awk`-generated sine
  table, Zig's explicit casts, AArch64's `SMULH+MUL` pair, OpenQASM's
  phase-encoding analog of fixed-point).
- **`scripts/validate-content.sh` now validates Cyrius examples**.
  New `HAS_CYRIUS` toolchain probe + per-topic `cyrius run` block
  mirroring the skip-if-missing pattern of the other languages.
  Toolchain banner expanded: `zig=…  aarch64=…  qasm=…  cyrius=…`.
- **Three new field-note entries in
  `content/cyrius/field_notes/language/parser_syntax.cyml`**
  (5 → 8 entries; total field-note entries 131 → 134), captured
  during the v2.3.2 backfill sweep:
  - `multi_line_struct_enum_bodies_dont_parse` — struct/enum
    bodies must be on one line; multi-line braces silently
    mis-tokenise the body and surface as misleading "undefined
    variable" or "unexpected ';'" errors far from the real cause.
  - `return_struct_literal_dangles_or_rejected` — `return Type {
    … }` either fails to parse or (if wrapped via `var b = …;
    return &b`) returns a dangling stack pointer. Construct in
    caller scope; `alloc()` for heap-resident.
  - `bare_return_in_if_block_rejected` — bare `return;` inside an
    `if { … }` block triggers "unexpected ';'"; must be `return
    0;` (Cyrius has no void).

### Fixed
- **14 pre-existing example failures surfaced by the new validator
  coverage and resolved**. Validator sweep: was 406/420 before
  the Cyrius branch landed, now 420/420 with zero skips on a fully
  stocked toolchain.
  - **4 OpenQASM** files (`instruction_encoding`,
    `linking_and_loading`, `ownership_and_borrowing`,
    `virtual_memory`) used `swap a, b;` — qiskit's `qelib1.inc`
    doesn't define `swap`. Expanded to the canonical 3-CNOT
    decomposition.
  - **2 C** files: `code_generation/c.c` missing `<stdint.h>`
    (gcc 15 strict on `int64_t`); `syscalls_and_abi/c.c` missing
    `_GNU_SOURCE` and `<sys/types.h>` for `pid_t` and `syscall(2)`.
  - **2 x86_64 ASM**: `game_ai_decisions/asm_x86_64.s` had `add
    rax, imm64` (x86 `add` only sign-extends imm32) — split into
    `mov rcx, imm64; add rax, rcx`. `projectile_physics/asm_x86_64.s`
    had a bounce-decay convergence test calibrated for too few
    frames — bumped 200 → 1000 frames, threshold to `2 * GRAVITY`.
  - **5 Cyrius**: `game_ai_decisions`, `state_machines`,
    `sprite_rendering` — multi-line struct/enum bodies, `return
    Struct { … }` builders returning dangling stack pointers, bare
    `return;` inside `if { … }` blocks. `projectile_physics`
    had the same convergence-window miscalibration as its asm
    sibling. `strings` called `fmt_sprintf(buf, fmt, args)` with
    the `bufsz` arg missing (correct shape: `fmt_sprintf(buf,
    bufsz, fmt, args)`). All three cyrius parser quirks captured
    in field notes (see Added).
  - **1 Shell**: `quantum_computing/shell.sh` used `bc -l` for
    floating-point math (`bc` is not POSIX-mandatory and absent
    on default Arch installs); rewrote three helpers to use `awk`
    (always available, same `sqrt`/`log`/`exp` semantics).

### Changed
- **Roadmap rewrite** (`docs/development/roadmap.md`). Header refreshed
  (v2.2.0 → v2.3.2, last-updated 2026-04-08 → 2026-05-01, topics
  36 → 60, examples 396 → 411, Cyrius 5.8.3 noted). Substantive
  updates:
  - **P0B Service Layer marked partially shipped** — HTTP server,
    JSON responses, and 5 of 7 endpoints (`/stats`, `/list`,
    `/languages`, `/search`, `/info/{topic}`) confirmed live in
    `src/main.cyr`'s `cmd_serve`, running on `lib/sandhi.cyr`.
  - **P0B remaining items (P0B-1 … P0B-4)** carved out: wire
    `/compare` and `/gaps` HTTP routes (CLI handlers exist;
    HTTP routing doesn't), verify or implement memory-resident
    mode, sakshi request tracing, content hot-reload.
  - **Completed-since-v2.2 section** added listing the 24 new
    topics that landed alongside cyrius-doom, mabda v3 GPU, and
    ENCOM's Hits, grouped into clusters: graphics (9),
    game-engine (8), database (3), systems & misc (4).
  - **P0C Backfill section** added: ~249 source files needed to
    bring the 24 new topics to 11/11 language parity with the
    original 36. Sized as a multi-release sweep, prioritized by
    cluster maturity (P0C-1 game-engine, P0C-2 graphics, P0C-3
    database, P0C-4 systems & misc). `fixed_point_arithmetic`
    is the first P0C-1 topic landed (see Added).
  - **P3 reorganized**: graphics cluster crossed off (covered by
    P0C-2); audio + AI/ML topics retained.
  - **Field-notes growth pattern** documented as Established at
    v2.3.1 with the three split axes (version arc, surface area,
    phase).
  - **Cyrius pin maintenance** cadence note added: every Cyrius
    minor drives a vidya patch bump for stdlib + language-feature
    alignment, with the 6-step playbook (cyrius.cyml, field
    notes, index verification range, CHANGELOG, zugot recipe).
- **`content/cyrius/field_notes/index.cyml`** — language section
  count 26 → 29 entries; `parser_syntax.cyml` per-file count
  5 → 8 entries with the three new entries listed.
- `VERSION` 2.3.1 → 2.3.2.

## [2.3.1] — 2026-05-01

### Changed
- **Cyrius toolchain pin bumped 5.7.0 → 5.8.3** (`cyrius.cyml`). No
  source changes required — the 5.8.x stdlib is API-compatible with
  the 5.7.0 surface vidya consumes (syscalls, string, alloc, str,
  fmt, vec, hashmap, io, fs, tagged, json, fnptr, args, toml, regex,
  net, sandhi). `cyrius.lock` (sakshi 2.0.0 sha) unchanged.
- **`content/cyrius/field_notes/` reorganised by topic**. The three
  longest field-note files were converted into per-topic subfolders;
  the other five stayed flat. All 131 entries preserved byte-exact
  (`diff` clean against the pre-split source). Index regenerated.
  - `compiler.cyml` (3,944 lines, 46 entries) → `compiler/` split by
    version arc: `v3.cyml` (8), `v4.cyml` (4), `v5_0_to_5_4.cyml` (4),
    `v5_5.cyml` (4), `v5_6.cyml` (11), `v5_7.cyml` (15).
  - `language.cyml` (1,239 lines, 26 entries) → `language/` split by
    surface area: `parser_syntax.cyml` (5), `semantics_runtime.cyml`
    (8), `platform_abi.cyml` (4), `stdlib_format.cyml` (5),
    `diagnostics_caps.cyml` (4).
  - `mabda-v3-gpu.cyml` (1,276 lines, 23 entries) → `mabda_v3_gpu/`
    split by phase: `overview.cyml` (3), `phase_a.cyml` (1),
    `phase_b.cyml` (4), `phase_c.cyml` (9), `phase_d.cyml` (4),
    `research.cyml` (2).
  - `doom.cyml` (11), `cyim.cyml` (12), `encom-hits.cyml` (8),
    `meta.cyml` (4), `kernel.cyml` (1) left flat.
  - `index.cyml` refreshed: stale per-section counts corrected
    (compiler 22→46, language 24→26, mabda 19→23, meta 3→4, encom-hits
    7→8), file-by-file breakdown added for split topics, verification
    range updated to "Cyrius 2.2 → 5.8.x".
- `docs/development/content-grouping.md` field_notes diagram updated
  to `.cyml` extensions and the new subfolder pattern; added a
  "Field-notes subfolder pattern (proven at v2.3.1)" section
  documenting the ~800-line / distinct-sub-topic threshold and the
  three split axes (version arc, surface area, phase).
- `content/cyrius/archive/README.md` path references corrected:
  `../language.toml` → `../language.cyml`,
  `../field_notes/{compiler,language}.toml` → `../field_notes/{compiler,language}/`,
  `../{ecosystem,dependencies,types}.toml` → `.cyml`.

## [2.3.0] — 2026-04-25

### Added
- Four new field-note entries in
  `content/cyrius/field_notes/language.cyml` capturing what surfaced
  during this upgrade:
  - `var_buf_in_library_functions` — `var buf[N]` inside a function
    is **static data**, not stack; consecutive calls clobber any
    Str/buf-borrowing return values. Diagnostic: the build's
    "large static data (N bytes)" warning.
  - `stdlib_str_to_cstr_key_migration` — cyrius 5.x lookup helpers
    (`toml_get`, `toml_get_sections`, …) take cstr keys; passing
    `str_from("…")` silently returns 0.
  - `cyml_toml_plus_markdown_frontmatter` — the CYML format (TOML
    header + markdown body separated by `---`), `lib/cyml.cyr`
    parser API, and the prose-quoting `---` gotcha.
  - `sandhi_service_layer_dep` — sandhi as the cyrius 5.x
    service-boundary stdlib, current `[deps.sandhi]` git-pin
    pattern, planned fold-into-stdlib transition.
- `cyrius.lock` — sha256 hash for `lib/sakshi.cyr` (sakshi 2.0.0,
  the only git-pinned dep); generated by `cyrius deps --lock`,
  enforced by `cyrius deps --verify` on CI once present. Stdlib
  modules (sandhi included) ship with the toolchain and are not
  hashed in the lock.

### Changed
- **HTTP server now runs on `lib/sandhi.cyr`**. Sandhi is the
  service-boundary stdlib that folded into the cyrius toolchain
  at 5.7.0 (HTTP client/server, TLS, headers, service discovery);
  declared as `"sandhi"` in `[deps] stdlib = [...]`. Replaces the
  vendored `lib/http_server.cyr`. Caller renames in
  `src/main.cyr`:
  `http_send_response` → `sandhi_server_send_response`,
  `http_get_param` → `sandhi_server_get_param`,
  `http_path_segment` → `sandhi_server_path_segment`,
  `http_get_path` → `sandhi_server_get_path`,
  `http_server_run` → `sandhi_server_run`.
  `HTTP_OK` / `HTTP_NOT_FOUND` / `HTTP_BAD_REQUEST` / `INADDR_ANY()`
  re-export through sandhi unchanged.
- Build manifest migrated `cyrius.toml` → `cyrius.cyml` with
  `[deps] stdlib = [...]` (sandhi listed as a stdlib name) and a
  `[deps.sakshi]` (2.0.0) git stanza, matching the yukti layout.
  `version = "${file:VERSION}"` so the manifest pulls from the
  VERSION file. Stdlib deps ship with the cyrius toolchain;
  `[deps.<name>]` stanzas are reserved for heavier external
  git-pinned libraries (e.g. sakshi).
- **`content/cyrius/`** migrated TOML → CYML: 13 files, 318
  entries. `[[entries]]` markers preserved; the
  `content = '''...'''` body of each entry moved below a `---`
  delimiter (CYML's TOML-header + markdown-body convention). All
  files round-trip cleanly through `lib/cyml.cyr`. The 64
  `content/<topic>/concept.toml` files are untouched — different
  format, different consumer.
- Vendored stdlib refreshed via `cyrius deps`: `lib/sakshi.cyr`
  (now 2.0.0), `lib/sandhi.cyr` (new, 1.0.0), and incidental
  refreshes to `alloc.cyr`, `args.cyr`, `fmt.cyr`, `fnptr.cyr`,
  `hashmap.cyr`, `io.cyr`, `json.cyr`, `regex.cyr`, `str.cyr`,
  `string.cyr`, `syscalls.cyr`, `tagged.cyr`, `toml.cyr` to match
  the cyrius 5.7.0 stdlib snapshot.
- CI/release workflows ported to the yukti pattern: toolchain
  version derived from `cyrius.cyml` (no env pin), `cyrius deps`
  runs before build, `cyrius deps --verify` gates on `cyrius.lock`
  existing (warns + skips on first push, enforces afterward),
  docs check requires `cyrius.cyml`, version-verify trusts
  `${file:VERSION}` instead of grepping the manifest, and release
  tags accept both `v2.3.0` and `2.3.0` shapes.
- `content/cyrius/field_notes/index.cyml` refreshed: section
  pointer suffixes `.toml` → `.cyml`, "Language Gotchas" entry
  count 17 → 22, verification range "Cyrius 2.2 → 5.7.0".

### Fixed
- Concept loader rewritten to call `toml_parse` directly on a heap-
  allocated read buffer instead of `lib/toml.cyr::toml_parse_file`.
  The stdlib helper declares `var buf[262144]`, which the cyrius
  compiler emits as **static data** (not stack-local) — every
  `toml_parse_file` call shares the same backing memory, so 59 of
  60 concepts' parsed Str values dangled into the last-read file's
  bytes once the 5.7.0 stdlib refresh exposed the path. The build's
  "large static data" warning is the upstream tell.
- All `toml_get` / `toml_get_sections` callers updated from
  `str_from("key")` to bare cstr literals. The 5.x stdlib lookup
  helpers compare via `str_eq_cstr`, which calls `strlen` on the
  second argument — Str values lack a NUL terminator, so every
  lookup silently returned 0, leaving concepts with null ids and
  triggering a `path_join(0, fname)` segfault during content load.

### Removed
- Orphan `lib/http_server.cyr` — superseded by sandhi 1.0.0.
- All `content/cyrius/**/*.toml` files — replaced by `*.cyml`
  equivalents (lossless conversion, verified by entry-count
  parity through the `lib/cyml.cyr` parser).

### Verified
- `cyrius deps --verify` → "1 verified, 0 failed" (sakshi 2.0.0;
  sandhi resolves through the stdlib path, not lockfile-tracked).
- `cyrius build src/main.cyr build/vidya` → 623,712-byte ELF, clean.
- `./build/vidya stats` → 60 topics, 411 examples, 11 languages.
- `list` / `search` / `info` / `gaps` / `languages` exit 0 with
  expected output.
- `lib/cyml.cyr` smoke test against every converted file:
  18 + 6 + 41 + 72 + 1 + 11 + 3 + 8 + 6 + 22 + 31 + 0 + 99 = 318
  entries, matching the original `[[entries]]` counts exactly
  (index.cyml is comment-only, valid as a 0-entry CYML doc).

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
