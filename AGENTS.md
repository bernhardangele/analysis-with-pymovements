# AGENTS.md

## Repository
Workshop material: analysing reading (and visual-world) eye-tracking data with
[pymovements](https://github.com/pymovements/pymovements) (Python) and
[fixated](https://github.com/bernhardangele/fixated) / tidyverse / lme4 (R). See `plan.md` for open work.

| Path | Purpose |
|---|---|
| `workshop/presentation.qmd` | Quarto revealjs presentation; Python (reticulate) and R chunks in one document, `engine: knitr` |
| `workshop/data/sub_1_example.asc` | Real binocular EyeLink recording (4 Spanish sentences, 1000 Hz), copied from `fixated/inst/extdata` |
| `workshop/data/frases-comas/` | Angele et al. comma experiment: 30 ASC files (UMass EyeTrack), original `.da1`/`.IXS`, Tim10drop.pl, manuscript |
| `tools/replication/frases_comas.py` | Not part of the workshop: exact Python ports of Tim10drop.pl and EyeDry, used to explain the differences to the paper |
| `workshop/commas_preprocessing.py`, `commas_measures.R`, `commas_statistics.R` | Part 2 of the slides: analysis of frases-comas (pymovements + fixated + lme4); differences to the paper in `commas_README.md` |
| `sources/eyedry.c`, `tools/eyedry/` | EyeDry source; `run_eyedry.sh` compiles it and reruns the paper's analyses |
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
- frases-comas: Part 2 of the slides shows the code of the `commas_*` scripts via `knitr::read_chunk` ("## ---- name"
  sections); keep labels in sync. The slides run `commas_preprocessing.py` if
  `workshop/data/frases-comas/derived/simple/fixations.csv` is missing (~1.5 min); delete that folder after changing
  the script. Paths are relative to `workshop/`. pymovements 0.28 drops `EFIX` lines with negative coordinates
  unless the regex is patched (`allow_negative_coordinates()`).
- EyeDry reads past the end of `.da1` lines when column 8 exceeds the fixations on the line ("phantom" fixations);
  the published IXS contain them. `eyedry_read_fixations(overrun=True)` reproduces this.
