`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) {
    b
  } else {
    a
  }
}

round_df <- function(df, digits = 3) {
  as.data.frame(lapply(df, function(col) {
    if (is.numeric(col)) {
      round(col, digits)
    } else {
      col
    }
  }), check.names = FALSE)
}

rows_from_df <- function(df) {
  jsonlite::fromJSON(jsonlite::toJSON(round_df(df), dataframe = "rows"))
}

matrix_to_df <- function(mat, row_name = "Row") {
  mat <- as.matrix(mat)
  df <- as.data.frame(mat, check.names = FALSE)
  df[[row_name]] <- rownames(mat)
  df[, c(row_name, setdiff(names(df), row_name)), drop = FALSE]
}

run_efa_analysis <- function(request) {
  csv_text <- request$csvText %||% ""
  selected_variables <- unlist(request$selectedVariables %||% list(), use.names = FALSE)
  options <- request$options %||% list()

  if (nchar(csv_text) == 0) {
    stop("No CSV data was supplied.")
  }

  if (length(selected_variables) < 3) {
    stop("At least three variables are required for EFA.")
  }

  data <- read.csv(text = csv_text, stringsAsFactors = FALSE, check.names = FALSE)

  missing_columns <- setdiff(selected_variables, names(data))
  if (length(missing_columns) > 0) {
    stop(paste("Variables not found in dataset:", paste(missing_columns, collapse = ", ")))
  }

  analysis_data <- data[, selected_variables, drop = FALSE]
  analysis_data[] <- lapply(analysis_data, function(column) as.numeric(column))

  if (all(!complete.cases(analysis_data))) {
    stop("The selected variables do not contain enough complete numeric data.")
  }

  missing_handling <- options$missingHandling %||% "pairwise"
  retention_method <- options$retentionMethod %||% "parallel"
  extraction_method <- options$extractionMethod %||% "minres"
  rotation_method <- options$rotationMethod %||% "oblimin"
  factor_count <- as.integer(options$factorCount %||% 0)

  cor_use <- if (missing_handling == "listwise") "complete.obs" else "pairwise.complete.obs"
  efa_input <- if (missing_handling == "listwise") na.omit(analysis_data) else analysis_data

  if (nrow(efa_input) < 5) {
    stop("Not enough observations remain after missing data handling.")
  }

  correlation_matrix <- cor(efa_input, use = cor_use)
  if (!isTRUE(all.equal(correlation_matrix, t(correlation_matrix)))) {
    correlation_matrix <- (correlation_matrix + t(correlation_matrix)) / 2
  }
  if (any(!is.finite(correlation_matrix))) {
    stop("Correlation matrix contains invalid values. Check the selected variables for constant or empty data.")
  }
  smoothed_correlation <- psych::cor.smooth(correlation_matrix)
  eigenvalues <- eigen(correlation_matrix)$values

  if (retention_method == "fixed") {
    if (is.na(factor_count) || factor_count < 1) {
      stop("Provide a valid fixed number of factors.")
    }
    retained_factors <- factor_count
    parallel_values <- rep(NA_real_, length(eigenvalues))
  } else if (retention_method == "kaiser") {
    retained_factors <- sum(eigenvalues > 1)
    parallel_values <- rep(NA_real_, length(eigenvalues))
  } else {
    parallel_result <- psych::fa.parallel(
      efa_input,
      fa = "fa",
      fm = extraction_method,
      plot = FALSE,
      error.bars = FALSE
    )
    retained_factors <- parallel_result$nfact
    parallel_values <- parallel_result$fa.sim
  }

  retained_factors <- max(1, min(retained_factors, ncol(efa_input) - 1))

  rotation_arg <- if (rotation_method == "none") "none" else rotation_method
  fa_result <- psych::fa(
    r = smoothed_correlation,
    nfactors = retained_factors,
    n.obs = nrow(efa_input),
    rotate = rotation_arg,
    fm = extraction_method,
    SMC = FALSE,
    scores = "none",
    residuals = FALSE
  )

  loadings_matrix <- matrix_to_df(unclass(fa_result$loadings), row_name = "Variable")

  communalities <- data.frame(
    Variable = names(fa_result$communality),
    Communality = unname(fa_result$communality),
    Uniqueness = unname(fa_result$uniquenesses),
    check.names = FALSE
  )

  variance <- matrix_to_df(t(as.matrix(fa_result$Vaccounted)), row_name = "Factor")

  retention <- data.frame(
    Component = seq_along(eigenvalues),
    ActualEigenvalue = eigenvalues,
    ParallelEigenvalue = parallel_values,
    Retained = seq_along(eigenvalues) <= retained_factors,
    check.names = FALSE
  )

  kmo_result <- tryCatch(
    psych::KMO(correlation_matrix),
    error = function(error) psych::KMO(smoothed_correlation)
  )
  bartlett_result <- tryCatch(
    psych::cortest.bartlett(correlation_matrix, n = nrow(efa_input)),
    error = function(error) psych::cortest.bartlett(smoothed_correlation, n = nrow(efa_input))
  )

  list(
    summary = list(
      factorsRetained = retained_factors,
      observationsUsed = nrow(efa_input),
      kmo = round(kmo_result$MSA, 3),
      bartlettPValue = signif(bartlett_result$p.value, 4)
    ),
    variance = rows_from_df(variance),
    loadings = rows_from_df(loadings_matrix),
    communalities = rows_from_df(communalities),
    retention = rows_from_df(retention)
  )
}
