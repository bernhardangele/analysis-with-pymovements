FROM bangele1/analysis-in-a-box-rocker:latest

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV RETICULATE_PYTHON=/opt/venv/bin/python

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt jupyter pyyaml

RUN R -q -e 'install.packages(c("reticulate","tidyverse","lme4","lmerTest","emmeans","knitr","rmarkdown"), repos="https://cloud.r-project.org")'

WORKDIR /home/rstudio/workshop
COPY workshop/ /home/rstudio/workshop/
RUN chown -R rstudio:rstudio /home/rstudio/workshop
