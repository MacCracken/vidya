# Learning Paths

> **Last Updated**: 2026-05-16 (v2.7.1 — post-P3; covers all 74 topics across P0–P3. P4 build-system paths added when those topics ship.)

Ordered topic sequences for structured learning. Each path builds on the previous topic. Run `vidya list` for the full topic index.

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

## Networked Service (P1)

Build a service that survives the open internet.

```
networking_fundamentals      — sockets, addressing, connection lifecycle
  → dns                          — resolution, caching, RR types
    → http_and_web_protocols       — request/response, parsing, headers, status codes
      → tls_and_encryption           — TLS handshake, ALPN, session resumption
        → ipc                          — Unix sockets, pipes, shared memory
```

**Prerequisite knowledge**: basic POSIX, OS fundamentals
**Capstone**: stand up an HTTP service with TLS termination and IPC between workers

## Database Internals (P0C / P2)

How storage engines work under the hood.

```
serialization                — wire formats, varints, encoding choices
  → jsonl_format                 — line-delimited streams, recovery, append semantics
    → btree_indexing               — leaf vs internal nodes, splits, range queries
      → sql_parsing                  — tokenizer, AST, plan basics
        → transactions_and_acid        — isolation levels, MVCC, snapshot reads
          → write_ahead_logging          — WAL records, recovery, checkpoints
            → compression                  — LZ4, DEFLATE, dictionary methods
```

**Prerequisite knowledge**: data structures, basic SQL
**Capstone**: understand why your favorite database makes its trade-offs

## Distributed Systems (P2)

From a single node to a cluster that doesn't lie to you.

```
ipc                          — single-host process communication primitives
  → networking_fundamentals      — sockets across hosts
    → consensus                    — Paxos, Raft, leader election, log replication
      → distributed_systems          — partitioning, replication, CAP, failure modes
```

**Prerequisite knowledge**: networking, transactions, async
**Capstone**: read a distributed system's paper and predict its failure modes

## Audio (P3)

DSP fundamentals through real-time synthesis.

```
fixed_point_arithmetic       — Q-format, saturation, scale management
  → audio_dsp                    — FIR/IIR filters, FFT, sample rates
    → audio_synthesis              — oscillators, envelopes, PolyBLEP, voice allocation
```

**Prerequisite knowledge**: complex numbers, basic signal processing intuition
**Capstone**: write a synth voice that doesn't alias

## AI / ML Systems (P3)

From the math to a deployable inference pipeline.

```
neural_networks              — layers, gradients, backprop, training loop
  → embeddings                   — vector spaces, similarity, projection
    → inference                    — quantization, batching, KV-cache, attention
```

**Prerequisite knowledge**: linear algebra, calculus, probability
**Capstone**: serve a model with the right batching + caching strategy

## Graphics (P0C)

From pixels to the GPU pipeline.

```
framebuffer_rendering        — pixel buffers, blit, double-buffering
  → line_rasterization           — Bresenham, antialiasing, sub-pixel
    → sprite_rendering             — alpha, batching, tile maps
      → collision_detection_2d       — AABB, swept, broad-phase
        → projectile_physics           — integration schemes (Euler, Verlet)
          → bloom_and_glow               — post-process passes, bloom, HDR
            → render_graph_architecture    — pass graphs, transient resources, barriers
              → gpu_memory_pooling           — pools, suballocation, freelists
                → explicit_gpu_synchronization — fences, semaphores, barriers
                  → direct_drm_gpu_compute       — DRM/KMS, compute dispatch, no swapchain
                    → bindless_resources           — descriptor heaps, indexes-as-pointers
```

**Prerequisite knowledge**: 2D geometry, basic linear algebra
**Capstone**: design a frame's render graph without invalidating a pipeline

## Game Systems (P0C)

Game architecture from the inside out.

```
game_loop_architecture       — fixed timestep, interpolation, decoupled update/render
  → state_machines               — FSMs, transitions, hierarchical states
    → grid_pathfinding             — A*, Dijkstra, JPS on lattices
      → maze_generation              — DFS, Prim's, Wilson's, BSP
        → game_ai_decisions            — behavior trees, GOAP, utility AI
```

**Prerequisite knowledge**: data structures, recursion
**Capstone**: ship a game loop with an NPC that feels intentional, not scripted

## Observability (cross-cutting)

How to know what your program is doing.

```
tracing                      — structured logging, levels, spans, ring buffers
  → performance                  — benchmarking, profiling, allocation, cache effects
    → testing                      — unit, property, mocking, coverage
```

**Prerequisite knowledge**: one programming language
**Capstone**: instrument a service so its failures debug themselves
