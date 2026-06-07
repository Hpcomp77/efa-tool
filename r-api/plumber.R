library(plumber)
library(jsonlite)
library(psych)

source("scripts/efa_core.R")

#* Health check
#* @get /health
function() {
  list(status = "ok")
}

#* Run exploratory factor analysis
#* @post /api/efa
#* @serializer json
function(req, res) {
  payload <- fromJSON(req$postBody, simplifyVector = FALSE)

  tryCatch(
    run_efa_analysis(payload),
    error = function(error) {
      res$status <- 400
      list(error = error$message)
    }
  )
}
