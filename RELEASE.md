# Release procedure

This file is the runbook Claude follows when the user says
**"release"**. It is not a script — several steps involve git and
require the user's eyes on the diff before they happen.

The procedure assumes the typical case: the user has edited
`documents/sat_model.qmd` (or `_inputs.R` / `_headlines.R` / a small
text file like `RELEASE.md` itself), the manuscript needs
re-rendering, and the result has to land in both `replicated/docs/`
and `submitted/docs/` before pushing. Heavier releases (data parser
or Stan-model changes that invalidate `submitted/data/` or
`submitted/sims/`) are not handled here — run `bin/everything data`
or `bin/everything sims` first and re-sync `submitted/` from
`replicated/` by hand, then come back to this procedure.

## Steps

### 1. Confirm working state

Run:

```bash
git status -sb
```

Confirm the branch is `main` and the only modified or staged paths
are the ones the user intended to change. If anything unexpected
is in the diff, **stop and ask** before going further.

### 2. Run the test suite

```bash
bash tests/run_all.sh
```

Every test must pass. The two scripts (`test_syntax.sh` and
`test_artifacts.sh`) take ~1 second total. If anything fails, stop
and surface the specific failure to the user — don't try to render
on top of a broken state.

### 3. Render and promote — `bin/release_docs`

**Run this step inside a Codespace, not on the author's laptop.**
Quarto/Typst output is byte-sensitive to the rendering environment,
so a docx/pdf built on macOS will not byte-match the same .qmd
rendered in a Codespace even with the same Quarto and Typst versions
installed. Users replicating the paper open a Codespace and run
`bin/everything docs`; for `bin/compare docs` to be a meaningful
check, `submitted/docs/` has to hold a Codespace render too. The
release script enforces this by rendering once in the current
environment and writing the result to both trees.

```bash
bin/release_docs
```

Expected: ~5 minutes. The script renders **only** `sat_model.qmd`
(not ancillary qmds the user may have locally), copies the resulting
`docx`/`html`/`pdf` into both `replicated/docs/` and `submitted/docs/`,
and `cmp`s to confirm byte-identity. If any `cmp` fails the script
exits non-zero — **stop and investigate**; it means either `cp`
didn't take or the filesystem is doing something surprising. If
`bin/release_docs` warns that it doesn't see Codespace env vars
(`CODESPACES` / `GITHUB_CODESPACE_NAME`), abort with Ctrl-C and
re-run in the actual Codespace.

### 4. Review the diff

Show the user:

```bash
git status -sb
git diff --stat
git diff documents/sat_model.qmd     # the source-of-truth change
```

**Pause** and let the user look. Don't auto-commit. Common things
that should show up:

- `documents/sat_model.qmd` — the substantive change the user made.
- `submitted/docs/sat_model.{docx, html, pdf}` — modified (the
  rebuilt artifacts).
- `replicated/docs/sat_model.{docx, html, pdf}` — modified (same
  reason).

If anything else is in the diff that the user didn't expect (a stray
`__pycache__/`, a regenerated CSV, a sim file), pause and figure
out why before continuing.

### 5. Compose the commit message

Write a good commit message: a short imperative subject line that
names the **prose / logic change** (not the rebuilt artifacts — those
are a consequence). Add a body paragraph or two if the *why* needs
explaining beyond what the subject line conveys.

**Pause** and show the user the draft message. Wait for confirmation
or edits before committing.

### 6. Stage and commit

After the user confirms:

```bash
git add -A
git commit -m "$(cat <<'EOF'
<the agreed message goes here>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Then `git status -s` to confirm the working tree is clean.

### 7. Push

```bash
git push origin main
```

After push, tell the user:

- CI (`.github/workflows/devcontainer.yml`) will start automatically
  because the push touched paths covered by its filter (any of
  `.devcontainer/`, `bin/`, `code/`, `documents/`, or `.github/`).
- The user can watch progress at the PR / commit page on GitHub.
- The compare-against-`submitted/` step in CI is a **warning**, not
  a hard failure (Quarto / Typst can emit tiny per-render
  differences), so a yellow ⚠️ there doesn't block the merge.

### 8. (Optional) Tag

Only do this step if the user mentions the release is a milestone
("v1 submission", "post-revision-1", etc.). Otherwise skip.

```bash
git tag -a v<N> -m "<description>"
git push origin v<N>
```

---

## When NOT to use this procedure

- If the user has changed `code/*.py` and the **data CSVs** in
  `submitted/data/` are now stale: run `bin/everything data` first,
  hand-sync `replicated/data/` → `submitted/data/`, then start this
  procedure.
- If the user has changed `code/run_fit_mi.R`, `code/shash_dirichlet_bands.stan`,
  or anything that affects the Stan fit: run `bin/everything sims`
  first (~50 min on 8 cores), hand-sync `replicated/sims/mi/` →
  `submitted/sims/mi/`, then start this procedure.
- If `tests/run_all.sh` is reporting failures unrelated to the
  user's change: **stop and investigate**, don't bypass the test
  failure.
