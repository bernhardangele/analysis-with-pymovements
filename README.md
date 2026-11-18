# analysis-with-pymovements
Workshop and example scripts for analyzing eye movement experiments (reading and visual world) with
[pymovements](https://github.com/pymovements/pymovements) (preprocessing and reading measures) and R
(statistics).

It follows the [OpenSesame and PyGaze workshop](https://github.com/bernhardangele/eye-movement-experiments-with-opensesame), in which the experiments
(reading, boundary, moving window, visual world) are built and recorded; this workshop analyses the recorded data.
Part 2 analyses a published comma experiment that was recorded with the UMass EyeTrack software instead of
OpenSesame, so its messages differ (`TRIALID`/`DISPLAY ON`/`ENDBUTTON` instead of `TRIALINFO`/`STIMONSET`/`TRIALEND`).

- `workshop/workshop.qmd`: the **workshop**: the conceptual analysis steps (log-file variables, design
  check, cleaning, measures, one mixed model) for all four experiments of the recording workshop, using its
  example data (`workshop/data/example_data/`: OpenSesame runs with a simulated 1000 Hz EyeLink, 18 participants in reading and
  6 in the others, with deliberate data problems). One Python step (`simple_preprocessing.py`, stock pymovements),
  the rest in R (`simple_analysis.R`); `workshop/Makefile` builds it (`make`).
- `workshop/full_presentation/full_presentation.qmd`: the detailed workshop, Quarto (R + Python) presentation, computed from the real EyeLink example recording
  `workshop/data/sub_1_example.asc` (copied from [fixated](https://github.com/bernhardangele/fixated))
- `Dockerfile` / `docker-compose.yml`: environment with R, RStudio, Quarto and pymovements, based on
  [bangele1/analysis-in-a-box-rocker](https://hub.docker.com/r/bangele1/analysis-in-a-box-rocker)

## Usage (Docker)
```bash
docker compose up --build
```
Open http://localhost:8787 (user `rstudio`, password `workshop` — do not expose port 8787 on a shared network),
then run `make` (or `quarto render workshop.qmd`, or `cd full_presentation && quarto render full_presentation.qmd`) from `workshop/`.

## Usage without Docker
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
Rscript install_r_packages.R
cd workshop && make                          # or: cd full_presentation && quarto render full_presentation.qmd
```
