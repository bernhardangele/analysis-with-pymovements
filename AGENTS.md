# AGENTS.md

## Repository
Workshop material: analysing reading (and visual-world) eye-tracking data with
[pymovements](https://github.com/pymovements/pymovements) (Python) and tidyverse / lme4 (R). See `plan.md` for open work.
Participants should use pymovements wherever it can do the job (including reading measures); R is for plots and
statistics. Do not use the R package `fixated` (maintained by one person only).
This workshop follows the recording workshop https://github.com/bernhardangele/eye-movement-experiments-with-opensesame (OpenSesame + PyGaze experiments: reading, boundary, moving
window, visual world; messages `start_trial N`, `TRIALINFO item=…`, `STIMONSET`, `TRIALEND`, `DISPLAYCHANGE`, ...;
sentences at x = 125 px in a monospace font; answers in the OpenSesame CSV) and should refer to it. frases-comas
was recorded with UMass EyeTrack instead (`TRIALID`, `DISPLAY ON`, `ENDBUTTON`, `REGION CHAR`, `QUESTION_ANSWER`).
Its sentences are not in that repository; EyeTrack logged accented characters as blanks.

| Path | Purpose |
|---|---|
| `workshop/workshop.qmd`, `workshop/Makefile` | Simplified workshop: six conceptual steps for the four OpenSesame experiments, on their example data; `Makefile` builds `workshop.html` (including preprocessing) |
| `workshop/data/example_data/` | Copy of `experiments/example_data/` of the recording workshop (e94abd3, regenerated with 18 reading participants): OpenSesame CSV + simulated 1000 Hz EyeLink ASC, participants 1–18 (reading) and 1–6 (others), made by its `make_example_data.py` (problems built in: see its `PROBLEMS`) |
| `workshop/simple_preprocessing.py`, `simple_analysis.R` | Its one Python step (stock pymovements only) and its R steps (cleaning, measures, lme4) |
| `workshop/simple_{reading,boundary,movingwindow,vwp}.R`, `tools/make_standalone.py` | One self-contained R script per experiment (Python step embedded, run with `reticulate::py_run_string`, then the R steps). **Generated** from the `## ---- name` sections of `simple_preprocessing.py` / `simple_analysis.R`: after changing those, rerun `python3 tools/make_standalone.py`; a new section must be added to its `EXPERIMENTS` / `PYTHON` lists |
| `workshop/simple_animations.py` | Data (`data-trial` JSON in a `<div>`) for the three animations of `workshop.qmd`: `samples_div` (samples → velocity → saccades/fixations vs. EyeLink events), `aoi_div` (REGION boxes, fixations → words, subjects 1 and 5), `measures_div` (scanpath with measures; item 2 of subject 1 has a regression) |
| `workshop/full_presentation/full_presentation.qmd` | Detailed workshop: Quarto revealjs presentation; Python (reticulate) and R chunks in one document, `engine: knitr` |
| `workshop/data/sub_1_example.asc` | Real binocular EyeLink recording (4 Spanish sentences, 1000 Hz), copied from `fixated/inst/extdata` |
| `workshop/data/frases-comas/` | Angele et al. comma experiment: 30 ASC files (UMass EyeTrack), original `.da1`/`.IXS`, Tim10drop.pl, manuscript |
| `tools/replication/frases_comas.py` | Not part of the workshop: exact Python ports of Tim10drop.pl and EyeDry, used to explain the differences to the paper |
| `workshop/full_presentation/commas_preprocessing.py`, `commas_statistics.R` | Part 2 of the full presentation: analysis of frases-comas (pymovements, then lme4); differences to the paper in `commas_README.md` |
| `sources/eyedry.c`, `tools/eyedry/` | EyeDry source; `run_eyedry.sh` compiles it and reruns the paper's analyses |
| `Dockerfile`, `docker-compose.yml` | Image based on `bangele1/analysis-in-a-box-rocker` (R, RStudio, Quarto) plus a Python venv at `/opt/venv` |
| `install_r_packages.R` | Installs missing R packages (CRAN, GitHub fallback) |
| `requirements.txt` | Python packages (pymovements, polars, pandas, pyarrow, matplotlib) |
| `requirements-dev.txt`, `tools/check_slides.py` | Playwright + Chromium; checks that every slide of the rendered presentation fits |
| `workshop/assets/` | Slide theme (`custom.scss`), GSAP 3.12.5 (vendored) and `animations.js` (pipeline, step strip, animated scanpath) |

## What has been done
- `quarto render workshop/workshop.qmd` (or `make -C workshop`) and `quarto render workshop/full_presentation/full_presentation.qmd` work inside the container.
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
- Always verify changes by rendering; chunks run real code. Render in a copy so no rendered HTML,
  `*_files/` or `derived/` caches end up in the repository:
  `rsync -a --delete --exclude '*.EDF' workshop/ /tmp/ws/ && cd /tmp/ws && make` (or `cd /tmp/ws/full_presentation && quarto render full_presentation.qmd`)
  To test a render from scratch (Part 2 then runs `commas_preprocessing.py` first), also
  `rm -rf /tmp/ws/data/frases-comas/derived` (`rsync --exclude derived` keeps an old copy there).
- A full render takes several minutes (Part 2 preprocessing alone ~1.5 min without cache): run it in the background
  and wait for it instead of hitting command timeouts.
- After rendering, test the slides as described under *Testing*.
- To stop a hung render, kill the R/quarto processes by PID; `pkill -f '<pattern>'` also matches (and kills) the
  shell that runs it.
- No network to CRAN may be available; GitHub is reachable. OSF is not reachable from some sandboxes.

## Testing
Nothing here has unit tests; changes are tested by running the real analysis and the real slides.

**Analysis** (`workshop/full_presentation/commas_*`)
1. Before changing a script, save the current outputs (`cp -r workshop/data/frases-comas/derived/simple
   <scratchpad>/old_simple`), then rerun from `workshop/full_presentation/`: `python3 commas_preprocessing.py` (~1 min) and
   `Rscript commas_statistics.R`.
2. Compare old and new `measures.csv` cell by cell (join on subject, item, cond, region; count differing
   ffd/gd/gpt/tvt values, NA vs. value included) and compare the printed tables and model estimates. Expected
   now: 58 of 3900 trials excluded for blinks, accuracy 95.7 %, sentence time 2445 / 2483 ms, sentence effect
   40.8 [2.8, 78.7] ms. Explain every difference: look at the fixation sequence (regions in time order) of the
   trials that differ, and say which version is right.
3. When replacing one method with another (e.g. `fixated` with `compute_reading_measures`), run both on the
   same fixations and compare the same way; check new pymovements functions on a trial that can be checked by
   hand (e.g. C1L1 `E2I36D0`, regions 1 1 1 2 1 2 2 2 3 4 5).
4. If numbers change, update `commas_README.md` (results table, explanation of differences). The comparison
   with the paper rests on `tools/replication/frases_comas.py` (exact Tim10drop/EyeDry port) and
   `tools/eyedry/run_eyedry.sh` (reruns EyeDry: 0/0/1/1 lines differ from the published IXS); rerun them only
   when that comparison is in question.

**Slides** (`workshop/workshop.qmd` and `workshop/full_presentation/full_presentation.qmd`)
1. Render in the copy (see *How to work here*), in the background; from scratch (`rm -rf
   /tmp/ws/data/frases-comas/derived`) whenever a `commas_*` script changed, so the slides run the new script.
2. Check `render.log` (exit code, errors) and that chunk output appears in the HTML (no R/Python errors printed
   on slides).
3. `python3 tools/check_slides.py /tmp/ws/workshop.html --screenshots <scratchpad>/shots` (or `full_presentation/full_presentation.html`) must report
   0 slides with overflowing content (exit code 0) and no SCROLL lines. SMALL is only acceptable for the
   one-line animated sentence. The checker shows all fragments and jumps GSAP animations to their end.
4. Look at the screenshots, not only the report: put them on contact sheets (PIL, 3 x 4 per image) and check
   readability (code and tables not shrunk), that figures fill their slide, and that example outputs show
   something meaningful.
5. Animations: open the page with Playwright, go to the slide, take screenshots at a few points in time and
   collect `pageerror`/console errors; there must be none.
6. Copy `/tmp/ws/workshop.html` (or `full_presentation.html`) to `workshop/` only for the user to look at; it is not committed.

**Simplified workshop** (`workshop/workshop.qmd`, `workshop/simple*`)
1. Data: `workshop/data/example_data/` (copied from the recording workshop). The Python step writes
   `data/example_data/derived/` (git-ignored); delete it after the data change. The slides quote the problem
   participants by number (reading 5 and 6, boundary 4 and 2, VWP 5 and 2) and the built-in effects of
   `make_example_data.py`; check them on the "Did we find what we built in?" slide after new data arrive.
2. Regenerate the standalone scripts (`python3 tools/make_standalone.py`) and check them: with `derived/` deleted,
   the four `Rscript simple_<experiment>.R` runs must write the same CSVs as `simple_preprocessing.py` and print,
   concatenated (reading, boundary, movingwindow, vwp), the same output as `simple_analysis.R`.
3. Run `python3 simple_preprocessing.py` (~10 s) and `Rscript simple_analysis.R` from `workshop/` (or `make` in
   `workshop/`), then render `workshop.qmd` as described above. No model is singular with these data (18 reading
   participants); with fewer participants the SDs often are 0, and the slides mention this.

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
- Do not commit rendered HTML (`workshop.html` or `full_presentation.html`).
- Slides are 1280x720 without code line numbers; code lines in the scripts and slides should stay under ~110 characters.
  Put a figure, or a long output, on its own slide with `#| output-location: slide` instead of shrinking it, and
  avoid `{.smaller}` (the code becomes unreadable). Quarto's 500 px cap on code blocks is switched off in
  `custom.scss`, so overlong code shows up in `check_slides.py`.
- Animations: `animations.js` runs on `Reveal` slide changes. `::: {.pipeline}` with `.stage` / `.arrow` divs,
  `::: {.step-strip data-step="N"}` for the frases-comas steps, and a `div.scanpath-anim` with a `data-trial` JSON
  (written by a hidden Python chunk with `output: asis`). `workshop.qmd` also has `div.samples-anim` and `div.aoi-anim`
  (`buildSamples`, `buildAoi` in `animations.js`). Their buttons sit in `div.controls`, a class reveal.js uses for
  its navigation arrows (hidden, absolute): `custom.scss` overrides that inside the animation divs.
- pymovements `from_asc(patterns=[{"pattern": ..., "column": ..., "value": ...}])` puts the pattern after its own
  `MSG <time>` prefix without a group: an alternation `A|B` breaks the whole regex. Use one entry per message.
  `compute_reading_measures` only counts events named `fixation` unless `event_name="fixation_eyelink"` is given.
- frases-comas: Part 2 of the full presentation shows the code of the `commas_*` scripts via `knitr::read_chunk` ("## ---- name"
  sections); keep labels in sync, and give everything that must not run in the slides (e.g. `main()`, the
  `if __name__ == "__main__"` block) its own label: under reticulate `__name__` is `"__main__"`. The slides run `commas_preprocessing.py` if
  `../data/frases-comas/derived/simple/measures.csv` is missing (~1.5 min); delete that folder after changing
  the script. Paths in `full_presentation/` are relative to `workshop/full_presentation/`. pymovements 0.28 drops `EFIX` lines with negative coordinates
  unless the regex is patched (`allow_negative_coordinates()`).
- EyeDry reads past the end of `.da1` lines when column 8 exceeds the fixations on the line ("phantom" fixations);
  the published IXS contain them. `eyedry_read_fixations(overrun=True)` reproduces this.
