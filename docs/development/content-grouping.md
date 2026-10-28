# Content Grouping

> **Status**: in force since 3.0.0. `content/` is organized by group, and a
> topic's id is its path. This replaces the 2.x plan (written at 36 topics,
> flat ids, a symlinked transition), which 3.0.0 did not follow: the break is
> clean, with no aliases or symlinks.

## Rules

1. **A group is a directory under `content/` with a `group.toml`** (`id`,
   `title`, `description`, `order`). `id` is the directory's name; `order`
   sets where it lists (reading order, fundamentals first).
2. **A topic is a directory inside a group with a `concept.toml`.** Its id is
   its path, `<group>/<topic>`, and its `concept.toml` must say so: the
   loader refuses any other id.
3. **Exactly two levels.** The loader reads `content/<group>/<topic>/` and
   nothing else. A `concept.toml` directly under `content/` (the 2.x layout)
   or in a directory without a `group.toml` would be skipped silently, so
   `cyrius test` (`content_layout`) and CI both fail on one.
4. **Everything addresses a topic by its id**: the CLI (`vidya info
   fundamentals/strings`), the HTTP routes (`/info/fundamentals/strings`,
   `/code/fundamentals/strings/rust`), `related_topics`, and `path` fields,
   which are relative to `content/` (`fundamentals/strings/rust.rs`).
5. **A topic's name does not repeat its group's.** `networking/fundamentals`,
   not `networking/networking_fundamentals`. Ids need to be unique only as
   whole paths.
6. **`cyrius/` is a group like the others.** Its root also holds the Cyrius
   language reference (`language/`, `types.cyml`, …) and the field notes
   (`field_notes/`), which have no `concept.toml` and so are not topics.
   P6's Cyrius concept topics land as `cyrius/<topic>/`.

## Groups

| Group | Title | Topics | Covers |
|---|---|---|---|
| `fundamentals` | Fundamentals | 14 | The material every other group assumes: text, iteration, I/O, errors, testing, tracing, concurrency, memory, performance, security, and the patterns and algorithms everyday code is built from. |
| `languages` | Language Design | 9 | How programming languages are designed: type systems, traits and typeclasses, pattern matching, ownership, macros and modules, then functional programming, effect systems and dependent types. |
| `compilers` | Compilers | 9 | From source text to a running binary: lexing and parsing, intermediate representations, optimization, code generation, instruction encoding, linking, executable formats, and bootstrapping a compiler that compiles itself. |
| `systems` | Operating Systems | 8 | From power-on to processes and files: boot, virtual memory, interrupts, scheduling, system calls and the ABI, filesystems, allocators and kernel structure. |
| `networking` | Networking | 5 | Services on the network: sockets and addressing, DNS, HTTP, TLS, and communication between processes on one host. |
| `data` | Data and Storage | 9 | How data is encoded, compressed and stored: serialization formats, pages and B-trees, SQL parsing, transactions, write-ahead logging and file locking. |
| `distributed` | Distributed Systems | 2 | From one node to a cluster that keeps agreeing: replication, partitions, quorums, vector clocks and consensus. |
| `build` | Build and Release | 3 | From sources to an artifact anyone can rebuild: build graphs and incremental rebuilds, package resolution and lockfiles, reproducible builds. |
| `audio` | Audio | 2 | Digital signal processing through real-time synthesis: filters, sample rates, oscillators, envelopes and voices, in fixed-point arithmetic. |
| `ai` | AI and ML Systems | 3 | From the math to an inference pipeline: neural network layers, embeddings and vector search, decoding and inference. |
| `graphics` | Graphics | 9 | From pixels to the GPU pipeline: framebuffers, rasterization, sprites, post-processing, render graphs, GPU memory, synchronization, compute and bindless resources. |
| `games` | Game Systems | 6 | Game architecture from the inside out: the game loop, collision and physics, pathfinding, procedural mazes, and AI that decides. |
| `quantum` | Quantum Computing | 1 | Qubits, gates, superposition, entanglement and the algorithms that use them, written as OpenQASM circuits beside classical simulations. |
| `cyrius` | Cyrius | 0 | The Cyrius language reference (language/) and field notes (field_notes/) live at this group's root. Cyrius-specific concept topics (P6) are its topics. |

```
content/
├── fundamentals/         — Fundamentals
│   ├── algorithms/
│   ├── concurrency/
│   ├── design_patterns/
│   ├── error_handling/
│   ├── fixed_point_arithmetic/
│   ├── input_output/
│   ├── iterators/
│   ├── memory_management/
│   ├── performance/
│   ├── security/
│   ├── state_machines/
│   ├── strings/
│   ├── testing/
│   ├── tracing/
├── languages/            — Language Design
│   ├── dependent_types/
│   ├── effect_systems/
│   ├── functional_patterns/
│   ├── macro_systems/
│   ├── module_systems/
│   ├── ownership_and_borrowing/
│   ├── pattern_matching/
│   ├── trait_and_typeclass_systems/
│   ├── type_systems/
├── compilers/            — Compilers
│   ├── binary_formats/
│   ├── bootstrapping/
│   ├── code_generation/
│   ├── elf_and_executable_formats/
│   ├── instruction_encoding/
│   ├── intermediate_representations/
│   ├── lexing_and_parsing/
│   ├── linking_and_loading/
│   ├── optimization_passes/
├── systems/              — Operating Systems
│   ├── allocators/
│   ├── boot_and_startup/
│   ├── filesystems/
│   ├── interrupt_handling/
│   ├── kernel_topics/
│   ├── process_and_scheduling/
│   ├── syscalls_and_abi/
│   ├── virtual_memory/
├── networking/           — Networking
│   ├── dns/
│   ├── fundamentals/
│   ├── http_and_web_protocols/
│   ├── ipc/
│   ├── tls_and_encryption/
├── data/                 — Data and Storage
│   ├── btree_indexing/
│   ├── compression/
│   ├── concurrent_file_access/
│   ├── jsonl_format/
│   ├── page_management/
│   ├── serialization/
│   ├── sql_parsing/
│   ├── transactions_and_acid/
│   ├── write_ahead_logging/
├── distributed/          — Distributed Systems
│   ├── consensus/
│   ├── foundations/
├── build/                — Build and Release
│   ├── build_systems/
│   ├── package_resolution/
│   ├── reproducible_builds/
├── audio/                — Audio
│   ├── dsp/
│   ├── synthesis/
├── ai/                   — AI and ML Systems
│   ├── embeddings/
│   ├── inference/
│   ├── neural_networks/
├── graphics/             — Graphics
│   ├── bindless_resources/
│   ├── bloom_and_glow/
│   ├── direct_drm_gpu_compute/
│   ├── explicit_gpu_synchronization/
│   ├── framebuffer_rendering/
│   ├── gpu_memory_pooling/
│   ├── line_rasterization/
│   ├── render_graph_architecture/
│   ├── sprite_rendering/
├── games/                — Game Systems
│   ├── ai_decisions/
│   ├── collision_detection_2d/
│   ├── grid_pathfinding/
│   ├── loop_architecture/
│   ├── maze_generation/
│   ├── projectile_physics/
├── quantum/              — Quantum Computing
│   ├── fundamentals/
├── cyrius/               — Cyrius
```

## Adding a topic or a group

- **A topic**: create `content/<group>/<topic>/concept.toml` with
  `id = "<group>/<topic>"`, then the 11 implementations
  (`content-format.md`). `related_topics` take full ids.
- **A group**: create `content/<group>/group.toml`. Pick `order` so the group
  reads where it belongs; renumbering the others is fine, since `order` is
  only a sort key.
- **Moving a topic** changes its id, which is a breaking change for anyone
  who stored the old one. Update the `id`, every `related_topics` that names
  it, and say so in the CHANGELOG.

## 2.x → 3.0.0 ids

Every topic id gained its group. Eight topics were also renamed, because
their name repeated the group:

| 2.x id | 3.0.0 id |
|---|---|
| `audio_dsp` | `audio/dsp` |
| `audio_synthesis` | `audio/synthesis` |
| `compiler_bootstrapping` | `compilers/bootstrapping` |
| `distributed_systems` | `distributed/foundations` |
| `game_ai_decisions` | `games/ai_decisions` |
| `game_loop_architecture` | `games/loop_architecture` |
| `networking_fundamentals` | `networking/fundamentals` |
| `quantum_computing` | `quantum/fundamentals` |

The full table of all 80 is in the CHANGELOG's 3.0.0 entry.

## Field-notes subfolder pattern (proven at v2.3.1)

Field-note topics follow a different threshold from the top-level `content/` reorg:
when a single `field_notes/<topic>.cyml` grows past ~800 lines or accumulates
distinct sub-topics, convert it into a folder of chunked `.cyml` files.

- **By version arc** when entries cluster around release timelines
  (`compiler/v3.cyml`, `v4.cyml`, ...).
- **By surface area** when entries cluster around language layers
  (`language/parser_syntax.cyml`, `semantics_runtime.cyml`, ...).
- **By phase** when entries cluster around project milestones
  (`mabda_v3_gpu/phase_a.cyml`, `phase_b.cyml`, ...).

Each chunk file gets a 3-line header (title, one-line scope, entry count) and
the same `[[entries]]` body format. `index.cyml` lists every file with its
entry count and per-entry one-liner.
