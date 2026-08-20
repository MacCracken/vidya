#!/usr/bin/env bash
# Validate all content examples compile and run correctly.
# Usage: ./scripts/validate-content.sh [content-dir]
# Skips languages whose toolchain isn't installed (counted separately).
#
# Diagnostics contract:
#   - Every test prints `  → <Lang>` BEFORE running, so if a CI step
#     truncates we can see which language was last active.
#   - On success: `  ✓ <Lang>`.
#   - On failure: `  ✗ <Lang> (exit=N)` + the combined stdout+stderr
#     captured during the run, dumped inline. Combined capture matters:
#     a program that prints to stdout then aborts loses that stdout
#     under stderr-only capture (the bug that bit content/module_systems
#     diagnosis in 2.7.1 CI).
set -euo pipefail

CONTENT_DIR="${1:-content}"
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ── Detect available toolchains ────────────────────────────────────────
has_cmd() { command -v "$1" &>/dev/null; }

HAS_ZIG=false;         has_cmd zig && HAS_ZIG=true
HAS_AARCH64_AS=false;  has_cmd aarch64-linux-gnu-as && HAS_AARCH64_AS=true
# qemu-user ships `qemu-aarch64`; qemu-user-static (what CI installs, and
# what --no-install-recommends leaves you with on noble) ships ONLY
# `qemu-aarch64-static`. Probing the unsuffixed name alone silently skipped
# all 77 AArch64 examples on every CI run — accept either, and remember which.
QEMU_AA64=""
HAS_QEMU_AA64=false
if has_cmd qemu-aarch64; then        QEMU_AA64=qemu-aarch64;        HAS_QEMU_AA64=true
elif has_cmd qemu-aarch64-static; then QEMU_AA64=qemu-aarch64-static; HAS_QEMU_AA64=true
fi
HAS_CYRIUS=false;      has_cmd cyrius && HAS_CYRIUS=true

# TypeScript type-checking. `tsx` STRIPS types and runs — it never type-checks,
# so without this the corpus was shipping TypeScript nobody had checked. Needs
# both tsc and @types/node; probed separately so a dev without them still gets
# a useful run (and VIDYA_STRICT catches the omission in CI).
HAS_TSC=false
TSC_TYPEROOTS=""
if npx -y -p typescript@latest tsc --version >/dev/null 2>&1; then
    # VIDYA_TSC_TYPEROOTS lets a caller point at an out-of-tree @types dir.
    for r in "${VIDYA_TSC_TYPEROOTS:-}" ./node_modules/@types \
             "$(npm root -g 2>/dev/null)/@types" \
             "$HOME/.npm-global/lib/node_modules/@types"; do
        [[ -n "$r" && -d "$r/node" ]] && { TSC_TYPEROOTS="$r"; break; }
    done
    [[ -n "$TSC_TYPEROOTS" ]] && HAS_TSC=true
fi

# OpenQASM: qiskit only. The former `cargo run --example test_qasm` probe was
# Rust-era debt (vidya migrated off Rust at v2.0; the example survives only in
# rust-old/) AND a latent false-green: its branch printed "✓ OpenQASM (native)"
# and incremented PASS without validating anything.
QASM_VALIDATOR=""
QASM_PYTHON="python3"
[[ -f ".venv/bin/python3" ]] && QASM_PYTHON=".venv/bin/python3"
if $QASM_PYTHON -c "import qiskit" 2>/dev/null; then
    QASM_VALIDATOR="qiskit"
fi

# Line-buffer wrapper: forces external commands to flush per-line so
# CI log streaming sees output before any abort/crash. Falls back to
# direct exec when stdbuf isn't available.
if has_cmd stdbuf; then
    LB() { stdbuf -oL -eL "$@"; }
else
    LB() { "$@"; }
fi

echo "=== Vidya Content Validation ==="
echo "  Toolchain: zig=$HAS_ZIG aarch64-as=$HAS_AARCH64_AS qemu-aarch64=$HAS_QEMU_AA64${QEMU_AA64:+ ($QEMU_AA64)} qasm=${QASM_VALIDATOR:-none} cyrius=$HAS_CYRIUS tsc=$HAS_TSC"
[[ "${VIDYA_STRICT:-0}" == "1" ]] && echo "  VIDYA_STRICT=1 — any skipped example fails the run"
echo ""

# run_lang <label> <topic-rel-file> <command...>
#   Streams the command's combined stdout+stderr live (so long-running
#   tests show progress) AND captures a copy via tee for the failure
#   dump. Combined capture matters: stdout-buffered programs that
#   abort lose their stdout under stderr-only capture.
run_lang() {
    local label="$1" rel="$2"; shift 2
    local logfile="/tmp/vidya_${$}_log"
    echo "  → $label"
    set +e
    LB "$@" 2>&1 | tee "$logfile"
    local rc=${PIPESTATUS[0]:-99}
    set -e
    if [[ "$rc" = "0" ]]; then
        echo "  ✓ $label"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $label (exit=$rc)"
        ERRORS+=("$rel (exit=$rc)")
        FAIL=$((FAIL + 1))
    fi
    rm -f "$logfile"
}

for topic_dir in "$CONTENT_DIR"/*/; do
    topic=$(basename "$topic_dir")

    # Skip directories without concept.toml
    [[ -f "$topic_dir/concept.toml" ]] || continue

    echo "--- $topic ---"

    # Rust
    if [[ -f "$topic_dir/rust.rs" ]]; then
        bin=/tmp/vidya_test_$$
        # Two passes. The plain build runs main(); the --test build is ADDITIVE
        # and only runs for files that actually carry test blocks. Without it,
        # everything behind #[cfg(test)] is never compiled at all: a deliberate
        # type error plus a false assertion inside `mod tests` still exits 0 and
        # prints "All testing examples passed". --test catches it as E0308.
        # It must be additive, not a replacement — --test discards main().
        run_lang "Rust" "$topic/rust.rs" bash -c "rustc --edition 2024 '$topic_dir/rust.rs' -o $bin && $bin && if grep -qE '#\[test\]|#\[cfg\(test\)\]' '$topic_dir/rust.rs'; then rustc --edition 2024 --test '$topic_dir/rust.rs' -o ${bin}_t && ${bin}_t --test-threads=1; fi"
        rm -f "$bin"
    fi

    # Python
    if [[ -f "$topic_dir/python.py" ]]; then
        # -X warn_default_encoding + EncodingWarning as an error: an open()
        # with no explicit encoding= is a portability bug the corpus's own
        # concept.toml warns about, and it is invisible to a plain run.
        run_lang "Python" "$topic/python.py" env PYTHONUNBUFFERED=1 python3 -X warn_default_encoding -W error::EncodingWarning "$topic_dir/python.py"
    fi

    # C
    if [[ -f "$topic_dir/c.c" ]]; then
        bin=/tmp/vidya_test_$$
        # -fno-stack-protector? No — keep -Wall -Werror semantics. Pipe through tee
        # gives us the captured output even when assert→abort drops buffered stdout.
        run_lang "C" "$topic/c.c" bash -c "gcc -std=c23 -Wall -Werror '$topic_dir/c.c' -o $bin -lm -lpthread && $bin"
        rm -f "$bin"
    fi

    # Go
    if [[ -f "$topic_dir/go.go" ]]; then
        # `go run` alone accepts code gofmt would reformat and that vet flags.
        # Seven files shipped a redundant-newline Println straight past the gate.
        run_lang "Go" "$topic/go.go" bash -c "gofmt -l '$topic_dir/go.go' | grep -q . && { echo 'gofmt: file is not formatted'; exit 1; }; go vet '$topic_dir/go.go' && go run '$topic_dir/go.go'"
    fi

    # TypeScript
    if [[ -f "$topic_dir/typescript.ts" ]]; then
        if [[ "$HAS_TSC" == "true" ]]; then
            run_lang "TypeScript" "$topic/typescript.ts" bash -c "npx -y -p typescript@latest tsc --noEmit --strict --module nodenext --moduleResolution nodenext --target es2025 --lib es2025 --typeRoots '$TSC_TYPEROOTS' --types node --skipLibCheck '$topic_dir/typescript.ts' && npx tsx '$topic_dir/typescript.ts'"
        else
            echo "  ⊘ TypeScript (skipped — tsc or @types/node not installed)"
            SKIP=$((SKIP + 1))
        fi
    fi

    # Shell
    if [[ -f "$topic_dir/shell.sh" ]]; then
        run_lang "Shell" "$topic/shell.sh" bash "$topic_dir/shell.sh"
    fi

    # OpenQASM
    if [[ -f "$topic_dir/openqasm.qasm" ]]; then
        if [[ "$QASM_VALIDATOR" == "qiskit" ]]; then
            run_lang "OpenQASM" "$topic/openqasm.qasm" \
                $QASM_PYTHON -c "from qiskit import qasm2; qc = qasm2.load('$topic_dir/openqasm.qasm', include_path=['$CONTENT_DIR'], custom_instructions=qasm2.LEGACY_CUSTOM_INSTRUCTIONS); print(f'OpenQASM OK: {qc.num_qubits}q, depth {qc.depth()}')"
        else
            echo "  ⊘ OpenQASM (skipped — no qiskit or native validator)"
            SKIP=$((SKIP + 1))
        fi
    fi

    # Zig
    if [[ -f "$topic_dir/zig.zig" ]]; then
        if [[ "$HAS_ZIG" == "true" ]]; then
            bin=/tmp/vidya_test_$$
            run_lang "Zig" "$topic/zig.zig" bash -c "zig build-exe '$topic_dir/zig.zig' -femit-bin=$bin && $bin"
            rm -f "$bin"
        else
            echo "  ⊘ Zig (skipped — zig not installed)"
            SKIP=$((SKIP + 1))
        fi
    fi

    # x86_64 Assembly
    if [[ -f "$topic_dir/asm_x86_64.s" ]]; then
        bin=/tmp/vidya_test_$$
        obj=/tmp/vidya_test_$$.o
        run_lang "x86_64 Assembly" "$topic/asm_x86_64.s" \
            bash -c "as --64 '$topic_dir/asm_x86_64.s' -o $obj && ld $obj -o $bin && $bin"
        rm -f "$bin" "$obj"
    fi

    # AArch64 Assembly
    if [[ -f "$topic_dir/asm_aarch64.s" ]]; then
        if [[ "$HAS_AARCH64_AS" == "true" && "$HAS_QEMU_AA64" == "true" ]]; then
            bin=/tmp/vidya_test_$$
            obj=/tmp/vidya_test_$$.o
            run_lang "AArch64 Assembly" "$topic/asm_aarch64.s" \
                bash -c "aarch64-linux-gnu-as '$topic_dir/asm_aarch64.s' -o $obj && aarch64-linux-gnu-ld $obj -o $bin && $QEMU_AA64 $bin"
            rm -f "$bin" "$obj"
        else
            echo "  ⊘ AArch64 Assembly (skipped — cross-tools not installed)"
            SKIP=$((SKIP + 1))
        fi
    fi

    # Cyrius
    if [[ -f "$topic_dir/cyrius.cyr" ]]; then
        if [[ "$HAS_CYRIUS" == "true" ]]; then
            # A `duplicate fn` shadow is not cosmetic: gpu_memory_pooling
            # shadowed the stdlib `alloc` and segfaulted as soon as any stdlib
            # allocation was added. Fail on it rather than printing it.
            run_lang "Cyrius" "$topic/cyrius.cyr" bash -c "out=\$(cyrius run '$topic_dir/cyrius.cyr' 2>&1); rc=\$?; printf '%s\\n' \"\$out\"; if [ \$rc -ne 0 ]; then exit \$rc; fi; if printf '%s' \"\$out\" | grep -q 'duplicate fn'; then echo 'FAIL: duplicate fn shadow (see warning above)'; exit 1; fi; exit 0"
        else
            echo "  ⊘ Cyrius (skipped — cyrius not installed)"
            SKIP=$((SKIP + 1))
        fi
    fi

    echo ""
done

echo "=== Results ==="
echo "  Passed:  $PASS"
echo "  Failed:  $FAIL"
echo "  Skipped: $SKIP"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

# A skip is a silently-unvalidated example. Locally that is fine (not every
# dev has zig + an aarch64 cross-toolchain + qiskit); in CI, where the full
# set IS installed, a skip means a probe broke and the gate is reporting green
# on work it never did. VIDYA_STRICT=1 turns that into a failure.
if [[ "${VIDYA_STRICT:-0}" == "1" && $SKIP -gt 0 ]]; then
    echo ""
    echo "VIDYA_STRICT=1 and $SKIP example(s) were skipped — a toolchain probe"
    echo "failed, so the gate did not validate everything it reports on."
    exit 1
fi

echo ""
echo "All available examples validated successfully."
