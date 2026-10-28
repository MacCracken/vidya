# Vidya — Roadmap

> **Future work only.** Shipped work is in [CHANGELOG.md](../../CHANGELOG.md).
> The current version, pins, sizes and gate counts are in [state.md](state.md).
> Process, toolchains and gates are in [CLAUDE.md](../../CLAUDE.md).
>
> **Last updated**: 2026-10-28, at 2.9.2.

## Sequence

| Release | Theme | Consumer-visible |
|---|---|---|
| 2.9.x | `serve` longevity, content review, P5 | No. Content grows 77 → 80 topics. |
| **3.0.0** | Content reorganization | **Yes**: `content/` paths change |
| after 3.0.0 | Renderer surface, P6 Cyrius concepts | Additive |

Toolchain patches (cyrius, vyakarana, Zig) land between these whenever
upstream moves. They follow CLAUDE.md's work loop.

Why this order:

- **P5 before the reorg** keeps the corpus near 80 topics when it moves.
- **P6 after the reorg.** Where Cyrius concept topics sit next to
  `content/cyrius/` is a reorg decision, so P6 should land once, in its
  final place.
- **Renderer after 3.0.0.** It is additive (opt-in flags), and it adds the
  third and fourth tokenize call sites. Those are what justify adopting
  vyakarana's pull adapter.

---

## 2.9.x

Each item is its own patch unless noted, in this order.

### `serve` longevity

`serve` is meant to run for days under agnoshi and hoosh. Two things stand
in the way.

- [ ] **Memory.** Every response, and every hot reload's staging registry,
  allocates from the bump heap and is never freed. A long-running `serve`
  eventually exhausts it (overview.md, "Known limits"). `lib/alloc.cyr` now
  has arenas (`arena_new` / `arena_reset` / `arena_free`). Give each request
  an arena and reset it after the response, and free a replaced registry's
  arena on reload. Check first whether the response path (`str_builder_*`,
  bayan, sandhi's server) can allocate from an arena. If it can't, that is
  an upstream ask. Done when a test serves N requests with flat heap use and
  the "Known limits" bullet is gone.
- [ ] **Clock drift.** sakshi stamps spans from a calibrated cycle counter.
  `sakshi_clock_recalibrate()` exists for long-running processes, and sakshi
  recommends calling it hourly. `cmd_serve` never calls it. Call it from the
  accept loop once an hour has passed. It requires a single thread, which
  `serve` is.

### Content review

This has been queued ahead of P5 since 2.8.x. The last full pass was 2.8.3,
which found 80 verified defects behind a green gate. Since then the corpus
has had the Zig 0.17 port (45 files), C23, and the cyrius 6.7 line.

- [ ] Review every example for what the gate cannot see (CLAUDE.md lists the
  blind spots): false comments, tests that cannot fail, and examples that
  teach the opposite of their subject.
- [ ] Close one blind spot while there. For example: simulate the OpenQASM
  circuits and assert their documented outcomes, since today they are only
  parsed. Any new check goes into both validators (CLAUDE.md's
  byte-equivalence rule).

### P5 — functional / type theory (77 → 80 topics)

`functional_patterns`, `effect_systems`, `dependent_types`. One topic per
patch: each is large effort, Cyrius reference first, then the other ten.

- [ ] Before starting, settle `dependent_types`' scope. Most of the 11
  languages have no dependent types, so the topic will mostly teach
  encodings (phantom types, const generics, runtime-checked refinements)
  and say plainly where a language cannot express the idea.

---

## 3.0.0 — content reorganization

**Why it's a major release**: two consumers depend on `content/` paths.
hoosh reads `content/` directly, and vyakarana snapshots
`content/lexing_and_parsing/<lang>` as its test corpus (vyakarana ADR 0001).

The spec is [`content-grouping.md`](content-grouping.md), and it is stale.
It was written at 36 topics and places only those 36. The other 41,
including all of P1–P4, have no group. Rewriting it is the first step.

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
| Loader buffer | An example nears 64 KB (largest today: 20.5 KB) | `load_concept` reads each example into 64 KB and truncates the rest silently. Raise the cap or size the read from the file. |
| Rehydration field note | A third port hits it (vidya and sit so far) | Promote `cyrius lib sync` vs `cyrius update`, plus the clean-rehydrate requirement, to a field note. |
| Content integrity route | A consumer asks for it | Hash `content/` at startup with sigil and serve the result at `/integrity`. |

## Cross-repo (not vidya's to edit)

- **zugot**: `marketplace/vidya.cyml` still pins 2.7.3, and its
  `make = "cyrius build"` fails. Details are in [state.md](state.md).
- **Sibling repos' CI action majors**: see
  [ecosystem-action-pins.md](ecosystem-action-pins.md).
