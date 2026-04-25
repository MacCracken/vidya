# Cyrius vidya — Archive

Historical Cyrius implementation patterns and pinned-plan documents.
Kept for design-log value but no longer the source of truth for current
state. Live state lives in:

- `../language.toml` — language usage + v5.6.x feature additions
- `../field_notes/compiler.toml` — compiler internals + IR-pass gotchas
- `../field_notes/language.toml` — user-facing language gotchas
- `../ecosystem.toml` — ecosystem consumer roster
- `../dependencies.toml` — dep registry
- `../types.toml` — type system reference

…and in the cyrius repo itself:

- `cyrius/CLAUDE.md` — durable preferences/process/procedures
- `cyrius/docs/development/state.md` — volatile state (refreshed every release)
- `cyrius/docs/development/completed-phases.md` — historical release narrative
- `cyrius/docs/development/roadmap.md` — pinned slot plan
- `cyrius/docs/architecture/cyrius.md` — durable architecture / how + why
- `cyrius/CHANGELOG.md` — release source-of-truth

## Files

- `implementation.toml` — moved here at v5.6.17 (2026-04-23). 4,216 lines
  of feature-implementation patterns and v5.5.x-era pinned plans (Win64
  ABI completion, NSS/PAM arc, fdlopen orchestration, O1–O6 sequencing,
  etc.). The currently-active patterns are duplicated into the live docs
  above; this archive preserves the design log + the in-flight notes from
  when each pattern was being actively designed.

  Read this when you want to understand the **why** behind a current
  implementation — the trade-offs that were considered, the dead-ends
  that were ruled out, the alternatives that lost. Don't read this for
  current state — those notes have rotted.
