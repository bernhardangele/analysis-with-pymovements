# Reading measures for the frases-comas experiment (workshop version).
# Input: the CSV files written by commas_preprocessing.py. Run from the workshop/ folder:
#   Rscript commas_measures.R
# The "## ---- name" lines mark the parts that are shown in the slides.

## ---- measures-read
library(tidyverse)
library(fixated)

dir <- "data/frases-comas/derived/simple"
fixations <- read_csv(file.path(dir, "fixations.csv"), show_col_types = FALSE)
blinks    <- read_csv(file.path(dir, "blinks.csv"), show_col_types = FALSE)
regions   <- read_csv(file.path(dir, "regions.csv"), show_col_types = FALSE)

## ---- measures-short
# 1. Very short fixations (<= 80 ms) are not real reading fixations: remove them.
fixations <- fixations |> filter(duration > 80)

## ---- measures-blinks
# 2. Blinks distort the fixations around them. Mark fixations that overlap a blink or are within 100 ms of one,
#    and exclude trials in which this happened on the critical (pre-comma) region.
fixations <- fixations |>
  rename(t_start = onset, t_end = offset) |>
  group_by(subject) |>
  group_modify(\(f, s) mark_fixations_close_to_blinks(f, filter(blinks, subject == s$subject) |>
                                                          rename(t_start = onset, t_end = offset))) |>
  ungroup()
blink_trials <- fixations |> filter(region == 2, near_blink) |> distinct(subject, trial_id)
cat(nrow(blink_trials), "of", n_distinct(fixations$subject, fixations$trial_id), "trials excluded because of blinks\n")
fixations <- fixations |> anti_join(blink_trials, by = c("subject", "trial_id"))

## ---- measures-fixated
# 3. Reading measures per trial and region with fixated: first fixation duration (ffd), gaze duration (gd),
#    go-past time (gpt) and total viewing time (tvt). fixated needs one trial id across all participants.
fixations <- fixations |>
  mutate(trial = paste(subject, trial_id), start_time = t_start, end_time = t_end, avg_x = x, avg_y = y)
roi <- fixations |>
  distinct(trial, subject, trial_id, item, cond) |>
  inner_join(regions, by = "trial_id", relationship = "many-to-many") |>
  rename(word_id = region)
measures <- compute_eye_measures(fixations, roi, trial_col = "trial", eye_col = NULL, include_word_col = FALSE) |>
  left_join(distinct(roi, trial, subject, trial_id, item, cond), by = "trial") |>
  # go-past time is only defined when the region was entered in first pass (from the left); fixated also
  # computes it when the region was skipped and later entered by a regression
  mutate(gpt = if_else(is.na(gd), NA, gpt)) |>
  select(subject, item, cond, region = word_id, ffd, gd, gpt, tvt)

## ---- measures-write
write_csv(measures, file.path(dir, "measures.csv"))
cat("Wrote", nrow(measures), "rows (trials x regions) to", file.path(dir, "measures.csv"), "\n")
