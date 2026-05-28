# Multiple-imputation variant of the SHASH+Dirichlet fit.
#
# Each named group's published band percentages are integer-rounded.  We
# sample M datasets in which each named-group cell is replaced by a draw
# from its rounding interval, with NR derived by subtraction from the
# exact cohort band counts.  We fit the canonical SHASH+Dirichlet model
# on each of the M imputed datasets and pool the M sets of posterior
# draws.  The pooled posterior reflects band-percentage rounding
# uncertainty in addition to the model-fit uncertainty already captured
# by the Dirichlet.

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(purrr)
  library(cmdstanr); library(posterior)
  library(parallel)
})

DATA_DIR  <- "../replicated/data/race/augmented"
STAN_FILE <- "shash_dirichlet_bands.stan"
# Per-imputation draws files (small enough to commit) + a small meta
# file.  The paper reassembles them in memory at render time. Paths
# are relative to code/, so this script must be run from code/
# (which the bin/generate driver does via `cd code && Rscript ...`).
MI_DIR    <- "../replicated/sims/mi"
SEED      <- 20260514
M         <- 50   # number of imputations
dir.create(MI_DIR, showWarnings = FALSE, recursive = TRUE)

YEARS      <- 2018:2025
MAIN_RACES <- c("White", "Hispanic/Latino", "Black/African American",
                "Asian", "Two or More Races",
                "American Indian/Alaska Native",
                "Native Hawaiian/Other Pacific Islander")
RACES      <- c(MAIN_RACES, "No Response")
NR_IDX     <- which(RACES == "No Response")
BAND_LO    <- c(-Inf, 595, 795, 995, 1195, 1395)
BAND_HI    <- c( 595, 795, 995, 1195, 1395, +Inf)
BAND_ORDER <- c("400-590", "600-790", "800-990",
                "1000-1190", "1200-1390", "1400-1600")

all_data <- map_dfr(YEARS, function(yr)
  read.csv(sprintf("%s/%d.csv", DATA_DIR, yr)) |> mutate(year = yr))

# Group sizes (exact)
N_arr <- array(0, dim = c(length(RACES), length(YEARS)))
mu_arr <- array(0, dim = c(length(RACES), length(YEARS)))
for (r_i in seq_along(RACES)) for (y_i in seq_along(YEARS)) {
  rec <- subset(all_data,
                year == YEARS[y_i] & race == RACES[r_i] & score_range == "all")
  N_arr[r_i, y_i]  <- rec$test_takers[1]
  mu_arr[r_i, y_i] <- rec$mean_total[1]
}

# Cohort total band counts (exact, no rounding uncertainty)
cohort_counts <- array(0, dim = c(length(YEARS), 6))
for (y_i in seq_along(YEARS)) for (b in seq_len(6)) {
  rec <- subset(all_data,
                year == YEARS[y_i] & race == "Total" & score_range == BAND_ORDER[b])
  cohort_counts[y_i, b] <- rec$test_takers[1]
}

# Named-group printed band percentages (integers; need imputation)
printed_pct <- array(0, dim = c(length(MAIN_RACES), length(YEARS), 6))
for (i in seq_along(MAIN_RACES)) for (y_i in seq_along(YEARS)) for (b in seq_len(6)) {
  rec <- subset(all_data,
                year == YEARS[y_i] & race == MAIN_RACES[i] & score_range == BAND_ORDER[b])
  printed_pct[i, y_i, b] <- rec$percent[1]
}

# One imputation: for each named-group row, draw uniformly from the
# rounding-box-intersected simplex by rejection sampling.  Sample five
# cell proportions independently from their rounding intervals, derive
# the sixth as the residual, and accept iff that residual falls in its
# own rounding interval.  Every accepted row therefore (a) has each
# cell in its rounding interval and (b) sums exactly to one, with no
# renormalization step.  No Response is then derived by subtraction
# from the exact published cohort band counts.
sample_row <- function(k, max_tries = 100000) {
  los <- pmax(0, (k - 0.5) / 100)
  his <- pmin(1, (k + 0.5) / 100)
  # Choose the band with the widest interval to be the "computed by
  # subtraction" one; ties broken by index.  For the SAT data every
  # interval has width 1 pp (the zero-band interval is also 1 pp wide
  # because los is clamped at 0), so we just leave band 6 as last.
  for (try in seq_len(max_tries)) {
    pi <- numeric(6)
    pi[1:5] <- runif(5, los[1:5], his[1:5])
    pi[6]   <- 1 - sum(pi[1:5])
    if (pi[6] >= los[6] && pi[6] < his[6]) return(pi)
  }
  stop("rejection sampling failed for printed_pct = ",
       paste(k, collapse = ","))
}

sample_imputation <- function() {
  p_obs <- array(0, dim = c(length(RACES), length(YEARS), 6))
  for (y_i in seq_along(YEARS)) {
    named_counts <- matrix(0, nrow = length(MAIN_RACES), ncol = 6)
    for (i in seq_along(MAIN_RACES)) {
      r_i <- match(MAIN_RACES[i], RACES)
      pi  <- sample_row(printed_pct[i, y_i, ])
      named_counts[i, ] <- pi * N_arr[r_i, y_i]
      p_obs[r_i, y_i, ] <- pi
    }
    # NR by subtraction from exact cohort band counts
    nr_counts <- cohort_counts[y_i, ] - colSums(named_counts)
    nr_counts <- pmax(nr_counts, 1)   # guard against rare negatives
    p_obs[NR_IDX, y_i, ] <- nr_counts / sum(nr_counts)
  }
  p_obs
}

gauss_hermite_normal <- function(n) {
  i <- 1:(n - 1)
  J <- matrix(0, n, n)
  J[cbind(i, i + 1)] <- sqrt(i); J[cbind(i + 1, i)] <- sqrt(i)
  eg <- eigen(J, symmetric = TRUE); ord <- order(eg$values)
  list(nodes = eg$values[ord], weights = (eg$vectors[1, ]^2)[ord])
}
G  <- 24L; gq <- gauss_hermite_normal(G)

mod <- cmdstan_model(STAN_FILE)

init_fn <- function() list(
  beta_sigma_mean   = log(230) + rnorm(1, 0, 0.05),
  tau_sigma         = abs(rnorm(1, 0.15, 0.03)),
  sigma_log_raw     = rnorm(length(RACES), 0, 0.3),
  lambda_mean       = rnorm(1, 0.04, 0.01),
  tau_lambda        = abs(rnorm(1, 0.02, 0.005)),
  lambda_raw        = rnorm(length(RACES), 0, 0.3),
  eta_raw           = matrix(rnorm(length(RACES) * length(YEARS), 0, 0.3),
                             length(RACES), length(YEARS)),
  beta_eps_mean     = rnorm(1, 0.2, 0.05),
  tau_eps           = abs(rnorm(1, 0.25, 0.05)),
  eps_raw           = rnorm(length(RACES), 0, 0.3),
  beta_log_delta    = rnorm(1, 0.1, 0.05),
  tau_log_delta     = abs(rnorm(1, 0.05, 0.02)),
  log_delta_raw     = rnorm(length(RACES), 0, 0.3),
  beta_log_phi      = log(280) + rnorm(1, 0, 0.05),
  tau_log_phi       = abs(rnorm(1, 0.1, 0.05)),
  log_phi_raw       = rnorm(length(RACES), 0, 0.3),
  beta_log_tau_eta  = log(0.02) + rnorm(1, 0, 0.05),
  tau_log_tau_eta   = abs(rnorm(1, 0.1, 0.05)),
  log_tau_eta_raw   = rnorm(length(RACES), 0, 0.3),
  log_sigma_nr      = log(230) + rnorm(length(YEARS), 0, 0.05),
  theta_mean        = mu_arr +
                      matrix(rnorm(length(RACES) * length(YEARS), 0, 5),
                             length(RACES), length(YEARS))
)

# Run M imputations and collect key quantities.  We save a subset of
# parameters per imputation rather than the full draws object to keep
# the combined file size manageable.
collect_one <- function(m) {
  set.seed(SEED + m)
  p_obs_arr <- sample_imputation()
  stan_data <- list(
    R = length(RACES), Y = length(YEARS), B = 6,
    N = N_arr, mu_printed = mu_arr, p_obs = p_obs_arr,
    lo = BAND_LO, hi = BAND_HI,
    year_z = as.numeric(scale(YEARS)),
    prior_mu = 1050, prior_sd = 300,
    G = G, gh_node = gq$nodes, gh_weight = gq$weights,
    nr_idx = NR_IDX
  )
  fit <- mod$sample(
    data            = stan_data, chains = 2, parallel_chains = 2,
    iter_warmup     = 1000, iter_sampling = 1000, adapt_delta = 0.95,
    seed            = SEED + m, refresh = 0, init = init_fn,
    show_messages   = FALSE, show_exceptions = FALSE
  )
  # All parameters the paper references
  keep <- c("p_above_1400", "p_above_1450", "p_above_1500",
            "p_above_1550", "p_above_1600", "p_rep",
            "theta_mean", "mean_implied", "mu", "sigma_ry",
            "epsilon", "delta", "phi", "tau_eta", "lambda_mean",
            "lambda", "sigma_log0", "beta_eps_mean", "tau_eps",
            "beta_log_delta", "beta_log_phi", "beta_log_tau_eta")
  out <- list(
    draws    = fit$draws(keep, format = "matrix"),
    diag     = fit$diagnostic_summary(),
    summary  = fit$summary(keep)[, c("variable","rhat","ess_bulk","ess_tail")]
  )
  out$draws <- matrix(as.numeric(out$draws),
                      nrow = nrow(out$draws),
                      dimnames = list(NULL, colnames(out$draws)))
  out
}

# Run the M imputations in parallel across cores.  Each imputation is
# fully independent: all randomness comes from the per-m seeds set
# inside collect_one() (the R-side rejection-sampler / init RNG via
# set.seed(SEED + m), and the cmdstan HMC seed argument SEED + m),
# so parallel execution produces bit-identical results to the
# sequential for-loop this replaces.
#
# Each fit uses 2 cmdstan chains (parallel_chains = 2, inside
# collect_one), so the total subprocess count is
# N_PARALLEL_IMP * 2.  We cap N_PARALLEL_IMP so that total roughly
# matches detectCores().
#
# mc.preschedule = FALSE forks one child per imputation rather than
# batching them per core: that keeps the "set.seed() inside the
# function is the only randomness source" property and rules out a
# subtle non-reproducibility hazard from inherited RNG state.
N_PARALLEL_CHAINS <- 2L
N_PARALLEL_IMP    <- max(1L, parallel::detectCores() %/% N_PARALLEL_CHAINS)
cat(sprintf(
  "\nRunning %d multiple-imputation fits with %d in parallel (%d chains each, %d cores)\n",
  M, N_PARALLEL_IMP, N_PARALLEL_CHAINS, parallel::detectCores()
))

run_one <- function(m) {
  out_path <- file.path(MI_DIR, sprintf("imp_%02d.rds", m))
  # Resume: if imp_NN.rds already exists from a prior (interrupted)
  # run and reads cleanly, skip the fit and reuse the result.  This
  # makes bin/generate sims (without bin/clean sims first) idempotent
  # at the per-imputation granularity, so a 3-hour run that gets killed
  # halfway can be restarted without losing the imputations already
  # completed.  A corrupt partial-write triggers a refit.
  if (file.exists(out_path)) {
    prior <- tryCatch(readRDS(out_path), error = function(e) NULL)
    if (!is.null(prior)) {
      cat(sprintf("  imputation %2d/%d  (already done, skipping)\n", m, M))
      return(prior)
    }
    cat(sprintf("  imputation %2d/%d  (existing file unreadable; refitting)\n", m, M))
    unlink(out_path)
  }
  t0 <- Sys.time()
  out <- collect_one(m)
  # Write this imputation's draws + diagnostics to its own file so
  # each file fits well under git's 100 MB per-file limit; xz-compressed
  # to keep typical per-file size ~10 MB.  Different imputations write
  # to different filenames, so no race condition.
  saveRDS(out, out_path, compress = "xz")
  cat(sprintf("  imputation %2d/%d  (%.1fs)\n", m, M,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  out
}

imputations <- mclapply(
  seq_len(M),
  run_one,
  mc.cores       = N_PARALLEL_IMP,
  mc.preschedule = FALSE
)

# Surface mclapply failures as hard errors (mc.preschedule = FALSE
# returns a try-error object instead of stopping the parent).
.errs <- which(sapply(imputations, inherits, what = "try-error"))
if (length(.errs)) {
  stop("collect_one() failed for imputation(s): ", paste(.errs, collapse = ", "))
}

n_div_total <- sum(sapply(imputations, function(x) sum(x$diag$num_divergent)))
cat(sprintf("Total divergences across %d imputations: %d\n", M, n_div_total))

# Aggregate diagnostics across imputations (max R-hat, min ESS).
per_imp_summary <- lapply(imputations, function(x) x$summary)
max_rhat <- max(sapply(per_imp_summary, function(s) max(s$rhat, na.rm = TRUE)))
min_bulk <- min(sapply(per_imp_summary, function(s) min(s$ess_bulk, na.rm = TRUE)))
min_tail <- min(sapply(per_imp_summary, function(s) min(s$ess_tail, na.rm = TRUE)))
# Per-parameter aggregation across imputations.
per_param <- per_imp_summary[[1]][, c("variable","rhat","ess_bulk","ess_tail")]
for (s in per_imp_summary[-1]) {
  m <- match(per_param$variable, s$variable)
  per_param$rhat     <- pmax(per_param$rhat,     s$rhat[m],     na.rm = TRUE)
  per_param$ess_bulk <- pmin(per_param$ess_bulk, s$ess_bulk[m], na.rm = TRUE)
  per_param$ess_tail <- pmin(per_param$ess_tail, s$ess_tail[m], na.rm = TRUE)
}
saveRDS(list(RACES = RACES, YEARS = YEARS, N_arr = N_arr,
             M = M, SEED = SEED,
             n_div = n_div_total,
             max_rhat_across_imp     = max_rhat,
             min_ess_bulk_across_imp = min_bulk,
             min_ess_tail_across_imp = min_tail,
             per_param_diag          = per_param),
        file.path(MI_DIR, "meta.rds"),
        compress = "xz")
cat(sprintf("\nSaved %d per-imputation files + meta.rds in %s\n", M, MI_DIR))

# Headline
combined <- do.call(rbind, lapply(imputations, function(x) x$draws))
y25 <- match(2025, YEARS); ai <- match("Asian", RACES); bi <- match("Black/African American", RACES)
counts <- sapply(seq_along(RACES), function(r)
  N_arr[r, y25] * combined[, sprintf("p_above_1500[%d,%d]", r, y25)])
pb <- 100 * counts[, bi] / rowSums(counts)
rr <- counts[, ai] / counts[, bi]
cat(sprintf("\n=== Multiple-imputation pooled posterior, 2025 ===\n"))
cat(sprintf("Black share of 1500+: %.2f%% (95%% CI %.2f%%-%.2f%%)\n",
            median(pb), quantile(pb, .025), quantile(pb, .975)))
cat(sprintf("Asian/Black ratio 1500+: %.1f (95%% CI %.1f-%.1f)\n",
            median(rr), quantile(rr, .025), quantile(rr, .975)))
