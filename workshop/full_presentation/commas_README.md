# frases-comas: a simple analysis with pymovements and R

This is the analysis of the comma experiment (Angele, Gutiérrez-Cordero, Perea & Marcet; manuscript in
`../data/frases-comas/`) the way we would do it today. Everything up to the reading measures is done with pymovements, the
statistics in R; the scripts are short and each step is explained in comments. Part 2 of the slides
(`full_presentation.qmd`) walks through the same code.

| Step | Script | Main functions | Output (`../data/frases-comas/derived/simple/`) |
|---|---|---|---|
| 1. Read the ASC files, label trials, fixation positions, regions, cleaning, reading measures | `commas_preprocessing.py` | `pm.gaze.from_asc(patterns=..., events=True)`, `Gaze.compute_event_properties`, `pm.stimulus.TextStimulus`, `Events.map_to_aois`, `pymovements.measure.reading.compute_reading_measures` | `fixations.csv`, `measures.csv`, `questions.csv`, `summary.csv` |
| 2. Tables and models, comparison with the paper | `commas_statistics.R` | `lme4::lmer`, `lme4::glmer` | printed tables, `comma_effects.png` |

```bash
cd workshop/full_presentation
python commas_preprocessing.py   # ~1 min
Rscript commas_statistics.R      # ~15 s
```

## Decisions

- **Fixations**: right-eye EyeLink fixation events (`eye="right"`), positioned at the mean of their samples.
  pymovements 0.28 drops fixations with negative coordinates; the script works around this (`allow_negative_coordinates()`).
- **Trial window**: every `TRIALID` attempt is numbered and the last attempt is kept (`42` repeated experimental
  trials across the 30 participants); window is `[DISPLAY ON, ENDBUTTON]` (`<= 20 000` ms asserted).
- **Regions**: from the EyeDry count file `frases_c.cnt` (`16` px/char), with outer sentence edges padded by `0.5`
  characters (`8` px).
- **Short fixations**: fixations under `80` ms (`duration < 80`) are removed (an optional `merge_short_fixations()`
  helper is also provided).
- **Reading measures**: `compute_reading_measures` per trial and region: FFD, first-pass reading time (gaze
  duration), inclusive regression-path duration (go-past time), total fixation time, and `fpf`/`fpreg`. pymovements
  reports `0` for a region not fixated (in first pass); the script turns these into `NA` via `FPF` / `Fix`.
- **Blinks**: a trial is excluded if a fixation on any critical region (`regions = (2, 3, 4)`) overlaps a blink
  or is within `100` ms of one.
- **Outliers**: the paper's cut-offs: sentence (`sum(tvt)`) `< 8000` ms, FFD `< 800`, GD `< 1500`, go-past and
  TVT `< 1800` ms.
- **Statistics**: linear mixed models of the mean (`comma present = −0.5`, `omitted = +0.5`) with random
  intercepts `(1 | subject) + (1 | item)` for `lme4` demonstration (maximal slopes yield singular fits / convergence
  warnings), alongside a `log(time)` sensitivity check (`t_raw / t_log`) and pre-comma skipping binomial GLMM.
  The paper used Bayesian ex-Gaussian models (`brms`), which handle maximal random effects via priors.

## Results compared with the paper

| | Paper | This analysis |
|---|---|---|
| Comprehension accuracy | 95.6 % (89.2–100) | 95.7 % (89.2–100.0) |
| Trials excluded (blinks, long fixations) | 124 | 109 |
| Sentence reading time, comma present / omitted | 2523 / 2545 ms | 2453 (SE 110.8) / 2488 (SE 107.4) ms |
| Local measures (Table 4) | | within 0–9 ms of the paper in reported go-past cells |

Comma effect (omitted − present, ms, 95 % Wald CI):

| | Paper (brms, μ) | This analysis (lme4, intercepts) |
|---|---|---|
| Sentence reading time | 30.3 [−3.8, 63.8] | 39.2 [5.1, 73.4] |
| Pre-comma GD | −7.7 [−16.7, 0.9] | −15.1 [−22.9, −7.3] |
| Pre-comma go-past | −27.8 [−40.7, −15.9] | −30.4 [−41.1, −19.6] |
| Post-comma 1 GD | 8.1 [−1.1, 18.0] | 13.4 [4.7, 22.1] |
| Post-comma 1 go-past | 25.5 [14.7, 36.8] | 31.0 [20.2, 41.8] |
| Post-comma 1 TVT | 29.5 [19.0, 40.5] | 33.7 [23.6, 43.9] |
| Post-comma 2 GD | 7.7 [0.6, 15.0] | 7.8 [0.2, 15.4] |
| Post-comma 2 go-past | 23.2 [13.2, 33.4] | 26.4 [16.2, 36.5] |

All effects go in the same direction and have a similar size; the conclusions are the same (the comma shifts
reading time from after the comma to before it). Under `log(time)` sensitivity checks, go-past and post-comma
total time hold cleanly (`|t| >= 3.3`), whereas gaze-duration (`gd`) effects weaken (`t_log = -2.80, 1.77, 1.93`).

## Where the differences come from

The reading measures were compared trial by trial with an exact Python reproduction of the original pipeline
(Tim10drop.pl → EyeDry, `tools/replication/frases_comas.py`), and the updated script was also verified cell-by-cell
against the earlier `measures.csv` baseline (`51` additional blink trials across regions 2 and 4; half-char edge
padding affecting `r1`; `>= 80` vs `> 80` boundary recovering exact `80` ms fixations). In trials kept by both
pipelines, **about 99 %** of FFD, GD, go-past and TVT values on critical regions match. The rest is explained by:

1. **A bug in EyeDry (paper).** EyeDry read as many fixations per trial as the `.da1` file announced. That number
   included fixations after the button press that were not in the file, so EyeDry added fixations left over
   from earlier trials (2467 in total). They made the published sentence reading times ~80 ms too long in both
   conditions and changed go-past by a few ms. Without them the paper's pipeline gives 2441 / 2470 ms.
2. **Blink exclusion.** The paper excluded a trial when a blink occurred right before or after *any* fixation
   on the pre-comma region (a blink before the trial started could count too), and when one of those fixations
   was longer than 800 ms. Here we exclude trials when a fixation in any critical region (2–4) overlaps or lies
   within 100 ms of a blink (`109` vs `124` trials).
3. **Short fixations.** The paper merged 117 fixations under 80 ms into a neighbouring fixation within 16 px
   and ignored the other short ones; here fixations `< 80` ms are removed (leaving `duration == 80` ms). EyeDry
   also let a short fixation start go-past time.
4. **EyeDry cut-offs.** EyeDry set a region's gaze duration to missing above 2000 ms and total time above
   4000 ms. In seven trials with a lot of rereading this removed seconds from the paper's sentence reading time
   (five of them in the comma-omitted condition), which is the main reason why our sentence effect is ~8 ms larger than in
   a bug-free version of the original pipeline (33.3 [−3.9, 70.4] with lme4).
5. **Positions.** pymovements averages the samples of each fixation; EyeLink's own average differs by < 0.05 px,
   which moves a handful of fixations across a character boundary.
6. **Model.** On the paper's own data, lme4 gives the same GD effects as here (pre-comma −12.3 [−23.6, −1.0],
   post-comma 1 13.0 [4.0, 22.1]). The difference to the paper is the model: an ex-Gaussian μ describes the bulk of
   the distribution, a linear model the mean, which includes the long right tail.

Fixations off the text (no region) are ignored by `compute_reading_measures`: a reader who first looks left of
the sentence and then reads it normally still gets first-pass measures. An earlier version of this analysis
used `fixated::compute_eye_measures()`, which gave identical values except in 3 such trials (no first-pass
measures there) and also computed go-past time for regions skipped in first pass.
