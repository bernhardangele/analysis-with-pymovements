"""Example preprocessing for OpenSesame + PyGaze recordings (companion reading.osexp).

Demonstrates the exact bridge from the companion recording workshop
(https://github.com/bernhardangele/eye-movement-experiments-with-opensesame):
  1. Load samples, EyeLink events, and messages with `pm.gaze.from_asc` (pattern: `TRIALINFO item=...`).
  2. Extract the reading window (`STIMONSET` -> `TRIALEND`) and drop `TRIAL ABORTED` / timeout trials.
  3. Parse word AOIs (including `top`/`bottom` y-bounds) directly from `REGION` messages.
  4. Map fixations to AOIs, compute reading measures, and join the OpenSesame CSV (`reading-subject-1.csv`).

Note: `data/opensesame_example/` contains a simulated recording matching `reading.osexp` until replaced
with a lab recording. The `## ---- name` markers select chunks shown in `presentation.qmd`.
"""

## ---- os-setup
from pathlib import Path

import polars as pl
import pymovements as pm
from pymovements.measure.reading import compute_reading_measures

OS_DIR = Path("data") / "opensesame_example"


## ---- os-load
def load_opensesame_asc(asc_file):
    """Read an OpenSesame EyeLink ASC file, tagging samples and events with `item`."""
    return pm.gaze.from_asc(
        asc_file,
        patterns=[r"TRIALINFO item=(?P<item>\d+)"],
        events=True,
        messages=True,
    )


## ---- os-trials
def opensesame_trials(messages):
    """Reading window (`STIMONSET` -> `TRIALEND`) per item, excluding aborted or timed-out trials."""
    msgs = (
        messages
        .with_columns(
            time=pl.col("time").cast(pl.Int64),
            item=pl.col("content").str.extract(r"^TRIALINFO item=(\d+)").cast(pl.Int64).forward_fill(),
        )
        .filter(pl.col("item").is_not_null())
    )
    trials = msgs.group_by("item", maintain_order=True).agg(
        stim_onset=pl.col("time").filter(pl.col("content") == "STIMONSET").last(),
        trial_end=pl.col("time").filter(pl.col("content") == "TRIALEND").last(),
        aborted=pl.col("content").str.contains(r"^(TRIAL ABORTED|CORNER TIMEOUT|BOUNDARY TIMEOUT)").any(),
    )
    n_aborted = trials.filter(pl.col("aborted")).height
    if n_aborted:
        print(f"Excluded {n_aborted} aborted/timed-out trial(s) from ASC messages.")
    return trials.filter(~pl.col("aborted") & pl.col("stim_onset").is_not_null())


## ---- os-regions
def opensesame_regions(messages, valid_items):
    """Parse word AOIs (`n`, `label`, `left`, `top`, `right`, `bottom`) from `REGION` messages."""
    pattern = (
        r"^REGION n=(?P<word_nr>\d+) label=(?P<word>\S+) "
        r"left=(?P<x_start>-?\d+) top=(?P<y_start>-?\d+) "
        r"right=(?P<x_end>-?\d+) bottom=(?P<y_end>-?\d+)"
    )
    return (
        messages
        .with_columns(item=pl.col("content").str.extract(r"^TRIALINFO item=(\d+)").cast(pl.Int64).forward_fill())
        .join(valid_items.select("item"), on="item", how="inner")
        .with_columns(pl.col("content").str.extract_groups(pattern).alias("r"))
        .filter(pl.col("r").is_not_null())
        .unnest("r")
        .with_columns(
            pl.col("word_nr", "x_start", "y_start", "x_end", "y_end").cast(pl.Int64),
            pl.col("word").str.replace_all("_", " "),
        )
        .select("item", "word_nr", "word", "x_start", "y_start", "x_end", "y_end")
    )


## ---- os-measures
def opensesame_measures(gaze, csv_file, eye="right"):
    """Map EyeLink fixations for one eye to `REGION` AOIs, compute reading measures, and join OpenSesame CSV."""
    trials = opensesame_trials(gaze.messages)
    regions = opensesame_regions(gaze.messages, trials)

    fix_ev = gaze.events.frame.filter((pl.col("name") == "fixation_eyelink") & (pl.col("eye") == eye))
    assert fix_ev["eye"].n_unique() == 1, f"Expected 1 eye ({eye!r}), got {fix_ev['eye'].unique().to_list()}"
    gaze.events = pm.Events(fix_ev)
    gaze.compute_event_properties(("location", {"position_column": "pixel"}))
    stimulus = pm.stimulus.TextStimulus(
        regions, aoi_column="word_nr", trial_column="item",
        start_x_column="x_start", end_x_column="x_end",
        start_y_column="y_start", end_y_column="y_end",
    )
    gaze.events.map_to_aois(stimulus, verbose=False)

    fix = (
        gaze.events.frame
        .with_columns(pl.col("item").cast(pl.Int64))
        .join(trials, on="item", how="inner")
        .filter((pl.col("offset") > pl.col("stim_onset")) & (pl.col("onset") < pl.col("trial_end")))
        .with_columns(onset=pl.max_horizontal("onset", "stim_onset"))
        .select(
            "item", "onset", "offset",
            (pl.col("offset") - pl.col("onset")).alias("duration"),
            pl.col("location_x").alias("x"), pl.col("location_y").alias("y"), "word_nr",
        )
        .filter(pl.col("duration") >= 80)
        .sort("item", "onset")
    )
    measures = (
        compute_reading_measures(fix, regions, word_index_column="word_nr", group_columns=["item"])
        .with_columns(
            pl.col("item").cast(pl.Int64),
            FFD=pl.when(pl.col("FPF") == 1).then(pl.col("FFD")),
            FPRT=pl.when(pl.col("FPF") == 1).then(pl.col("FPRT")),
            RPD_inc=pl.when(pl.col("FPF") == 1).then(pl.col("RPD_inc")),
            TFT=pl.when(pl.col("Fix") == 1).then(pl.col("TFT")),
        )
    )
    behav = (
        pl.read_csv(csv_file)
        .filter(pl.col("trial_aborted") == 0)
        .select("item", "block", "condition", "correct")
    )
    return measures.join(behav, on="item", how="inner")


## ---- os-run
if __name__ == "__main__":
    gaze = load_opensesame_asc(OS_DIR / "subject-1.asc")
    measures = opensesame_measures(gaze, OS_DIR / "reading-subject-1.csv")
    print(measures.select("item", "condition", "word_index", "word", "FFD", "FPRT", "RPD_inc", "TFT").head(10))
