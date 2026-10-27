"""Preprocessing of the frases-comas experiment with pymovements (workshop version).

For each participant (one ASC file), pymovements
  1. reads samples, the EyeLink fixation/blink events and the messages; a message pattern labels every sample and
     event with the trial it belongs to (TRIALID E1I39D0 = experimental trial, condition 1, item 39),
  2. computes the position of each fixation from its samples,
  3. assigns each fixation to a region of the sentence (areas of interest).

The script writes four CSV files to data/frases-comas/derived/simple/. Cleaning, reading measures and statistics
are done in R (commas_measures.R, commas_statistics.R).

    cd workshop
    python commas_preprocessing.py      # about 1-2 minutes

The "## ---- name" lines mark the parts that are shown in the slides.
"""

## ---- prep-setup
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import polars as pl
import pymovements as pm

DATA = Path("data") / "frases-comas"
ASC_DIR = DATA / "edf"
OUT = DATA / "derived" / "simple"


def allow_negative_coordinates():
    """Work around a pymovements 0.28 bug: EFIX lines with a negative x (gaze left of the screen) are dropped."""
    from pymovements.gaze._utils import _parsing_eyelink as eyelink

    num = r"(-?\d+[.]?\d*|[.])"
    eyelink.FIXATION_STOP_REGEX = (
        r"EFIX\s+(?P<eye>R|L)\s+(?P<timestamp_start>(\d+[.]?\d*))\s+"
        r"(?P<timestamp_end>(\d+[.]?\d*))\s+(?P<duration_ms>(\d+[.]?\d*))\s+"
        rf"(?P<avg_x_pix>{num})\s+(?P<avg_y_pix>{num})\s+(?P<avg_pupil>{num})\s*.*"
    )


## ---- prep-load
def load_participant(asc_file):
    """Samples, EyeLink events and messages. The pattern copies the trial id of the last TRIALID message
    (e.g. E1I39D0: experimental trial, condition 1, item 39) to all following samples and events."""
    allow_negative_coordinates()
    return pm.gaze.from_asc(
        asc_file,
        patterns=[r"TRIALID (?P<trial_id>(?P<trial_type>[A-Z])(?P<cond>\d+)I(?P<item>\d+)D\d+)"],
        events=True,
        messages=True,
    )


## ---- prep-trials
def trial_times(messages):
    """Start (DISPLAY ON) and end (ENDBUTTON: the reader pressed the button) of each trial; for the
    comprehension questions also the answer and the correct answer."""
    first_number = lambda prefix: (pl.col("content").filter(pl.col("content").str.starts_with(prefix)).first()
                                   .str.extract(r"(\d+)").cast(pl.Int64))
    return (
        messages
        .with_columns(trial_id=pl.col("content").str.extract(r"^TRIALID (\S+)").forward_fill())
        .group_by("trial_id")
        .agg(
            display_on=pl.col("time").filter(pl.col("content") == "DISPLAY ON").first().cast(pl.Int64),
            display_off=pl.col("time").filter(pl.col("content").str.starts_with("ENDBUTTON")).first().cast(pl.Int64),
            button=first_number("ENDBUTTON"),
            correct_button=first_number("QUESTION_ANSWER"),
        )
    )


## ---- prep-regions
# Sentence layout (from the REGION CHAR messages): monospaced font, 16 px per character, first character at x = 93
FIRST_CHAR_X, CHAR_WIDTH = 93, 16


def read_regions(path=ASC_DIR / "frases_c.cnt"):
    """Regions (areas of interest) per item and condition.

    Each line of the count file is: item, condition, number of regions, then the character positions where the
    regions start, and where the last one ends. Regions: 1 sentence start, 2 pre-comma, 3 post-comma 1,
    4 post-comma 2, 5 sentence end (6 = space after the sentence).
    """
    rows = []
    for line in open(path):
        values = [int(v) for v in line.split()]
        if not values:
            continue
        item, cond, n_regions, bounds = values[0], values[1], values[2], values[3:]
        for region in range(1, n_regions + 1):
            rows.append(dict(trial_id=f"E{cond}I{item}D0", region=region,
                             x_start=FIRST_CHAR_X + CHAR_WIDTH * bounds[region - 1],
                             x_end=FIRST_CHAR_X + CHAR_WIDTH * bounds[region]))
    # the calibration was horizontal only (all y = 540), so the regions span the whole screen height
    return pl.DataFrame(rows).with_columns(y_start=pl.lit(0), y_end=pl.lit(1080))


## ---- prep-fixations
def fixations_on_regions(gaze, regions):
    """EyeLink fixations with their position (mean of their samples) and the region they are in."""
    gaze.events = pm.Events(gaze.events.frame.filter(pl.col("name") == "fixation_eyelink"))
    gaze.compute_event_properties(("location", {"position_column": "pixel"}))
    stimulus = pm.stimulus.TextStimulus(
        regions, aoi_column="region", trial_column="trial_id",
        start_x_column="x_start", end_x_column="x_end", start_y_column="y_start", end_y_column="y_end",
    )
    gaze.events.map_to_aois(stimulus, verbose=False)
    return gaze.events.frame


## ---- prep-window
def reading_fixations(fixations, times):
    """Fixations of experimental trials that ended while the sentence was on screen. The fixation that was
    running when the sentence appeared is shortened to start at DISPLAY ON; the one during which the reader
    pressed the button is left out (it contains the response, not reading)."""
    return (
        fixations
        .filter(pl.col("trial_type") == "E")
        .join(times, on="trial_id")
        .filter((pl.col("offset") > pl.col("display_on")) & (pl.col("offset") <= pl.col("display_off")))
        .with_columns(onset=pl.max_horizontal("onset", "display_on"))
        .select(
            "trial_id", pl.col("item").cast(pl.Int64), pl.col("cond").cast(pl.Int64),
            "onset", "offset", (pl.col("offset") - pl.col("onset")).alias("duration"),
            pl.col("location_x").alias("x"), pl.col("location_y").alias("y"), "region",
        )
        .sort("onset")
    )


## ---- prep-participant
def preprocess(asc_file):
    gaze = load_participant(asc_file)
    events = gaze.events.frame                     # keep the blinks before selecting the fixations
    times = trial_times(gaze.messages)
    subject = pl.lit(asc_file.stem).alias("subject")
    fixations = reading_fixations(fixations_on_regions(gaze, read_regions()), times)
    blinks = events.filter((pl.col("name") == "blink_eyelink") & (pl.col("trial_type") == "E"))
    questions = times.filter(pl.col("correct_button").is_not_null())
    return dict(
        fixations=fixations.select(subject, pl.all()),
        blinks=blinks.select(subject, "trial_id", "onset", "offset"),
        questions=questions.select(subject, "trial_id", "button", "correct_button").sort("trial_id"),
    )


## ---- prep-main
def main(workers=4):
    files = sorted(ASC_DIR.glob("*.asc"))
    with ProcessPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(preprocess, files))
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ["fixations", "blinks", "questions"]:
        pl.concat([r[name] for r in results]).write_csv(OUT / f"{name}.csv")
    read_regions().write_csv(OUT / "regions.csv")
    print(f"{len(files)} participants -> {OUT}")


if __name__ == "__main__":
    main()
