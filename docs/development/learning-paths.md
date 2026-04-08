# Learning Paths

Ordered topic sequences for structured learning. Each path builds on the previous topic.

## Build a Compiler

From source text to running binary. The complete compilation pipeline.

```
lexing_and_parsing           — tokenizer + recursive descent parser
  → intermediate_representations  — SSA, CFG, basic blocks, phi nodes
    → optimization_passes          — DCE, constant folding, inlining
      → code_generation              — instruction selection, register alloc, stack frames
        → instruction_encoding         — x86_64 ModR/M, SIB, REX, machine code bytes
          → linking_and_loading          — symbol resolution, relocations, GOT/PLT
            → elf_and_executable_formats   — ELF headers, sections, segments
              → compiler_bootstrapping       — self-hosting, multi-stage, seed trust
```

**Prerequisite knowledge**: basic data structures, recursion
**Capstone**: understand how Cyrius compiles itself (see `../cyrius/`)

## OS from Scratch

From power-on to a running operating system with processes and files.

```
boot_and_startup             — BIOS/UEFI, multiboot, GDT/IDT, long mode
  → virtual_memory              — page tables, TLB, 4-level paging
    → interrupt_handling           — IDT, exceptions, IRQ routing, PIC
      → process_and_scheduling       — task structs, context switch, round-robin, CFS
        → syscalls_and_abi             — SYSCALL/SYSRET, System V AMD64 ABI
          → filesystems                  — VFS, inodes, block allocation, initrd
            → kernel_topics                — MMIO, drivers, the full picture
```

**Prerequisite knowledge**: C, basic assembly, memory layout
**Capstone**: understand how AGNOS boots and runs (see `../cyrius/kernel/`)

## Systems Programming Fundamentals

Core concepts for writing any systems-level software.

```
memory_management            — stack vs heap, allocation, deallocation
  → allocators                   — bump, slab, buddy, arena patterns
    → ownership_and_borrowing      — move semantics, lifetimes, borrow checking
      → concurrency                  — threads, locks, channels, async
        → error_handling               — Result types, error codes, propagation
          → performance                  — benchmarking, profiling, optimization
            → security                     — bounds checking, input validation, permissions
```

**Prerequisite knowledge**: one programming language
**Capstone**: write a safe, fast, correct systems program

## Language Design

How programming languages are designed and implemented.

```
type_systems                 — static vs dynamic, generics, inference
  → trait_and_typeclass_systems  — monomorphization, vtables, coherence
    → pattern_matching             — exhaustiveness, guards, destructuring
      → ownership_and_borrowing      — Rust's key innovation in type safety
        → macro_systems                — hygiene, declarative vs procedural
          → module_systems               — namespacing, visibility, separate compilation
```

**Prerequisite knowledge**: experience in 2+ languages
**Capstone**: understand why languages make different tradeoffs

## Quantum Computing

From classical bits to quantum algorithms.

```
algorithms                   — classical algorithm foundation
  → quantum_computing           — qubits, gates, superposition, entanglement, Grover, Shor
```

**Prerequisite knowledge**: linear algebra basics
**Capstone**: understand what quantum computers can (and can't) do better
