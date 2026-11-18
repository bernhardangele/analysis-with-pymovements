# R part of the workshop (workshop.qmd): from the OpenSesame log files and the tables written by
# simple_preprocessing.py to cleaned data, plots and one mixed model per experiment.
#
#   cd workshop
#   python3 simple_preprocessing.py     # once: data/example_data/*/subject-*.asc -> data/example_data/derived/
#   Rscript simple_analysis.R
#
# The "## ---- name" lines mark the parts shown in the slides.

## ---- r-setup
library(tidyverse)
library(lme4)

DATA <- "data/example_data"

# All OpenSesame log files of one experiment (subject-1.csv, subject-2.csv, ...) in one table
read_log <- function(experiment) {
  list.files(file.path(DATA, experiment), pattern = "^subject-\\d+\\.csv$", full.names = TRUE) |>
    map(\(file) read_csv(file, col_types = cols(.default = "c"))) |>
    list_rbind() |>
    type_convert(col_types = cols())
}

# A table written by simple_preprocessing.py; "subject-3" becomes subject_nr 3, as in the log file
read_tracker <- function(experiment, table) {
  read_csv(file.path(DATA, "derived", experiment, paste0(table, ".csv")), show_col_types = FALSE) |>
    mutate(subject_nr = as.integer(str_extract(subject, "\\d+")), .before = 1) |>
    select(-subject)
}

# Messages with the item they belong to (the last TRIALINFO before them)
read_messages <- function(experiment) {
  read_tracker(experiment, "messages") |>
    mutate(item = as.integer(str_match(content, "^TRIALINFO item=(\\d+)")[, 2])) |>
    group_by(subject_nr) |>
    fill(item) |>
    ungroup()
}

## ---- r-reading-log
reading_log <- read_log("reading")
dim(reading_log)                          # rows = trials of all participants, columns = variables

## ---- r-reading-select
reading <- reading_log |>
  filter(block != "practice") |>
  select(subject_nr, item_list, item, condition, sentence_type, comma, no_comma,
         question, answer, response, correct, trial_aborted, validation_max_error)
reading |> select(subject_nr, item_list, item, condition, correct, trial_aborted) |> head(4)

## ---- r-reading-design
reading |> count(item_list, condition)                          # 12 + 12 here (full study: 65 + 65)
reading |> distinct(item, item_list, condition) |>              # each item: both versions
  count(item, name = "versions") |> count(versions)

## ---- r-reading-critical
# The word before the comma: the word that ends in "," in `comma` but not in `no_comma`
precomma_word <- function(comma, no_comma) {
  a <- str_split_1(comma, " ")
  b <- str_split_1(no_comma, " ")
  which(str_ends(a, ",") & !str_ends(b, ","))[1]
}
critical <- reading |>
  distinct(item, comma, no_comma) |>
  mutate(precomma = map2_int(comma, no_comma, precomma_word)) |>
  select(item, precomma)
critical |> head(3)

## ---- r-reading-tracker
measures <- read_tracker("reading", "measures")
fixations <- read_tracker("reading", "fixations")
blinks <- read_tracker("reading", "blinks")

## ---- r-reading-participants
on_text <- fixations |>
  filter(phase == "stimulus", x < 1700) |>               # not the corner square at the end
  group_by(subject_nr) |>
  summarise(on_text = mean(!is.na(region)))
participants <- reading |>
  group_by(subject_nr) |>
  summarise(validation = first(validation_max_error), accuracy = mean(correct, na.rm = TRUE),
            aborted = sum(trial_aborted)) |>
  left_join(on_text, by = "subject_nr") |>
  mutate(exclude = validation > 1 | accuracy < 0.75)
participants |> arrange(desc(exclude), subject_nr) |> head(6)

## ---- r-reading-trials
blink_trials <- blinks |> filter(phase == "stimulus") |> distinct(subject_nr, item)
clean <- reading |>
  semi_join(filter(participants, !exclude), by = "subject_nr") |>
  filter(trial_aborted == 0) |>
  anti_join(blink_trials, by = c("subject_nr", "item"))
c(trials = nrow(reading), kept = nrow(clean), percent = round(100 * nrow(clean) / nrow(reading), 1))

## ---- r-reading-measures
words <- measures |>
  rename(word_nr = word_index) |>
  inner_join(critical, by = "item") |>
  mutate(region = case_when(word_nr == precomma ~ "pre-comma word",
                            word_nr == precomma + 1 ~ "post-comma word")) |>
  mutate(ffd = if_else(FPF == 1, FFD, NA),         # first fixation duration
         gd = if_else(FPF == 1, FPRT, NA),         # gaze duration (first-pass reading time)
         gopast = if_else(FPF == 1, RPD_inc, NA),  # go-past time
         tvt = if_else(Fix == 1, TFT, NA),         # total viewing time
         skipped = 1 - FPF)
sentence_time <- words |> group_by(subject_nr, item) |> summarise(sentence = sum(TFT), .groups = "drop")
reading_data <- clean |>
  inner_join(filter(words, !is.na(region)), by = c("subject_nr", "item")) |>
  select(subject_nr, item, condition, region, word, ffd, gd, gopast, tvt, skipped) |>
  mutate(condition = factor(condition, c("no_comma", "comma"))) |>
  left_join(sentence_time, by = c("subject_nr", "item"))
reading_data |> head(4)

## ---- r-reading-means
reading_data |>
  group_by(region, condition) |>
  summarise(across(c(ffd, gd, gopast, skipped), \(v) round(mean(v, na.rm = TRUE), 2)), .groups = "drop")

## ---- r-reading-plot
reading_data |>
  pivot_longer(c(ffd, gd, gopast), names_to = "measure", values_to = "ms") |>
  mutate(measure = factor(measure, c("ffd", "gd", "gopast"),
                          c("first fixation", "gaze duration", "go-past time")),
         region = fct_rev(region)) |>
  group_by(subject_nr, region, measure, condition) |>
  summarise(ms = mean(ms, na.rm = TRUE), .groups = "drop") |>
  ggplot(aes(condition, ms, colour = condition)) +
  stat_summary(fun.data = mean_se, size = 0.6, linewidth = 1) +
  facet_grid(measure ~ region, scales = "free_y") +
  labs(x = NULL, y = "ms (mean ± SE over participants)") +
  theme_minimal(base_size = 15) + theme(legend.position = "none")

## ---- r-reading-model
reading_pre <- reading_data |> filter(region == "pre-comma word")
m_reading <- lmer(gd ~ condition + (1 | subject_nr) + (1 | item), data = reading_pre)
summary(m_reading)$coefficients |> round(2)
VarCorr(m_reading)                               # standard deviations of the random effects

## ---- r-boundary-log
boundary <- read_log("boundary") |>
  filter(block != "practice") |>
  select(subject_nr, subject_parity, block_order, block, item, preview_condition, target_word_nr,
         display_changed, display_change_draw_duration, correct, trial_aborted, validation_max_error)
boundary |> count(subject_parity, block_order, preview_condition) |>
  pivot_wider(names_from = preview_condition, values_from = n)

## ---- r-boundary-change
changes <- read_messages("boundary") |>
  filter(str_starts(content, "DISPLAYCHANGE")) |>
  select(subject_nr, item, change = time)
boundary_fix <- read_tracker("boundary", "fixations") |> filter(phase == "stimulus")
# The display has to change during a saccade: find the trials where it changed during a fixation
late <- boundary_fix |>
  inner_join(changes, by = join_by(subject_nr, item, onset <= change, offset >= change)) |>
  distinct(subject_nr, item) |>
  mutate(late = TRUE)
display <- boundary |>
  left_join(late, by = c("subject_nr", "item")) |>
  mutate(late = replace_na(late, FALSE))
display |>
  group_by(subject_nr) |>
  summarise(draw_ms = mean(display_change_draw_duration, na.rm = TRUE), late = mean(late)) |>
  arrange(desc(late)) |> head(4)

## ---- r-boundary-clean
boundary_blinks <- read_tracker("boundary", "blinks") |>
  filter(phase == "stimulus") |>
  distinct(subject_nr, item)
boundary_clean <- display |>
  filter(validation_max_error <= 1, trial_aborted == 0, display_changed == 1, !late) |>
  anti_join(boundary_blinks, by = c("subject_nr", "item"))
c(trials = nrow(boundary), kept = nrow(boundary_clean))

## ---- r-boundary-measures
target <- read_tracker("boundary", "measures") |>
  inner_join(boundary_clean, by = join_by(subject_nr, item, word_index == target_word_nr)) |>
  mutate(ffd = if_else(FPF == 1, FFD, NA), gd = if_else(FPF == 1, FPRT, NA), skipped = 1 - FPF,
         preview = factor(preview_condition, c("identical", "dissimilar")))
target |>
  group_by(preview) |>
  summarise(across(c(ffd, gd, skipped), \(v) round(mean(v, na.rm = TRUE), 2)), n = n())

## ---- r-boundary-model
m_boundary <- lmer(gd ~ preview + (1 | subject_nr) + (1 | item), data = target)
summary(m_boundary)$coefficients |> round(2)
VarCorr(m_boundary)                               # standard deviations of the random effects

## ---- r-mw-log
mw <- read_log("movingwindow") |>
  select(subject_nr, item_list, item, version, window, condition, sentence, correct, trial_aborted,
         validation_max_error) |>
  mutate(window = factor(window, c(12, 4), c("12 letters", "4 letters")))
mw |> count(item_list, item, condition) |>
  pivot_wider(names_from = item, values_from = condition, names_prefix = "item ", id_cols = item_list)

## ---- r-mw-measures
mw_fix <- read_tracker("movingwindow", "fixations") |>
  filter(phase == "stimulus", !is.na(region), duration >= 80)
mw_blinks <- read_tracker("movingwindow", "blinks") |>
  filter(phase == "stimulus") |>
  distinct(subject_nr, item)
per_trial <- mw_fix |>
  group_by(subject_nr, item) |>
  summarise(fixations = n(), mean_fix = mean(duration), reading_time = sum(duration),
            saccade_letters = mean(diff(x)[diff(x) > 0]) / 14.4, .groups = "drop")
mw_data <- mw |>
  filter(trial_aborted == 0, validation_max_error <= 1) |>
  anti_join(mw_blinks, by = c("subject_nr", "item")) |>
  inner_join(per_trial, by = c("subject_nr", "item"))
mw_data |>
  group_by(window) |>
  summarise(across(c(fixations, mean_fix, reading_time, saccade_letters), \(v) round(mean(v), 1)), n = n())

## ---- r-mw-plot
mw_data |>
  pivot_longer(c(mean_fix, saccade_letters, reading_time), names_to = "measure") |>
  mutate(measure = factor(measure, c("mean_fix", "saccade_letters", "reading_time"),
                          c("fixation duration (ms)", "forward saccade (letters)", "reading time (ms)"))) |>
  ggplot(aes(window, value, colour = version)) +
  stat_summary(fun.data = mean_se, position = position_dodge(0.3), size = 0.6, linewidth = 1) +
  facet_wrap(~measure, scales = "free_y") +
  labs(x = "window (letters visible on each side)", y = "mean ± SE", colour = "version") +
  theme_minimal(base_size = 15)

## ---- r-mw-model
m_mw <- lmer(mean_fix ~ window + version + (1 | subject_nr) + (1 | item), data = mw_data)
summary(m_mw)$coefficients |> round(2)
VarCorr(m_mw)                               # standard deviations of the random effects

## ---- r-vwp-log
vwp <- read_log("vwp") |>
  select(subject_nr, item, target, competitor, distractor1, distractor2, object_order,
         clicked, click_correct, click_rt, validation_max_error)
vwp |> select(item, target, competitor, distractor1, distractor2, clicked, click_rt) |> head(3)

## ---- r-vwp-time0
# Time 0 = the start of the target word: AUDIO_ONSET + target_onset (TARGET_ONSET can be a few ms late)
time0 <- read_messages("vwp") |>
  filter(str_starts(content, "AUDIO_ONSET")) |>
  mutate(t0 = time + as.integer(str_match(content, "target_onset=(\\d+)")[, 2])) |>
  select(subject_nr, item, t0)
time0 |> head(3)

## ---- r-vwp-trackloss
trial_ms <- read_messages("vwp") |>
  filter(str_detect(content, "^(PREVIEW_ONSET|TRIALEND)")) |>
  group_by(subject_nr, item) |>
  summarise(trial_ms = diff(range(time)), .groups = "drop")
track_loss <- read_tracker("vwp", "blinks") |>
  filter(phase == "stimulus") |>
  group_by(subject_nr, item) |>
  summarise(missing_ms = sum(duration), .groups = "drop") |>
  right_join(trial_ms, by = c("subject_nr", "item")) |>
  mutate(missing = replace_na(missing_ms, 0) / trial_ms) |>
  group_by(subject_nr) |>
  summarise(missing = mean(missing))
track_loss |> arrange(desc(missing)) |> head(3)

## ---- r-vwp-clean
vwp_clean <- vwp |>
  semi_join(filter(track_loss, missing < 0.1), by = "subject_nr") |>
  filter(click_correct == 1, validation_max_error <= 1)
c(trials = nrow(vwp), kept = nrow(vwp_clean))

## ---- r-vwp-bins
looks <- read_tracker("vwp", "fixations") |>
  filter(phase == "stimulus") |>
  inner_join(time0, by = c("subject_nr", "item")) |>
  inner_join(vwp_clean, by = c("subject_nr", "item")) |>
  mutate(onset = onset - t0, offset = offset - t0,
         object = case_when(label == target ~ "target", label == competitor ~ "competitor",
                            label %in% c(distractor1, distractor2) ~ "distractor"))
# Which object was fixated at -200, -180, ..., 1000 ms? (until the click)
bins <- vwp_clean |>
  select(subject_nr, item, click_rt) |>
  cross_join(tibble(time = seq(-200, 1000, by = 20))) |>
  filter(time < click_rt) |>
  left_join(looks |> select(subject_nr, item, onset, offset, object),
            by = join_by(subject_nr, item, between(time, onset, offset))) |>
  mutate(object = replace_na(object, "elsewhere"))
bins |> head(3)

## ---- r-vwp-plot
bins |>
  group_by(time) |>
  summarise(target = mean(object == "target"), competitor = mean(object == "competitor"),
            distractor = mean(object == "distractor") / 2) |>              # two distractors: per picture
  pivot_longer(-time, names_to = "object", values_to = "proportion") |>
  ggplot(aes(time, proportion, colour = object)) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_line(linewidth = 1.2) +
  labs(x = "time from target word onset (ms)", y = "proportion of trials fixating") +
  theme_minimal(base_size = 15)

## ---- r-vwp-model
vwp_window <- bins |>
  filter(between(time, 200, 800)) |>
  group_by(subject_nr, item) |>
  summarise(competitor = mean(object == "competitor"), distractor = mean(object == "distractor") / 2,
            .groups = "drop") |>
  pivot_longer(c(competitor, distractor), names_to = "object", values_to = "proportion") |>
  mutate(object = factor(object, c("distractor", "competitor")))
# Only 8 items: their variance cannot be estimated (singular fit), so items get no random effect here
m_vwp <- lmer(proportion ~ object + (1 | subject_nr), data = vwp_window)
summary(m_vwp)$coefficients |> round(3)
VarCorr(m_vwp)
