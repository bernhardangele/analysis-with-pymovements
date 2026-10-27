# AGENTS.md

## Repository
Workshop material: analysing reading (and visual-world) eye-tracking data with
[pymovements](https://github.com/pymovements/pymovements) (Python) and tidyverse / lme4 (R). See `plan.md` for open work.
Participants should use pymovements wherever it can do the job (including reading measures); R is for plots and
statistics. Do not use the R package `fixated` (maintained by one person only).

| Path | Purpose |
|---|---|
| `workshop/presentation.qmd` | Quarto revealjs presentation; Python (reticulate) and R chunks in one document, `engine: knitr` |
| `workshop/data/sub_1_example.asc` | Real binocular EyeLink recording (4 Spanish sentences, 1000 Hz), copied from `fixated/inst/extdata` |
| `workshop/data/frases-comas/` | Angele et al. comma experiment: 30 ASC files (UMass EyeTrack), original `.da1`/`.IXS`, Tim10drop.pl, manuscript |
| `tools/replication/frases_comas.py` | Not part of the workshop: exact Python ports of Tim10drop.pl and EyeDry, used to explain the differences to the paper |
| `workshop/commas_preprocessing.py`, `commas_statistics.R` | Part 2 of the slides: analysis of frases-comas (pymovements, then lme4); differences to the paper in `commas_README.md` |
| `sources/eyedry.c`, `tools/eyedry/` | EyeDry source; `run_eyedry.sh` compiles it and reruns the paper's analyses |
| `Dockerfile`, `docker-compose.yml` | Image based on `bangele1/analysis-in-a-box-rocker` (R, RStudio, Quarto) plus a Python venv at `/opt/venv` |
| `install_r_packages.R` | Installs missing R packages (CRAN, GitHub fallback) |
| `requirements.txt` | Python packages (pymovements, polars, pandas, pyarrow, matplotlib) |

## What has been done
- `quarto render workshop/presentation.qmd` works inside the container.
- Part 1 (one recording, `data/sub_1_example.asc`): `pm.gaze.from_asc` -> trials, display window and word boundaries
  parsed from ASC messages -> pix2deg / velocity -> fixation detection with I-DT and Engbert & Kliegl
  (`pm.events.microsaccades` + `pm.events.fill`), compared with EyeLink's own fixations -> `TextStimulus` +
  `Events.map_to_aois` -> `compute_reading_measures` -> hand-over to R via `py$`; word length / frequency
  (SUBTLEX-ESP Zipf) mixed models, time-course plot.
- Part 2 (frases-comas, 30 participants): `commas_preprocessing.py` (pymovements: message pattern, EyeLink events,
  `compute_event_properties`, `TextStimulus` + `Events.map_to_aois`, short-fixation and blink cleaning,
  `compute_reading_measures`) -> CSV -> `commas_statistics.R` (lme4, comparison with the paper).

## How to work here
You run **inside the workshop container** (devcontainer built from `Dockerfile`); there is no `docker` command.
- The repository is at `/home/rstudio/project`. `python3` is the venv `/opt/venv/bin/python3` (pymovements etc.
  installed), `RETICULATE_PYTHON` points to it, `Rscript` and `quarto` are on the PATH, `gcc` is available.
- The machine is arm64 (`char` is unsigned in C; see `tools/eyedry/run_eyedry.sh`).
- Python/R packages and SUBTLEX-ESP come from the image. A new dependency must be added to `requirements.txt` /
  `install_r_packages.R` (and the `Dockerfile`), not only installed in the running container.
- Always verify changes by rendering; chunks run real code. Render in a copy so no `presentation.html`,
  `presentation_files/` or `derived/` caches end up in the repository:
  `rsync -a --delete --exclude '*.EDF' workshop/ /tmp/ws/ && cd /tmp/ws && quarto render presentation.qmd`
  To test a render from scratch (Part 2 then runs `commas_preprocessing.py` first), also
  `rm -rf /tmp/ws/data/frases-comas/derived` (`rsync --exclude derived` keeps an old copy there).
- A full render takes several minutes (Part 2 preprocessing alone ~1.5 min without cache): run it in the background
  and wait for it instead of hitting command timeouts.
- To stop a hung render, kill the R/quarto processes by PID; `pkill -f '<pattern>'` also matches (and kills) the
  shell that runs it.
- No network to CRAN may be available; GitHub is reachable. OSF is not reachable from some sandboxes.

## Gotchas
- Python/pymovements 0.28: `compute_event_properties(("location", {"position_column": "pixel"}))` takes a tuple, not kwargs.
  `from_asc(..., messages=True)` gives `gaze.messages` (`time` is float; cast to Int64). Samples are binocular:
  `pixel = [xL, yL, xR, yR]`. There is no built-in EK fixation detector: detect saccades per trial, then `pm.events.fill`.
- polars: `join_where` for range joins; `extract_groups` for regex parsing.
- Reading measures: `pymovements.measure.reading.compute_reading_measures(fixations, aois, word_index_column=,
  group_columns=[trial])` needs `onset`, `duration` and the AOI index in the fixations (from `map_to_aois`) and a
  text column (`word`) in the AOI table. If the fixations have a `name` column, only `name == "fixation"` is used.
  Words not (first-pass) fixated get 0, not missing: use `FPF`/`Fix` to set them to NA. Off-text fixations
  (null index) are ignored. Equivalents: FFD = ffd, FPRT = gaze duration, RPD_inc = go-past, TFT = total time.
- The ASC file has lost accents (`Ser?`); frequency lookup resolves `?` to the most frequent accented form.
- SUBTLEX-ESP is CC BY-NC: downloaded at build time to `/opt/data` (env `SUBTLEX_ESP`), not committed.
  `/opt/data` is outside `workshop/` because the compose bind mount hides files baked into that folder.
- Do not commit rendered `presentation.html`.
- frases-comas: Part 2 of the slides shows the code of the `commas_*` scripts via `knitr::read_chunk` ("## ---- name"
  sections); keep labels in sync, and give everything that must not run in the slides (e.g. `main()`, the
  `if __name__ == "__main__"` block) its own label: under reticulate `__name__` is `"__main__"`. The slides run `commas_preprocessing.py` if
  `workshop/data/frases-comas/derived/simple/measures.csv` is missing (~1.5 min); delete that folder after changing
  the script. Paths are relative to `workshop/`. pymovements 0.28 drops `EFIX` lines with negative coordinates
  unless the regex is patched (`allow_negative_coordinates()`).
- EyeDry reads past the end of `.da1` lines when column 8 exceeds the fixations on the line ("phantom" fixations);
  the published IXS contain them. `eyedry_read_fixations(overrun=True)` reproduces this.
