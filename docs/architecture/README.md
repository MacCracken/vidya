# Architecture Notes

This directory captures *how the world is* — non-obvious invariants, constraints, and quirks a reader cannot derive from the code alone. Architecture notes are not decisions (those go in [`../adr/`](../adr/README.md)) and not how-tos (those live in [`../usage.md`](../usage.md)).

**Conventions** (per [agnosticos first-party-documentation §"Architecture Notes"](https://github.com/MacCracken/agnosticos/blob/main/docs/development/planning/first-party-documentation.md#architecture-notes)):

- **Filename**: `NNN-kebab-case-title.md`, zero-padded to three digits. **Never renumber.**
- Numbered chronologically in order of discovery.
- Each note documents reality, not intent.

## Index

| # | Title | Affects |
|---|---|---|
| — | [`overview.md`](overview.md) | System-level module map: loader → registry → search/compare/render/serve pipeline; consumer relationships (agnoshi, hoosh, sandhi, sakshi). Read this first. |

(Numbered architecture notes are added as invariants surface that aren't covered by `overview.md` or an ADR. Vidya is small enough today that none have been written; the overview carries the load.)
