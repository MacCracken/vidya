# How 396 Programming Examples Got Written in One Session

> 2026-04-08 | vidya v2.0.0

## The Starting Point

Vidya started as a Rust crate — 2,396 lines of Rust across 11 modules, serving 36 programming topics with 193 examples across 10 languages. Fifteen topics had full coverage (all 10 languages). Twenty-one topics had only Rust implementations, scaffolded during Cyrius compiler development but never fleshed out. The crate worked. It was clean. But it was two-thirds empty.

## The Port

The first move was porting vidya from Rust to Cyrius — the language it documents. `cyrb port /home/macro/Repos/vidya` moved the Rust source to `rust-old/`, scaffolded a Cyrius project, and vendored 28 stdlib modules.

The Cyrius port is 600 lines. The Rust crate was 2,396. The binary is 85KB (Rust release was ~800KB). The Cyrius version loads content faster (2.35ms vs 3.83ms for all 35 topics) and searches faster (4us vs 30us) because simpler algorithms win on small datasets. Rust's hashmap is 30x faster on raw lookups because that's what world-class `HashMap` implementations do.

The port hit real bugs. TOML-parsed strings weren't null-terminated, corrupting hashmap lookups. `fmt_int` clobbered caller registers when using large stack frames — a compiler bug that got fixed during this session. Sakshi (the tracing library) couldn't integrate initially because its 32KB ring buffer overflowed the compiler's BSS segment — fixed by shipping a stderr-only profile.

Every bug found in vidya's port led to a fix in the Cyrius compiler or its ecosystem. The port was a forcing function.

## The Expansion

With the Cyrius CLI working — `vidya list`, `vidya search`, `vidya info`, `vidya compare`, `vidya gaps` — the coverage gaps became visible. `vidya gaps` reported 141 missing implementations across 21 topics.

The approach: batch by language, parallelize with subagents, verify every file compiles and runs.

**Round 1 — High-priority topics (compiler + systems):**
9 topics got Python, C, Go, Cyrius implementations. Compiler bootstrapping's Cyrius file was deliberately pattern-focused — documenting the actual Cyrius bootstrap chain (29KB seed -> 12KB stage1f -> 164KB cc2) rather than reimplementing a compiler. Because the reader can just go look at the Cyrius repo for the real thing.

**Round 2 — Medium-priority topics (OS + language design):**
11 topics got Python, C, Cyrius. The OS topics (virtual memory, interrupts, scheduling, filesystems) needed C for the struct layouts and bit manipulation. The language-design topics (ownership, traits, macros, modules) needed each language to show how IT handles the concept — Go's interfaces vs Rust's traits vs C's vtables vs Cyrius's function-pointer dispatch.

**Round 3 — Quantum computing:**
One file: `quantum_computing/cyrius.cyr`. Fixed-point integer arithmetic (1000 = 1.0) to simulate qubits, Hadamard gates, Bell states, Grover's algorithm, and noise/decoherence fidelity decay. Pattern-focused, not a full simulator.

**Round 4 — Language sweep (Go, Zig, TypeScript, Shell):**
Four passes, 16-21 files each. Go and Zig were the biggest gaps. TypeScript modeled everything — even boot_and_startup — using DataView for byte-level work. Shell used `/proc`, `xxd`, and arithmetic to demonstrate OS concepts. Every file was tested: `go run`, `zig run`, `npx tsx`, `bash`.

**Round 5 — Assembly (x86_64, AArch64):**
The hardest files to write. x86_64 assembly had to actually assemble with `as --64`, link with `ld`, and produce a working Linux executable. AArch64 had to cross-compile and run under `qemu-aarch64`. The assembly files ARE the concepts — vtable dispatch is an indirect `call` through a loaded function pointer, not a class hierarchy.

**Round 6 — OpenQASM:**
Quantum analogies for classical concepts. Some genuine (gate decomposition as code generation, circuit optimization as compiler passes), some stretched (measurement as interrupts, SWAP as virtual memory mapping). All valid OpenQASM 2.0, all parse cleanly.

**Round 7 — Closing the last 4:**
Tracing needed Rust, Python, C, and AArch64 ASM. Four files. Zero gaps.

## The Numbers

| Metric | Before | After |
|--------|--------|-------|
| Topics complete (11/11 langs) | 15 | 36 |
| Total examples | 193 | 396 |
| Languages | 10 | 11 (+Cyrius) |
| Coverage gaps | 203 | 0 |
| Crate implementation | 2,396 lines Rust | 600 lines Cyrius |
| Binary size | ~800KB | 85KB |

203 new implementations written, tested, and verified in one session. Every file compiles and runs. Every file starts with an explanation of what it demonstrates. Every file teaches something.

## What Made It Work

**Parallel subagents.** Three agents writing Go/Zig/TypeScript simultaneously, each responsible for 5-7 topics. The main thread verified results as they landed, fixed issues (missing includes, reserved keywords, null-termination bugs), and launched the next batch.

**Pattern-focused Cyrius files.** The Cyrius implementations don't reimplement compilers or operating systems. They document the actual Cyrius and AGNOS patterns with `assert_eq` — bootstrap chain sizes, stack frame offsets, PTE bit layouts, GDT selectors. The reader learns the concept, then goes to the real code.

**The `vidya gaps` command.** Written during this session, it reports exactly which topics are missing which languages. It turned "we need more content" into "we need 16 Go files for these specific topics." Concrete, actionable, measurable.

**Testing everything.** Every Python file ran with `python3`. Every C file compiled with `gcc -Wall`. Every Go file ran with `go run`. Every Zig file built with `zig run`. Every x86_64 assembly file assembled, linked, and executed. Every AArch64 file cross-compiled and ran under QEMU. Every Cyrius file compiled with `cc2` and ran. Every OpenQASM file parsed. No exceptions.

## What's Next

The corpus is complete for 36 topics across 11 languages. The roadmap now points forward:
- P1: Networking (TCP/UDP, HTTP, TLS, DNS, IPC, serialization)
- P2: Databases (SQL, transactions, consensus, distributed systems)
- P3: Graphics/Audio/AI (GPU, DSP, neural networks, inference)
- P4: Build systems and package management
- P5: Functional programming and type theory
- P6: Cyrius-specific topics (when the language matures further)

Every new topic starts at 11 languages from day one. The infrastructure is built. The patterns are established. The gap reporter keeps us honest.
