# syntax=docker/dockerfile:1

FROM bangele1/analysis-in-a-box-rocker:4.6.2

ARG TARGETARCH

USER root

# Python packages go in their own venv. The base image already provides python3
# and python3-venv, and the venv brings its own pip; libpython3-dev is needed so
# reticulate can embed the venv's Python shared library when rendering workshop.qmd.
RUN apt-get update && apt-get install -y --no-install-recommends libpython3-dev \
    && rm -rf /var/lib/apt/lists/*
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV RETICULATE_PYTHON=/opt/venv/bin/python

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt jupyter pyyaml

# Development only: Playwright + Chromium for tools/check_slides.py (checks that every slide fits)
COPY requirements-dev.txt /tmp/requirements-dev.txt
RUN pip install --no-cache-dir -r /tmp/requirements-dev.txt \
    && PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright playwright install --with-deps chromium \
    && rm -rf /var/lib/apt/lists/*
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# R packages. install_r_packages.R should use pak::pkg_install() so that everything
# comes from the CRAN snapshot set in the base image's Rprofile.site.
# PKG_SYSREQS=false matches the base image: letting pak run apt could pull in
# libnode-dev, which conflicts with NodeSource's nodejs.
COPY install_r_packages.R /tmp/install_r_packages.R
RUN --mount=type=cache,id=pkgcache-${TARGETARCH},target=/root/.cache/R/pkgcache \
    PKG_SYSREQS=false Rscript /tmp/install_r_packages.R

# SUBTLEX-ESP (Cuetos et al., 2011; CC BY-NC) Zipf values; kept outside /home/rstudio/workshop so the
# docker-compose bind mount does not hide it. The original is at https://osf.io/xp6sz
RUN mkdir -p /opt/data && curl -fsSL -o /opt/data/SUBTLEX-ESP_form_zipf.txt \
    https://raw.githubusercontent.com/LaSTUS-TALN-UPF/TSAR-LSBert/25ac18b5748b41741e65d009e5cce5820dfc83ae/code/resources/es/SUBTLEX-ESP/SUBTLEX-ESP_form_zipf.txt
ENV SUBTLEX_ESP=/opt/data/SUBTLEX-ESP_form_zipf.txt

# RStudio sessions don't inherit Docker ENV, so repeat the variables R code needs
# in Renviron.site (ENV above still covers Rscript, Jupyter and the shell).
RUN { \
      echo "RETICULATE_PYTHON=/opt/venv/bin/python"; \
      echo "SUBTLEX_ESP=/opt/data/SUBTLEX-ESP_form_zipf.txt"; \
      echo "PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright"; \
    } >> /usr/local/lib/R/etc/Renviron.site

WORKDIR /home/rstudio/workshop
COPY workshop/ /home/rstudio/workshop/
RUN chown -R rstudio:rstudio /home/rstudio/workshop