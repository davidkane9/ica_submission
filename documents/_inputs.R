# Shared data-loading for the submission qmds.  Sourced by
# documents/_headlines.R and by the setup chunk of
# documents/sat_model.qmd; must be run from documents/ (which is the
# qmds' working directory at render time).
#
# Reads:
#   * The MI posterior — 50 per-imputation .rds files plus meta.rds
#     under ../replicated/sims/mi/.
#   * The eight per-year augmented race CSVs under
#     ../replicated/data/race/augmented/, which carry the test-taker
#     counts, printed group means, printed band percentages, cohort
#     band counts, and derived No Response band percentages that the
#     model was fit to.
#
# Exposes the following private (dot-prefixed) names in the caller's
# environment:
#
#   .draws_dm   posterior draws (as_draws_matrix; M_total × n_params)
#   .mi_meta    MI meta list: M, SEED, n_div, max_rhat_across_imp,
#               min_ess_bulk_across_imp, min_ess_tail_across_imp,
#               per_param_diag, plus RACES, YEARS, N_arr
#   .n_div_mi   total divergences across the M imputations
#   .RACES      character(8), the order Stan used
#   .YEARS      integer(8), 2018:2025
#   .N_arr      8 × 8 numeric, test_takers[r, y]
#   .mu_arr     8 × 8 numeric, printed mean_total[r, y]
#   .p_obs      8 × 8 × 6 numeric, raw band proportions
#               (percent/100, NOT renormalised)
#   .P_OBS      8 × 8 × 6 numeric, row-renormalised band proportions
#               so each (race, year) row sums to 1 exactly — matches
#               the Stan transformed-data block.
#
# Replacing the legacy single-fit `shash_dirichlet_bands_meta.rds`:
# the printed-data fields used to come from that .rds; they now come
# straight from the CSVs, so the data the qmd documents is by
# construction the same data the user can `cat` in the repo.

suppressPackageStartupMessages({
  library(posterior)
})

.MI_DIR     <- "../replicated/sims/mi"
.RACE_DIR   <- "../replicated/data/race/augmented"
.BAND_ORDER <- c("400-590", "600-790", "800-990",
                 "1000-1190", "1200-1390", "1400-1600")

# ----- MI posterior -----------------------------------------------------------
.mi_meta   <- readRDS(file.path(.MI_DIR, "meta.rds"))
.imp_files <- sort(list.files(.MI_DIR, pattern = "^imp_\\d+\\.rds$",
                              full.names = TRUE))
stopifnot(length(.imp_files) == .mi_meta$M)
.draws_dm  <- as_draws_matrix(
  do.call(rbind, lapply(.imp_files, function(f) readRDS(f)$draws)))
.n_div_mi  <- .mi_meta$n_div

# ----- data the model was fit to (read from CSVs) -----------------------------
.RACES <- .mi_meta$RACES
.YEARS <- .mi_meta$YEARS
.all_data <- do.call(rbind, lapply(.YEARS, function(yr) {
  d <- read.csv(sprintf("%s/%d.csv", .RACE_DIR, yr),
                stringsAsFactors = FALSE)
  d$year_idx <- match(yr, .YEARS)
  d
}))

.N_arr  <- array(0, dim = c(length(.RACES), length(.YEARS)))
.mu_arr <- array(0, dim = c(length(.RACES), length(.YEARS)))
for (.r in seq_along(.RACES)) for (.y in seq_along(.YEARS)) {
  .rec <- subset(.all_data,
                 race == .RACES[.r] & year_idx == .y & score_range == "all")
  .N_arr [.r, .y] <- .rec$test_takers[1]
  .mu_arr[.r, .y] <- .rec$mean_total[1]
}

.p_obs <- array(0, dim = c(length(.RACES), length(.YEARS), 6))
for (.r in seq_along(.RACES)) for (.y in seq_along(.YEARS))
  for (.b in seq_along(.BAND_ORDER)) {
    .rec <- subset(.all_data,
                   race == .RACES[.r] & year_idx == .y &
                   score_range == .BAND_ORDER[.b])
    .p_obs[.r, .y, .b] <- .rec$percent[1] / 100
}

# Renormalise to an exact simplex so each (race, year) row sums to 1.
# Matches the Stan transformed-data block.
.P_OBS <- .p_obs
for (.r in seq_along(.RACES)) for (.y in seq_along(.YEARS))
  .P_OBS[.r, .y, ] <- .P_OBS[.r, .y, ] / sum(.P_OBS[.r, .y, ])

# Clean up loop temporaries so they don't leak into the caller's namespace.
rm(.r, .y, .b, .rec, .all_data)
