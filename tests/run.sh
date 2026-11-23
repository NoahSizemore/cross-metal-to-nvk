#!/bin/sh
# Run every test. No GPU, no CrossOver and no Steam required.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
failed=0
for t in "$ROOT"/tests/test-*.sh; do
  [ -f "$t" ] || continue
  sh "$t" || failed=$((failed + 1))
  echo
done
if [ "$failed" -eq 0 ]; then
  echo "all test files passed"
  exit 0
fi
echo "$failed test file(s) failed"
exit 1
