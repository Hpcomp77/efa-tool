FROM rocker/r-ver:4.4.1

RUN apt-get update && apt-get install -y --no-install-recommends \
  libcurl4-openssl-dev \
  libssl-dev \
  libxml2-dev \
  && rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages(c('plumber','jsonlite','psych','GPArotation'), repos='https://cloud.r-project.org')"

WORKDIR /app
COPY scripts ./scripts
COPY r-api/plumber.R ./plumber.R

EXPOSE 8000

CMD ["R", "-e", "pr <- plumber::plumb('/app/plumber.R'); pr$run(host='0.0.0.0', port=8000)"]
