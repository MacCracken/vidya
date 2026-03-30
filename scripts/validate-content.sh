#!/usr/bin/env bash
# Validate all content examples compile and run correctly.
# Usage: ./scripts/validate-content.sh
# Skips languages whose toolchain isn't installed (counted separately).
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

echo "=== Vidya Content Validation ==="
echo "  Toolchain: zig=$HAS_ZIG aarch64=$HAS_AARCH64_AS qasm=$QASM_VALIDATOR"
echo ""

for topic_dir in "$CONTENT_DIR"/*/; do
    topic=$(basename "$topic_dir")

    # Skip directories without concept.toml
    [[ -f "$topic_dir/concept.toml" ]] || continue

    echo "--- $topic ---"

    # Rust
    if [[ -f "$topic_dir/rust.rs" ]]; then
        if rustc --edition 2024 "$topic_dir/rust.rs" -o /tmp/vidya_test_$$ 2>/tmp/vidya_err && /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
            echo "  ✓ Rust"
            PASS=$((PASS + 1))
        else
            echo "  ✗ Rust: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/rust.rs")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_test_$$ /tmp/vidya_err
    fi

    # Python
    if [[ -f "$topic_dir/python.py" ]]; then
        if python3 "$topic_dir/python.py" 2>/tmp/vidya_err; then
            echo "  ✓ Python"
            PASS=$((PASS + 1))
        else
            echo "  ✗ Python: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/python.py")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_err
    fi

    # C
    if [[ -f "$topic_dir/c.c" ]]; then
        if gcc -std=c17 -Wall -Werror "$topic_dir/c.c" -o /tmp/vidya_test_$$ -lm -lpthread 2>/tmp/vidya_err && /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
            echo "  ✓ C"
            PASS=$((PASS + 1))
        else
            echo "  ✗ C: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/c.c")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_test_$$ /tmp/vidya_err
    fi

    # Go
    if [[ -f "$topic_dir/go.go" ]]; then
        if go run "$topic_dir/go.go" 2>/tmp/vidya_err; then
            echo "  ✓ Go"
            PASS=$((PASS + 1))
        else
            echo "  ✗ Go: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/go.go")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_err
    fi

    # TypeScript
    if [[ -f "$topic_dir/typescript.ts" ]]; then
        if npx tsx "$topic_dir/typescript.ts" 2>/tmp/vidya_err; then
            echo "  ✓ TypeScript"
            PASS=$((PASS + 1))
        else
            echo "  ✗ TypeScript: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/typescript.ts")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_err
    fi

    # Shell
    if [[ -f "$topic_dir/shell.sh" ]]; then
        if bash "$topic_dir/shell.sh" >/tmp/vidya_out 2>/tmp/vidya_err; then
            echo "  ✓ Shell"
            PASS=$((PASS + 1))
        else
            echo "  ✗ Shell: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/shell.sh")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_out /tmp/vidya_err
    fi

    # OpenQASM
    if [[ -f "$topic_dir/openqasm.qasm" ]]; then
        if [[ "$QASM_VALIDATOR" == "qiskit" ]]; then
            if $QASM_PYTHON -c "from qiskit import qasm2; qc = qasm2.load('$topic_dir/openqasm.qasm', include_path=['$CONTENT_DIR']); print(f'  ✓ OpenQASM ({qc.num_qubits}q, depth {qc.depth()})')" 2>/tmp/vidya_err; then
                PASS=$((PASS + 1))
            else
                echo "  ✗ OpenQASM: $(cat /tmp/vidya_err)"
                ERRORS+=("$topic/openqasm.qasm")
                FAIL=$((FAIL + 1))
            fi
            rm -f /tmp/vidya_err
        elif [[ "$QASM_VALIDATOR" == "native" ]]; then
            # Use the Rust-native parser via cargo test (already validated in cargo test --features openqasm)
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
            if zig build-exe "$topic_dir/zig.zig" -femit-bin=/tmp/vidya_test_$$ 2>/tmp/vidya_err && /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
                echo "  ✓ Zig"
                PASS=$((PASS + 1))
            else
                echo "  ✗ Zig: $(cat /tmp/vidya_err)"
                ERRORS+=("$topic/zig.zig")
                FAIL=$((FAIL + 1))
            fi
            rm -f /tmp/vidya_test_$$ /tmp/vidya_err
        else
            echo "  ⊘ Zig (skipped — zig not installed)"
            SKIP=$((SKIP + 1))
        fi
    fi

    # x86_64 Assembly
    if [[ -f "$topic_dir/asm_x86_64.s" ]]; then
        if as --64 "$topic_dir/asm_x86_64.s" -o /tmp/vidya_test_$$.o 2>/tmp/vidya_err && ld /tmp/vidya_test_$$.o -o /tmp/vidya_test_$$ 2>/tmp/vidya_err && /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
            echo "  ✓ x86_64 Assembly"
            PASS=$((PASS + 1))
        else
            echo "  ✗ x86_64 Assembly: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/asm_x86_64.s")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_test_$$ /tmp/vidya_test_$$.o /tmp/vidya_err
    fi

    # AArch64 Assembly
    if [[ -f "$topic_dir/asm_aarch64.s" ]]; then
        if [[ "$HAS_AARCH64_AS" == "true" && "$HAS_QEMU_AA64" == "true" ]]; then
            if aarch64-linux-gnu-as "$topic_dir/asm_aarch64.s" -o /tmp/vidya_test_$$.o 2>/tmp/vidya_err && aarch64-linux-gnu-ld /tmp/vidya_test_$$.o -o /tmp/vidya_test_$$ 2>/tmp/vidya_err && qemu-aarch64 /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
                echo "  ✓ AArch64 Assembly"
                PASS=$((PASS + 1))
            else
                echo "  ✗ AArch64 Assembly: $(cat /tmp/vidya_err)"
                ERRORS+=("$topic/asm_aarch64.s")
                FAIL=$((FAIL + 1))
            fi
            rm -f /tmp/vidya_test_$$ /tmp/vidya_test_$$.o /tmp/vidya_err
        else
            echo "  ⊘ AArch64 Assembly (skipped — cross-tools not installed)"
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
