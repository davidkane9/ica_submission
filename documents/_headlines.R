# Headline numbers used in the manuscript prose of sat_model.qmd
# (the abstract paragraph, the introduction, and the conclusion).
# sat_model.qmd sources this file in its setup chunk.
#
# The other submission documents (abstract.qmd, cover_letter.qmd,
# lede.qmd, title_page.qmd) live outside this replication repo and
# carry their own copy of an equivalent headline-numbers helper.
#
# Exposes these variables in the caller's environment:
#
#   blk_1500_med, blk_1500_lo, blk_1500_hi   -- 2025 Black share (%) of
#                                               the >=1500 pool, model
#                                               posterior median and
#                                               95% credible interval
#   ab_1500_med,  ab_1500_lo,  ab_1500_hi    -- 2025 Asian/Black count
#                                               ratio above 1500,
#                                               model posterior, integer
#   blk_1400_pct                              -- 2025 Black share (%) of
#                                               the >=1400 pool,
#                                               data-pinned from band-6
#                                               counts
#   asn_blk_1400                              -- 2025 Asian/Black count
#                                               ratio above 1400,
#                                               data-pinned
#
# Percentage values are pre-formatted as strings with one decimal
# (so "1.0" does not render as "1"); the count ratios are integers.

# Load the MI posterior + CSV-derived data arrays
# (.draws_dm, .RACES, .YEARS, .N_arr, .P_OBS, .mu_arr, .p_obs).
source("_inputs.R")

.y25 <- match(2025, .YEARS)
.ai  <- match("Asian", .RACES)
.bi  <- match("Black/African American", .RACES)

# 2025 1500+ Black share -- from MI draws
.counts_1500 <- sapply(
  seq_along(.RACES),
  function(r) .N_arr[r, .y25] *
              .draws_dm[, sprintf("p_above_1500[%d,%d]", r, .y25)]
)
.blk_1500 <- 100 * .counts_1500[, .bi] / rowSums(.counts_1500)
.fmt_pct      <- function(x) sprintf("%.1f", x)
blk_1500_med <- .fmt_pct(median(.blk_1500))
blk_1500_lo  <- .fmt_pct(quantile(.blk_1500, 0.025))
blk_1500_hi  <- .fmt_pct(quantile(.blk_1500, 0.975))

# 2025 Asian/Black ratio at 1500+ -- model posterior, integer-rounded
.ab_1500 <- .counts_1500[, .ai] / .counts_1500[, .bi]
ab_1500_med <- round(median(.ab_1500))
ab_1500_lo  <- round(quantile(.ab_1500, 0.025))
ab_1500_hi  <- round(quantile(.ab_1500, 0.975))

# 2025 1400+ data-pinned quantities (no model)
.n_1400      <- .N_arr[, .y25] * .P_OBS[, .y25, 6]
blk_1400_pct <- .fmt_pct(100 * .n_1400[.bi] / sum(.n_1400))
asn_blk_1400 <- round(.n_1400[.ai] / .n_1400[.bi])
