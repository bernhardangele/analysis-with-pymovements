"""Write one self-contained R script per experiment of the simplified workshop.

    python3 tools/make_standalone.py          # from the repository root

`workshop/simple_<experiment>.R` = the Python step of `simple_preprocessing.py` (run from R with reticulate)
followed by the R steps of `simple_analysis.R` for that experiment. The code is copied from the
"## ---- name" sections of those two scripts (the ones shown in `workshop.qmd`), so rerun this after changing
them; do not edit the generated files.
"""
import re
from pathlib import Path

WORKSHOP = Path(__file__).resolve().parents[1] / "workshop"
PYTHON = ["py-setup", "py-quiet", "py-patterns", "py-load", "py-regions", "py-aois", "py-measures", "py-one",
          "py-experiment"]
STEP_3 = "the Python step"      # its place among the steps of an experiment
# experiment -> (title, question, [(heading, [sections of simple_analysis.R])])
EXPERIMENTS = {
    "reading": ("Reading with and without commas (reading.osexp)",
                "Does a comma change how long readers look at the word before and after it?", [
        ("Step 1: the log file (your variables)", ["r-reading-log", "r-reading-select"]),
        ("Step 2: is the design what you planned? Where is the comma?", ["r-reading-design", "r-reading-critical"]),
        STEP_3,
        ("Step 4: cleaning (participants, then trials)",
         ["r-reading-tracker", "r-reading-participants", "r-reading-trials"]),
        ("Step 5: reading measures on the critical words", ["r-reading-measures"]),
        ("Step 6: means, plot, mixed model", ["r-reading-means", "r-reading-plot", "r-reading-model"]),
    ]),
    "boundary": ("The boundary paradigm (boundary.osexp)",
                 "Is the target word read faster after an identical preview (preview benefit)?", [
        ("Steps 1-2: variables and design", ["r-boundary-log"]),
        STEP_3,
        ("Step 4: did the display change in time? Cleaning", ["r-boundary-change", "r-boundary-clean"]),
        ("Step 5: reading measures on the target word", ["r-boundary-measures"]),
        ("Step 6: mixed model", ["r-boundary-model"]),
    ]),
    "movingwindow": ("The moving window (movingwindow.osexp)",
                     "Does a small window (4 instead of 12 letters on each side) slow reading?", [
        ("Steps 1-2: variables and the Latin square", ["r-mw-log"]),
        STEP_3,
        ("Steps 4-5: cleaning, measures for the whole sentence", ["r-mw-measures"]),
        ("Step 6: plot, mixed model", ["r-mw-plot", "r-mw-model"]),
    ]),
    "vwp": ("The visual world (vwp.osexp)",
            "Do listeners look at the competitor (candy) while they hear the target (candle)?", [
        ("Step 1: which picture is which?", ["r-vwp-log"]),
        STEP_3,
        ("Step 3 (continued): time zero = the start of the target word", ["r-vwp-time0"]),
        ("Step 4: cleaning (track loss, wrong clicks)", ["r-vwp-trackloss", "r-vwp-clean"]),
        ("Step 5: which picture was fixated, every 20 ms?", ["r-vwp-bins"]),
        ("Step 6: plot, mixed model", ["r-vwp-plot", "r-vwp-model"]),
    ]),
}


def sections(file):
    """{name: code} for the "## ---- name" sections of a script."""
    parts = re.split(r"^## ---- (\S+)[ \t]*\n", (WORKSHOP / file).read_text(), flags=re.M)
    return {name: code.strip("\n") for name, code in zip(parts[1::2], parts[2::2])}


def heading(text):
    return f"# ---- {text} {'-' * max(4, 100 - len(text))}"


def script(experiment, python, r):
    title, question, steps = EXPERIMENTS[experiment]
    table = "fixations" if experiment == "vwp" else "measures"
    code = "\n\n\n".join(python[name] for name in PYTHON)
    assert ')---"' not in code
    lines = [
        f"# {title}: the complete analysis in one file.",
        f"# {question}",
        "#",
        "#   cd workshop",
        f"#   Rscript simple_{experiment}.R        (or run it line by line in RStudio, working directory workshop/)",
        "#",
        f"# Input: data/example_data/{experiment}/subject-N.csv (OpenSesame log file) and subject-N.asc (EyeLink file).",
        "# The steps are in the order of the slides. Steps 1 and 2 need only the log files; step 3 is Python",
        "# (pymovements, run from R with reticulate) and reads the tracker files; everything after it is R again.",
        "# The same code as in the slides (workshop.qmd); written by tools/make_standalone.py from",
        "# simple_preprocessing.py and simple_analysis.R: change those, not this file.",
        "",
        "# All paths are relative to the workshop folder: stop early if R is somewhere else",
        'if (!dir.exists("data/example_data")) {',
        '  stop("Run this script from the workshop folder: setwd(\\"~/project/workshop\\") or, in RStudio,\\n",',
        '       "Session > Set Working Directory > To Source File Location. Now it is ", getwd(), call. = FALSE)',
        "}",
        "",
        "library(reticulate)                 # Python from R; uses the Python in RETICULATE_PYTHON",
        r["r-setup"].replace(
            "library(lme4)\n",
            "library(lme4)\n"
            "library(conflicted)                 # dplyr's filter(), not stats::filter(), even without tidyverse\n"
            'conflict_prefer("filter", "dplyr")\n',
        ).replace("# A table written by simple_preprocessing.py;", "# A table written by step 3;"),
    ]
    step_3 = [
        "",
        heading("Step 3: the tracker file -> tables (Python: pymovements)"),
        "# Messages label every fixation with its item and the phase of the trial; REGION messages give the",
        "# interest areas; each fixation gets its interest area"
        + ("." if experiment == "vwp" else "; reading measures per word."),
        "# The Python code is defined here and used from R as py$...; it writes its tables as CSV files to",
        f"# data/example_data/derived/{experiment}/, which the R steps below read with read_tracker().",
        'py_run_string(r"---(',
        code,
        ')---")',
        "",
        f'# Takes a few seconds per recording; delete {table}.csv (or the folder) to run it again',
        f'if (!file.exists(file.path(DATA, "derived", "{experiment}", "{table}.csv"))) {{',
        f'  py$preprocess_experiment("{experiment}")',
        "}",
    ]
    for step in steps:
        if step == STEP_3:
            lines += step_3
        else:
            lines += ["", heading(step[0])] + ["\n\n".join(r[name] for name in step[1])]
    return "\n".join(lines) + "\n"


def main():
    python, r = sections("simple_preprocessing.py"), sections("simple_analysis.R")
    for experiment in EXPERIMENTS:
        out = WORKSHOP / f"simple_{experiment}.R"
        out.write_text(script(experiment, python, r))
        print(out.relative_to(WORKSHOP.parent))


if __name__ == "__main__":
    main()
