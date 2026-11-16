# Tables and statistics for the frases-comas experiment (workshop version), compared with the paper.
# Input: measures.csv and questions.csv (written by commas_preprocessing.py). Run from workshop/:
#   Rscript commas_statistics.R
# The "## ---- name" lines mark the parts that are shown in the slides.

## ---- stats-read
library(tidyverse)
library(lme4)

dir <- "data/frases-comas/derived/simple"
measures  <- read_csv(file.path(dir, "measures.csv"), show_col_types = FALSE) |>
  mutate(comma = factor(cond, 1:2, c("comma present", "comma omitted")))
questions <- read_csv(file.path(dir, "questions.csv"), show_col_types = FALSE)

## ---- stats-accuracy
accuracy <- questions |>
  filter(!is.na(button)) |>   # a few questions have no recorded answer
  group_by(subject) |>
  summarise(correct = 100 * mean(button == correct_button))
# Standard practice: pre-specify a minimum accuracy threshold (e.g. >= 80%); all 30 here are >= 89.2%.
cat(sprintf("Accuracy: M = %.1f%%, range %.1f-%.1f%%\n",
            mean(accuracy$correct), min(accuracy$correct), max(accuracy$correct)))

## ---- stats-data
# sentence reading time = summed region TVT (on-text fixation time only, not DISPLAY ON -> ENDBUTTON)
sentence_all <- measures |>
  group_by(subject, item, comma) |>
  summarise(time = sum(tvt, na.rm = TRUE), .groups = "drop")
sentence <- sentence_all |> filter(time < 8000)

# Upper cut-offs (tuned for skilled L1 readers; check counts per condition, and adjust for L2 readers)
cutoff <- c(ffd = 800, gd = 1500, gpt = 1800, tvt = 1800)
local_all <- measures |>
  filter(region %in% 2:4) |>
  mutate(region = factor(region, 2:4, c("pre-comma", "post-comma 1", "post-comma 2"))) |>
  pivot_longer(c(ffd, gd, gpt, tvt), names_to = "measure", values_to = "time") |>
  filter(!is.na(time))
local <- local_all |> filter(time < cutoff[measure])
local_all |> filter(time >= cutoff[measure]) |> count(comma, measure) |>
  pivot_wider(names_from = comma, values_from = n, values_fill = 0) |> print()

## ---- stats-tables
# Aggregate by participant first so SE reflects between-participant variance, not trial-level N
mean_se <- \(x) sprintf("%.0f (%.1f)", mean(x), sd(x) / sqrt(length(x)))

sentence |> group_by(subject, comma) |> summarise(time = mean(time), .groups = "drop") |>
  group_by(comma) |> summarise(`sentence reading time` = mean_se(time)) |> print()
local |>
  group_by(subject, region, comma, measure) |> summarise(time = mean(time), .groups = "drop") |>
  group_by(region, comma, measure) |>
  summarise(m = mean_se(time), .groups = "drop") |>
  pivot_wider(names_from = measure, values_from = m) |>
  print()

## ---- stats-models
# Primary hypothesis: go-past & total time on pre-comma and post-comma 1 (all 13 models shown for comparison).
# comma present = -0.5, omitted = +0.5: the estimate is the difference "omitted - present" in ms.
# Raw ms keeps the same scale as the paper's brms ex-Gaussian mu; see stats-scale for log(time) sensitivity.
# Random intercepts only here for demonstration: maximal slopes `(1 + comma | subject) + (1 + comma | item)`
# produce singular fits / convergence warnings in lme4; the paper used Bayesian models (brms) instead.
comma_effect <- function(d) {
  contrasts(d$comma) <- c(-0.5, 0.5)
  model <- lmer(time ~ comma + (1 | subject) + (1 | item), data = d)
  ci <- confint(model, parm = "comma1", method = "Wald")
  tibble(estimate = fixef(model)[["comma1"]], lower = ci[1], upper = ci[2])
}
effects <- bind_rows(
  sentence |> comma_effect() |> mutate(region = "sentence", measure = "reading time"),
  local |> group_by(region, measure) |> group_modify(\(d, g) comma_effect(d)) |> ungroup()
)

## ---- stats-skipping
# First-pass skipping (fpf == 0) on the pre-comma region: durations are conditional on fixation
skip_pre <- measures |> filter(region == 2) |> mutate(skipped = as.integer(fpf == 0))
contrasts(skip_pre$comma) <- c(-0.5, 0.5)
skip_pre |> group_by(comma) |> summarise(skip_pct = round(100 * mean(skipped), 1)) |> print()
m_skip <- glmer(skipped ~ comma + (1 | subject) + (1 | item), data = skip_pre, family = binomial)
round(summary(m_skip)$coefficients, 3) |> print()

## ---- stats-scale
# Reading times are right-skewed (Part 1 models log(gd)). Compare t-statistics on raw ms vs. log(time):
scale_t <- function(d) {
  contrasts(d$comma) <- c(-0.5, 0.5)
  t_raw <- summary(lmer(time ~ comma + (1 | subject) + (1 | item), data = d))$coefficients["comma1", "t value"]
  t_log <- summary(lmer(log(time) ~ comma + (1 | subject) + (1 | item), data = d))$coefficients["comma1", "t value"]
  sprintf("%.2f / %.2f", t_raw, t_log)
}
local |>
  group_by(region, measure) |>
  summarise(t_raw_log = scale_t(pick(everything())), .groups = "drop") |>
  pivot_wider(names_from = measure, values_from = t_raw_log) |>
  print()

## ---- stats-plot
# estimates of the paper: mu of a Bayesian ex-Gaussian model (brms), 95% credible interval
paper <- tribble(
  ~region, ~measure, ~estimate, ~lower, ~upper,
  "sentence", "reading time", 30.29, -3.76, 63.78,
  "pre-comma", "ffd", -2.75, -7.32, 1.79, "pre-comma", "gd", -7.66, -16.69, 0.87,
  "pre-comma", "gpt", -27.81, -40.70, -15.90, "pre-comma", "tvt", -5.39, -15.94, 4.62,
  "post-comma 1", "ffd", 4.07, -0.85, 9.12, "post-comma 1", "gd", 8.14, -1.06, 18.01,
  "post-comma 1", "gpt", 25.51, 14.66, 36.79, "post-comma 1", "tvt", 29.54, 19.04, 40.53,
  "post-comma 2", "ffd", 4.91, 0.81, 9.15, "post-comma 2", "gd", 7.72, 0.61, 15.03,
  "post-comma 2", "gpt", 23.23, 13.21, 33.42, "post-comma 2", "tvt", 11.76, 2.42, 21.30)

comparison <- bind_rows(`this analysis (lme4)` = effects, `paper (brms)` = paper, .id = "source") |>
  mutate(region = fct_relevel(as.character(region), "sentence", "pre-comma", "post-comma 1", "post-comma 2"))

effect_plot <- ggplot(comparison, aes(measure, estimate, colour = source)) +
  geom_hline(yintercept = 0, linetype = 2) +
  geom_pointrange(aes(ymin = lower, ymax = upper), position = position_dodge(width = 0.5)) +
  facet_wrap(~region, nrow = 1, scales = "free") +
  labs(x = NULL, y = "Omitted - present (ms, 95% CI)", colour = NULL) +
  theme_minimal(base_size = 14) +
  theme(legend.position = "bottom")
ggsave(file.path(dir, "comma_effects.png"), effect_plot, width = 11, height = 4.5)
if (interactive() || isTRUE(getOption("knitr.in.progress"))) print(effect_plot)
