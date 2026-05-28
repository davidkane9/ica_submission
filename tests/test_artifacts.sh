#!/usr/bin/env bash
# tests/test_artifacts.sh — verify the canonical artifacts in
# submitted/ and replicated/ are present in the expected count and
# byte-identical between the two trees at HEAD.  Sub-second total.
# PASS: / FAIL: lines.  Exits non-zero on any failure.
#
# Covers:
#   counts          24 data CSVs, 50 imp_*.rds + meta.rds, 3 sat_model.*
#   HEAD-blob sync  every tracked file under submitted/ has the same
#                   blob hash as its counterpart under replicated/
#                   (git's content-addressable storage means equal hash
#                   ⟺ byte-identical content)

set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; failures=$((failures + 1)); }

EXPECT_DATA_CSVS=24
EXPECT_SIM_IMPS=50
EXPECT_DOCS=3

count_files() { find "$1" -type f -name "$2" 2>/dev/null | wc -l | tr -d ' '; }

# ----- counts -----
for tree in submitted replicated; do
    n=$(count_files "$tree/data" '*.csv')
    if [[ "$n" -eq "$EXPECT_DATA_CSVS" ]]; then
        pass "$tree/data: $n CSVs"
    else
        fail "$tree/data" "expected $EXPECT_DATA_CSVS CSVs, got $n"
    fi

    n=$(count_files "$tree/sims/mi" 'imp_*.rds')
    if [[ "$n" -eq "$EXPECT_SIM_IMPS" ]]; then
        pass "$tree/sims/mi: $n imp_*.rds"
    else
        fail "$tree/sims/mi" "expected $EXPECT_SIM_IMPS imp_*.rds, got $n"
    fi

    if [[ -f "$tree/sims/mi/meta.rds" ]]; then
        pass "$tree/sims/mi/meta.rds present"
    else
        fail "$tree/sims/mi/meta.rds" "missing"
    fi

    n=$(ls "$tree"/docs/sat_model.docx "$tree"/docs/sat_model.html \
            "$tree"/docs/sat_model.pdf 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$n" -eq "$EXPECT_DOCS" ]]; then
        pass "$tree/docs: 3 sat_model.{docx,html,pdf}"
    else
        fail "$tree/docs" "expected $EXPECT_DOCS sat_model.{docx,html,pdf}, got $n"
    fi
done

# ----- HEAD-blob sync between submitted/ and replicated/ -----
# Walks every tracked file under submitted/; for each, looks up the
# blob hash at HEAD and compares against the corresponding replicated/
# path.  git's content-addressable storage guarantees: same hash ⟺
# same byte content.
echo
echo "  HEAD-blob sync (submitted/ vs replicated/):"
mismatches=0
n_compared=0
while IFS= read -r s; do
    rel="${s#submitted/}"
    r="replicated/$rel"
    sh=$(git ls-tree HEAD "$s" 2>/dev/null | awk '{print $3}')
    rh=$(git ls-tree HEAD "$r" 2>/dev/null | awk '{print $3}')
    if [[ -z "$rh" ]]; then
        # File tracked in submitted but not replicated.  Not necessarily
        # an error (submitted has a top-level README.md, for example),
        # but worth flagging if it's under data/sims/docs.
        if [[ "$rel" == data/* || "$rel" == sims/* || "$rel" == docs/* ]]; then
            mismatches=$((mismatches + 1))
            echo "    not-in-replicated: $rel"
        fi
        continue
    fi
    n_compared=$((n_compared + 1))
    if [[ "$sh" != "$rh" ]]; then
        mismatches=$((mismatches + 1))
        echo "    DRIFT: $rel"
    fi
done < <(git ls-files submitted/)

if (( mismatches == 0 )); then
    pass "submitted/ ↔ replicated/ — $n_compared tracked files byte-identical at HEAD"
else
    fail "submitted/ ↔ replicated/" "$mismatches divergence(s) (see lines above)"
fi

echo
if (( failures == 0 )); then
    echo "All artifact checks passed."
    exit 0
fi
printf '%d artifact check(s) failed.\n' "$failures"
exit 1
