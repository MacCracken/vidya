# Strings

## What

Text representation and manipulation — the most common data type in every language, and the one with the most hidden complexity.

## Key Concepts

- **Encoding**: UTF-8 (Rust, Go), UTF-16 (JavaScript, Java), or platform-dependent (C)
- **Ownership**: Who owns the memory? Mutable or immutable? Borrowed or owned?
- **Interpolation**: Embedding values inside string literals
- **Slicing**: Extracting substrings safely (byte boundaries vs character boundaries)
- **Comparison**: Case-sensitive, case-insensitive, locale-aware

## Best Practices

1. **Know your encoding** — UTF-8 is the standard. If you're not sure, you're probably in UTF-8.
2. **Borrow when you can** — pass `&str` (Rust), `const char*` (C), `string` (Go) instead of owned strings to avoid unnecessary allocation.
3. **Never index by byte position into multi-byte strings** — "café"[4] is not 'é' in UTF-8.
4. **Pre-allocate when you know the size** — `String::with_capacity(n)`, `strings.Builder` (Go), `StringBuilder` (Java/C#).
5. **Prefer interpolation over concatenation** — more readable, often more efficient.

## Gotchas

- **Rust**: `String` is heap-allocated and owned; `&str` is a borrowed slice. You can't return `&str` from a function that creates the string.
- **Rust**: Indexing a `String` by `[n]` doesn't compile — use `.chars().nth(n)` or byte slicing with care.
- **C**: No built-in string type — `char*` is a pointer to bytes, null-terminated. Buffer overflows are your problem.
- **Go**: Strings are immutable byte slices. `range` over a string iterates runes, not bytes.
- **Python**: Strings are immutable. `+=` creates a new string every time — use `"".join()` for loops.

## Performance Notes

- **Rust**: `write!(&mut buf, ...)` avoids allocation vs `format!(...)` which always allocates a new `String`.
- **Rust**: `Cow<'_, str>` avoids cloning when you might or might not need to modify a string.
- **Go**: `strings.Builder` with `Grow(n)` pre-allocation is ~3x faster than naive concatenation.
- **Python**: `"".join(list)` is O(n), while `+=` in a loop is O(n²).
