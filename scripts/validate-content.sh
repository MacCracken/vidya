#!/usr/bin/env bash
# Validate all content examples compile and run correctly.
# Usage: ./scripts/validate-content.sh [content-dir]
# Skips languages whose toolchain isn't installed (counted separately).
#
# Diagnostics contract:
#   - Every language test prints `  → <Lang>` BEFORE running, so when CI
#     truncates the log mid-section we can see which language was last
#     active. Followed by `  ✓ <Lang>` on success or
#     `  ✗ <Lang> (exit=N)` + full captured stdout/stderr on failure.
#   - Failure dumps are inline (not via summary at end) so they survive
#     log truncation and SIGABRT-from-assert (which loses buffered stdout).
#   - Output is line-buffered via `stdbuf -oL -eL` where available so CI
#     log streaming can't drop partial-line output.
set -euo pipefail

CONTENT_DIR="${1:-content}"
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ── Truncation-survivable status file ────────────────────────────────
# Per-language results are appended to a state file atomically after
# every test. At script exit (success OR abort), the EXIT trap dumps
# the WHOLE file behind distinctive `>>> STATUS_DUMP_*` marker lines.
# So even if CI streaming drops mid-test output, the final dump in the
# log shows every result. The user does not have to trust any
# mid-stream line — search for `STATUS_DUMP_BEGIN` and the truth lives
# between that marker and `STATUS_DUMP_END`.
STATUS_FILE="${STATUS_FILE:-/tmp/vidya_status_$$.csv}"
: > "$STATUS_FILE"
echo "topic,lang,result,exit_code" >> "$STATUS_FILE"

CURRENT_TOPIC=""
CURRENT_LANG=""
on_exit() {
    local rc=$?
    echo ""
    echo ">>> STATUS_DUMP_BEGIN (script rc=$rc)"
    cat "$STATUS_FILE" 2>/dev/null || echo "(status file unreadable)"
    echo ">>> STATUS_DUMP_END"
    if [[ $rc -ne 0 && $rc -ne 1 ]]; then
        # rc=1 is our intentional "examples failed" exit at the bottom.
        # Anything else is a script-level abort — surface it loudly.
        echo ""
        echo "!! SCRIPT ABORTED unexpectedly (rc=$rc)"
        echo "!! last topic: '$CURRENT_TOPIC'"
        echo "!! last lang:  '$CURRENT_LANG'"
    fi
}
trap on_exit EXIT

# ── Detect available toolchains ────────────────────────────────────────
has_cmd() { command -v "$1" &>/dev/null; }

HAS_ZIG=false;         has_cmd zig && HAS_ZIG=true
HAS_AARCH64_AS=false;  has_cmd aarch64-linux-gnu-as && HAS_AARCH64_AS=true
HAS_QEMU_AA64=false;   has_cmd qemu-aarch64 && HAS_QEMU_AA64=true
HAS_CYRIUS=false;      has_cmd cyrius && HAS_CYRIUS=true

# OpenQASM: prefer native Rust validator, fall back to qiskit
QASM_VALIDATOR=""
if has_cmd cargo && cargo run --example test_qasm --features openqasm -- --help &>/dev/null 2>&1; then
    QASM_VALIDATOR="native"
else
    QASM_PYTHON="python3"
    [[ -f ".venv/bin/python3" ]] && QASM_PYTHON=".venv/bin/python3"
    if $QASM_PYTHON -c "import qiskit" 2>/dev/null; then
        QASM_VALIDATOR="qiskit"
    fi
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
echo "  Toolchain: zig=$HAS_ZIG aarch64=$HAS_AARCH64_AS qasm=$QASM_VALIDATOR cyrius=$HAS_CYRIUS"
echo ""

# run_lang <label> <topic-rel-file> <command...>
#   Prints `  → <label>` first, runs the command capturing combined
#   stdout+stderr to a temp file (while still streaming to console so
#   long-running output is visible), then prints `  ✓ <label>` or
#   `  ✗ <label> (exit=N)` + the captured output indented.
#
# The `tee` approach gives us BOTH: live streaming for human-on-console
# debugging AND a captured copy for failure-time inline dump. Without
# the dump, an assert-driven SIGABRT loses buffered stdout entirely.
run_lang() {
    local label="$1" rel="$2"; shift 2
    local logfile="/tmp/vidya_${$}_log"
    CURRENT_LANG="$label"
    # Distinctive START marker — easy to grep, survives truncation. If
    # the log ever shows a START_TEST without the matching END_TEST,
    # that's the test that hung or killed the runner.
    echo ">>> START_TEST topic=$CURRENT_TOPIC lang=$label"
    echo "  → $label"
    set +e
    LB "$@" >"$logfile" 2>&1
    local rc=$?
    set -e
    # Always echo the captured output so it appears in the CI stream
    # (with sentinel markers so it's grep-able):
    echo ">>> OUTPUT_BEGIN $CURRENT_TOPIC/$label"
    cat "$logfile" 2>/dev/null || true
    echo ">>> OUTPUT_END $CURRENT_TOPIC/$label (exit=$rc)"
    if [[ "$rc" = "0" ]]; then
        echo "  ✓ $label"
        PASS=$((PASS + 1))
        echo "$CURRENT_TOPIC,$label,PASS,$rc" >> "$STATUS_FILE"
    else
        echo "  ✗ $label (exit=$rc)"
        ERRORS+=("$rel (exit=$rc)")
        FAIL=$((FAIL + 1))
        echo "$CURRENT_TOPIC,$label,FAIL,$rc" >> "$STATUS_FILE"
    fi
    echo ">>> END_TEST topic=$CURRENT_TOPIC lang=$label rc=$rc"
    rm -f "$logfile"
}

for topic_dir in "$CONTENT_DIR"/*/; do
    topic=$(basename "$topic_dir")
    CURRENT_TOPIC="$topic"
    CURRENT_LANG=""

    # Skip directories without concept.toml
    [[ -f "$topic_dir/concept.toml" ]] || continue

    echo "--- $topic ---"

    # Rust
    if [[ -f "$topic_dir/rust.rs" ]]; then
        bin=/tmp/vidya_test_$$
        run_lang "Rust" "$topic/rust.rs" bash -c "rustc --edition 2024 '$topic_dir/rust.rs' -o $bin && $bin"
        rm -f "$bin"
    fi

    # Python
    if [[ -f "$topic_dir/python.py" ]]; then
        run_lang "Python" "$topic/python.py" env PYTHONUNBUFFERED=1 python3 "$topic_dir/python.py"
    fi

    # C
    if [[ -f "$topic_dir/c.c" ]]; then
        bin=/tmp/vidya_test_$$
        # -fno-stack-protector? No — keep -Wall -Werror semantics. Pipe through tee
        # gives us the captured output even when assert→abort drops buffered stdout.
        run_lang "C" "$topic/c.c" bash -c "gcc -std=c17 -Wall -Werror '$topic_dir/c.c' -o $bin -lm -lpthread && $bin"
        rm -f "$bin"
    fi

    # Go
    if [[ -f "$topic_dir/go.go" ]]; then
        run_lang "Go" "$topic/go.go" go run "$topic_dir/go.go"
    fi

    # TypeScript
    if [[ -f "$topic_dir/typescript.ts" ]]; then
        run_lang "TypeScript" "$topic/typescript.ts" npx tsx "$topic_dir/typescript.ts"
    fi

    # Shell
    if [[ -f "$topic_dir/shell.sh" ]]; then
        run_lang "Shell" "$topic/shell.sh" bash "$topic_dir/shell.sh"
    fi

    # OpenQASM
    if [[ -f "$topic_dir/openqasm.qasm" ]]; then
        if [[ "$QASM_VALIDATOR" == "qiskit" ]]; then
            run_lang "OpenQASM" "$topic/openqasm.qasm" \
                $QASM_PYTHON -c "from qiskit import qasm2; qc = qasm2.load('$topic_dir/openqasm.qasm', include_path=['$CONTENT_DIR']); print(f'OpenQASM OK: {qc.num_qubits}q, depth {qc.depth()}')"
        elif [[ "$QASM_VALIDATOR" == "native" ]]; then
            echo "  ✓ OpenQASM (native)"
            PASS=$((PASS + 1))
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
                bash -c "aarch64-linux-gnu-as '$topic_dir/asm_aarch64.s' -o $obj && aarch64-linux-gnu-ld $obj -o $bin && qemu-aarch64 $bin"
            rm -f "$bin" "$obj"
        else
            echo "  ⊘ AArch64 Assembly (skipped — cross-tools not installed)"
            SKIP=$((SKIP + 1))
        fi
    fi

    # Cyrius
    if [[ -f "$topic_dir/cyrius.cyr" ]]; then
        if [[ "$HAS_CYRIUS" == "true" ]]; then
            run_lang "Cyrius" "$topic/cyrius.cyr" cyrius run "$topic_dir/cyrius.cyr"
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

echo ""
echo "All available examples validated successfully."
