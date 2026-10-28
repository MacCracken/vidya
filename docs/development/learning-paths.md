# Learning Paths

> **Last Updated**: 2026-10-28 (v3.0.0 — topic ids are `<group>/<topic>`). Every topic is on at least one path (80 of 80): 2.9.6 added the Language Fundamentals, Build & Release and Functional Programming & Type Theory paths and placed the ten topics that had none.

Ordered topic sequences for structured learning. Each path builds on the previous topic. Run `vidya list` for the full topic index.

## Language Fundamentals

The everyday material every other path assumes.

```
fundamentals/strings                    — encodings, slicing, interning, the hidden complexity
  → fundamentals/iterators              — lazy sequences, adapters, fusion
    → fundamentals/input_output         — files, streams, buffering, composable readers/writers
      → compilers/binary_formats        — headers, segments, how a program reaches the loader
        → fundamentals/design_patterns  — builder, strategy, observer, RAII, dependency injection
```

**Prerequisite knowledge**: one programming language
**Capstone**: read an unfamiliar codebase and name the patterns it uses

## Build a Compiler

From source text to running binary. The complete compilation pipeline.

```
compilers/lexing_and_parsing                        — tokenizer + recursive descent parser
  → compilers/intermediate_representations          — SSA, CFG, basic blocks, phi nodes
    → compilers/optimization_passes                 — DCE, constant folding, inlining
      → compilers/code_generation                   — instruction selection, register alloc, stack frames
        → compilers/instruction_encoding            — x86_64 ModR/M, SIB, REX, machine code bytes
          → compilers/linking_and_loading           — symbol resolution, relocations, GOT/PLT
            → compilers/elf_and_executable_formats  — ELF headers, sections, segments
              → compilers/bootstrapping             — self-hosting, multi-stage, seed trust
```

**Prerequisite knowledge**: basic data structures, recursion
**Capstone**: understand how Cyrius compiles itself (see `content/cyrius/`, the language reference and the `field_notes/compiler/` arc)

## OS from Scratch

From power-on to a running operating system with processes and files.

```
systems/boot_and_startup                — BIOS/UEFI, multiboot, GDT/IDT, long mode
  → systems/virtual_memory              — page tables, TLB, 4-level paging
    → systems/interrupt_handling        — IDT, exceptions, IRQ routing, PIC
      → systems/process_and_scheduling  — task structs, context switch, round-robin, CFS
        → systems/syscalls_and_abi      — SYSCALL/SYSRET, System V AMD64 ABI
          → systems/filesystems         — VFS, inodes, block allocation, initrd
            → systems/kernel_topics     — MMIO, drivers, the full picture
```

**Prerequisite knowledge**: C, basic assembly, memory layout
**Capstone**: understand how AGNOS boots and runs (see `content/cyrius/field_notes/kernel.cyml`)

## Systems Programming Fundamentals

Core concepts for writing any systems-level software.

```
fundamentals/memory_management           — stack vs heap, allocation, deallocation
  → systems/allocators                   — bump, slab, buddy, arena patterns
    → languages/ownership_and_borrowing  — move semantics, lifetimes, borrow checking
      → fundamentals/concurrency         — threads, locks, channels, async
        → fundamentals/error_handling    — Result types, error codes, propagation
          → fundamentals/performance     — benchmarking, profiling, optimization
            → fundamentals/security      — bounds checking, input validation, permissions
```

**Prerequisite knowledge**: one programming language
**Capstone**: write a safe, fast, correct systems program

## Language Design

How programming languages are designed and implemented.

```
languages/type_systems                     — static vs dynamic, generics, inference
  → languages/trait_and_typeclass_systems  — monomorphization, vtables, coherence
    → languages/pattern_matching           — exhaustiveness, guards, destructuring
      → languages/ownership_and_borrowing  — Rust's key innovation in type safety
        → languages/macro_systems          — hygiene, declarative vs procedural
          → languages/module_systems       — namespacing, visibility, separate compilation
```

**Prerequisite knowledge**: experience in 2+ languages
**Capstone**: understand why languages make different tradeoffs

## Functional Programming & Type Theory (P5)

From pure functions to types that carry proofs.

```
languages/type_systems             — static vs dynamic, generics, inference
  → languages/functional_patterns  — purity, closures, composition, persistent data, folds
    → languages/effect_systems     — effects as data, handlers, capabilities, pure core
      → languages/dependent_types  — length-indexed vectors, Fin, refinements, parse don't validate
```

**Prerequisite knowledge**: Language Design, or experience with closures in 2+ languages
**Capstone**: move a program's effects to its edge and its invariants into its types

## Quantum Computing

From classical bits to quantum algorithms.

```
fundamentals/algorithms   — classical algorithm foundation
  → quantum/fundamentals  — qubits, gates, superposition, entanglement, Grover, Shor
```

**Prerequisite knowledge**: linear algebra basics
**Capstone**: understand what quantum computers can (and can't) do better

## Networked Service (P1)

Build a service that survives the open internet.

```
networking/fundamentals                  — sockets, addressing, connection lifecycle
  → networking/dns                       — resolution, caching, RR types
    → networking/http_and_web_protocols  — request/response, parsing, headers, status codes
      → networking/tls_and_encryption    — TLS handshake, ALPN, session resumption
        → networking/ipc                 — Unix sockets, pipes, shared memory
```

**Prerequisite knowledge**: basic POSIX, OS fundamentals
**Capstone**: stand up an HTTP service with TLS termination and IPC between workers

## Database Internals (P0C / P2)

How storage engines work under the hood.

```
data/serialization                           — wire formats, varints, encoding choices
  → data/jsonl_format                        — line-delimited streams, recovery, append semantics
    → data/page_management                   — fixed-size pages, free lists, the unit of I/O
      → data/btree_indexing                  — leaf vs internal nodes, splits, range queries
        → data/sql_parsing                   — tokenizer, AST, plan basics
          → data/transactions_and_acid       — isolation levels, MVCC, snapshot reads
            → data/write_ahead_logging       — WAL records, recovery, checkpoints
              → data/concurrent_file_access  — flock, shared readers, exclusive writers
                → data/compression           — LZ4, DEFLATE, dictionary methods
```

**Prerequisite knowledge**: data structures, basic SQL
**Capstone**: understand why your favorite database makes its trade-offs

## Distributed Systems (P2)

From a single node to a cluster that doesn't lie to you.

```
networking/ipc                   — single-host process communication primitives
  → networking/fundamentals      — sockets across hosts
    → distributed/consensus      — Paxos, Raft, leader election, log replication
      → distributed/foundations  — partitioning, replication, CAP, failure modes
```

**Prerequisite knowledge**: networking, transactions, async
**Capstone**: read a distributed system's paper and predict its failure modes

## Audio (P3)

DSP fundamentals through real-time synthesis.

```
fundamentals/fixed_point_arithmetic  — Q-format, saturation, scale management
  → audio/dsp                        — FIR/IIR filters, FFT, sample rates
    → audio/synthesis                — oscillators, envelopes, PolyBLEP, voice allocation
```

**Prerequisite knowledge**: complex numbers, basic signal processing intuition
**Capstone**: write a synth voice that doesn't alias

## AI / ML Systems (P3)

From the math to a deployable inference pipeline.

```
ai/neural_networks  — layers, gradients, backprop, training loop
  → ai/embeddings   — vector spaces, similarity, projection
    → ai/inference  — quantization, batching, KV-cache, attention
```

**Prerequisite knowledge**: linear algebra, calculus, probability
**Capstone**: serve a model with the right batching + caching strategy

## Graphics (P0C)

From pixels to the GPU pipeline.

```
graphics/framebuffer_rendering                           — pixel buffers, blit, double-buffering
  → graphics/line_rasterization                          — Bresenham, antialiasing, sub-pixel
    → graphics/sprite_rendering                          — alpha, batching, tile maps
      → games/collision_detection_2d                     — AABB, swept, broad-phase
        → games/projectile_physics                       — integration schemes (Euler, Verlet)
          → graphics/bloom_and_glow                      — post-process passes, bloom, HDR
            → graphics/render_graph_architecture         — pass graphs, transient resources, barriers
              → graphics/gpu_memory_pooling              — pools, suballocation, freelists
                → graphics/explicit_gpu_synchronization  — fences, semaphores, barriers
                  → graphics/direct_drm_gpu_compute      — DRM/KMS, compute dispatch, no swapchain
                    → graphics/bindless_resources        — descriptor heaps, indexes-as-pointers
```

**Prerequisite knowledge**: 2D geometry, basic linear algebra
**Capstone**: design a frame's render graph without invalidating a pipeline

## Game Systems (P0C)

Game architecture from the inside out.

```
games/loop_architecture          — fixed timestep, interpolation, decoupled update/render
  → fundamentals/state_machines  — FSMs, transitions, hierarchical states
    → games/grid_pathfinding     — A*, Dijkstra, JPS on lattices
      → games/maze_generation    — DFS, Prim's, Wilson's, BSP
        → games/ai_decisions     — behavior trees, GOAP, utility AI
```

**Prerequisite knowledge**: data structures, recursion
**Capstone**: ship a game loop with an NPC that feels intentional, not scripted

## Build & Release (P4)

From sources to an artifact anyone can rebuild and check.

```
build/build_systems              — target DAGs, topological order, incremental rebuilds
  → build/package_resolution     — semver constraints, solving, lockfiles
    → build/reproducible_builds  — bit-for-bit artifacts, pinned inputs, independent rebuilds
```

**Prerequisite knowledge**: graphs, one build tool used in anger
**Capstone**: rebuild a release on a second machine and get the same hash

## Observability (cross-cutting)

How to know what your program is doing.

```
fundamentals/tracing          — structured logging, levels, spans, ring buffers
  → fundamentals/performance  — benchmarking, profiling, allocation, cache effects
    → fundamentals/testing    — unit, property, mocking, coverage
```

**Prerequisite knowledge**: one programming language
**Capstone**: instrument a service so its failures debug themselves
