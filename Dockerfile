FROM rocker/r-ver:4.5.1

# System deps: headless Chrome for gt/webshot2 PNG export, plus build deps
# for duckdb/atrrr/itscalledsoccer's compiled/curl-based packages.
#
# This base image is Ubuntu (jammy), where Ubuntu's own "chromium" apt
# package is just a non-functional transitional stub (Chromium moved to
# Snap-only distribution) -- install Google Chrome from Google's own apt
# repo instead, which still ships a real .deb.
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    gnupg \
    ca-certificates \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff-dev \
    libjpeg-dev \
    libuv1-dev \
    && wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

ENV CHROMOTE_CHROME=/usr/bin/google-chrome-stable

WORKDIR /app

# rocker/r-ver images point at a Posit Package Manager binary snapshot for
# this image's exact R version/Ubuntu release by default -- install.packages()
# via pak below pulls prebuilt binaries straight from DESCRIPTION's
# dependency list, no lockfile, no from-source compilation.
COPY DESCRIPTION DESCRIPTION
RUN R -e "install.packages('pak', repos = sprintf('https://r-lib.github.io/p/pak/stable/%s/%s/%s', .Platform[['pkgType']], R.Version()[['os']], R.Version()[['arch']]))" \
    && R -e "pak::local_install_deps(dependencies = TRUE)"

COPY . .

CMD ["Rscript", "main.R"]
