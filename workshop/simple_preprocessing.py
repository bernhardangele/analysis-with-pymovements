"""The one Python step of the workshop (`workshop.qmd`): eye-tracker file -> tables for R.

For each recording (subject-N.asc) of the four experiments of the recording workshop, pymovements
  1. reads the samples, the EyeLink events and the messages; the messages that OpenSesame wrote label every
     fixation with its item and with the phase of the trial (gaze target, stimulus, after the trial),
  2. computes where each fixation was (from its samples),
  3. assigns each fixation to an interest area (the REGION messages: words or pictures),
  4. for the reading experiments, computes the reading measures per word.
Everything else (the OpenSesame log files, the other messages, cleaning, statistics) happens in R.

    cd workshop
    python3 simple_preprocessing.py

Reads data/example_data/<experiment>/subject-N.asc (the example data of the recording workshop: OpenSesame runs of
the experiments with a simulated 1000 Hz EyeLink) and writes
data/example_data/derived/<experiment>/{fixations,blinks,messages,measures}.csv.
The "## ---- name" lines mark the parts shown in the slides.
"""
## ---- py-setup
from pathlib import Path

import polars as pl
import pymovements as pm
from pymovements.measure.reading import compute_reading_measures

DATA = Path("data") / "example_data"

## ---- py-quiet
import warnings  # noqa: E402

# pymovements warns about details that an EyeLink ASC header does not contain (mount, tracker model)
warnings.filterwarnings("ignore", message="No (mount|eye tracker|recording configuration|screen resolution)")

## ---- py-patterns

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


## ---- py-load
def load(asc_file):
    """Samples, EyeLink events and messages; every event gets `item` and `phase` from the messages."""
    gaze = pm.gaze.from_asc(asc_file, patterns=PATTERNS, events=True, messages=True)
    gaze.compute_event_properties(("location", {"position_column": "pixel"}), name="fixation_eyelink")
    return gaze


## ---- py-regions
def regions(gaze):
    """The REGION messages as an interest-area table (one row per word or picture and item)."""
    messages = gaze.messages.with_columns(item=pl.col("content").str.extract(r"TRIALINFO item=(\d+)"))
    return (
        messages.with_columns(pl.col("item").forward_fill())
        .filter(pl.col("content").str.starts_with("REGION "))
        .select("item", pl.col("content").str.extract_groups(REGION).alias("r")).unnest("r")
        .with_columns(pl.col("n", "left", "top", "right", "bottom").cast(pl.Int64))
    )


## ---- py-aois
def fixations_on_regions(gaze, aois):
    """Assign each fixation to the interest area it falls into (`n`, `label`; empty = outside)."""
    gaze.events = pm.Events(gaze.events.fixations.filter(pl.col("item").is_not_null()))
    stimulus = pm.stimulus.TextStimulus(
        aois, aoi_column="n", trial_column="item",
        start_x_column="left", end_x_column="right", start_y_column="top", end_y_column="bottom",
    )
    gaze.events.map_to_aois(stimulus, verbose=False)
    return gaze.events.frame


## ---- py-measures
def word_measures(fixations, aois):
    """Reading measures per item and word, from the fixations made while the sentence was on screen
    (without very short fixations)."""
    reading = fixations.filter((pl.col("phase") == "stimulus") & (pl.col("duration") >= MIN_FIXATION_MS))
    reading = reading.sort("onset")
    return compute_reading_measures(
        reading, aois.rename({"label": "word"}), word_index_column="n", group_columns=["item"],
        event_name="fixation_eyelink",
    )


## ---- py-one
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


## ---- py-experiment
def preprocess_experiment(experiment, map=map):
    """All recordings of one experiment -> data/example_data/derived/<experiment>/<table>.csv."""
    files = sorted((DATA / experiment).glob("subject-*.asc"), key=lambda f: int(f.stem.split("-")[1]))
    results = list(map(preprocess, files, [experiment != "vwp"] * len(files)))  # no words in the VWP
    out = DATA / "derived" / experiment
    out.mkdir(parents=True, exist_ok=True)
    for name in results[0]:
        pl.concat([r[name] for r in results], how="diagonal_relaxed").write_csv(out / f"{name}.csv")
    print(f"{experiment}: {len(files)} recordings -> {out}")


## ---- py-main
def main(experiments=("reading", "boundary", "movingwindow", "vwp"), workers=4):
    from concurrent.futures import ProcessPoolExecutor
    with ProcessPoolExecutor(max_workers=workers) as pool:      # several recordings at the same time
        for experiment in experiments:
            preprocess_experiment(experiment, pool.map)


## ---- py-run
if __name__ == "__main__":
    main()
