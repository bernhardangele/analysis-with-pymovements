# Plan: remaining work

## Goal
Teach the analysis of eye-tracking experiments with pymovements wherever possible (reading, events, AOIs,
reading measures), R (tidyverse, lme4) for plots and statistics. The R package `fixated` is not used: it is
maintained by one person only, pymovements is actively developed.

## Still to do

### 1. Visualizations
- [ ] Scanpath / trial plots with pymovements plotting functions instead of hand-written matplotlib.
- [ ] Use more of `compute_reading_measures` (skipping, regressions in/out, landing position with character AOIs).

### 2. Removed
- Visualizations and other functions of `fixated` (`plot_trial`, Shiny viewers, `merge_fixations`, ...): no
  longer planned.

### 3. Data and preprocessing
- [ ] Use both eyes (currently left eye only).
- [ ] Add a y-dimension to the ROIs (currently the whole screen height).
- [ ] Replace the hand-written message parsing with `from_asc(patterns=..., trial_columns=...)` if the
      pymovements `patterns` option can handle the trial/display messages.
- [ ] Tune the EK and I-DT parameters against the EyeLink events (e.g. report overlap, not only counts).
- [ ] Use the larger recordings in `fixated/data_to_incorporate` (not in `inst/extdata`; ~230 MB, kept out of this repo)
      for a meaningful statistical analysis.

### 4. Statistics
- [ ] Word frequency effect is not significant with 4 sentences / 1 participant. Use more data
      (item 3) and add random effects for subject and item.
- [ ] Add predictability or other lexical predictors.

### 5. Visual world
- [ ] No visual world recording is available in `fixated`; the time-course slide re-uses the reading data
      with words as AOIs. Find or record real visual-world data (AOIs: target, competitor, distractors),
      then add proportion-of-looks plots and growth-curve analysis.

### 6. Environment
- [ ] CRAN is unreachable in some environments; the image installs `reticulate` from GitHub as a
      fallback. Verify a normal build with CRAN access.
- [ ] SUBTLEX-ESP is downloaded at build time from a GitHub mirror because OSF was not reachable
      (original: https://osf.io/xp6sz). Switch to the official file and check the licence (CC BY-NC).
- [ ] Pin R/Python package versions.
- [ ] Test `docker compose up` (RStudio on port 8787), not only `quarto render`.
- [ ] Add CI that builds the image and renders the presentation.
