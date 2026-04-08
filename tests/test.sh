#!/bin/sh
CC="${1:-./build/cc2}"
echo "=== vidya tests ==="
cat src/main.cyr | "$CC" > /tmp/vidya_test && chmod +x /tmp/vidya_test && /tmp/vidya_test
echo "exit: $?"
rm -f /tmp/vidya_test
