#!/usr/bin/env bash
# Validate all content examples compile and run correctly.
# Usage: ./scripts/validate-content.sh
set -euo pipefail

CONTENT_DIR="${1:-content}"
PASS=0
FAIL=0
ERRORS=()

echo "=== Vidya Content Validation ==="
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
        if gcc -std=c11 -Wall -Werror "$topic_dir/c.c" -o /tmp/vidya_test_$$ 2>/tmp/vidya_err && /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
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
        if bash -n "$topic_dir/shell.sh" 2>/tmp/vidya_err; then
            echo "  ✓ Shell (syntax check)"
            PASS=$((PASS + 1))
        else
            echo "  ✗ Shell: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/shell.sh")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_err
    fi

    # Zig
    if [[ -f "$topic_dir/zig.zig" ]]; then
        if zig build-exe "$topic_dir/zig.zig" -femit-bin=/tmp/vidya_test_$$ 2>/tmp/vidya_err && /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
            echo "  ✓ Zig"
            PASS=$((PASS + 1))
        else
            echo "  ✗ Zig: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/zig.zig")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_test_$$ /tmp/vidya_err
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
        if aarch64-linux-gnu-as "$topic_dir/asm_aarch64.s" -o /tmp/vidya_test_$$.o 2>/tmp/vidya_err && aarch64-linux-gnu-ld /tmp/vidya_test_$$.o -o /tmp/vidya_test_$$ 2>/tmp/vidya_err && qemu-aarch64 /tmp/vidya_test_$$ 2>/tmp/vidya_err; then
            echo "  ✓ AArch64 Assembly"
            PASS=$((PASS + 1))
        else
            echo "  ✗ AArch64 Assembly: $(cat /tmp/vidya_err)"
            ERRORS+=("$topic/asm_aarch64.s")
            FAIL=$((FAIL + 1))
        fi
        rm -f /tmp/vidya_test_$$ /tmp/vidya_test_$$.o /tmp/vidya_err
    fi

    echo ""
done

echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

echo ""
echo "All examples validated successfully."
