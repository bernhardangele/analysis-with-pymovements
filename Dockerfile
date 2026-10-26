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

COPY install_r_packages.R /tmp/install_r_packages.R
RUN Rscript /tmp/install_r_packages.R

# SUBTLEX-ESP (Cuetos et al., 2011; CC BY-NC) Zipf values; kept outside /home/rstudio/workshop so the
# docker-compose bind mount does not hide it. The original is at https://osf.io/xp6sz
RUN mkdir -p /opt/data && curl -fsSL -o /opt/data/SUBTLEX-ESP_form_zipf.txt \
    https://raw.githubusercontent.com/LaSTUS-TALN-UPF/TSAR-LSBert/25ac18b5748b41741e65d009e5cce5820dfc83ae/code/resources/es/SUBTLEX-ESP/SUBTLEX-ESP_form_zipf.txt
ENV SUBTLEX_ESP=/opt/data/SUBTLEX-ESP_form_zipf.txt

WORKDIR /home/rstudio/workshop
COPY workshop/ /home/rstudio/workshop/
RUN chown -R rstudio:rstudio /home/rstudio/workshop
