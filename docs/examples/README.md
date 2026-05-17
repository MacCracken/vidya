# Examples

Working code that exercises vidya's surfaces. Most readers don't need this directory — the **`content/` tree itself is the largest example collection in the project**, with 814 runnable implementations across 11 languages.

This directory is for examples of **using vidya as a consumer**, not examples *in* vidya's corpus.

## When examples land here

- Shell scripts that wrap the CLI for common workflows (e.g. "show me every Rust example with allocation").
- Curl recipes for the `vidya serve` HTTP routes.
- Snippets demonstrating programmatic integration (a consumer reading `GET /code/{topic}/{lang}` to render syntax-highlighted source in a UI).

## Current contents

None yet — vidya's CLI is small enough that the README quick-start and [`../usage.md`](../usage.md) carry the load. Examples land here as concrete consumer-integration patterns emerge from agnoshi / hoosh / future consumers.

For examples of vidya's *content* (the 814 reference implementations), see [`../../content/`](../../content/) directly or run `vidya list`.
