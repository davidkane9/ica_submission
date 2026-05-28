# /// script
# requires-python = ">=3.11"
# ///
"""Extract the College Board SAT *User Percentile* column from the
"Understanding SAT Scores" reference documents under
downloads/sat/understanding/.

Each file in that directory carries a User Percentile table for a
specific pooled-cohort window (single year for the earliest report,
three graduating classes pooled for the later releases). The College
Board moved the same reference from a PDF document
(2017-2021 release cycle) to a stand-alone web page (2023 onward); both
formats are handled here.

Output: one CSV per pooled-cohort window at
replicated/data/percentiles/user_group_<window>.csv, with two columns:

    score,user_pct

where `score` runs in 10-point steps from 400 to 1600 and `user_pct` is
the published User Percentile (percentage of test-takers in the pooled
cohort with a total score at or below `score`). Censored values printed
as "1-" in the source are written as 0.  The College Board reports the
very-top scores as "99+", meaning *at least* 99.5%.  We preserve that
distinction by writing 99.5 in the CSV: a row with user_pct = 99 means
"reported as 99" (true value in [98.5, 99.5)), a row with
user_pct = 99.5 means "reported as 99+" (true value in [99.5, 100]).
Readers should treat any half-integer value (X.5) as a one-sided lower
bound at that value.
"""

from __future__ import annotations

import html as ihtml
import re
import sys
from pathlib import Path

ROOT       = Path(__file__).resolve().parent.parent
SRC_DIR    = ROOT / "downloads" / "sat" / "understanding"
OUT_DIR    = ROOT / "replicated" / "data" / "percentiles"


def _parse_pct(s: str) -> float | None:
    s = ihtml.unescape(s).strip()
    plus = False
    if s.endswith("+"):
        s = s[:-1]
        plus = True
    if s.endswith("-"):
        return 0.0           # "1-" means "<1%"; we report it as 0
    if s in ("&nbsp;", ""):
        return None
    try:
        k = int(s)
    except ValueError:
        return None
    # "99+" means "at least 99.5%": encode as 99.5 so downstream readers
    # can distinguish a one-sided lower bound from a rounded integer.
    return k + 0.5 if plus else float(k)


def parse_pdf(pdf_path: Path) -> dict[int, float]:
    """Parse the User Percentile column from an Understanding-Scores PDF
    (via pdftotext -layout). The "Percentiles for Total Scores" table is
    laid out as three side-by-side score columns; each text line has up
    to three (score, NatRep, User) triples."""
    import subprocess
    txt = subprocess.check_output(
        ["pdftotext", "-layout", str(pdf_path), "-"], text=True
    )
    start = txt.find("Percentiles for Total Scores")
    if start < 0:
        start = 0
    end = txt.find("Percentiles for Section Scores", start + 1)
    if end < 0:
        end = start + 10_000
    chunk = txt[start:end]

    triple = re.compile(r"(\d{3,4})\s+(\d{2,3}\+?|\d-?)\s+(\d{2,3}\+?|\d-?)")
    scores: dict[int, float] = {}
    for line in chunk.splitlines():
        for m in triple.finditer(line):
            sc = int(m.group(1))
            if 400 <= sc <= 1600 and sc % 10 == 0:
                u = _parse_pct(m.group(3))
                if u is not None:
                    scores[sc] = u
    return scores


def parse_html(html_path: Path) -> dict[int, float]:
    """Parse the User Group Percentiles column from the College Board
    Understanding-Scores web page (the table is identified by
    summary="Percentiles for Total Scores"). Each row has shape
    <th>SCORE</th><td>NAT_REP</td><td>USER</td>."""
    src = html_path.read_text(encoding="utf-8", errors="replace")
    m = re.search(
        r'<table[^>]*summary="Percentiles for Total Scores"[^>]*>(.*?)</table>',
        src, re.DOTALL)
    if not m:
        raise ValueError(f"Total Scores table not found in {html_path}")
    rows = re.findall(
        r'<tr[^>]*>\s*<th[^>]*>\s*(\d+)\s*</th>\s*<td[^>]*>([^<]*)</td>\s*<td[^>]*>([^<]*)</td>',
        m.group(1), re.DOTALL)
    scores: dict[int, float] = {}
    for sc_s, _nat, user in rows:
        sc = int(sc_s)
        u = _parse_pct(user)
        if u is not None:
            scores[sc] = u
    return scores


def window_label(src_name: str) -> str:
    """Pull the cohort-window label (e.g. '2017-2019', '2023-2025', '2017')
    out of a source filename like 'understanding_2017-2019.pdf' or
    'user_group_2023-2025.html'."""
    stem = Path(src_name).stem
    for prefix in ("understanding_", "user_group_"):
        if stem.startswith(prefix):
            return stem[len(prefix):]
    return stem


def write_csv(out_path: Path, scores: dict[int, float]) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w") as f:
        f.write("score,user_pct\n")
        for sc in sorted(scores):
            v = scores[sc]
            # Integer values render without a decimal point; half-integer
            # ("99+" -> 99.5) renders as a float so downstream readers can
            # distinguish a rounded integer from a one-sided lower bound.
            s = f"{int(v)}" if v == int(v) else f"{v}"
            f.write(f"{sc},{s}\n")


def main() -> None:
    if not SRC_DIR.exists():
        sys.exit(f"missing source dir: {SRC_DIR}")
    for src in sorted(SRC_DIR.iterdir()):
        if src.suffix == ".pdf":
            scores = parse_pdf(src)
        elif src.suffix == ".html":
            scores = parse_html(src)
        else:
            continue
        label = window_label(src.name)
        out = OUT_DIR / f"user_group_{label}.csv"
        write_csv(out, scores)
        print(f"{src.name}  ->  {out.relative_to(ROOT)}  ({len(scores)} rows)")


if __name__ == "__main__":
    main()
