# 0003 — Group the content, and make a topic's id its path

**Status**: Accepted
**Date**: 2026-10-28

## Context

Through 2.9.6, `content/` was flat: 80 topic directories side by side, each
with an id equal to its directory name (`strings`, `lexing_and_parsing`).
`concept.toml` also carried a `topic` field meant as a category, but 59 of
its 67 values were used by exactly one topic, so it grouped almost nothing. The
corpus had grown past what a flat directory or `vidya list` could show
legibly, and the 2.x grouping plan (36 topics, flat ids kept, old paths
symlinked for one release) was stale.

Two consumers read `content/` paths directly: hoosh reads the tree, and
vyakarana snapshots `content/lexing_and_parsing/<lang>` as its test corpus.
agnoshi reads only the CLI and HTTP. Any change to paths is a major release.

## Decision

Organize `content/` into **groups**, and make **a topic's id its path**:

- A group is `content/<group>/` with a `group.toml` (`id`, `title`,
  `description`, `order`). A topic is `content/<group>/<topic>/` with a
  `concept.toml` whose `id` is `"<group>/<topic>"`. The loader refuses any
  other id, and reads exactly those two levels.
- The id is the same string everywhere: the CLI argument, the HTTP path
  (`/info/<group>/<topic>`, `/code/<group>/<topic>/<lang>`),
  `related_topics`, and every `path` field. The group replaces the `topic`
  category, which is removed.
- A topic's name does not repeat its group's (`networking/fundamentals`),
  so eight topics were renamed.
- `content/cyrius/` is a group. Its language reference and field notes stay
  at the group's root (they have no `concept.toml`), and the P6 Cyrius
  concept topics become `cyrius/<topic>/`.
- A clean break: no symlinks, aliases or old-id resolution. The CLI's "topic
  not found" error suggests the new id when a bare name matches one topic.

## Consequences

- **Positive**: one identity per topic, so a path, an id and a URL can never
  disagree, and the loader enforces it. `list`, `/groups` and
  `/list?group=` give the corpus a structure consumers can use. The group is
  a real category where `topic` was not. A new group or topic has an obvious
  place.
- **Negative**: every consumer's stored ids and paths break at once. Ids are
  52 % longer on average (15.8 → 24.1 bytes), which shows in micro-benchmarks
  that scan ids (`search_text` +46 %); production search is unchanged. The
  two-level walk costs ~3 % of `load_all`.
- **Neutral**: hoosh and vyakarana must move to the new paths
  (`compilers/lexing_and_parsing`). The two-level rule means a group cannot
  nest groups; if one ever must, that is a new decision.

## Alternatives considered

- **Group the directories, keep flat ids** (the recommendation in the 2.x
  roadmap). Rejected: paths and ids would then disagree for every topic, a
  bare id would hide which group a topic is in, and the move would change
  the files without organizing what anyone reads or queries.
- **Symlink the old paths for one release** (the 2.x plan). Rejected: it
  doubles every topic in a filesystem walk, and it delays the break rather
  than easing it, because the old ids would still have to go.
- **Arbitrary nesting** (`languages/types/dependent_types`). Rejected for
  now: 80 topics fit in one level of 14 groups, and a fixed depth keeps the
  loader, the gate and the routes simple.
