#!/usr/bin/env bash
# tests/test_syntax.sh — verify every script and source file in the
# repo parses cleanly.  Sub-second total.  PASS: / FAIL: lines.
# Exits non-zero on any failure.
#
# Covers:
#   bash       bin/*, tests/*.sh                        (bash -n)
#   python     code/*.py                                (ast.parse)
#   R          code/run_fit_mi.R, documents/_*.R        (parse(file=))
#   JSON       .devcontainer/devcontainer.json          (json.loads after
#                                                        stripping JSONC
#                                                        line comments)

set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; failures=$((failures + 1)); }

# ----- bash scripts -----
for f in bin/* tests/*.sh; do
    [[ -f "$f" ]] || continue
    # Only check files that are bash scripts (have shebang or are .sh).
    if [[ "$f" == *.sh ]] || head -1 "$f" 2>/dev/null | grep -q '^#!.*bash'; then
        if bash -n "$f" 2>/dev/null; then
            pass "$f"
        else
            fail "$f" "bash -n syntax error"
        fi
    fi
done

# ----- python scripts -----
for f in code/*.py; do
    [[ -f "$f" ]] || continue
    if python3 -c "import ast; ast.parse(open('$f').read())" 2>/dev/null; then
        pass "$f"
    else
        fail "$f" "python ast.parse error"
    fi
done

# ----- R source -----
for f in code/run_fit_mi.R documents/_inputs.R documents/_headlines.R; do
    [[ -f "$f" ]] || continue
    if command -v Rscript >/dev/null 2>&1; then
        if Rscript -e "invisible(parse(file = '$f'))" >/dev/null 2>&1; then
            pass "$f"
        else
            fail "$f" "R parse error"
        fi
    else
        printf '  SKIP  %s — Rscript not on PATH\n' "$f"
    fi
done

# ----- JSON (devcontainer.json uses JSONC: strip // line comments before parse) -----
for f in .devcontainer/devcontainer.json; do
    [[ -f "$f" ]] || continue
    if python3 -c "
import re, json
src = open('$f').read()
src = re.sub(r'(?m)^\s*//.*$', '', src)  # whole-line comments
src = re.sub(r'\s+//.*$', '', src, flags=re.M)  # end-of-line comments
json.loads(src)
" 2>/dev/null; then
        pass "$f"
    else
        fail "$f" "JSON parse error (after stripping line comments)"
    fi
done

echo
if (( failures == 0 )); then
    echo "All syntax checks passed."
    exit 0
fi
printf '%d syntax check(s) failed.\n' "$failures"
exit 1
