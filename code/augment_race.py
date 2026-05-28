# /// script
# requires-python = ">=3.11"
# ///
"""bin/augment_race — turn the PDF-extracted wide race files in
replicated/data/race/raw/ into the long-format files that the model
and the manuscript consume:

    replicated/data/race/raw/<year>.csv         (input,  wide)
    replicated/data/race/raw/cohort_bands.csv   (input,  long, cross-year)
    replicated/data/race/augmented/<year>.csv   (output, long)

The augmented file is a strict superset of the raw file:

  * The seven named-race summary rows (race, N, mean), unchanged.
  * The No Response and Total summary rows, unchanged.
  * The 7 × 6 named-race × band rows, percentages unchanged.
  * The 6 cohort × band rows (race="Total"), counts copied from
    cohort_bands.csv.
  * The 6 No Response × band rows, **derived by subtraction** from the
    seven named-race counts and the cohort totals.

The No Response derivation is the only non-trivial part:

    NR_count[band] = cohort_count[band] − Σ_named  round(N_race × pct[race,band] / 100)
    NR_pct[band]   = round(100 × max(NR_count[band], 0) / N_no_response, 1)

The College Board does not print a per-band breakdown for the
"No Response" row.  This derivation reconstructs the missing row from
the seven named rows' implied counts and the published cohort totals.

The result is reported with one decimal so the small-percent rows
(e.g. 1400-1600 ≈ 12.7%) don't collapse to zero at integer precision.

Run:
    python3 code/augment_race.py
"""

from __future__ import annotations

import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "replicated" / "data" / "race" / "raw"
AUG_DIR = ROOT / "replicated" / "data" / "race" / "augmented"

BAND_ORDER = ["400-590", "600-790", "800-990",
              "1000-1190", "1200-1390", "1400-1600"]
BAND_COL   = {b: f"b_{b.replace('-', '_')}" for b in BAND_ORDER}

NAMED_RACES = [
    "American Indian/Alaska Native",
    "Asian",
    "Black/African American",
    "Hispanic/Latino",
    "Native Hawaiian/Other Pacific Islander",
    "White",
    "Two or More Races",
]
# Group write order for the long output: 7 named, then No Response,
# then Total.  Used for the "summary" block (race, "all", N, "", mean).
WRITE_ORDER = NAMED_RACES + ["No Response", "Total"]


def read_raw(year: int) -> dict[str, dict]:
    """Return {race: {"N": int, "mean": int, "pcts": {band: int}}} for
    one year, read from raw/<year>.csv."""
    out: dict[str, dict] = {}
    with (RAW_DIR / f"{year}.csv").open() as f:
        for row in csv.DictReader(f):
            entry = {"N": int(row["N"]), "mean": int(row["mean"]), "pcts": {}}
            for band in BAND_ORDER:
                v = row[BAND_COL[band]]
                if v != "":
                    entry["pcts"][band] = int(v)
            out[row["race"]] = entry
    return out


def read_cohort_bands() -> dict[int, dict[str, int]]:
    """Return {year: {band: count}} from cohort_bands.csv."""
    out: dict[int, dict[str, int]] = {}
    with (RAW_DIR / "cohort_bands.csv").open() as f:
        for row in csv.DictReader(f):
            out.setdefault(int(row["year"]), {})[row["band"]] = int(row["count"])
    return out


def derive_nr_pcts(raw: dict[str, dict],
                   cohort_bands: dict[str, int]) -> dict[str, float]:
    """Back out No Response band percentages by subtraction.  See module
    docstring for the formula."""
    if "No Response" not in raw or not cohort_bands:
        return {}
    n_nr = raw["No Response"]["N"]
    nr_pcts: dict[str, float] = {}
    for band in BAND_ORDER:
        if band not in cohort_bands:
            continue
        seven_sum = 0
        for race in NAMED_RACES:
            if race not in raw or band not in raw[race]["pcts"]:
                continue
            seven_sum += round(raw[race]["N"] * raw[race]["pcts"][band] / 100)
        nr_count = max(cohort_bands[band] - seven_sum, 0)
        nr_pcts[band] = round(100 * nr_count / n_nr, 1) if n_nr > 0 else 0.0
    return nr_pcts


def write_augmented(year: int,
                    raw: dict[str, dict],
                    cohort_bands: dict[str, int],
                    nr_pcts: dict[str, float]) -> Path:
    """Long-format file: summary rows (race, "all", N, "", mean), then
    named-race × band percentages, then cohort × band counts, then
    derived NR × band percentages."""
    out = AUG_DIR / f"{year}.csv"
    AUG_DIR.mkdir(parents=True, exist_ok=True)
    fields = ["year", "race", "score_range", "test_takers", "percent", "mean_total"]
    rows = []
    # Block 1: per-group summary rows.
    for race in WRITE_ORDER:
        if race not in raw:
            continue
        rows.append({"year": year, "race": race, "score_range": "all",
                     "test_takers": raw[race]["N"], "percent": "",
                     "mean_total": raw[race]["mean"]})
    # Block 2: named-race band percentages (race-major, band-ascending).
    for race in NAMED_RACES:
        if race not in raw:
            continue
        for band in BAND_ORDER:
            if band in raw[race]["pcts"]:
                rows.append({"year": year, "race": race, "score_range": band,
                             "test_takers": "", "percent": raw[race]["pcts"][band],
                             "mean_total": ""})
    # Block 3: cohort band counts (race="Total", band-ascending).
    for band in BAND_ORDER:
        if band in cohort_bands:
            rows.append({"year": year, "race": "Total", "score_range": band,
                         "test_takers": cohort_bands[band], "percent": "",
                         "mean_total": ""})
    # Block 4: derived No Response band percentages (band-ascending).
    for band in BAND_ORDER:
        if band in nr_pcts:
            rows.append({"year": year, "race": "No Response", "score_range": band,
                         "test_takers": "", "percent": nr_pcts[band],
                         "mean_total": ""})
    with out.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    return out


def main() -> None:
    years = sorted(int(p.stem) for p in RAW_DIR.glob("*.csv")
                   if p.stem.isdigit())
    if not years:
        raise SystemExit(f"no raw race CSVs found under {RAW_DIR}")
    cohort_bands_by_year = read_cohort_bands()
    for year in years:
        raw = read_raw(year)
        cohort_bands = cohort_bands_by_year.get(year, {})
        nr_pcts = derive_nr_pcts(raw, cohort_bands)
        out = write_augmented(year, raw, cohort_bands, nr_pcts)
        n_rows = sum(1 for _ in open(out)) - 1
        print(f"{year}: {n_rows} rows → {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
