FROM rocker/r-ver:4.4.1

# System deps: headless Chromium for gt/webshot2 PNG export, plus build
# deps for duckdb/atrrr/itscalledsoccer's compiled/curl-based packages.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    chromium \
    && rm -rf /var/lib/apt/lists/*

ENV CHROMOTE_CHROME=/usr/bin/chromium

WORKDIR /app

COPY renv.lock renv.lock
RUN R -e "install.packages('renv')" \
    && R -e "renv::restore()"

COPY . .

CMD ["Rscript", "main.R"]
