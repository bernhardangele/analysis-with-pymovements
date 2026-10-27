# frases-comas: a simple analysis with pymovements and R

This is the analysis of the comma experiment (Angele, Gutiérrez-Cordero, Perea & Marcet; manuscript in
`data/frases-comas/`) the way we would do it today. Everything up to the reading measures is done with pymovements, the
statistics in R; the scripts are short and each step is explained in comments. Part 2 of the slides
(`presentation.qmd`) walks through the same code.

| Step | Script | Main functions | Output (`data/frases-comas/derived/simple/`) |
|---|---|---|---|
| 1. Read the ASC files, label trials, fixation positions, regions, cleaning, reading measures | `commas_preprocessing.py` | `pm.gaze.from_asc(patterns=..., events=True)`, `Gaze.compute_event_properties`, `pm.stimulus.TextStimulus`, `Events.map_to_aois`, `pymovements.measure.reading.compute_reading_measures` | `fixations.csv`, `measures.csv`, `questions.csv` |
| 2. Tables and models, comparison with the paper | `commas_statistics.R` | `lme4::lmer` | printed tables, `comma_effects.png` |

```bash
cd workshop
python commas_preprocessing.py   # ~1 min
Rscript commas_statistics.R      # ~15 s
```

## Decisions

- **Fixations**: the EyeLink fixation events, positioned at the mean of their samples. pymovements 0.28 drops
  fixations with negative coordinates; the script works around this.
- **Trial window**: from `DISPLAY ON` (a fixation already running is shortened) to the button press (the
  fixation during which the button was pressed is left out).
- **Regions**: from the EyeDry count file `frases_c.cnt` (character positions, 16 px per character).
- **Short fixations**: fixations of 80 ms or less are removed.
- **Reading measures**: `compute_reading_measures` per trial and region: FFD, first-pass reading time (gaze
  duration), inclusive regression-path duration (go-past time) and total fixation time. pymovements reports 0
  for a region that was not fixated (in first pass); the script turns these into missing values.
- **Blinks**: a trial is excluded if a fixation on the pre-comma region overlaps a blink or is within 100 ms
  of one.
- **Outliers**: the paper's cut-offs: sentence < 8000 ms, FFD < 800, GD < 1500, go-past and TVT < 1800 ms.
- **Statistics**: linear mixed models of the mean (comma present = −0.5, omitted = +0.5, maximal random
  effects). The paper used Bayesian ex-Gaussian models (brms), which are much slower to fit.

## Results compared with the paper

| | Paper | This analysis |
|---|---|---|
| Comprehension accuracy | 95.6 % (89.2–100) | 95.7 % (89.2–100) |
| Trials excluded (blinks, long fixations) | 124 | 58 |
| Sentence reading time, comma present / omitted | 2523 / 2545 ms | 2445 / 2483 ms |
| Local measures (Table 4) | | within 1–7 ms of the paper in every cell |

Comma effect (omitted − present, ms, 95 % interval):

| | Paper (brms, μ) | This analysis (lme4) |
|---|---|---|
| Sentence reading time | 30.3 [−3.8, 63.8] | 40.8 [2.8, 78.7] |
| Pre-comma GD | −7.7 [−16.7, 0.9] | −13.4 [−24.5, −2.4] |
| Pre-comma go-past | −27.8 [−40.7, −15.9] | −29.9 [−45.0, −14.9] |
| Post-comma 1 GD | 8.1 [−1.1, 18.0] | 12.2 [3.1, 21.2] |
| Post-comma 1 go-past | 25.5 [14.7, 36.8] | 28.2 [14.2, 42.2] |
| Post-comma 1 TVT | 29.5 [19.0, 40.5] | 32.5 [21.0, 43.9] |
| Post-comma 2 GD | 7.7 [0.6, 15.0] | 8.0 [−1.7, 17.6] |
| Post-comma 2 go-past | 23.2 [13.2, 33.4] | 25.9 [9.9, 42.0] |

All effects go in the same direction and have a similar size; the conclusions are the same (the comma shifts
reading time from after the comma to before it). Effects close to the 95 % boundary (sentence time, GD) can
fall on either side of it.

## Where the differences come from

The reading measures were compared trial by trial with an exact Python reproduction of the original pipeline
(Tim10drop.pl → EyeDry, `tools/replication/frases_comas.py`). In the trials that both analyses keep, **about 99 %** of the FFD, GD,
go-past and TVT values on the critical regions are identical. The rest is explained by:

1. **A bug in EyeDry (paper).** EyeDry read as many fixations per trial as the `.da1` file announced. That number
   included fixations after the button press that were not in the file, so EyeDry added fixations left over
   from earlier trials (2467 in total). They made the published sentence reading times ~80 ms too long in both
   conditions and changed go-past by a few ms. Without them the paper's pipeline gives 2441 / 2470 ms.
2. **Blink exclusion.** The paper excluded a trial when a blink occurred right before or after *any* fixation
   on the pre-comma region (a blink before the trial started could count too), and when one of those fixations
   was longer than 800 ms. Our rule is simpler and excludes fewer trials (58 instead of 124).
3. **Short fixations.** The paper merged 117 fixations under 80 ms into a neighbouring fixation within 16 px
   and ignored the other short ones; we remove all of them. EyeDry also let a short fixation start go-past time.
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
