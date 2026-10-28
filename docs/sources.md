# Source Citations

> **Last Updated**: 2026-10-28 (2.9.6: the P5 topics' references)

References for language specifications, algorithms, and standards used across vidya content.

## Language Specifications

| Language | Spec / Reference | Version / Edition |
|----------|-----------------|-------------------|
| Cyrius | [Cyrius language guide](https://github.com/MacCracken/cyrius/blob/main/docs/cyrius-guide.md) | Pinned at 6.7.18 (see `cyrius.cyml`) |
| Rust | [The Rust Reference](https://doc.rust-lang.org/reference/) | Edition 2024 (toolchain: latest stable, 1.99 at 2.9.4) |
| Python | [Python Documentation](https://docs.python.org/3.15/) | 3.15 |
| C | ISO/IEC 9899:2024 (C23) | C23 |
| Go | [The Go Specification](https://go.dev/ref/spec) | Go 1.27 |
| TypeScript | [ECMAScript Language Specification](https://tc39.es/ecma262/) / [TypeScript Handbook](https://www.typescriptlang.org/docs/handbook/) | TS 7.0.2 / ES2025 |
| Shell | [POSIX Shell Command Language](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html) / [Bash Reference Manual](https://www.gnu.org/software/bash/manual/) | POSIX.1-2017 / Bash 5.3 |
| Zig | [Zig Language Reference](https://ziglang.org/documentation/0.17.0/) | 0.17 (CI: Arch's `zig` package) |
| x86_64 ASM | Intel 64 and IA-32 Architectures Software Developer Manuals | Vol 1–4 |
| AArch64 ASM | Arm Architecture Reference Manual (Arm ARM) | ARMv8-A / ARMv9-A |
| OpenQASM | [OpenQASM 3 specification](https://openqasm.com/) | 3.1 (2.0 through vidya 2.9.3) |

## Algorithm & Data Structure References

| Topic | Source |
|-------|--------|
| Sorting algorithms | Cormen et al., *Introduction to Algorithms* (CLRS), 4th ed. |
| Hash tables | Knuth, *The Art of Computer Programming*, Vol. 3 |
| Graph algorithms | Sedgewick & Wayne, *Algorithms*, 4th ed. |
| Quantum circuits | Nielsen & Chuang, *Quantum Computation and Quantum Information*, 10th anniversary ed. |

## Functional Programming & Type Theory

Cited by `functional_patterns`, `effect_systems` and `dependent_types` (2.9.6).

| Topic | Source |
|-------|--------|
| Persistent data, structural sharing | Okasaki, *Purely Functional Data Structures*, Cambridge University Press, 1998 |
| 32-way tries (Clojure / Scala vectors) | Bagwell, "Ideal Hash Trees", EPFL technical report, 2001 |
| Explicit tail calls in Rust (`become`) | [Rust RFC 3407](https://github.com/rust-lang/rfcs/pull/3407), unstable as of rustc 1.99 |
| Effect handler costs (OCaml 5) | Sivaramakrishnan, Dolan, White, Kelly, Jaffer and Madhavapeddy, "Retrofitting Effect Handlers onto OCaml", PLDI 2021, §6.3 |
| OCaml 5 effects API (`Effect.Unhandled`, `Effect.Continuation_already_resumed`) | [OCaml manual, "Effect handlers"](https://ocaml.org/manual/effects.html) |
| Deferred measurement principle | Nielsen & Chuang, *Quantum Computation and Quantum Information*, §4.4 |
| Parse, don't validate | King, ["Parse, don't validate"](https://lexi-lambda.github.io/blog/2019/11/05/parse-don-t-validate/), 2019 |

## Standards & Specifications

| Standard | Reference |
|----------|-----------|
| OpenQASM 3 standard gates | `stdgates.inc`, built into qiskit's OpenQASM 3 importer (2.0's `qelib1.inc` was bundled through vidya 2.9.3) |
| ELF format | [System V ABI / ELF Specification](https://refspecs.linuxfoundation.org/elf/elf.pdf) |
| x86_64 ABI | [System V AMD64 ABI](https://gitlab.com/x86-psABIs/x86-64-ABI) |
| POSIX | IEEE Std 1003.1-2017 (POSIX.1-2017) |

## Compiler & Systems References

| Topic | Source |
|-------|--------|
| Compiler design | Aho et al., *Compilers: Principles, Techniques, and Tools* (Dragon Book), 2nd ed. |
| Operating systems | Tanenbaum & Bos, *Modern Operating Systems*, 4th ed. |
| Linkers & loaders | Levine, *Linkers and Loaders*, 1st ed. |
| Virtual memory | Intel SDM Vol. 3, Ch. 4 (Paging) |
