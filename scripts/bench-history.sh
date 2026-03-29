#!/usr/bin/env bash
# Run benchmarks and record results with git context.
# Usage: ./scripts/bench-history.sh
set -euo pipefail

BENCH_DIR="target/bench-history"
mkdir -p "$BENCH_DIR"

TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_DESC=$(git describe --tags --always --dirty 2>/dev/null || echo "$GIT_SHA")
OUTFILE="$BENCH_DIR/${TIMESTAMP}-${GIT_SHA}.txt"

echo "=== Vidya Benchmark Run ==="
echo "  Date:   $(date -u)"
echo "  Commit: $GIT_DESC"
echo "  Output: $OUTFILE"
echo ""

# Run benchmarks and tee to file
cargo bench 2>&1 | tee "$OUTFILE"

echo ""
echo "Results saved to $OUTFILE"
echo ""

# Show comparison with previous run if available
PREV=$(ls -t "$BENCH_DIR"/*.txt 2>/dev/null | head -2 | tail -1)
if [[ -n "$PREV" && "$PREV" != "$OUTFILE" ]]; then
    echo "Previous run: $PREV"
    echo "Compare manually with: diff $PREV $OUTFILE"
fi
