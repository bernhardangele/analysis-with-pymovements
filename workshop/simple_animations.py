"""Data for the animations of the workshop (`workshop.qmd`); not a step of the analysis.

Each function returns a `<div>` with the data of one trial as JSON; `assets/animations.js` (GSAP) draws
and animates it:
  samples_div   samples -> velocity -> saccades and fixations, next to the EyeLink's own events
  aoi_div       REGION messages -> word boxes -> the word of each fixation
  measures_div  the fixations of a trial in real time, with the reading measures adding up
"""
import html
import json

import numpy as np
import polars as pl
from pymovements.measure.reading import annotate_fixations

from simple_preprocessing import DATA, MIN_FIXATION_MS, fixations_on_regions, load, regions

PX_PER_DEG = 44          # the example data: ESACC reports 2.18 deg for a 96 px saccade
VELOCITY_THRESHOLD = 30  # deg/s, the EyeLink's velocity criterion for a saccade
CONTROLS = ('<div class="controls"><button class="replay">▶ replay</button>'
            '<button class="slow">▶ slow motion</button>{extra} {legend}</div>')


def _div(css_class, data, legend, extra=""):
    payload = html.escape(json.dumps(data), quote=True)
    return f'<div class="{css_class}" data-trial="{payload}">{CONTROLS.format(extra=extra, legend=legend)}</div>'


def _trial(experiment, subject, item):
    """Samples, EyeLink events, interest areas and fixations of one trial while the stimulus was shown."""
    gaze = load(DATA / experiment / f"subject-{subject}.asc")
    this = (pl.col("item") == str(item)) & (pl.col("phase") == "stimulus")
    samples, events = gaze.samples.filter(this), gaze.events.frame.filter(this)
    aois = regions(gaze)
    fixations = fixations_on_regions(gaze, aois).filter(this).sort("onset")
    aois = aois.filter(pl.col("item") == str(item))
    # the tracker file has lost the accents (label=aprobar?): take the words from the log file
    words = _log(experiment, subject, item)["sentence"][0].split() if experiment != "vwp" else []
    if len(words) == aois.height:
        aois = aois.with_columns(label=pl.Series(words))
        fixations = fixations.drop("label").join(aois.select("n", "label"), on="n", how="left")
    return samples, events, aois, fixations


def _log(experiment, subject, item):
    """The row of one item in the OpenSesame log file of one participant."""
    log = pl.read_csv(DATA / experiment / f"subject-{subject}.csv", infer_schema_length=None)
    return log.filter(pl.col("item").cast(pl.String) == str(item))


def _runs(state):
    """[(state, first, last + 1)] for each run of equal values."""
    edges = np.flatnonzero(np.r_[True, state[1:] != state[:-1], True])
    return [(state[a], int(a), int(b)) for a, b in zip(edges[:-1], edges[1:])]


def samples_div(subject=1, item=6, ms=1450, experiment="reading"):
    """The first `ms` milliseconds of a trial: gaze position, velocity, and what a velocity threshold finds."""
    samples, events, _, _ = _trial(experiment, subject, item)
    t0 = samples["time"][0]
    xy = np.array(samples["pixel"].to_list(), dtype=float)[:ms, :2]
    # velocity over 4 ms (two samples before to two samples after), in degrees per second
    velocity = np.full(len(xy), np.nan)
    velocity[2:-2] = np.hypot(*(xy[4:] - xy[:-4]).T) / 4 * 1000 / PX_PER_DEG
    velocity[[0, 1, -2, -1]] = velocity[[2, 2, -3, -3]]
    state = np.where(np.isnan(velocity), "blink", np.where(velocity > VELOCITY_THRESHOLD, "saccade", "fixation"))
    detected = [dict(type=s, t0=a, t1=b) for s, a, b in _runs(state) if s != "fixation" or b - a >= 20]
    eyelink = [dict(type=e["name"].split("_")[0], t0=max(e["onset"] - t0, 0), t1=min(e["offset"] - t0, ms))
               for e in events.iter_rows(named=True) if e["onset"] - t0 < ms]
    data = dict(
        x=[None if np.isnan(v) else round(v) for v in xy[:, 0]],
        v=[None if np.isnan(v) else round(v) for v in velocity],
        threshold=VELOCITY_THRESHOLD, detected=detected, eyelink=eyelink,
    )
    return _div("samples-anim", data, "red = saccade (velocity above the threshold), blue = fixation, grey = blink")


def aoi_div(item=6, subjects=(1, 5), names=("subject 1", "subject 5 (poor calibration)"), experiment="reading"):
    """Word boxes of one item and the fixations of one or more participants on it."""
    trials = []
    for subject, name in zip(subjects, names):
        _, _, aois, fixations = _trial(experiment, subject, item)
        fixations = fixations.filter(pl.col("location_x") < aois["right"].max() + 100)   # not the corner square
        trials.append(dict(name=name, fixations=fixations.select(
            x=pl.col("location_x").round(), y=pl.col("location_y").round(), duration="duration", n="n",
            label="label").to_dicts()))
    data = dict(regions=aois.drop("item").to_dicts(), trials=trials)
    buttons = "".join(f'<button class="trial" data-trial-index="{i}">▶ {t["name"]}</button>'
                      for i, t in enumerate(trials)) if len(trials) > 1 else ""
    return _div("aoi-anim", data, "orange = word with a fixation, red dot = outside every interest area", buttons)


def critical_word(item, experiment="reading"):
    """Number of the pre-comma word of an item (from the comma version of the sentence in the log file)."""
    words = _log(experiment, 1, item)["comma"][0].split()
    return next(i for i, w in enumerate(words, start=1) if w.endswith(","))


def measures_div(subject=1, item=6, experiment="reading"):
    """Fixations of one trial with pymovements' first-pass flag; the table shows the words around the comma."""
    _, _, aois, fixations = _trial(experiment, subject, item)
    fixations = fixations.filter((pl.col("duration") >= MIN_FIXATION_MS)
                                 & (pl.col("location_x") < aois["right"].max() + 100))
    fixations = annotate_fixations(fixations.with_columns(name=pl.lit("fixation")), word_idx="n").sort("onset")
    pre = critical_word(item, experiment)
    words = aois.with_columns(
        region="n", x_start="left", x_end="right", label=pl.format("{} {}", "n", "label"),
        critical=pl.col("n").is_in([pre, pre + 1]), table=pl.col("n").is_between(pre - 1, pre + 2),
    )
    chars = [dict(c=c, x=round(w["left"] + 7.2 + 14.4 * i - 0.8, 1))     # 14.4 px per letter (monospace)
             for w in words.iter_rows(named=True) for i, c in enumerate(w["label"].split(" ", 1)[1])]
    data = dict(
        chars=chars,
        regions=words.select("region", "x_start", "x_end", "label", "critical", "table").to_dicts(),
        fixations=fixations.select(
            x=pl.col("location_x").round(), duration="duration", region="n",
            label=pl.col("label").fill_null("no word"), first_pass=pl.col("is_first_pass").fill_null(False),
        ).to_dicts(),
    )
    return _div("scanpath-anim", data, "blue = first pass, orange = rereading; yellow = the words around the comma")
