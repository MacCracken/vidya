# Contributing to Vidya

## Development

1. Install Cyrius toolchain (`cyrius`)
2. Clone the repo
3. Build: `cyrius build src/main.cyr build/vidya`
4. Test: `cyrius test`
5. Bench: `cyrius bench`

## Adding a Topic

1. Create `content/{topic}/concept.toml` with required fields: `id`, `title`, `topic`, `description`, `tags`, `related_topics`
2. Add at least `[[best_practices]]`, `[[gotchas]]`, `[[performance_notes]]` sections
3. Add language implementations (all 11 required for completion):
   - `rust.rs`, `python.py`, `c.c`, `go.go`, `typescript.ts`, `shell.sh`, `zig.zig`
   - `asm_x86_64.s`, `asm_aarch64.s`, `openqasm.qasm`, `cyrius.cyr`
4. Every implementation must compile and run successfully
5. Run `./build/vidya gaps` to verify zero missing implementations

## Adding a Language Implementation

1. Follow the naming convention: `{lang_stem}.{extension}` (e.g. `rust.rs`, `cyrius.cyr`)
2. Start with a comment header: `// Vidya — {Topic} in {Language}`
3. Explain the concept in leading comments
4. Include working, testable code
5. Exit successfully (exit code 0)

## Content Standards

- Every code example MUST compile/run successfully
- Gotchas MUST include both bad and good examples
- Performance notes SHOULD include evidence (benchmark numbers or complexity)
- Best practices explain WHY, not just WHAT
- Cyrius implementations are pattern-focused — document real AGNOS/Cyrius patterns, don't reimplement

## Code Quality

```sh
cyrius check src/main.cyr    # syntax check
cyrius vet src/main.cyr       # audit includes
cyrius fmt src/main.cyr       # format
cyrius lint src/main.cyr      # static analysis
```

## Do Not

- Do not add unnecessary dependencies
- Do not write examples that don't compile/run
- Do not claim performance improvements without evidence
- Do not write gotchas without both bad and good examples
