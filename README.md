# EFA Studio

EFA Studio is a browser-based exploratory factor analysis app with drag-and-drop variable selection and an R-powered analysis engine.

## Deployment architecture

There are now two deployment paths in this repository:

- Netlify frontend + separate R API
- Single-app Shiny deployment on Posit Connect Cloud or shinyapps.io

Netlify can host the app interface, but Netlify does not run R server-side. The split setup is:

- `public/`: static frontend deployed to Netlify
- `netlify/functions/efa.mjs`: proxy function at `/api/efa`
- `r-api/`: separate hosted R API service that runs the EFA analysis
- `scripts/efa_core.R`: shared EFA logic used by both the API and script runner

The browser sends analysis requests to Netlify, Netlify forwards them to the R API, and the response comes back to the same page.

## Posit-hosted option

As of now, Posit Cloud itself no longer publishes applications. The Posit-hosted path for this project is a Shiny app deployed to Posit Connect Cloud or shinyapps.io.

Files for that path:

- `app.R`: single-app Shiny interface that runs the EFA directly in R
- `scripts/efa_core.R`: shared analysis logic
- `scripts/write_manifest.R`: helper script for generating `manifest.json`

### Connect Cloud workflow

1. Make the repository available on GitHub.
2. Install the R packages needed locally:
   `shiny`, `bslib`, `psych`, `jsonlite`, `GPArotation`, `rsconnect`
3. Generate `manifest.json`:

```bash
Rscript scripts/write_manifest.R
```

4. In Posit Connect Cloud, deploy the repository using `app.R` and `manifest.json`.

### shinyapps.io workflow

You can also deploy `app.R` with `rsconnect::deployApp()` from an R session after configuring your shinyapps.io account.

## Netlify deploy

1. Deploy this repository to Netlify.
2. Set the Netlify environment variable `R_ANALYSIS_API_URL` to your hosted R API endpoint, for example:

```text
https://your-r-service.onrender.com/api/efa
```

3. Netlify will publish `public/` and expose the proxy at `/api/efa`.

## R API deploy

The `r-api/` folder contains a Dockerized R service for platforms such as Render, Railway, or Fly.io.

Expected API routes:

- `GET /health`
- `POST /api/efa`

The `POST /api/efa` body matches the JSON payload sent by the frontend.

## Local fallback

If you still want a local version for development, `server.js` can serve the same frontend and run `Rscript` directly:

```bash
npm start
```

## Analysis features

- Drag-and-drop variable selection
- Extraction methods: `minres`, `ml`, `pa`, `uls`, `wls`, `gls`
- Retention methods: parallel analysis, Kaiser criterion, fixed factors
- Rotations: `oblimin`, `varimax`, `promax`, `none`
- Missing-data handling: pairwise or listwise
- Returned results: loadings, communalities, variance explained, KMO, Bartlett test, retention diagnostics
