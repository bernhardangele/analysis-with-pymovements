PYTHON        ?= python3
RSCRIPT       ?= Rscript
QUARTO        ?= quarto
PORT          ?= 4200
HOST          ?= 127.0.0.1
PREVIEW_FLAGS ?=

EXPERIMENTS := reading boundary movingwindow vwp
ASC_FILES   := $(foreach e,$(EXPERIMENTS),$(wildcard data/example_data/$(e)/subject-*.asc))
CSV_FILES   := $(foreach e,$(EXPERIMENTS),$(wildcard data/example_data/$(e)/subject-*.csv))
DERIVED     := data/example_data/derived/vwp/fixations.csv
ASSETS      := assets/custom.scss assets/animations.js assets/gsap.min.js assets/scripts.html

.PHONY: all preview preprocess analysis standalone check clean clean-all help

all: workshop.html

workshop.html: workshop.qmd $(DERIVED) simple_analysis.R simple_animations.py $(ASSETS) $(CSV_FILES)
	$(QUARTO) render $<

preview: $(DERIVED)
	$(QUARTO) preview workshop.qmd --host $(HOST) --port $(PORT) $(PREVIEW_FLAGS)

$(DERIVED): simple_preprocessing.py $(ASC_FILES)
	$(PYTHON) $<

preprocess: $(DERIVED)

analysis: $(DERIVED) simple_analysis.R $(CSV_FILES)
	$(RSCRIPT) simple_analysis.R

standalone:
	$(PYTHON) ../tools/make_standalone.py

check: workshop.html
	$(PYTHON) ../tools/check_slides.py $<

clean:
	rm -rf workshop.html workshop_files Rplots.pdf __pycache__

clean-all: clean
	rm -rf data/example_data/derived

help:
	@echo "Targets:"
	@echo "  all (default)  Render workshop.html (runs preprocessing if needed)"
	@echo "  preview        Start live preview server for workshop.qmd (PORT=$(PORT))"
	@echo "  preprocess     Run simple_preprocessing.py -> data/example_data/derived/"
	@echo "  analysis       Run simple_analysis.R"
	@echo "  standalone     Regenerate simple_{reading,boundary,movingwindow,vwp}.R"
	@echo "  check          Run ../tools/check_slides.py on workshop.html"
	@echo "  clean          Remove workshop.html and temporary build files"
	@echo "  clean-all      Also remove data/example_data/derived/"
