suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(psych)
  library(jsonlite)
})

source("scripts/efa_core.R")

theme <- bs_theme(
  version = 5,
  bg = "#f4efe7",
  fg = "#1f2933",
  primary = "#146356",
  secondary = "#bf6d46",
  base_font = font_google("Source Sans 3"),
  heading_font = font_google("Fraunces")
)

ui <- page_fluid(
  theme = theme,
  tags$head(
    tags$style(HTML("
      .app-shell {
        max-width: 1180px;
        margin: 0 auto;
        padding: 28px 0 40px;
      }
      .hero-card, .panel-card {
        background: rgba(255, 252, 247, 0.92);
        border: 1px solid rgba(31, 41, 51, 0.10);
        border-radius: 24px;
        box-shadow: 0 20px 48px rgba(31, 41, 51, 0.08);
      }
      .hero-card {
        padding: 28px;
        margin-bottom: 20px;
        background:
          radial-gradient(circle at top left, rgba(20, 99, 86, 0.12), transparent 24%),
          radial-gradient(circle at top right, rgba(191, 109, 70, 0.12), transparent 18%),
          rgba(255, 252, 247, 0.92);
      }
      .panel-card {
        padding: 20px;
        height: 100%;
      }
      .eyebrow {
        margin: 0 0 10px;
        font-size: 12px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: #146356;
      }
      .hero-title {
        font-size: clamp(2rem, 4vw, 4rem);
        line-height: 0.95;
        margin: 0 0 12px;
      }
      .hero-copy {
        color: #61707d;
        max-width: 760px;
        margin-bottom: 0;
      }
      .metric-strip {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 14px;
        margin-bottom: 18px;
      }
      .metric-card {
        background: rgba(255,255,255,0.62);
        border: 1px solid rgba(31, 41, 51, 0.10);
        border-radius: 18px;
        padding: 14px 16px;
      }
      .metric-label {
        display: block;
        color: #61707d;
        font-size: 13px;
        margin-bottom: 8px;
      }
      .metric-value {
        font-size: 24px;
        font-weight: 700;
      }
      .section-title {
        margin-top: 0;
        margin-bottom: 16px;
      }
      .hint {
        color: #61707d;
        font-size: 14px;
      }
      .status-note {
        margin-top: 10px;
        color: #61707d;
      }
      @media (max-width: 900px) {
        .metric-strip {
          grid-template-columns: 1fr 1fr;
        }
      }
      @media (max-width: 640px) {
        .metric-strip {
          grid-template-columns: 1fr;
        }
      }
    "))
  ),
  div(
    class = "app-shell",
    div(
      class = "hero-card",
      tags$p(class = "eyebrow", "Exploratory Factor Analysis"),
      tags$h1(class = "hero-title", "EFA Studio"),
      tags$p(
        class = "hero-copy",
        "Upload a CSV, choose the variables for analysis, select retention, extraction, and rotation, then run the factor analysis directly in R and inspect the results in the same app."
      )
    ),
    layout_columns(
      col_widths = c(4, 4, 4),
      div(
        class = "panel-card",
        tags$h3(class = "section-title", "1. Data"),
        fileInput("csv_file", "Upload CSV", accept = c(".csv", "text/csv")),
        uiOutput("dataset_meta"),
        tags$p(
          class = "hint",
          "The app auto-detects numeric variables. You can adjust the final set before running EFA."
        )
      ),
      div(
        class = "panel-card",
        tags$h3(class = "section-title", "2. Variables"),
        uiOutput("variable_selector"),
        tags$p(
          class = "hint",
          "For the first Posit-hosted version, variable selection is multi-select rather than drag-and-drop. We can add drag-and-drop later with an extra package."
        )
      ),
      div(
        class = "panel-card",
        tags$h3(class = "section-title", "3. Model"),
        selectInput(
          "extraction_method",
          "Extraction method",
          choices = c(
            "Minimum residual (minres)" = "minres",
            "Maximum likelihood (ml)" = "ml",
            "Principal axis (pa)" = "pa",
            "Unweighted least squares (uls)" = "uls",
            "Weighted least squares (wls)" = "wls",
            "Generalized least squares (gls)" = "gls"
          )
        ),
        selectInput(
          "retention_method",
          "Factor retention",
          choices = c(
            "Parallel analysis" = "parallel",
            "Kaiser criterion" = "kaiser",
            "Fixed number of factors" = "fixed"
          )
        ),
        conditionalPanel(
          condition = "input.retention_method === 'fixed'",
          numericInput("factor_count", "Number of factors", value = 2, min = 1, step = 1)
        ),
        selectInput(
          "rotation_method",
          "Rotation",
          choices = c(
            "Oblimin" = "oblimin",
            "Varimax" = "varimax",
            "Promax" = "promax",
            "None" = "none"
          )
        ),
        selectInput(
          "missing_handling",
          "Missing data handling",
          choices = c(
            "Pairwise correlations" = "pairwise",
            "Listwise complete cases" = "listwise"
          )
        ),
        actionButton("run_analysis", "Run analysis", class = "btn btn-primary"),
        textOutput("status_note", container = tags$p, class = "status-note")
      )
    ),
    br(),
    div(
      class = "panel-card",
      tags$h3(class = "section-title", "Results"),
      uiOutput("summary_cards"),
      tabsetPanel(
        tabPanel("Variance", tableOutput("variance_table")),
        tabPanel("Loadings", tableOutput("loadings_table")),
        tabPanel("Communalities", tableOutput("communality_table")),
        tabPanel("Retention", tableOutput("retention_table"))
      )
    )
  )
)

server <- function(input, output, session) {
  uploaded <- reactive({
    req(input$csv_file)
    read.csv(input$csv_file$datapath, stringsAsFactors = FALSE, check.names = FALSE)
  })

  numeric_columns <- reactive({
    data <- uploaded()
    candidates <- names(data)[vapply(data, is.numeric, logical(1))]
    candidates
  })

  observeEvent(uploaded(), {
    updateSelectizeInput(
      session,
      "selected_variables",
      choices = names(uploaded()),
      selected = numeric_columns(),
      server = TRUE
    )
  })

  output$dataset_meta <- renderUI({
    req(uploaded())
    data <- uploaded()
    tags$div(
      tags$p(tags$strong(nrow(data)), " rows"),
      tags$p(tags$strong(ncol(data)), " columns"),
      tags$p(tags$strong(length(numeric_columns())), " numeric columns detected")
    )
  })

  output$variable_selector <- renderUI({
    req(uploaded())
    selectizeInput(
      "selected_variables",
      "Variables for EFA",
      choices = names(uploaded()),
      selected = numeric_columns(),
      multiple = TRUE,
      options = list(plugins = list("remove_button"))
    )
  })

  analysis_result <- eventReactive(input$run_analysis, {
    req(uploaded())

    selected <- input$selected_variables %||% character()
    validate(
      need(length(selected) >= 3, "Select at least three variables for exploratory factor analysis.")
    )

    csv_text <- paste(
      capture.output(write.csv(uploaded(), row.names = FALSE, quote = TRUE)),
      collapse = "\n"
    )

    request <- list(
      fileName = input$csv_file$name,
      csvText = csv_text,
      selectedVariables = selected,
      options = list(
        extractionMethod = input$extraction_method,
        retentionMethod = input$retention_method,
        factorCount = input$factor_count,
        rotationMethod = input$rotation_method,
        missingHandling = input$missing_handling
      )
    )

    run_efa_analysis(request)
  })

  output$status_note <- renderText({
    if (is.null(input$csv_file)) {
      "Upload a dataset to begin."
    } else {
      "Ready to run R-based analysis."
    }
  })

  output$summary_cards <- renderUI({
    result <- analysis_result()
    summary <- result$summary

    div(
      class = "metric-strip",
      div(class = "metric-card", tags$span(class = "metric-label", "Factors retained"), tags$div(class = "metric-value", summary$factorsRetained)),
      div(class = "metric-card", tags$span(class = "metric-label", "Observations used"), tags$div(class = "metric-value", summary$observationsUsed)),
      div(class = "metric-card", tags$span(class = "metric-label", "KMO"), tags$div(class = "metric-value", summary$kmo)),
      div(class = "metric-card", tags$span(class = "metric-label", "Bartlett p-value"), tags$div(class = "metric-value", summary$bartlettPValue))
    )
  })

  output$variance_table <- renderTable({
    as.data.frame(analysis_result()$variance, check.names = FALSE)
  }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "m")

  output$loadings_table <- renderTable({
    as.data.frame(analysis_result()$loadings, check.names = FALSE)
  }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "m")

  output$communality_table <- renderTable({
    as.data.frame(analysis_result()$communalities, check.names = FALSE)
  }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "m")

  output$retention_table <- renderTable({
    as.data.frame(analysis_result()$retention, check.names = FALSE)
  }, striped = TRUE, hover = TRUE, bordered = FALSE, spacing = "m")
}

shinyApp(ui, server)
