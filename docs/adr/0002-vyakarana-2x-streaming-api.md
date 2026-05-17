# 0002 — Adopt vyakarana 2.x streaming tokenizer API

**Status**: Accepted
**Date**: 2026-05-16

## Context

Vidya integrated [vyakarana](https://github.com/MacCracken/vyakarana) — AGNOS's source-code tokenizer — at v2.7.0 to power `vidya code <topic> <lang>` (ANSI-colored CLI output) and `GET /code/{topic}/{lang}` (JSON tokens over HTTP). The integration used the 1.x synchronous API:

```cyrius
var tb = tokenize_source(src, lang);
// walk tb...
```

One call. Hands over a complete buffer; returns a fully-populated tokenbuf. Worked for files under the 1 MB `VYK_SRC_CAP` (every example in `content/` fits well under).

At v2.0.0, vyakarana removed `tokenize_source` in favor of a push-based streaming primitive (vyakarana's own [ADR 0017](https://github.com/MacCracken/vyakarana/blob/main/docs/adr/0017-streaming-api.md)) — the only scheduled API break in their entire roadmap. Migration was mechanical but unavoidable for any consumer staying on the 2.x line:

```cyrius
var s = tokenize_stream_new(lang);
if (s == 0) { /* unknown grammar */ }
var tb = tokenbuf_new();
tokenize_stream_feed(s, src, strlen(src));
tokenize_stream_finish(s, tb);
tokenize_stream_free(s);
// walk tb...
```

Two clean paths existed at the v2.7.1 dep-bump:

1. Pin vyakarana 1.13.3 (last 1.x release, no migration required).
2. Migrate to vyakarana 2.x (streaming primitives, picks up everything from 2.0.0 onward).

The 1.x line would receive no further development — pinning there meant accepting that ceiling.

## Decision

**Migrate to vyakarana 2.2.1 at v2.7.1.** Update the two consumers in `src/main.cyr` (`cmd_code` at `:877` and the `/code/...` HTTP route at `:1569`) from `tokenize_source` to the streaming sequence (`tokenize_stream_new` → `_feed` → `_finish` → `_free`). Preserve the rest of the integration surface (`tokenbuf_*` accessors, `kind_name`, `has_grammar`, the kind-name palette contract per vyakarana ADR 0004) — none of those changed across the 1.x → 2.x boundary.

**Scope in**:
- Both call sites rewritten in place. Each goes from one line to five lines (the cost of making the integration streaming-capable).
- Comment at `src/main.cyr:824` updated to point at vyakarana ADR 0017 as the migration recipe of record.
- vyakarana pin in `cyrius.cyml` bumped 1.11.1 → 2.2.1 (also pulls the compose-rule prefix-buffering streaming fix from 2.2.1's FINDING-011).

**Scope out**:
- No call-site wrapper helper. The CLAUDE.md "wait for the third instance before extracting" rule applies — two call sites is not three, so the five-line dance is inlined at each site.
- No use of `tokenize_stream_drain` yet. 2.0.0 implementation buffers everything before scanning anyway (drain returns 0 until `_finish` runs); the per-feed-drain capability lands in vyakarana 2.0.1+ when the scanner refactor ships. Tracked in `docs/development/roadmap.md` 2.7.x dep-track follow-ups.

## Consequences

### Positive

- **Output is byte-identical to the v1.x integration.** Smoke-verified at integration time: 2187 tokens on the rust track of `content/lexing_and_parsing/` (8829 source bytes) — same numbers as the 2.7.0 reference (`CHANGELOG.md` v2.7.0 entry).
- **Stays on the supported line.** Vyakarana's 2.x is where new grammars, fixes, and the eventual per-feed-drain scanner refactor land. Pinning 1.13.3 would have accepted a frozen feature set.
- **Picks up streaming-correctness fixes for free.** 2.2.1 closed FINDING-011 (compose-rule prefix buffering across chunks) — not load-bearing for vidya's current "buffer everything, finish once" pattern, but lands automatically when the per-feed-drain follow-up arrives.

### Negative

- **Five-line dance at each call site.** Verbose. Acceptable at two sites; would justify a wrapper at three or more.
- **Per-call overhead grows ~5–25%** on small inputs per vyakarana ADR 0017's bench note (extra alloc for the stream record, plus one byte-copy from chunk to internal buffer). Vidya's inputs (a single source file per call) are small; the overhead is well under the network/disk latency of the consuming path.

### Neutral

- The migration recipe is mechanical and reversible — should the project ever need to fork its own vyakarana branch, both 1.x and 2.x interfaces are well-documented.
- Drain semantics for 2.0.1+ are a tracked follow-up (`docs/development/roadmap.md` 2.7.x dep-track), not blocking work.

## Alternatives considered

- **Pin vyakarana 1.13.3 and skip the migration.** Rejected. The 1.x line is closed; staying there would have permanently frozen tokenizer behavior and forfeited any future grammar additions or fixes.
- **Wrap the five-line dance in a vidya-local `tokenize_buf(src, lang)` helper.** Rejected at this point per the "rule of three" — two call sites do not justify a helper. The wrapper is a natural follow-up if a third call site lands.
- **Adopt the `tokenize_stream_drain` per-feed loop now.** Rejected. Vyakarana 2.0.0's drain is a tease — returns 0 until `_finish` runs. The buffer-then-finish pattern is functionally identical and waiting for 2.0.1+'s real drain has zero cost today.
