"""Visual world paradigm (VWP) preprocessing matching companion `vwp.osexp`.

Time-locks gaze samples to `TARGET_ONSET` (the spoken target word), maps gaze onto the four picture
`REGION`s (target, competitor, distractors) joined from `vwp-subject-1.csv`, and computes the proportion
of each 50 ms bin spent fixating each role across running trials.
"""

from pathlib import Path
import polars as pl
import pymovements as pm


## ---- vwp-prep
def vwp_regions(asc_file, csv_file):
    """Parse picture REGION boxes and join target/competitor/distractor roles from CSV."""
    gaze = pm.gaze.from_asc(asc_file, patterns=[r"TRIALINFO item=(?P<item>\d+)"], messages=True)
    msgs = gaze.messages.with_columns(
        time=pl.col("time").cast(pl.Int64),
        item=pl.col("content").str.extract(r"^TRIALINFO item=(\d+)").cast(pl.Int64).forward_fill(),
    ).filter(pl.col("item").is_not_null())
    windows = msgs.group_by("item", maintain_order=True).agg(
        target_onset=pl.col("time").filter(pl.col("content") == "TARGET_ONSET").last(),
        trial_end=pl.col("time").filter(pl.col("content") == "TRIALEND").last(),
        aborted=pl.col("content").str.contains(r"^(TRIAL ABORTED|CLICK TIMEOUT)").any(),
    ).filter(~pl.col("aborted") & pl.col("target_onset").is_not_null())
    roles = (
        pl.read_csv(csv_file).filter(pl.col("trial_aborted") == 0)
        .select("item", "target", "competitor", "distractor1", "distractor2")
        .unpivot(index="item", variable_name="role", value_name="label")
        .with_columns(role=pl.col("role").str.replace(r"\d+$", ""))
    )
    pat = (r"^REGION n=\d+ label=(?P<label>\S+) left=(?P<x_start>-?\d+) "
           r"top=(?P<y_start>-?\d+) right=(?P<x_end>-?\d+) bottom=(?P<y_end>-?\d+)")
    regions = (
        msgs.with_columns(pl.col("content").str.extract_groups(pat).alias("r")).filter(pl.col("r").is_not_null())
        .unnest("r").with_columns(pl.col("x_start", "y_start", "x_end", "y_end").cast(pl.Int64))
        .join(roles, on=["item", "label"])
    )
    return gaze, windows, regions


## ---- vwp-bin
def vwp_timecourse(asc_file, csv_file, bin_ms=50, start_ms=-200, end_ms=900):
    """Proportion of each `bin_ms` bin spent on target, competitor, and distractors around TARGET_ONSET."""
    gaze, windows, regions = vwp_regions(asc_file, csv_file)
    samples = (
        gaze.samples.with_columns(
            item=pl.col("item").cast(pl.Int64),
            x=pl.col("pixel").list.get(0), y=pl.col("pixel").list.get(1),
        ).join(windows, on="item", how="inner")
        .filter(pl.col("time").is_between(pl.col("target_onset") + start_ms, pl.col("trial_end")))
        .with_columns(bin=((pl.col("time") - pl.col("target_onset")) // bin_ms) * bin_ms)
        .filter(pl.col("bin").is_between(start_ms, end_ms))
    )
    on_aoi = samples.join(regions, on="item", how="left").filter(
        pl.col("x").is_between(pl.col("x_start"), pl.col("x_end"))
        & pl.col("y").is_between(pl.col("y_start"), pl.col("y_end"))
    ).select("item", "time", "bin", "role")
    grid = samples.group_by("bin").agg(n_samples=pl.len()).join(
        pl.DataFrame({"role": ["target", "competitor", "distractor"], "n_obj": [1, 1, 2]}), how="cross"
    )
    return (
        grid.join(on_aoi.group_by("bin", "role").agg(n=pl.len()), on=["bin", "role"], how="left")
        .with_columns(prop=pl.col("n").fill_null(0) / (pl.col("n_samples") * pl.col("n_obj")))
        .select("bin", "role", "n_samples", "prop").sort("bin", "role")
    )


## ---- vwp-main
if __name__ == "__main__":
    vwp_dir = Path("..") / "data" / "opensesame_example"
    tc = vwp_timecourse(vwp_dir / "vwp-subject-1.asc", vwp_dir / "vwp-subject-1.csv")
    print(tc.head(12))
