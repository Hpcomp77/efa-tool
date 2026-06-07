args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 2) {
  stop("Usage: Rscript run_efa.R <request.json> <result.json>")
}

suppressPackageStartupMessages({
  library(jsonlite)
  library(psych)
})

request_path <- args[1]
result_path <- args[2]
source("scripts/efa_core.R")

request <- fromJSON(request_path, simplifyVector = FALSE)
output <- run_efa_analysis(request)

write_json(output, result_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
