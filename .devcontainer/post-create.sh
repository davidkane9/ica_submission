#!/usr/bin/env bash
# Post-create setup. Every R package, the Stan toolchain, and the
# Python dependencies are pinned so re-builds give byte-identical
# environments.
#
# Pin strategy:
#   * R packages — Posit Package Manager (PPM) dated snapshot. The URL
#     includes the Ubuntu codename so PPM serves precompiled binaries
#     (source compilation of the tidyverse would take ~15 min on a
#     4-core codespace; binaries land in under a minute).
#   * cmdstanr — installed from a github release tag (not on CRAN, so
#     PPM does not cover it).
#   * cmdstan — exact version via cmdstanr::install_cmdstan(version=).
#   * Python deps — exact-version (==) pip installs.
#   * System binaries (poppler-utils → pdftotext) — apt.
#
# After each install step we verify that what was supposed to land
# actually did, so a silent partial-install fails the build loudly
# rather than burning through the rest of the script. bin/check_env
# runs at the very end as a comprehensive safety net.

set -euo pipefail
trap 'echo "post-create.sh FAILED at line $LINENO" >&2' ERR

# Detect the Ubuntu codename of the rocker base (jammy, noble, ...) so
# PPM serves the matching prebuilt binary repository.
. /etc/os-release
UBUNTU_CODENAME="${VERSION_CODENAME:?could not detect Ubuntu codename}"
PPM_REPO="https://packagemanager.posit.co/cran/__linux__/${UBUNTU_CODENAME}/${PPM_SNAPSHOT}"

# ─── [1/5] Configure R's CRAN repo to the frozen PPM snapshot ────────
echo "=== [1/5] R: configure PPM snapshot ${PPM_SNAPSHOT} (${UBUNTU_CODENAME}) ==="
sudo tee /usr/local/lib/R/etc/Rprofile.site >/dev/null <<EOF
local({
  r <- getOption("repos")
  r["CRAN"] <- "${PPM_REPO}"
  options(repos = r,
          HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
            paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])),
          Ncpus = max(1, parallel::detectCores() - 1))
})
EOF
grep -q "$PPM_REPO" /usr/local/lib/R/etc/Rprofile.site || {
    echo "ERROR: Rprofile.site does not reference the PPM URL we tried to write" >&2
    exit 1
}
# Verify a fresh, non-vanilla R session actually loads Rprofile.site and
# resolves CRAN to the PPM URL. (Bug bait: --vanilla on later Rscript
# calls skips Rprofile.site and breaks install.packages with "trying to
# use CRAN without setting a mirror".)
Rscript -e "stopifnot(identical(unname(getOption('repos')['CRAN']), '${PPM_REPO}'))"

# ─── [2/5] R packages from the PPM snapshot ──────────────────────────
echo "=== [2/5] R packages: tidyverse + knitr + posterior ==="
# tidyverse brings dplyr, tidyr, purrr, ggplot2, tibble, readr, stringr,
# forcats, lubridate (scales rides along as a ggplot2 dep). knitr backs
# Quarto's R engine. posterior is the Stan-side draws-handling package.
# remotes is needed for the github install of cmdstanr below.
sudo Rscript -e '
pkgs <- c("tidyverse", "knitr", "posterior", "remotes")
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) install.packages(missing)
still_missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(still_missing)) {
    cat("R package install FAILED for:", paste(still_missing, collapse=", "), "\n", file = stderr())
    quit(status = 2)
}
for (p in pkgs) cat(sprintf("  %-12s %s\n", p, as.character(packageVersion(p))))
'

# ─── [3/5] cmdstanr + cmdstan ────────────────────────────────────────
echo "=== [3/5] cmdstanr ${CMDSTANR_VERSION} ==="
sudo Rscript -e "
remotes::install_github('stan-dev/cmdstanr@v${CMDSTANR_VERSION}',
                        upgrade = 'never', dependencies = TRUE,
                        quiet = FALSE)
if (!requireNamespace('cmdstanr', quietly = TRUE)) {
    cat('cmdstanr install FAILED\n', file = stderr())
    quit(status = 2)
}
if (as.character(packageVersion('cmdstanr')) != '${CMDSTANR_VERSION}') {
    cat(sprintf('cmdstanr version mismatch: got %s, expected ${CMDSTANR_VERSION}\n',
                packageVersion('cmdstanr')), file = stderr())
    quit(status = 2)
}
"

echo "=== [4/5] cmdstan ${CMDSTAN_VERSION} into ${CMDSTAN} ==="
CMDSTAN_PARENT="$(dirname "$CMDSTAN")"
sudo mkdir -p "$CMDSTAN_PARENT"
sudo chown -R "$(id -u)":"$(id -g)" "$CMDSTAN_PARENT"
Rscript -e "
cmdstanr::check_cmdstan_toolchain(fix = TRUE)
# cmdstan_version() throws when no cmdstan is installed; with
# error_on_NA=FALSE it returns NA. Treat 'no version' as 'need to install'.
have_ver <- tryCatch(
    as.character(cmdstanr::cmdstan_version(error_on_NA = FALSE)),
    error = function(e) NA_character_)
if (!isTRUE(identical(have_ver, '${CMDSTAN_VERSION}'))) {
    cmdstanr::install_cmdstan(dir = '${CMDSTAN_PARENT}',
                              version = '${CMDSTAN_VERSION}',
                              cores = max(1, parallel::detectCores() - 1),
                              overwrite = TRUE, quiet = FALSE)
}
cmdstanr::set_cmdstan_path('${CMDSTAN}')
final_ver <- as.character(cmdstanr::cmdstan_version())
if (final_ver != '${CMDSTAN_VERSION}') {
    cat(sprintf('cmdstan version mismatch after install: got %s, expected ${CMDSTAN_VERSION}\n',
                final_ver), file = stderr())
    quit(status = 2)
}
cat('cmdstan path: ', cmdstanr::cmdstan_path(), '\n', sep = '')
cat('cmdstan ver:  ', final_ver, '\n', sep = '')
"

# ─── [5/5] Python deps + system binaries ─────────────────────────────
echo "=== [5/5] system: poppler-utils ==="
# pdftotext (from poppler-utils) is shelled out to by
# code/extract_user_percentiles.py — a system dep, not a Python one.
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends poppler-utils
command -v pdftotext >/dev/null || {
    echo "pdftotext install FAILED — not on PATH" >&2; exit 2
}

echo "=== [5/5] Python: pdfplumber ${PDFPLUMBER_VERSION}, beautifulsoup4 ${BS4_VERSION} ==="
python3 -m pip install --user --upgrade "pip==25.1.1"
python3 -m pip install --user \
    "pdfplumber==${PDFPLUMBER_VERSION}" \
    "beautifulsoup4==${BS4_VERSION}"
python3 -c "import pdfplumber, bs4" || {
    echo "Python install verification FAILED" >&2; exit 2
}

# ─── final comprehensive check ───────────────────────────────────────
echo
echo "=== running bin/check_env ==="
bash "$(dirname "$0")/../bin/check_env"

cat <<'EOF'

============================================================
  Environment ready. Run bin/check_env to verify.
============================================================

EOF
