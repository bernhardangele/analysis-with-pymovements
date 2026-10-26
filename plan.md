# Plan: remaining work

## Goal
Show that the workflow of [fixated](https://github.com/bernhardangele/fixated) can be run on top of
pymovements preprocessing, with real data, in `workshop/presentation.qmd`.

## Still to do

### 1. Visualizations from `fixated` (priority)
`plot_trial()` and the Shiny viewers (`plot_trials_shiny`, `plot_trials_shiny_fast`, `plot_trials_shiny_linked`)
are not used yet. They expect the list returned by `fixated::read_asc()` (`samples`, `events`,
`word_boundaries`, `trial_db`, with a `trial_nr` column).
- [ ] Build that list from pymovements output (samples, fixations as `events` with `type == "FIXATION"`,
      `word_boundaries`, `trial_db` with `t_display_on`/`t_display_off`) and call `plot_trial()`
      for EK and I-DT fixations.
- [ ] Check which columns `plot_trial()` needs (`eye`, `start_time`, `end_time`, `avg_x`, `avg_y`, `duration`).
- [ ] Try the Shiny viewers (cannot be rendered in static revealjs; add as a separate script or a note).
- [ ] Use `show_measures = TRUE` to overlay FFD/GD/TVT.

### 2. Other fixated functions with pymovements fixations
Not tried yet: `clean_fixations`, `merge_fixations`, `mark_fixations_close_to_blinks`, `blink_overlap_or_near`,
`get_landing_info`, `categorize_fixation`, `assign_word_info`, `process_eyelink_trial`.
- [ ] Test each on the EK fixations; document what works and what needs adapting.
- [ ] Detect blinks with `pm.events` (or take them from the ASC) for the blink functions.

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
- [ ] CRAN is unreachable in some environments; the image installs `reticulate` and `fixated` from GitHub as a
      fallback. Verify a normal build with CRAN access.
- [ ] SUBTLEX-ESP is downloaded at build time from a GitHub mirror because OSF was not reachable
      (original: https://osf.io/xp6sz). Switch to the official file and check the licence (CC BY-NC).
- [ ] Pin R/Python package versions.
- [ ] Test `docker compose up` (RStudio on port 8787), not only `quarto render`.
- [ ] Add CI that builds the image and renders the presentation.
