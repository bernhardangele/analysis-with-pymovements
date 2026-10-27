# Most packages are already in the base image; install what is missing.
# CRAN is tried first, reticulate falls back to GitHub if CRAN is unreachable.
need <- c("reticulate", "tidyverse", "lme4", "lmerTest", "emmeans", "knitr", "rmarkdown", "remotes")
missing <- setdiff(need, rownames(installed.packages()))
if (length(missing)) try(install.packages(missing, repos = "https://cloud.r-project.org"))
if (!requireNamespace("reticulate", quietly = TRUE)) {
  remotes::install_github("rstudio/reticulate", upgrade = "never")
}
stopifnot(all(need %in% rownames(installed.packages())))
