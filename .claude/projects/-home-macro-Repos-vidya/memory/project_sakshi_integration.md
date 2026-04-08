---
name: Sakshi integration blocked
description: Sakshi tracing/error lib stubs in src/main.cyr — swap for real includes when compiler or sakshi packaging fixes land
type: project
---

Sakshi (../sakshi/) provides tracing, structured errors, and spans for Cyrius. Vidya has stub functions in src/main.cyr matching the sakshi API (sakshi_error, sakshi_warn, sakshi_info, sakshi_debug, sakshi_trace, sakshi_span_enter, sakshi_span_exit).

**Blocked by**: Including sakshi's format.cyr + output.cyr + trace.cyr + span.cyr causes argv corruption — likely global variable count overflow in cc2 when combined with vidya's 12 stdlib includes (string, fmt, alloc, vec, str, io, fs, args, hashmap, toml, regex, syscalls). The ring buffer (`var _sk_ring_buf[4096]` = 32KB BSS) and span stack (`var _sk_span_stack[384]`) compound the issue.

**Fix path (either one)**:
1. Compiler: bump global variable limit beyond 4096 or fix BSS allocation overlap
2. Sakshi: ship a vendorable single-file `lib/sakshi.cyr` (stderr-only profile, no ring buffer/UDP)

**How to apply**: In src/main.cyr, replace the stub block (comment says "Sakshi — stubbed for now") with `include "lib/sakshi.cyr"` and delete the stub functions.
