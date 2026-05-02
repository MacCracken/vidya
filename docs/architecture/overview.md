# Architecture Overview

> Vidya is a Cyrius CLI binary plus a content directory. This document
> describes how the two fit together and how the program runs at startup,
> per-command, and per-HTTP-request.
>
> Last updated: v2.3.5.

## Two Layers

```
┌─────────────────────────────────────────────────┐
│  Content Layer (content/)                       │
│  529+ source files across 60 topics × 11 langs  │
│  Human-readable, AI-trainable, CI-tested        │
└─────────────┬───────────────────────────────────┘
              │ load_all() at startup (one-shot)
┌─────────────▼───────────────────────────────────┐
│  Cyrius CLI (src/main.cyr → build/vidya)        │
│  Registry + search + compare + validate + serve │
│  ~600KB static ELF, no runtime deps             │
└─────────────────────────────────────────────────┘
```

### Content Layer

Each topic is a directory under `content/` containing:

- `concept.toml` — structured metadata (parsed by the loader)
- 11 language files (`rust.rs`, `python.py`, `c.c`, `go.go`,
  `typescript.ts`, `shell.sh`, `zig.zig`, `asm_x86_64.s`,
  `asm_aarch64.s`, `openqasm.qasm`, `cyrius.cyr`) — each tested
  by `scripts/validate-content.sh` against its native toolchain.

Plus `content/cyrius/` — the Cyrius language reference and field-notes
corpus (CYML format: TOML header + markdown body, separated by `---`).
This is content, not code: skipped by the topic loader, consumed by
hoosh and human readers.

See [content-format.md](../development/content-format.md) for the spec.

### Cyrius CLI Layer

```
src/
└── main.cyr           # Entry point — registry, loader, search,
                       # compare, validate, gaps, serve, all CLI
                       # dispatch. Single-file by intent.

lib/                   # Vendored Cyrius stdlib snapshot. Refreshed
                       # via `cyrius deps`. Sandhi and sakshi are
                       # the load-bearing service-layer modules:
├── sandhi.cyr         # HTTP/TLS/discovery service stdlib
├── sakshi.cyr         # Structured tracing (git-pinned, sakshi 2.0.0)
└── ...                # alloc, str, fmt, vec, hashmap, json, toml,
                       # cyml, fnptr, args, regex, net, fs, io, ...

tests/
├── vidya.tcyr         # 41 tests — language enum, TOML loading,
                       # registry, file discovery, content scanning
└── vidya.bcyr         # 6 benchmarks — load_concept, load_all,
                       # reg_get, search, ...
```

Build: `cyrius build src/main.cyr build/vidya`. Test: `cyrius test`.
Bench: `cyrius bench`.

## Data Flow

### Startup

```
main()
  ├─ alloc_init()          # bump allocator
  ├─ args_init()           # argv table
  ├─ reg_init()            # _reg_entries (vec) + _reg_index (hashmap) + _content_dir
  ├─ (dispatch help/usage if argc < 2 — does NOT load content)
  ├─ load_all()            # iterate content/*/, parse concept.toml + read
  │                        # each language file, build Concept records,
  │                        # push into _reg_entries, key by id in _reg_index.
  │                        # ~2.4ms for 60 topics × 11 langs.
  └─ command dispatch      # streq() chain on argv(1)
```

### Per-command (CLI mode)

`list`, `search`, `info`, `compare`, `validate`, `stats`, `gaps`,
`languages` all read from the loaded registry, write to stdout, exit.
The process terminates after one command — registry is freed implicitly
by process teardown.

### Per-request (`serve` mode)

```
cmd_serve(port)
  ├─ inotify_init_watches()                         # IN_NONBLOCK fd,
  │                                                  # one watch per topic dir
  └─ sandhi_server_run(INADDR_ANY(), port, &handle_request, 0)
       │       (blocking accept loop — process lifetime)
       │
       └─ handle_request(ctx, cfd, buf, blen)        # one per connection
            ├─ inotify_drain()                       # non-blocking poll;
            │                                         # sets _reload_pending
            ├─ if _reload_pending: do_reload()       # rebuild + swap inline
            ├─ sandhi_server_get_path(buf, blen)
            └─ http_route(cfd, path)                 # streq() chain
                 ├─ /stats     → json_stats_response()
                 ├─ /list      → json_list_response()
                 ├─ /languages → json_languages_response()
                 ├─ /search    → json_search_response(q)
                 ├─ /info/X    → json_info_response(X)
                 ├─ /compare   → json_compare_response(X, l1, l2)
                 └─ /gaps      → json_gaps_response()
```

Every JSON builder reads only from `reg_list()` / `reg_get()` /
`vec_get()` — pure in-memory hashmap and vec ops. **No content
file I/O during routing.** The only filesystem touch on the
request path is `inotify_drain` (a non-blocking `read(2)` on a
single fd, returns EAGAIN cheaply when no events are queued)
and, when events are present, `do_reload` (a one-shot rebuild
of the staging registry — see "Hot-reload contract" below).

## Memory-resident corpus contract (P0B-2)

The `serve` command depends on this invariant; document it here so
future edits don't quietly break it.

**Contract.** Per-request handlers read the live registry
(`_reg_entries`, `_reg_index`) and **never load concepts
themselves**. The only mutation point is `do_reload`, called
inline at the top of `handle_request` after `inotify_drain`
detects a content change — see "Hot-reload contract" below.

**What the contract guarantees.**

- Sub-millisecond per-request latency on the no-events path
  (verified at v2.3.5: 20µs–139µs across all endpoints). No
  TOML parse, no `dir_list`, no `read_file` on the hot path.
- Single-threaded vidya means the registry pointer pair
  (`_reg_entries`, `_reg_index`) is observed atomically — a
  request either sees the entire pre-swap registry or the
  entire post-swap one, never half of each.
- All-or-nothing reload. A malformed `concept.toml` mid-reload
  leaves the live registry untouched (verified by smoke test
  in v2.3.6).

**What the contract forbids inside the route handlers
(`http_route` and everything it transitively calls).**

- `dir_list`, `read_file`, `is_dir`, `path_join`, `load_concept`,
  `load_all`, `reg_init`, `reg_add` — none of these on the
  routing path. Reload is the only place new concepts get built;
  routing only reads.
- Mutation of `_reg_entries` / `_reg_index` from inside a route
  handler. The handler observes whatever the most recent
  `do_reload` swapped in.
- `alloc()` is allowed for response building — but the bump
  allocator never frees, so be aware that long-running serve
  processes accumulate per-response allocations until restart.
  See "Known limits" below.

**Verified by** `grep -E "read_file|file_read|dir_list|load_concept|fopen|open\(" src/main.cyr` over the line range of `http_route` and `json_*_response` — empty match as of v2.3.6. (`handle_request` itself does call `inotify_drain`/`do_reload`, but those are explicitly part of the contract; the prohibition is on the routing branches that follow.) Re-run after any edit to the serve path.

## Hot-reload contract (P0B-4)

Landed in v2.3.6. Replaces the prior "registry is immutable from
serve start" invariant with a controlled mutation point.

**Detection.** `inotify_init_watches()` opens a non-blocking
inotify fd at `cmd_serve` start and adds a watch on each topic
dir under `content/` (filtered to dirs that contain a
`concept.toml`, so `content/cyrius/` and other non-topic dirs
don't generate noise). Mask: `IN_MODIFY | IN_CLOSE_WRITE |
IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE | IN_DELETE` (= 970).

**Drain.** `inotify_drain()` runs at the top of every
`handle_request`. On the no-events path it's a single
`read(2)` returning -EAGAIN — typically sub-microsecond. When
events are present, the drain loop reads until EAGAIN and sets
`_reload_pending = 1`. The drain doesn't parse event records;
"any bytes read" is sufficient to trigger a reload, which is
itself a full re-scan.

**Build.** `build_next_registry()` populates a *staging*
pair (`_reg_entries_next`, `_reg_index_next`) from a fresh
`dir_list(_content_dir)` sweep. All-or-nothing: any topic dir
that has a `concept.toml` but fails to load aborts the reload,
leaks the partial staging pair (the bump allocator can't free
it, but next reload allocates a fresh one), and leaves the
live registry untouched. Topic dirs *without* a `concept.toml`
are skipped silently — same filter as the original `load_all`.

**Swap.** `swap_registry()` is two pointer assignments
(`_reg_entries = _reg_entries_next; _reg_index = _reg_index_next`).
Single-threaded means it's atomic by construction; no barrier
or lock. The next request reads the new pair.

**Re-watch.** After a successful swap, `inotify_init_watches()`
runs again — closes the prior fd and re-adds watches against
the now-current topic set. New topic dirs added by the reload
get watched; deleted ones stop being watched. The init is
idempotent (closes the prior fd first).

**Observability.** Every reload emits a sakshi event:
- `INFO reload OK: <n> topics in <ns>ns (reload #<count>)`
- `WARN reload aborted: a concept failed to load (failure #<count>); live registry untouched`

Verified end-to-end at v2.3.6 across five scenarios: baseline,
add a topic dir, remove a topic dir, corrupt a concept.toml
(reload aborts, live registry survives), restore (reload
succeeds). Reload latency: 17–22ms for 60 topics.

### Known limits (serve mode)

- **Bump allocator never frees.** Each response alloc and each
  reload's staging registry accumulates. Long-running serve
  processes will eventually exhaust the heap. Mitigation today:
  restart on a cron, or front with a process supervisor that
  cycles after N reloads or N requests. An arena/pool allocator
  is future work (no roadmap entry yet).
- **Single-threaded accept.** Sandhi 1.0.0's `sandhi_server_run`
  serves one connection at a time. Adequate for the local
  agnoshi/hoosh use case; not for public exposure.
- **Reload is triggered by the next request, not immediately.**
  Because the drain runs in `handle_request`, content changes
  during an idle period don't reload until the next HTTP hit.
  Acceptable for an interactive dev tool; if "automatic on
  edit" semantics are needed, drive a periodic curl (e.g. a
  10s `curl -s /stats > /dev/null` in another terminal).
- **No partial reload.** A single touched file triggers a full
  re-scan of all 60 topics. ~20ms; not worth optimising until
  topic count crosses ~500.

## Key Design Decisions

1. **CYML for the Cyrius corpus, TOML for concept metadata.**
   `content/cyrius/**` uses CYML (TOML header + markdown body) because
   field-note bodies are long-form prose with code blocks. The
   per-topic `content/<topic>/concept.toml` files use plain TOML
   because they're pure structured metadata.

2. **Sandhi over hand-rolled HTTP.** Pre-v2.3.0 vidya carried a
   ~270-LOC `lib/http_server.cyr`. v2.3.0 deleted it in favour of
   `lib/sandhi.cyr` (the cyrius 5.7.0 service-boundary stdlib).
   Sandhi handles parsing, query strings, URL decoding, and the
   accept loop; vidya only writes routes.

3. **Memory-resident, not lazy.** `load_all` runs unconditionally
   for every command except `help`/`usage` — even though `list`
   could in theory just glob the directory. The win: every command
   has the same data view, the same latency profile, and the
   `serve` path can re-use the same loader without a code split.

4. **Single-file `src/main.cyr`.** ~1500 LOC. Splitting into
   modules is feasible but unmotivated — Cyrius's module story
   is `include` + namespacing-by-prefix, and the win at this size
   is small. Will revisit when the file crosses ~3000 LOC or when
   the registry/serve halves diverge enough to test independently.

5. **TOML keys are bare cstr literals.** Cyrius 5.x stdlib
   `toml_get*` helpers compare via `str_eq_cstr`; passing a `Str`
   silently returns 0 (the v2.3.0 dangling-pointer bug). All
   lookups in `src/main.cyr` use `toml_get(pairs, "key")`, never
   `toml_get(pairs, str_from("key"))`. See field note
   `stdlib_str_to_cstr_key_migration`.

6. **Sentinel returns, not exceptions.** Cyrius has no
   throw/catch. Every fallible call returns 0 (or -1) and the
   caller checks. `json_compare_response` uses `0` for "topic not
   found" and `0 - 1` for "unknown language" so `http_route` can
   route them to 404 vs 400.

## Consumers

- **agnoshi** — shell uses `vidya search` / `vidya info` for
  programming help responses.
- **hoosh** — LLM consumes `content/` directly (TOML + source) and
  the corpus under `content/cyrius/` for grounded programming advice.
- **Cyrius** — vidya documents compiler patterns being implemented
  in real-time; field notes capture gotchas as they surface.
- **mabda** — vidya documents the GPU patterns mabda implements;
  mabda's field notes feed back into
  `content/cyrius/field_notes/mabda_v3_gpu/`.
- **sandhi** — vidya's HTTP service runs on sandhi (cyrius stdlib).
- **sakshi** — vidya uses sakshi for structured tracing (stderr-only
  profile today).
