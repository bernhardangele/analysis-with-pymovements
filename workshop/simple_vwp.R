# The visual world (vwp.osexp): the complete analysis in one file.
# Do listeners look at the competitor (candy) while they hear the target (candle)?
#
#   cd workshop
#   Rscript simple_vwp.R        (or run it line by line in RStudio, working directory workshop/)
#
# Input: data/example_data/vwp/subject-N.csv (OpenSesame log file) and subject-N.asc (EyeLink file).
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

# ---- Step 1: which picture is which? ---------------------------------------------------------------------
vwp <- read_log("vwp") |>
  select(subject_nr, item, target, competitor, distractor1, distractor2, object_order,
         clicked, click_correct, click_rt, validation_max_error)
vwp |> select(item, target, competitor, distractor1, distractor2, clicked, click_rt) |> head(3)

# ---- Step 3: the tracker file -> tables (Python: pymovements) --------------------------------------------
# Messages label every fixation with its item and the phase of the trial; REGION messages give the
# interest areas; each fixation gets its interest area.
# The Python code is defined here and used from R as py$...; it writes its tables as CSV files to
# data/example_data/derived/vwp/, which the R steps below read with read_tracker().
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

# Takes a few seconds per recording; delete fixations.csv (or the folder) to run it again
if (!file.exists(file.path(DATA, "derived", "vwp", "fixations.csv"))) {
  py$preprocess_experiment("vwp")
}

# ---- Step 3 (continued): time zero = the start of the target word ----------------------------------------
# Time 0 = the start of the target word: AUDIO_ONSET + target_onset (TARGET_ONSET can be a few ms late)
time0 <- read_messages("vwp") |>
  filter(str_starts(content, "AUDIO_ONSET")) |>
  mutate(t0 = time + as.integer(str_match(content, "target_onset=(\\d+)")[, 2])) |>
  select(subject_nr, item, t0)
time0 |> head(3)

# ---- Step 4: cleaning (track loss, wrong clicks) ---------------------------------------------------------
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

vwp_clean <- vwp |>
  semi_join(filter(track_loss, missing < 0.1), by = "subject_nr") |>
  filter(click_correct == 1, validation_max_error <= 1)
c(trials = nrow(vwp), kept = nrow(vwp_clean))

# ---- Step 5: which picture was fixated, every 20 ms? -----------------------------------------------------
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

# ---- Step 6: plot, mixed model ---------------------------------------------------------------------------
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
