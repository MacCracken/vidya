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
