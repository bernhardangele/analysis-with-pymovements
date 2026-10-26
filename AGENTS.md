# AGENTS.md

## Repository
Workshop material: analysing reading (and visual-world) eye-tracking data with
[pymovements](https://github.com/pymovements/pymovements) (Python) and
[fixated](https://github.com/bernhardangele/fixated) / tidyverse / lme4 (R). See `plan.md` for open work.

| Path | Purpose |
|---|---|
| `workshop/presentation.qmd` | Quarto revealjs presentation; Python (reticulate) and R chunks in one document, `engine: knitr` |
| `workshop/data/sub_1_example.asc` | Real binocular EyeLink recording (4 Spanish sentences, 1000 Hz), copied from `fixated/inst/extdata` |
| `Dockerfile`, `docker-compose.yml` | Image based on `bangele1/analysis-in-a-box-rocker` (R, RStudio, Quarto) plus a Python venv at `/opt/venv` |
| `install_r_packages.R` | Installs missing R packages (CRAN, GitHub fallback) and `fixated` from GitHub |
| `requirements.txt` | Python packages (pymovements, polars, pandas, pyarrow, matplotlib) |

## What has been done
- Image builds; `quarto render workshop/presentation.qmd` works inside it.
- Pipeline: `pm.gaze.from_asc` -> trials, display window and word boundaries parsed from ASC messages ->
  pix2deg / velocity -> fixation detection with I-DT and Engbert & Kliegl (`pm.events.microsaccades` + `pm.events.fill`),
  compared with EyeLink's own fixations -> hand-over to R via `py$` -> `fixated::compute_eye_measures`.
- Analyses: reading measures per algorithm, word length and word frequency (SUBTLEX-ESP Zipf) mixed models, time-course plot.
- Not done: `fixated` plotting (`plot_trial`, Shiny viewers) and most other `fixated` functions; see `plan.md`.

## How to work here
- Build: `docker build -t workshop .` (about 5 min, image ~16 GB).
- Render check (do not write into the bind mount unintentionally):
  `docker run --rm -v $PWD/workshop:/out workshop bash -c 'cp -r /out /tmp/ws && cd /tmp/ws && quarto render presentation.qmd'`
- Always verify changes by rendering; chunks run real code.
- No network to CRAN may be available; GitHub is reachable. OSF is not reachable from some sandboxes.

## Gotchas
- Python/pymovements 0.28: `compute_event_properties(("location", {"position_column": "pixel"}))` takes a tuple, not kwargs.
  `from_asc(..., messages=True)` gives `gaze.messages` (`time` is float; cast to Int64). Samples are binocular:
  `pixel = [xL, yL, xR, yR]`. There is no built-in EK fixation detector: detect saccades per trial, then `pm.events.fill`.
- polars: `join_where` for range joins; `extract_groups` for regex parsing.
- R/fixated: `compute_eye_measures(fixations, roi, trial_col=, eye_col=)` needs `start_time`, `end_time`, `duration`,
  `avg_x`, `avg_y` and an ROI table with `trial, word_id, x_start, x_end, y_start, y_end`.
- The ASC file has lost accents (`Ser?`); frequency lookup resolves `?` to the most frequent accented form.
- SUBTLEX-ESP is CC BY-NC: downloaded at build time to `/opt/data` (env `SUBTLEX_ESP`), not committed.
  `/opt/data` is outside `workshop/` because the compose bind mount hides files baked into that folder.
- Do not commit rendered `presentation.html`.
