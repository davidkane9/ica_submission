# Replication — *A Model for the Distribution of SAT Total Scores*

This repository contains everything needed to reproduce the manuscript:
the raw College Board source PDFs, the Python extractors that parse
them into CSVs, the Stan model and its R driver, and the Quarto
source that renders to DOCX, HTML, and PDF.

The single most important directory is **[`submitted/`](submitted/)**.
It is an immutable mirror of the artifacts that were submitted to ICA:

- `submitted/data/` — extracted CSVs (per-race × score-band counts and
  percentages, user-percentile reference tables, cohort moments).
- `submitted/sims/mi/` — the canonical Stan posterior, stored as 50
  per-imputation `.rds` files plus a `meta.rds`.
- `submitted/docs/` — the rendered manuscript:
  `sat_model.{docx, pdf, html}`.

**Nothing in `submitted/` is ever touched by the replication scripts.**
It is the ground truth that every reproduction is compared against;
treat it as immutable.

The parallel directory **[`replicated/`](replicated/)** is where the
replication scripts write their output. On a fresh clone, `replicated/`
starts as a byte-identical copy of `submitted/`. Running any stage of
the pipeline overwrites part of `replicated/`; the
[`bin/compare`](bin/compare) script then diffs the two trees. Byte
equality means the reproduction succeeded; any diff signals a
discrepancy worth investigating.

The aim is that anyone — including a user with no prior exposure to
the code — can open a Codespace straight from GitHub, run a couple of
commands, and reproduce the figures and numbers in the paper to the
last digit. No local install, no clone, no `git` setup.

Past that, the same machinery supports **sensitivity analysis** — what
if the prose changes, or the underlying data is different? Two worked
examples at the bottom of this README walk through both:

- *Worked example 1* — add a phrase to the abstract in
  `documents/sat_model.qmd`, re-render docs (~5 min), and watch
  `compare.html` show the prose change against the original abstract
  with every other table and figure visually identical.
- *Worked example 2* — change the **Black 1400-1600 percentage in
  the 2025 input data from 1% to 25%**, run the full pipeline
  (~1 hour, dominated by the Stan refit), and watch the headline
  numbers, validation plots, and figures shift visibly throughout
  the manuscript.

If you just want to verify the paper as-published, follow Quick start
and stop there. If you want to poke at it, jump to the examples first.

## Quick start

1. Sign in to GitHub. Any account works; a free account is fine. **You
   do not need to fork this repo** — Codespaces clones into your own
   tenancy, and the replication workflow only reads from the source
   repo, never writes back to it.
2. Click the green **Code** button on the repo's GitHub page →
   **Codespaces** tab → **Create codespace on main**. (Codespace
   compute is billed against your GitHub account; the free tier covers
   well over one full replication.)
3. Wait for the first-time setup to finish — about thirty seconds
   (the heavy R / Python / Stan install is already cached as a
   Codespaces Prebuild). The Codespace IDE waits for setup to finish
   before opening the terminal (via `waitFor` in `devcontainer.json`),
   so you won't see partial-install errors.
4. Verify the environment, then run a replication:

   ```bash
   bin/check_env          # verifies every pinned dep is installed
   bin/everything docs    # ~5 min: re-render the manuscript and diff vs submitted/
   ```

## The pipeline

```
downloads/ ─[code/*.py]─► data/ ─[code/run_fit_mi.R]─► sims/ ─[documents/sat_model.qmd]─► docs/
```

Each arrow corresponds to one *scope*. Five scripts in `bin/` each
take one scope argument and do exactly one thing to that scope's slot
in `replicated/`:

| Script | What it does to `replicated/<scope>/` |
|---|---|
| [`bin/clean`](bin/clean) `<scope>` | Remove everything under it. |
| [`bin/generate`](bin/generate) `<scope>` | Re-derive from prior-stage inputs. |
| [`bin/compare`](bin/compare) `<scope>` | Diff against `submitted/<scope>/`. For `data` and `sims`, byte-level cmp per file (with an inline unified diff on changed CSVs). For `docs`, a visual side-by-side: writes `replicated/docs/compare.html` and never fails (see below). |
| [`bin/restore`](bin/restore) `<scope>` | Restore from `submitted/<scope>/` (instant). |
| [`bin/everything`](bin/everything) `<scope>` | clean → generate → compare. |

The four valid `<scope>` values, with their inputs, outputs, and rough
wall time:

| Scope | Inputs | Produces | Wall time |
|---|---|---|---|
| `data` | `downloads/sat/**` (raw PDFs and HTML) | `replicated/data/{race/raw,race/augmented,moments,percentiles}/*.csv` | ~2 min |
| `sims` | `replicated/data/race/augmented/*.csv` | `replicated/sims/mi/imp_NN.rds` (50 files) + `meta.rds` | ~50 min |
| `docs` | `replicated/data/...` + `replicated/sims/mi/...` | `replicated/docs/sat_model.{docx, html, pdf}` | ~5 min |
| `all` | (chains the three above in order) | (all three) | ~1 hour |

Nothing reads from `submitted/`. If `bin/generate sims` (or
`bin/generate docs`) can't find its inputs in `replicated/`, it exits
with a clear error pointing at `bin/restore` (instant restore) or
`bin/generate` for the missing stage.

### `bin/compare docs` — a *visual* diff, not a byte diff

For `data` and `sims`, byte equality is meaningful and `bin/compare`
reports it per file. For `docs`, byte equality is the wrong
question: Quarto and Typst routinely emit tiny per-render
differences (timestamps inside the .docx zip, sub-pixel float jitter
in the .pdf) that don't matter for the published artifact. What
matters is whether the *content* — abstract, tables, figures — looks
right.

So `bin/compare docs` generates a side-by-side HTML page instead. It
reads `submitted/docs/sat_model.html` and
`replicated/docs/sat_model.html`, pulls out the abstract section plus
every `<div id="tbl-…">` and `<div id="fig-…">` from each, and writes
a single self-contained page at `replicated/docs/compare.html`:

```
Abstract                      ← from submitted/
Abstract                      ← from replicated/
Table tbl-pdf                 ← from submitted/
Table tbl-pdf                 ← from replicated/
Figure fig-data-trends        ← from submitted/
Figure fig-data-trends        ← from replicated/
... etc.
```

To view:

```bash
bin/compare docs
open replicated/docs/compare.html   # macOS; or just open the path in any browser
```

`compare.html` is gitignored — it's an ephemeral artifact, regenerated
every time the script runs. The `bin/compare docs` exit code is
always 0; only `bin/compare data` and `bin/compare sims` contribute
to the exit code of `bin/compare all` or `bin/everything all`. So a
visual difference in the rendered docs never fails the pipeline.

## Common workflows

**Re-render the manuscript and visually compare it against what was
submitted** (most common — ~5 min):

```bash
bin/everything docs            # clean + generate + compare
open replicated/docs/compare.html
```

`bin/everything docs` won't fail on render jitter; the comparison step
is visual, not byte-level. To confirm byte-identity of the canonical
artifacts at HEAD across `submitted/` and `replicated/`, run
`bash tests/run_all.sh` — its artifact check is the byte-level
guardrail.

**Test the PDF parsers end-to-end** (~2 min):

```bash
bin/everything data
```

**Re-fit the Stan model** (the long step — ~50 min on an 8-core
codespace):

```bash
bin/everything sims
```

**Reproduce the entire pipeline from raw inputs** (~1 hour, dominated
by Stan):

```bash
bin/everything all
```

**Recover from a hosed `replicated/` tree without regenerating**:

```bash
bin/restore all
```

Build timestamps inside the DOCX and PDF are pinned via the
`SOURCE_DATE_EPOCH` environment variable (see
[`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json))
so re-rendering on a different day still produces byte-identical
files. The Stan fit is fully seeded, so re-fitting on the same
software stack produces byte-identical `.rds` files. PDF rendering
uses Quarto's bundled Typst engine — no separate LaTeX install needed.

## Long runs: idle timeout, resume, and check_status

A full `bin/everything sims` takes ~50 minutes on an 8-core codespace,
and `bin/everything all` takes ~1 hour. Both runs are longer than
Codespaces' default **idle timeout of 30 minutes**, so without
mitigation a long run *will* be killed before it finishes if you walk
away.

### The trap: "idle" means *no input*, not *no work*

Codespaces' idle timer is reset only by keystrokes in the browser tab
and by terminal input — not by a running script. So
`bin/everything sims` chugging away for 50 minutes in your terminal,
with you reading email in another tab, looks 100% idle to GitHub. At
the 30-minute mark the container is stopped and your script dies
mid-imputation. (You'll come back to a "codespace is stopped" page
and a partial `replicated/sims/mi/imp_27.rds` or wherever it
happened to be.)

### Two mitigations, in increasing order of robustness

1. **Bump your idle timeout.** Per-user setting at
   <https://github.com/settings/codespaces> → *Default idle timeout*
   → 240 minutes (the maximum). Takes effect on the next codespace
   you create; for the current one, stop and restart it.
2. **Run inside `tmux`.** Codespaces ships with `tmux` preinstalled.
   ```bash
   tmux new -s rep        # start a named session
   bin/everything all     # kick off the long run
   # walk away: press Ctrl-B then D to detach (script keeps running)
   # come back: tmux attach -t rep
   ```
   This survives a dropped browser tab or laptop sleep. It does
   *not* survive a full codespace shutdown — that's what (1) is for.

### Recovering from a codespace shutdown

If your codespace got stopped mid-run (idle timeout fired, network
dropped, you closed the laptop, the machine was restarted), nothing
is lost — files persist across shutdowns. To resume:

1. **Reopen the codespace.** From <https://github.com/codespaces> click
   your codespace name → *Open in browser* (or *Open in VS Code*).
   The container resumes in ~15 seconds; all files in
   `replicated/` are exactly as you left them, including any
   per-imputation `.rds` files that finished before the shutdown.
2. **See where you are.** Run:
   ```bash
   bin/check_status
   ```
   It counts files in `replicated/{data,sims,docs}/`, classifies
   each scope as empty / partial / complete, and prints the exact
   command to run next.
3. **Resume.** The Stan fit is **resumable at the imputation level**:
   `code/run_fit_mi.R` skips any `imp_NN.rds` that already exists
   from a prior run and reuses it. So a sims run that got 30 of 50
   imputations done picks up at imputation 31:
   ```bash
   bin/generate sims      # NOT bin/everything sims — that wipes progress
                          # NOT bin/clean sims either — same reason
   ```
   The `data` and `docs` scopes are short enough that they don't
   need per-step resume; if either is partial, just re-run
   `bin/generate <scope>` and it'll redo the whole stage from
   scratch in a couple of minutes.

If you want defense in depth against another shutdown mid-resume,
combine the recovery commands with `tmux`:

```bash
tmux new -s rep
bin/generate sims
# Ctrl-B D to detach; close the browser without losing the run
```

## Repository layout

| Path | Contents |
|---|---|
| [`downloads/`](downloads/) | Raw, unmodified College Board source PDFs and HTML (graduating classes 2018+). Read-only inputs to the parsers. |
| [`code/`](code/) | Pipeline source: two Python extractors (`extract_sat.py`, `extract_user_percentiles.py`) plus a derivation step (`augment_race.py`) that back-computes the No Response band percentages from the PDF-sourced numbers; one R driver (`run_fit_mi.R`) and one Stan model (`shash_dirichlet_bands.stan`). |
| [`documents/`](documents/) | Paper-rendering source: `sat_model.qmd`, the two R helpers it sources (`_inputs.R`, `_headlines.R`), and Quarto fixtures (`references.bib`, `apa.csl`, `ica-manuscript.docx`). |
| [`submitted/`](submitted/) | Frozen canonical artifacts: `data/`, `sims/mi/`, `docs/`. Immutable. |
| [`replicated/`](replicated/) | User outputs: same shape as `submitted/`. Initially byte-identical; written to by `bin/generate` and `bin/restore`. |
| [`bin/`](bin/) | The five user-facing scripts (`clean`, `generate`, `compare`, `restore`, `everything`) plus [`bin/check_env`](bin/check_env) (verifies every pinned dep is installed) and [`bin/check_status`](bin/check_status) (reports where the pipeline left off and what to run next). |
| [`.devcontainer/`](.devcontainer/) | Codespace setup. Pins every R package, Python package, Stan version, and toolchain version. |
| [`.github/workflows/`](.github/workflows/) | CI that builds the devcontainer and runs the pipeline on every PR. |
| [`tests/`](tests/) | Author-side pre-release sanity checks ([`test_syntax.sh`](tests/test_syntax.sh): bash / Python / R / JSON parse checks; [`test_artifacts.sh`](tests/test_artifacts.sh): file counts and HEAD-level byte-identity between `submitted/` and `replicated/`). Runner: [`tests/run_all.sh`](tests/run_all.sh). ~1 second total. |
| [`RELEASE.md`](RELEASE.md) | Runbook the author follows to ship a release (re-render, sync `replicated/docs/` → `submitted/docs/`, commit, push). Used by Claude when the user says "release". Not a script. |

## Continuous integration

The workflow at
[`.github/workflows/devcontainer.yml`](.github/workflows/devcontainer.yml)
builds the devcontainer end-to-end on every PR that touches
`.devcontainer/`, `bin/`, `code/`, or `documents/`. Inside the built
container it runs `bin/check_env`, then `bin/everything data`, then
`bin/everything docs`. Any regression — a missing apt dep, a parser
path edit that broke, a `.qmd` change that won't render — fails the PR
before it reaches a user's codespace. (`bin/everything sims` is
skipped in CI: it's a ~50-minute Stan refit even on the 8-core
codespace spec the CI runner matches — too long for per-PR CI given
GitHub Actions' time budget. Users can run it themselves if they
want full coverage.)

## Worked examples: what changes when you change things

The two examples below show the replication pipeline working as a
sensitivity-analysis tool. The first is small and fast (a prose edit,
no refit needed). The second is large and slow (a data edit that
demands a full refit). Together they bracket what `bin/compare docs`
is for: it tells you what *visibly moved*, separately from any
build-time render jitter that `cmp` would have flagged. 

### Example 1 — prose edit: random phrase in the abstract

You decide to flag the abstract as a work-in-progress by inserting a
short marker. Open [`documents/sat_model.qmd`](documents/sat_model.qmd),
find the line in the abstract that begins:

> The College Board's SAT is the most widely used standardized test for
> university and college admissions in the United States, ...

Append a phrase — anything you'll recognize, e.g.:

> The College Board's SAT (**reviewer copy — draft, do not circulate**)
> is the most widely used standardized test for university and college
> admissions in the United States, ...

Save. Then:

```bash
bin/clean    docs
bin/generate docs           # ~5 min: re-renders sat_model.{docx, html, pdf}
bin/compare  docs           # generates replicated/docs/compare.html
open replicated/docs/compare.html
```

What you should see in `compare.html`:

- **Abstract** — two side-by-side panels. The `submitted` panel has
  the original prose; the `replicated` panel has the same prose plus
  your "reviewer copy — draft, do not circulate" marker. The
  surrounding headline numbers (e.g. *"approximately X% of
  SAT-takers scoring 1500 or higher are Black"*) are identical
  between the two panels — they come from a Stan posterior that
  wasn't refit, so the numbers don't move.
- **Every Table tbl-… and Figure fig-…** — visually identical.
  `sat_model.qmd` reads its inputs from the same `replicated/data/`
  and `replicated/sims/mi/` that were on disk before your edit, and
  those haven't changed, so every table cell and every plotted point
  is exactly where it was.

Two takeaways:

- *A pure prose edit is cheap.* No data or sims rebuild, ~5 minutes
  of render time, and `compare.html` localizes the change to a single
  panel pair.
- *The numbers in the abstract are sourced, not typed.* Because
  `blk_1500_med` and the other headline values are inline-R
  expressions evaluated against the posterior, you can't accidentally
  edit the prose into inconsistency with the model.

To revert: `git restore documents/sat_model.qmd`, then either
`bin/restore docs` (instant) or rerun `bin/generate docs` (~5 min).

### Example 2 — data edit: Black 1400-1600 from 1% → 25%

This is the counterfactual we walked through earlier in the session,
made concrete and end-to-end. We're going to hand-edit the 2025 input
data so that 25 percent of Black/African American test-takers scored
1400 or above (vs. the College Board's published 1 percent), with a
countervailing decrease in the modal band so the row still sums to
100. Then we'll refit, re-render, and look at how much of the
manuscript moves.

Open [`replicated/data/race/raw/2025.csv`](replicated/data/race/raw/2025.csv).
The Black row reads:

```
Black/African American,250887,904,5,26,40,21,7,1
```

Columns are `race, N, mean, b_400_590, b_600_790, b_800_990, b_1000_1190, b_1200_1390, b_1400_1600`.
Edit the row to:

```
Black/African American,250887,904,5,26,16,21,7,25
```

Two changes: the top band (`b_1400_1600`) goes from 1 to 25, and the
modal band (`b_800_990`) drops from 40 to 16 to keep the row summing
to 100. Save.

Then:

```bash
python3 code/augment_race.py   # rebuild race/augmented/ with the new NR derivation
                               # (the No Response 1400-1600 row will get clipped
                               # to 0.0%, because the named-race contributions
                               # now exceed the published cohort total)

bin/clean    sims              # wipe the canonical fit
bin/generate sims              # ~50 min on 8 cores: refit on the edited data
bin/clean    docs
bin/generate docs              # ~5 min: re-render against the new posterior
bin/compare  docs              # generates replicated/docs/compare.html
open replicated/docs/compare.html
```

What you should see in `compare.html`:

- **Abstract** — the headline figure is roughly an order of magnitude
  higher in the `replicated` panel. The original abstract says
  *"approximately ~1% of SAT-takers scoring 1500 or higher are Black,"*
  (or thereabouts); the replicated abstract will say something more
  like 25%, because the model is now fitting a much heavier
  Black upper tail. The 95% credible interval moves with it.
- **Most figures move.** The data-trends plot (`fig-data-trends`)
  will show a visibly bigger Black share in the 1400-1600 band for
  2025. The cohort-quartile-rank plot (`fig-cohort-quartile-ranks`)
  will degrade because the held-out cohort moments don't agree with
  the new fitted distribution. The validation figures
  (`fig-validate`, `fig-ppc-resid`) will show poorer fit — that's
  the model honestly reporting that the edited band table contradicts
  the published cohort moments and user-percentile tables.
- **Tables also move.** `tbl-pdf` shows the edited input directly
  (25 vs. 1 in the Black, 1400-1600 cell, and 16 vs. 40 in the
  Black, 800-990 cell). `tbl-params` shifts on every Black-specific
  posterior summary.

Three takeaways:

- *A data edit forces a full refit.* The Stan posterior depends on
  the band percentages; change them and every downstream number has
  to be recomputed. This is the ~1-hour path.
- *The compare tool is faithful even when the change is large.*
  `compare.html` doesn't care whether you moved one digit or
  rewrote the underlying probability — it shows you the abstract,
  every labeled table, and every labeled figure, submitted next to
  replicated, in document order.
- *Internal-consistency checks earn their keep.* The model didn't
  refuse to fit a contradictory data table; it produced a posterior
  that the validation plots then clearly flagged as a poor fit.
  Those held-out checks (cohort moments, user-percentile tables) are
  what tell you something's wrong when the input data isn't quite
  the published data.

To revert this experiment cleanly:

```bash
bin/restore all                # snaps replicated/ back to canonical
                               # ~1 second; no refit needed
```

`bin/restore all` is the instant antidote to a counterfactual run.
The frozen `submitted/` tree never changed throughout the
experiment, so restoring is just a `cp -a` from there.
