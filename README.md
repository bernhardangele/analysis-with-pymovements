# analysis-with-pymovements
Workshop and example scripts for analyzing eye movement experiments (reading and visual world) with
[pymovements](https://github.com/pymovements/pymovements), combining Python and R (as in
[fixated](https://github.com/bernhardangele/fixated)).

- `workshop/presentation.qmd`: Quarto (R + Python) presentation
- `Dockerfile` / `docker-compose.yml`: environment with R, RStudio, Quarto and pymovements, based on
  [bangele1/analysis-in-a-box-rocker](https://hub.docker.com/r/bangele1/analysis-in-a-box-rocker)

## Usage
```bash
docker compose up --build
```
Open http://localhost:8787 (user `rstudio`, password `workshop`), then render `workshop/presentation.qmd`.
