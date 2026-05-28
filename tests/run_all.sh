#!/usr/bin/env bash
# tests/run_all.sh — run every tests/test_*.sh and summarize.
# Exits non-zero if any test script failed.
#
# Each test_*.sh is expected to print PASS: / FAIL: lines as it goes
# and to exit non-zero on any failure.  This runner just sequences
# them, captures their exit codes, and prints a roll-up at the end.

set -uo pipefail
cd "$(dirname "$0")"

passed=0
failed=0
failing_scripts=()

for t in test_*.sh; do
    [[ -f "$t" ]] || continue
    printf '=== %s ===\n' "$t"
    if bash "$t"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failing_scripts+=("$t")
    fi
    echo
done

printf '===========================================\n'
printf 'summary: %d test script(s) passed, %d failed\n' "$passed" "$failed"
if (( failed > 0 )); then
    echo "failing:"
    for s in "${failing_scripts[@]}"; do echo "  - $s"; done
    exit 1
fi
exit 0
