#!/bin/bash
# Counts a run of apps/cli-ulh/tests/run.sh and decides red or green.
#
# Why a counter and not the exit code: the driver ends on (( FAILED == 0 )), so
# a run in which NOTHING ran - no case found, the copy step broken, the loop
# never entered - prints "passed: 0  failed: 0" and exits 0. The exit code
# answers "did anything fall", never "did anything run".
#
# NGC_ULH_FLOOR is the smallest number of PASSED cases a real run has. Skips do
# not exist in this driver, so passed is the whole measure. The number is a
# measured one: it comes from a run of this file, and that run is named in the
# workflow beside it.
set -u

log="${1:-}"
if [ -z "$log" ] || [ ! -f "$log" ]; then
    echo "ci-count: no log named" >&2
    exit 2
fi

# The LAST summary line, not the first: sourcing a test file could print one of
# its own, and the driver's own line is the last thing it writes.
line="$(grep -E '^passed: [0-9]+ +failed: [0-9]+$' "$log" | tail -1)"
if [ -z "$line" ]; then
    # No summary at all means the driver died before the end - a crash, a
    # refused copy, a missing bash. That is red, and it is the one case where
    # saying nothing would look like saying "fine".
    echo "ci-count: the driver wrote no summary - it did not reach its end" >&2
    tail -5 "$log" >&2
    exit 1
fi

passed="$(sed -E 's/^passed: ([0-9]+).*/\1/' <<< "$line")"
failed="$(sed -E 's/.*failed: ([0-9]+)$/\1/' <<< "$line")"
total=$((passed + failed))
echo "${passed} bestanden, ${failed} rot, ${total} Faelle"

if [ "$failed" -gt 0 ]; then
    echo ""
    echo "ROT - was der Fall selbst sagt:"
    grep -E '^  FAIL ' "$log" | sed 's/^  FAIL  /  /'
fi

floor="${NGC_ULH_FLOOR:-0}"
if [ "$passed" -eq 0 ]; then
    echo "" >&2
    echo "ci-count: kein einziger Fall ist bestanden - der Lauf hat nicht stattgefunden." >&2
    exit 1
fi
if [ "$passed" -lt "$floor" ]; then
    echo "" >&2
    echo "ci-count: nur ${passed} bestandene Faelle, erwartet mindestens ${floor} - der Lauf hat nicht stattgefunden." >&2
    exit 1
fi
if [ "$failed" -gt 0 ]; then
    echo ""
    echo "ci-count: rot"
    exit 1
fi
echo ""
echo "ci-count: gruen"
