"""Preprocessing of the frases-comas experiment with pymovements (workshop version).

For each participant (one ASC file), pymovements
  1. reads samples, the EyeLink fixation/blink events and the messages; a message pattern labels every sample and
     event with the trial it belongs to (TRIALID E1I39D0 = experimental trial, condition 1, item 39),
  2. computes the position of each fixation from its samples,
  3. assigns each fixation to a region of the sentence (areas of interest),
  4. after removing short fixations and trials with blinks, computes the reading measures per trial and region.

The script writes fixations.csv, measures.csv and questions.csv to data/frases-comas/derived/simple/. The
statistics are done in R (commas_statistics.R).

    cd workshop
    python commas_preprocessing.py      # about 1-2 minutes

The "## ---- name" lines mark the parts that are shown in the slides.
"""

## ---- prep-setup
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import polars as pl
import pymovements as pm
from pymovements.measure.reading import compute_reading_measures

DATA = Path("data") / "frases-comas"
ASC_DIR = DATA / "edf"
OUT = DATA / "derived" / "simple"

# --- Change these for your experiment ---
EYE = "right"
TRIAL_PATTERN = r"TRIALID (?P<trial_id>(?P<trial_type>[A-Z])(?P<cond>\d+)I(?P<item>\d+)D\d+)"
COUNT_FILE = ASC_DIR / "frases_c.cnt"
CRITICAL_REGIONS = (2, 3, 4)
EDGE_PAD_CHARS = 0.5
MIN_FIX_MS = 80
BLINK_MARGIN_MS = 100
MAX_TRIAL_MS = 20_000


def allow_negative_coordinates():
    """Work around a pymovements 0.28 bug: EFIX lines with a negative x (gaze left of the screen) are dropped."""
    from pymovements.gaze._utils import _parsing_eyelink as eyelink

    assert hasattr(eyelink, "FIXATION_STOP_REGEX"), "pymovements private regex changed; check EFIX parsing"
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
        patterns=[TRIAL_PATTERN],
        events=True,
        messages=True,
    )


## ---- prep-trials
def trial_times(messages, max_ms=MAX_TRIAL_MS):
    """Start (DISPLAY ON) and end (ENDBUTTON) of each trial's last attempt, plus question responses."""
    c = pl.col("content")
    t_msg = lambda cond: pl.col("time").filter(cond).first().cast(pl.Int64)
    n_msg = lambda p: c.filter(c.str.starts_with(p)).first().str.extract(r"(\d+)").cast(pl.Int64)
    times = (
        messages.with_columns(attempt=c.str.starts_with("TRIALID ").cum_sum(),
                              trial_id=c.str.extract(r"^TRIALID (\S+)").forward_fill())
        .filter(pl.col("trial_id").is_not_null())
        .group_by("attempt", "trial_id").agg(
            display_on=t_msg(c == "DISPLAY ON"),
            display_off=t_msg(c.str.starts_with("ENDBUTTON")),
            button=n_msg("ENDBUTTON"), correct_button=n_msg("QUESTION_ANSWER"),
        )
        .sort("attempt").group_by("trial_id").agg(pl.exclude("attempt").last(), attempts=pl.len())
    )
    bad = times.filter(
        pl.col("trial_id").str.starts_with("E") & ((pl.col("display_off") - pl.col("display_on")) > max_ms)
    )
    assert bad.is_empty(), f"Window > {max_ms} ms: {bad['trial_id'].to_list()}"
    return times


## ---- prep-layout
def asc_layout(messages):
    """Derive character x-origin, character width, and screen height from ASC messages."""
    chars = (
        messages.filter(pl.col("content").str.starts_with("REGION CHAR"))["content"]
        .str.extract_groups(r"^REGION CHAR \d+ \d+ \S+ (?P<l>\d+) \d+ (?P<r>\d+)").struct.unnest()
        .with_columns(pl.all().cast(pl.Int64))
    )
    coords = (
        messages.filter(pl.col("content").str.starts_with("GAZE_COORDS"))["content"]
        .str.extract(r"GAZE_COORDS \S+ \S+ \S+ (\S+)", 1).cast(pl.Float64)
    )
    first_x, char_w = int(chars["l"][0]), int(chars["r"][0] - chars["l"][0])
    height = int(round(coords[0])) + 1 if coords.len() and round(coords[0]) == 1079 else int(round(coords[0]))
    return first_x, char_w, height


## ---- prep-regions
def read_regions(path=COUNT_FILE, messages=None, edge_pad_chars=EDGE_PAD_CHARS):
    """Regions (areas of interest) per item and condition; outer sentence edges are padded by
    `edge_pad_chars` characters (0.5 char = 8 px) so near-edge fixations on word 1 are not dropped."""
    first_x, char_w, screen_h = asc_layout(messages) if messages is not None else (93, 16, 1080)
    pad = round(edge_pad_chars * char_w)
    rows = []
    for line in open(path):
        values = [int(v) for v in line.split()]
        if not values:
            continue
        item, cond, n_regions, bounds = values[0], values[1], values[2], values[3:]
        for region in range(1, n_regions + 1):
            x0 = first_x + char_w * bounds[region - 1] - (pad if region == 1 else 0)
            x1 = first_x + char_w * bounds[region] + (pad if region == n_regions else 0)
            rows.append(dict(trial_id=f"E{cond}I{item}D0", region=region, x_start=x0, x_end=x1))
    # the calibration was horizontal only (all y = 540), so the regions span the whole screen height
    return pl.DataFrame(rows).with_columns(y_start=pl.lit(0), y_end=pl.lit(screen_h))


## ---- prep-fixations
def fixations_on_regions(gaze, regions, eye=EYE):
    """EyeLink fixations for one eye (`eye`: `"left"` or `"right"`), their position, and their region."""
    fix = gaze.events.frame.filter((pl.col("name") == "fixation_eyelink") & (pl.col("eye") == eye))
    assert fix["eye"].n_unique() == 1, f"Expected 1 eye ({eye!r}), got {fix['eye'].unique().to_list()}"
    gaze.events = pm.Events(fix)
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


## ---- prep-clean
def remove_short_fixations(fixations, minimum=MIN_FIX_MS):
    """Drop fixations shorter than `minimum` (80 ms); merging into a nearby neighbour is an alternative.
    Interacts with detection: I-DT enforces 80 ms during detection, while EyeLink/EK detect down to 40 ms."""
    return fixations.filter(pl.col("duration") >= minimum)


def remove_blink_trials(fixations, blinks, margin=BLINK_MARGIN_MS, regions=CRITICAL_REGIONS):
    """EyeLink wraps a blink inside a saccade and distorts neighbouring fixations, so we use a 100 ms margin.
    Exclude trials with a blink-adjacent fixation on any critical region (2: pre-comma, 3-4: post-comma)."""
    near_blink = fixations.join_where(
        blinks.select(blink_onset="onset", blink_offset="offset"),
        pl.col("onset") <= pl.col("blink_offset") + margin,
        pl.col("offset") >= pl.col("blink_onset") - margin,
    )
    blink_trials = near_blink.filter(pl.col("region").is_in(regions)).select("trial_id").unique()
    return fixations.join(blink_trials, on="trial_id", how="anti")


## ---- prep-merge
def merge_short_fixations(fixations, minimum=MIN_FIX_MS, max_dist_px=16):
    """Merge fixations < `minimum` ms into the closest adjacent fixation within `max_dist_px`."""
    rows, merged = fixations.sort("trial_id", "onset").to_dicts(), []
    for i, cur in enumerate(rows):
        if cur["duration"] < minimum:
            nxt = rows[i + 1] if i + 1 < len(rows) and rows[i + 1]["trial_id"] == cur["trial_id"] else None
            prev = merged[-1] if merged and merged[-1]["trial_id"] == cur["trial_id"] else None
            cands = [nb for nb in (prev, nxt) if nb and abs(cur["x"] - nb["x"]) <= max_dist_px]
            if cands:
                min(cands, key=lambda nb: abs(cur["x"] - nb["x"]))["duration"] += cur["duration"]
                continue
        merged.append(cur)
    return pl.DataFrame(merged, schema=fixations.schema).filter(pl.col("duration") >= minimum)


## ---- prep-measures
def region_measures(fixations, regions):
    """Reading measures per trial and region with pymovements. pymovements gives 0 for a region that was not
    fixated (in first pass); we turn these into missing values."""
    aois = (
        regions.join(fixations.select("trial_id").unique(), on="trial_id")
        .with_columns(word=pl.col("region").cast(pl.String))   # a text column is required
    )
    measures = compute_reading_measures(
        fixations.sort("onset"), aois, word_index_column="region", group_columns=["trial_id"],
    )
    first_pass = pl.col("FPF") == 1
    return measures.join(fixations.select("trial_id", "item", "cond").unique(), on="trial_id").select(
        "trial_id", "item", "cond", region="word_index",
        ffd=pl.when(first_pass).then("FFD"),       # first fixation duration
        gd=pl.when(first_pass).then("FPRT"),       # gaze duration = first-pass reading time
        gpt=pl.when(first_pass).then("RPD_inc"),   # go-past time = regression-path duration
        tvt=pl.when(pl.col("Fix") == 1).then("TFT"),  # total viewing time
        fpf=pl.col("FPF"),                         # 1 = fixated in first pass, 0 = skipped
        fpreg=pl.when(first_pass).then("FPReg"),   # 1 = regression out in first pass
    ).sort("trial_id", "region")


## ---- prep-summary
def summarize_participant(asc_file, messages, times, raw_fix, fixations, clean):
    """Data-quality and exclusion summary row for one participant."""
    val = (
        messages.filter(pl.col("content").str.contains(r"VALIDATION.*ERROR"))["content"]
        .str.extract_groups(r"ERROR (?P<avg>[\d.]+) avg\. (?P<max>[\d.]+) max").struct.unnest()
        .with_columns(pl.all().cast(pl.Float64))
    )
    exp = times.filter(pl.col("trial_id").str.starts_with("E"))
    valid = exp.filter(pl.col("display_on").is_not_null() & pl.col("display_off").is_not_null())
    kept = clean.select("trial_id", "cond").unique()
    return pl.DataFrame({
        "subject": asc_file.stem,
        "val_avg": round(val["avg"].mean(), 2) if val.height else None,
        "val_max": round(val["max"].max(), 2) if val.height else None,
        "trials_found": exp.height,
        "trials_repeated": exp.filter(pl.col("attempts") > 1).height,
        "trials_no_window": exp.height - valid.height,
        "trials_empty": valid.height - fixations["trial_id"].n_unique(),
        "trials_blink": fixations["trial_id"].n_unique() - kept.height,
        "trials_kept": kept.height,
        "cond1_kept": kept.filter(pl.col("cond") == 1).height,
        "cond2_kept": kept.filter(pl.col("cond") == 2).height,
        "fix_total": raw_fix.height,
        "fix_short": raw_fix.height - fixations.height,
        "fix_off_text": fixations.filter(pl.col("region").is_null()).height,
    })


## ---- prep-participant
def preprocess(asc_file):
    gaze = load_participant(asc_file)
    blinks = gaze.events.frame.filter(pl.col("name") == "blink_eyelink")   # before only fixations are kept
    times = trial_times(gaze.messages)
    regions = read_regions(messages=gaze.messages)
    raw_fix = reading_fixations(fixations_on_regions(gaze, regions), times)
    fixations = remove_short_fixations(raw_fix)
    clean = remove_blink_trials(fixations, blinks)
    subject = pl.lit(asc_file.stem).alias("subject")
    questions = times.filter(pl.col("correct_button").is_not_null())
    return dict(
        fixations=clean.select(subject, pl.all()),
        measures=region_measures(clean, regions).select(subject, pl.all()),
        questions=questions.select(subject, "trial_id", "button", "correct_button").sort("trial_id"),
        summary=summarize_participant(asc_file, gaze.messages, times, raw_fix, fixations, clean),
    )


## ---- prep-main
def main(workers=4):
    assert ASC_DIR.exists(), f"Missing {ASC_DIR} — run from workshop/"
    files = sorted(ASC_DIR.glob("*.asc"))
    with ProcessPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(preprocess, files))
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ["fixations", "measures", "questions"]:
        pl.concat([r[name] for r in results]).write_csv(OUT / f"{name}.csv")
    all_sum = pl.concat([r["summary"] for r in results])
    all_sum.write_csv(OUT / "summary.csv")
    totals = all_sum.select(pl.col("^trials_.*$"), pl.col("^fix_.*$")).sum()
    print(f"{len(files)} participants -> {OUT}; {all_sum.filter(pl.col('val_max') > 1.0).height} with val_max > 1.0 deg")
    print(totals)


if __name__ == "__main__":
    main()
