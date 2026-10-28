# Vidya — Roadmap

> **Future work only.** Shipped work is in [CHANGELOG.md](../../CHANGELOG.md).
> The current version, pins, sizes and gate counts are in [state.md](state.md).
> Process, toolchains and gates are in [CLAUDE.md](../../CLAUDE.md).
>
> **Last updated**: 2026-10-28, at 2.9.6 (P5 landed).

## Sequence

| Release | Theme | Consumer-visible |
|---|---|---|
| **3.0.0** | Content reorganization | **Yes**: `content/` paths change |
| after 3.0.0 | Renderer surface, P6 Cyrius concepts | Additive |

Toolchain patches (cyrius, vyakarana, Zig) land between these whenever
upstream moves. They follow CLAUDE.md's work loop.

Why this order:

- **The reorg moves 80 topics.** P5 landed first (2.9.6), so the new
  layout is decided with the functional / type-theory group in place.
- **P6 after the reorg.** Where Cyrius concept topics sit next to
  `content/cyrius/` is a reorg decision, so P6 should land once, in its
  final place.
- **Renderer after 3.0.0.** It is additive (opt-in flags), and it adds the
  third and fourth tokenize call sites. Those are what justify adopting
  vyakarana's pull adapter.

---

## 3.0.0 — content reorganization

**Why it's a major release**: two consumers depend on `content/` paths.
hoosh reads `content/` directly, and vyakarana snapshots
`content/lexing_and_parsing/<lang>` as its test corpus (vyakarana ADR 0001).

The spec is [`content-grouping.md`](content-grouping.md), and it is stale.
It was written at 36 topics and places only those 36. The other 44,
including all of P1–P5, have no group. `learning-paths.md` (every topic
on a path since 2.9.6) is a starting point for the groups. Rewriting it is the first step.

**Decide first:**

- [ ] **Topic IDs stay flat and unique** (`strings`, not
  `fundamentals/strings`)? Recommended, because then CLI arguments and HTTP
  paths don't change; only filesystem paths do.
- [ ] **Back-compat**: symlink the old paths for one minor
  (content-grouping.md, rule 6), or make a clean break?
- [ ] Where `content/cyrius/` and the P6 topics sit.

**Work** (one atomic change):

- [ ] `load_all()` and the hot-reload watcher recurse.
- [ ] `scripts/validate-content.sh` and `validate_command` change together.
- [ ] CI's "Verify concept.toml in topic directories" loop.
- [ ] Tests, fixtures, and every output that carries a path: `/code/...` and
  `/compare` return a `path` field, and the CLI's `info` and `compare` print
  `file:` lines.
- [ ] Docs that name paths: `content-format.md`, `usage.md`,
  `guides/getting-started.md`, `learning-paths.md`.

**Coordinate before tagging:**

- hoosh: reads `content/` directly.
- vyakarana: its corpus sync names `content/lexing_and_parsing/<lang>`.
- agnoshi: uses only the CLI and HTTP, so it is unaffected if IDs stay flat.

Any other breaking change found during 2.9.x also goes in 3.0.0. None is
queued.

---

## After 3.0.0

### Renderer surface (additive)

- [ ] **Themes.** The ANSI palette is hard-coded in `ansi_open_for_kind`
  (`src/vidya_core.cyr:893`). Move palettes to `content/theme/*.toml`,
  keyed by vyakarana `kind_name` (its architecture note 004). Add
  `--theme=<name>` to `code` and `theme=<name>` to `GET /code/...`.
- [ ] **Wider scope, opt-in** so existing output is unchanged:
  `info <topic> --code <lang>` renders the example inline, and
  `compare <topic> <l1> <l2>` renders both sides.
- [ ] Those add the third and fourth tokenize call sites. Use vyakarana's
  `tokenize_stream_next` pull adapter there (it shipped upstream), rather
  than a third hand-written loop.
- Rule: if vyakarana mistokenizes a sample, file the bug at vyakarana. Never
  patch tokens in vidya's renderer.
- Start from vyakarana's
  [consumer integration guide](https://github.com/MacCracken/vyakarana/blob/main/docs/guides/consumer-integration.md)
  and
  [theme-palette contract](https://github.com/MacCracken/vyakarana/blob/main/docs/architecture/004-theme-palette-contract.md).

### P6 — Cyrius-specific concepts

`cyrius_basics`, `cyrius_bootstrap`, `cyrius_agents`, `cyrius_capabilities`,
`cyrius_ipc`. These are concept slots that document Cyrius patterns the way
other topics document general ones. They are distinct from `content/cyrius/`
(the language reference and field notes), and they land in the 3.0.0 layout.

---

## Waiting on a trigger

| Item | Trigger | Action |
|---|---|---|
| Redundant stdlib declarations | cyrius makes transitive follow-through contractual | Drop `ct`, `keccak` and `sigil` from `[deps] stdlib`. They have been redundant since 6.5.29 and are kept because an undeclared module fails at runtime (see `cyrius.cyml`). |
| Split the content CI job | Content Validation passes ~15 min (8.1 min on 2026-10-27) | A per-language matrix; the script's stages are independent. |
| Zig pin | The dev host or an example needs a newer Zig | Bump CI's `ZIG_VER` and its sha256, plus README and `docs/sources.md`. |
| Leak-free hot reload | bayan's `toml_parse` takes an allocator (it hard-codes `default_alloc()`) | Build each registry on one of two alternating arenas and reset the spare before the next reload. A reload then holds at two registries instead of adding ~9.4 MB (2.9.3). |
| `/code` leaves nothing | vyakarana can reuse a stream, or create one from an allocator | Render on the request arena. Each `/code` still leaves its stream on the bump heap, 29–119 KB (2.9.3). Also ask for `tokenbuf_drop_front` (which vidya relies on) to be added to the public list. |
| Back to sandhi's escaper | `sandhi_json_escape_a` builds on its `a` (it uses a plain `str_builder_new()` through sandhi 1.13.7) | `json_escape_a` can go, and `json_add_cstr` can call sandhi again. Keep the `json_escape_matches_sandhi` test until then. |
| Zig tail calls in the gate | Zig's self-hosted x86_64 backend performs `@call(.always_tail, …)` (0.17 refuses: "compiler backend 'stage2_x86_64' does not support tail calls") | Drop the `zig_backend == .stage2_llvm` guard in `functional_patterns/zig.zig`, so the gate runs `sumToTail` instead of skipping it on x86_64. |
| OpenQASM `const` | qiskit-qasm3-import accepts `const` declarations (0.6.0: "node of type ConstantDeclaration is not supported") | Size `dependent_types/openqasm.qasm`'s registers with `const` instead of literal expressions. |
| OpenQASM `for` over registers | qiskit-qasm3-import can index a register with a loop variable, and accepts `uint` (0.6.0 does neither) | Rewrite `iterators/openqasm.qasm`'s unrolled map and fold as `for` loops. |
| Rehydration field note | A third port hits it (vidya and sit so far) | Promote `cyrius lib sync` vs `cyrius update`, plus the clean-rehydrate requirement, to a field note. |
| Content integrity route | A consumer asks for it | Hash `content/` at startup with sigil and serve the result at `/integrity`. |

## Cross-repo (not vidya's to edit)

- **zugot**: `marketplace/vidya.cyml` still pins 2.7.3, and its
  `make = "cyrius build"` fails. Details are in [state.md](state.md).
- **Sibling repos' CI action majors**: see
  [ecosystem-action-pins.md](ecosystem-action-pins.md).
