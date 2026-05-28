// Per-race censored sinh-arcsinh (Jones & Pewsey 2009) score
// distributions, fit to OBSERVED BAND PROPORTIONS via a Dirichlet
// likelihood with a single concentration knob phi.
//
// We feed the College Board's rounded band percentages in directly as
// observed proportions p_obs[r,y,.] and model
//     p_obs[r,y,.] ~ Dirichlet( phi * pi[r,y,.] )
// where pi[r,y,.] are the SHASH band probabilities.  phi's Dirichlet
// variance pi*(1-pi)/(phi+1) does NOT depend on the race's N, so a
// huge-N race is not treated as orders of magnitude more precise than a
// small one -- the multinomial's main flaw.
//
// SHASH(eps, delta):  X = sinh( (asinh(Z) + eps) / delta ),  Z ~ N(0,1).
//   CDF:   F(x) = Phi( sinh( delta * asinh(x) - eps ) )
//   delta = 1, eps = 0  ->  standard normal;  delta < 1 -> heavy tails;
//   eps != 0 -> skew.   score ~ mu + sigma * X.
//
// Within-race shape and scale:
//   * epsilon[r]  -- per-race skewness, pooled hierarchically, year-constant.
//   * delta       -- ONE global tail weight.
//   * sigma[r,y]  -- for the seven named races:
//         exp( sigma_log0[r] + lambda[r]*year_z[y] + tau_eta*eta_raw[r,y] ),
//         a pooled mid-period log scale, a per-race log-linear scale
//         trend lambda[r] (pooled toward a common rate lambda_mean),
//         and a small per-(race,year) wiggle around that trend.
//     For "No Response" (r == nr_idx): FREE per-year log sigma,
//         log_sigma_nr[y] ~ N(log(230), 0.4) (mean, SD), decoupled from the
//         named-group trend.  Rationale: the No Response category is
//         not a population but a mixture defined by who declined to
//         report race, and its composition shifted around the SAT-
//         optional era (2020+); a smooth log-linear sigma trend
//         cannot track the resulting structural break and distorts
//         the named-group hierarchy if NR is forced into it.
//   * phi         -- the single Dirichlet concentration.
//
// Band edges: SAT total scores come in 10-point steps, so the "400-590"
// / "600-790" boundary is at 595, not 600.  The driver passes the
// mid-gap edges 595, 795, ..., 1395; below-400 mass folds into band 1,
// above-1600 into band 6.
//
// Location / the published mean: the per-cell mean theta_mean[r,y] is a
// FREE parameter with a generic weakly-informative prior,
// theta_mean[r,y] ~ N(prior_mu, prior_sd) (mean, SD) with prior_sd ~300 points,
// using NONE of the published per-group means.  The band proportions
// alone locate each curve; the published mean -- like the published
// SD and quartiles -- is used only as an external held-out check.

functions {
  real shash_F(real x, real eps, real delta) {
    return Phi(sinh(delta * asinh(x) - eps));
  }
}

data {
  int<lower=1> R;
  int<lower=1> Y;
  int<lower=1> B;
  array[R, Y]    int<lower=0> N;
  array[R, Y]    real           mu_printed;
  array[R, Y]    vector[B]       p_obs;
  array[B]       real           lo;
  array[B]       real           hi;
  vector[Y]      year_z;
  real           prior_mu;
  real<lower=0>  prior_sd;
  int<lower=1>   G;
  vector[G]      gh_node;
  vector[G]      gh_weight;
  int<lower=1, upper=R> nr_idx;       // index of the "No Response" race
}

transformed data {
  array[R, Y] vector[B] p_obs_n;
  for (r in 1:R)
    for (y in 1:Y)
      p_obs_n[r, y] = p_obs[r, y] / sum(p_obs[r, y]);
}

parameters {
  real beta_sigma_mean;
  real<lower=0> tau_sigma;
  vector[R] sigma_log_raw;
  real lambda_mean;
  real<lower=0> tau_lambda;
  vector[R] lambda_raw;
  matrix[R, Y] eta_raw;
  real beta_eps_mean;
  real<lower=0> tau_eps;
  vector[R] eps_raw;
  // Per-group tail-weight delta_r, hierarchically pooled
  real beta_log_delta;
  real<lower=0> tau_log_delta;
  vector[R] log_delta_raw;
  // Per-group Dirichlet concentration phi_r, hierarchically pooled
  real beta_log_phi;
  real<lower=0> tau_log_phi;
  vector[R] log_phi_raw;
  // Per-group wiggle spread tau_eta_r, hierarchically pooled
  real beta_log_tau_eta;
  real<lower=0> tau_log_tau_eta;
  vector[R] log_tau_eta_raw;
  vector[Y] log_sigma_nr;            // free per-year log sigma for NR
  array[R, Y] real theta_mean;
}

transformed parameters {
  vector[R] sigma_log0 = beta_sigma_mean + tau_sigma  * sigma_log_raw;
  vector[R] lambda     = lambda_mean      + tau_lambda * lambda_raw;
  vector[R] epsilon    = beta_eps_mean    + tau_eps    * eps_raw;
  vector[R] delta      = exp(beta_log_delta    + tau_log_delta    * log_delta_raw);
  vector[R] phi        = exp(beta_log_phi      + tau_log_phi      * log_phi_raw);
  vector[R] tau_eta    = exp(beta_log_tau_eta  + tau_log_tau_eta  * log_tau_eta_raw);

  vector[R] mX;
  for (r in 1:R) {
    real acc = 0;
    for (g in 1:G)
      acc += gh_weight[g] * sinh((asinh(gh_node[g]) + epsilon[r]) / delta[r]);
    mX[r] = acc;
  }

  array[R, Y] real sigma_ry;
  array[R, Y] real mu;
  for (r in 1:R)
    for (y in 1:Y) {
      if (r == nr_idx)
        sigma_ry[r, y] = exp(log_sigma_nr[y]);
      else
        sigma_ry[r, y] = exp(sigma_log0[r] + lambda[r] * year_z[y] + tau_eta[r] * eta_raw[r, y]);
      mu[r, y] = theta_mean[r, y] - sigma_ry[r, y] * mX[r];
    }
}

model {
  beta_sigma_mean ~ normal(log(230), 0.4);
  tau_sigma       ~ normal(0, 0.35);
  lambda_mean     ~ normal(0, 0.15);
  tau_lambda      ~ normal(0, 0.06);
  beta_eps_mean   ~ normal(0, 0.6);
  tau_eps         ~ normal(0, 0.8);

  // Hyperpriors for per-group tail-weight delta_r:
  //   delta_r = exp(beta_log_delta + tau_log_delta * raw),  raw ~ N(0,1)
  beta_log_delta   ~ normal(0, 0.3);        // centred at delta = 1 (normal tails)
  tau_log_delta    ~ normal(0, 0.2);         // weakly informative between-group spread

  // Hyperpriors for per-group Dirichlet concentration phi_r:
  beta_log_phi     ~ normal(log(300), 1.5);
  tau_log_phi      ~ normal(0, 0.5);

  // Hyperpriors for per-group per-year wiggle spread tau_eta_r:
  beta_log_tau_eta ~ normal(log(0.03), 0.6); // centred on the slack region
  tau_log_tau_eta  ~ normal(0, 0.3);

  sigma_log_raw       ~ std_normal();
  lambda_raw          ~ std_normal();
  to_vector(eta_raw)  ~ std_normal();
  eps_raw             ~ std_normal();
  log_delta_raw       ~ std_normal();
  log_phi_raw         ~ std_normal();
  log_tau_eta_raw     ~ std_normal();

  log_sigma_nr ~ normal(log(230), 0.4);

  for (r in 1:R)
    for (y in 1:Y)
      theta_mean[r, y] ~ normal(prior_mu, prior_sd);

  for (r in 1:R) {
    for (y in 1:Y) {
      vector[B] pi;
      for (b in 1:B) {
        real Fhi = is_inf(hi[b]) ? 1.0
                   : shash_F((hi[b] - mu[r, y]) / sigma_ry[r, y], epsilon[r], delta[r]);
        real Flo = is_inf(lo[b]) ? 0.0
                   : shash_F((lo[b] - mu[r, y]) / sigma_ry[r, y], epsilon[r], delta[r]);
        pi[b] = fmax(Fhi - Flo, 1e-12);
      }
      pi = pi / sum(pi);
      p_obs_n[r, y] ~ dirichlet(phi[r] * pi);
    }
  }
}

generated quantities {
  array[R, Y] vector[B] p_rep;
  array[R, Y] vector[B] pi_hat;
  array[R, Y] real mean_implied;
  array[R, Y] real p_above_1400;
  array[R, Y] real p_above_1450;
  array[R, Y] real p_above_1500;
  array[R, Y] real p_above_1550;
  array[R, Y] real p_above_1600;
  array[R, Y] real log_lik;

  for (r in 1:R) {
    for (y in 1:Y) {
      real s = sigma_ry[r, y];
      real e = epsilon[r];
      real d = delta[r];
      real m = mu[r, y];
      vector[B] pi;
      for (b in 1:B) {
        real Fhi = is_inf(hi[b]) ? 1.0 : shash_F((hi[b] - m) / s, e, d);
        real Flo = is_inf(lo[b]) ? 0.0 : shash_F((lo[b] - m) / s, e, d);
        pi[b] = fmax(Fhi - Flo, 1e-12);
      }
      pi = pi / sum(pi);
      pi_hat[r, y]       = pi;
      mean_implied[r, y] = theta_mean[r, y];
      p_rep[r, y]        = dirichlet_rng(phi[r] * pi);
      p_above_1400[r, y] = 1 - shash_F((1395 - m) / s, e, d);
      p_above_1450[r, y] = 1 - shash_F((1445 - m) / s, e, d);
      p_above_1500[r, y] = 1 - shash_F((1495 - m) / s, e, d);
      p_above_1550[r, y] = 1 - shash_F((1545 - m) / s, e, d);
      p_above_1600[r, y] = 1 - shash_F((1595 - m) / s, e, d);
      log_lik[r, y]      = dirichlet_lpdf(p_obs_n[r, y] | phi[r] * pi);
    }
  }
}
