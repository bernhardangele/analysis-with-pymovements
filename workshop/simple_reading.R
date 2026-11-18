# Reading with and without commas (reading.osexp): the complete analysis in one file.
# Does a comma change how long readers look at the word before and after it?
#
#   cd workshop
#   Rscript simple_reading.R        (or run it line by line in RStudio, working directory workshop/)
#
# Input: data/example_data/reading/subject-N.csv (OpenSesame log file) and subject-N.asc (EyeLink file).
# The steps are in the order of the slides. Steps 1 and 2 need only the log files; step 3 is Python
# (pymovements, run from R with reticulate) and reads the tracker files; everything after it is R again.
# The same code as in the slides (workshop.qmd); written by tools/make_standalone.py from
# simple_preprocessing.py and simple_analysis.R: change those, not this file.

# All paths are relative to the workshop folder: stop early if R is somewhere else
if (!dir.exists("data/example_data")) {
  stop("Run this script from the workshop folder: setwd(\"~/project/workshop\") or, in RStudio,\n",
       "Session > Set Working Directory > To Source File Location. Now it is ", getwd(), call. = FALSE)
}

library(reticulate)                 # Python from R; uses the Python in RETICULATE_PYTHON
library(tidyverse)
library(lme4)
library(conflicted)                 # dplyr's filter(), not stats::filter(), even without tidyverse
conflict_prefer("filter", "dplyr")

DATA <- "data/example_data"

# All OpenSesame log files of one experiment (subject-1.csv, subject-2.csv, ...) in one table
read_log <- function(experiment) {
  list.files(file.path(DATA, experiment), pattern = "^subject-\\d+\\.csv$", full.names = TRUE) |>
    map(\(file) read_csv(file, col_types = cols(.default = "c"))) |>
    list_rbind() |>
    type_convert(col_types = cols())
}

# A table written by step 3; "subject-3" becomes subject_nr 3, as in the log file
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

# ---- Step 1: the log file (your variables) ---------------------------------------------------------------
reading_log <- read_log("reading")
dim(reading_log)                          # rows = trials of all participants, columns = variables

reading <- reading_log |>
  filter(block != "practice") |>
  select(subject_nr, item_list, item, condition, sentence_type, comma, no_comma,
         question, answer, response, correct, trial_aborted, validation_max_error)
reading |> select(subject_nr, item_list, item, condition, correct, trial_aborted) |> head(4)

# ---- Step 2: is the design what you planned? Where is the comma? -----------------------------------------
reading |> count(item_list, condition)                          # 12 + 12 here (full study: 65 + 65)
reading |> distinct(item, item_list, condition) |>              # each item: both versions
  count(item, name = "versions") |> count(versions)

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

# ---- Step 3: the tracker file -> tables (Python: pymovements) --------------------------------------------
# Messages label every fixation with its item and the phase of the trial; REGION messages give the
# interest areas; each fixation gets its interest area; reading measures per word.
# The Python code is defined here and used from R as py$...; it writes its tables as CSV files to
# data/example_data/derived/reading/, which the R steps below read with read_tracker().
py_run_string(r"---(
from pathlib import Path

import polars as pl
import pymovements as pm
from pymovements.measure.reading import compute_reading_measures

DATA = Path("data") / "example_data"


import warnings  # noqa: E402

# pymovements warns about details that an EyeLink ASC header does not contain (mount, tracker model)
warnings.filterwarnings("ignore", message="No (mount|eye tracker|recording configuration|screen resolution)")


# Messages written by OpenSesame become columns of the eye-tracking data
PATTERNS = [
    r"TRIALINFO item=(?P<item>\d+)",                                            # which item?
    {"pattern": "GAZE TARGET ON", "column": "phase", "value": "gaze target"},   # which part of the trial?
    {"pattern": "STIMONSET", "column": "phase", "value": "stimulus"},        # sentence on screen
    {"pattern": "PREVIEW_ONSET", "column": "phase", "value": "stimulus"},    # pictures on screen (VWP)
    {"pattern": "TRIALEND", "column": "phase", "value": "after trial"},
]
MIN_FIXATION_MS = 80     # shorter fixations are left out of the reading measures

# Interest areas: REGION n=3 label=elegir left=254 top=512 right=352 bottom=568
REGION = r"REGION n=(?P<n>\d+) label=(?P<label>\S+) left=(?P<left>\d+) top=(?P<top>\d+) " \
         r"right=(?P<right>\d+) bottom=(?P<bottom>\d+)"


def load(asc_file):
    """Samples, EyeLink events and messages; every event gets `item` and `phase` from the messages."""
    gaze = pm.gaze.from_asc(asc_file, patterns=PATTERNS, events=True, messages=True)
    gaze.compute_event_properties(("location", {"position_column": "pixel"}), name="fixation_eyelink")
    return gaze


def regions(gaze):
    """The REGION messages as an interest-area table (one row per word or picture and item)."""
    messages = gaze.messages.with_columns(item=pl.col("content").str.extract(r"TRIALINFO item=(\d+)"))
    return (
        messages.with_columns(pl.col("item").forward_fill())
        .filter(pl.col("content").str.starts_with("REGION "))
        .select("item", pl.col("content").str.extract_groups(REGION).alias("r")).unnest("r")
        .with_columns(pl.col("n", "left", "top", "right", "bottom").cast(pl.Int64))
    )


def fixations_on_regions(gaze, aois):
    """Assign each fixation to the interest area it falls into (`n`, `label`; empty = outside)."""
    gaze.events = pm.Events(gaze.events.fixations.filter(pl.col("item").is_not_null()))
    stimulus = pm.stimulus.TextStimulus(
        aois, aoi_column="n", trial_column="item",
        start_x_column="left", end_x_column="right", start_y_column="top", end_y_column="bottom",
    )
    gaze.events.map_to_aois(stimulus, verbose=False)
    return gaze.events.frame


def word_measures(fixations, aois):
    """Reading measures per item and word, from the fixations made while the sentence was on screen
    (without very short fixations)."""
    reading = fixations.filter((pl.col("phase") == "stimulus") & (pl.col("duration") >= MIN_FIXATION_MS))
    reading = reading.sort("onset")
    return compute_reading_measures(
        reading, aois.rename({"label": "word"}), word_index_column="n", group_columns=["item"],
        event_name="fixation_eyelink",
    )


def preprocess(asc_file, reading=True):
    """All tables for one recording; `subject` is the file name (subject-3)."""
    gaze = load(asc_file)
    blinks = gaze.events.blinks
    aois = regions(gaze)
    fixations = fixations_on_regions(gaze, aois)
    subject = pl.lit(asc_file.stem).alias("subject")
    tables = dict(
        fixations=fixations.select(subject, "item", "phase", "onset", "offset", "duration",
                                   x="location_x", y="location_y", region="n", label="label"),
        blinks=blinks.select(subject, "item", "phase", "onset", "offset", "duration"),
        messages=gaze.messages.filter(~pl.col("content").str.starts_with("LETTER "))
                              .select(subject, pl.col("time").cast(pl.Int64), "content"),
    )
    if reading:
        tables["measures"] = word_measures(fixations, aois).select(subject, pl.all())
    return tables


def preprocess_experiment(experiment, map=map):
    """All recordings of one experiment -> data/example_data/derived/<experiment>/<table>.csv."""
    files = sorted((DATA / experiment).glob("subject-*.asc"), key=lambda f: int(f.stem.split("-")[1]))
    results = list(map(preprocess, files, [experiment != "vwp"] * len(files)))  # no words in the VWP
    out = DATA / "derived" / experiment
    out.mkdir(parents=True, exist_ok=True)
    for name in results[0]:
        pl.concat([r[name] for r in results], how="diagonal_relaxed").write_csv(out / f"{name}.csv")
    print(f"{experiment}: {len(files)} recordings -> {out}")
)---")

# Takes a few seconds per recording; delete measures.csv (or the folder) to run it again
if (!file.exists(file.path(DATA, "derived", "reading", "measures.csv"))) {
  py$preprocess_experiment("reading")
}

# ---- Step 4: cleaning (participants, then trials) --------------------------------------------------------
measures <- read_tracker("reading", "measures")
fixations <- read_tracker("reading", "fixations")
blinks <- read_tracker("reading", "blinks")

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

blink_trials <- blinks |> filter(phase == "stimulus") |> distinct(subject_nr, item)
clean <- reading |>
  semi_join(filter(participants, !exclude), by = "subject_nr") |>
  filter(trial_aborted == 0) |>
  anti_join(blink_trials, by = c("subject_nr", "item"))
c(trials = nrow(reading), kept = nrow(clean), percent = round(100 * nrow(clean) / nrow(reading), 1))

# ---- Step 5: reading measures on the critical words ------------------------------------------------------
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

# ---- Step 6: means, plot, mixed model --------------------------------------------------------------------
reading_data |>
  group_by(region, condition) |>
  summarise(across(c(ffd, gd, gopast, skipped), \(v) round(mean(v, na.rm = TRUE), 2)), .groups = "drop")

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

reading_pre <- reading_data |> filter(region == "pre-comma word")
m_reading <- lmer(gd ~ condition + (1 | subject_nr) + (1 | item), data = reading_pre)
summary(m_reading)$coefficients |> round(2)
VarCorr(m_reading)                               # standard deviations of the random effects
