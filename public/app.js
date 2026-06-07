const state = {
  fileName: "",
  csvText: "",
  headers: [],
  rows: [],
  selectedVariables: []
};

const csvFileInput = document.getElementById("csvFile");
const uploadZone = document.getElementById("uploadZone");
const availableVariables = document.getElementById("availableVariables");
const selectedVariables = document.getElementById("selectedVariables");
const variableCount = document.getElementById("variableCount");
const fileStatus = document.getElementById("fileStatus");
const datasetMeta = document.getElementById("datasetMeta");
const runButton = document.getElementById("runButton");
const runStatus = document.getElementById("runStatus");
const results = document.getElementById("results");
const errorBox = document.getElementById("errorBox");
const factorCountWrap = document.getElementById("factorCountWrap");
const retentionMethod = document.getElementById("retentionMethod");

let draggedVariable = null;

csvFileInput.addEventListener("change", async (event) => {
  const file = event.target.files[0];
  if (file) {
    await loadFile(file);
  }
});

["dragenter", "dragover"].forEach((eventName) => {
  uploadZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    uploadZone.classList.add("drag-over");
  });
});

["dragleave", "drop"].forEach((eventName) => {
  uploadZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    uploadZone.classList.remove("drag-over");
  });
});

uploadZone.addEventListener("drop", async (event) => {
  const file = event.dataTransfer.files[0];
  if (file) {
    await loadFile(file);
  }
});

retentionMethod.addEventListener("change", () => {
  factorCountWrap.classList.toggle("hidden", retentionMethod.value !== "fixed");
});

runButton.addEventListener("click", runAnalysis);

configureDropZone(availableVariables, "available");
configureDropZone(selectedVariables, "selected");

async function loadFile(file) {
  const text = await file.text();
  const preview = parseCsv(text);

  if (!preview.headers.length) {
    showError("The CSV appears to be empty or could not be read.");
    return;
  }

  state.fileName = file.name;
  state.csvText = text;
  state.headers = preview.headers;
  state.rows = preview.rows;
  state.selectedVariables = preview.headers.filter((header) => isNumericColumn(header, preview.rows));

  fileStatus.textContent = file.name;
  datasetMeta.classList.remove("hidden");
  datasetMeta.innerHTML = `
    <strong>${preview.rows.length}</strong> rows<br />
    <strong>${preview.headers.length}</strong> columns<br />
    <strong>${state.selectedVariables.length}</strong> numeric columns auto-selected
  `;

  renderVariableLists();
  clearError();
}

function parseCsv(text) {
  const lines = text
    .replace(/\r\n/g, "\n")
    .split("\n")
    .filter((line) => line.trim().length > 0);

  if (!lines.length) {
    return { headers: [], rows: [] };
  }

  const headers = splitCsvLine(lines[0]);
  const rows = lines.slice(1).map((line) => {
    const values = splitCsvLine(line);
    return headers.reduce((accumulator, header, index) => {
      accumulator[header] = values[index] ?? "";
      return accumulator;
    }, {});
  });

  return { headers, rows };
}

function splitCsvLine(line) {
  const values = [];
  let current = "";
  let inQuotes = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];

    if (char === "\"") {
      if (inQuotes && next === "\"") {
        current += "\"";
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char === "," && !inQuotes) {
      values.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }

  values.push(current.trim());
  return values;
}

function isNumericColumn(header, rows) {
  const observed = rows
    .map((row) => row[header])
    .filter((value) => value !== null && value !== undefined && String(value).trim() !== "");

  if (!observed.length) {
    return false;
  }

  return observed.every((value) => Number.isFinite(Number(value)));
}

function renderVariableLists() {
  const selected = new Set(state.selectedVariables);
  const available = state.headers.filter((header) => !selected.has(header));

  availableVariables.innerHTML = available.map(renderPill).join("");
  selectedVariables.innerHTML = state.selectedVariables.map(renderPill).join("");
  variableCount.textContent = `${state.selectedVariables.length} selected`;

  document.querySelectorAll(".variable-pill").forEach((pill) => {
    pill.addEventListener("dragstart", () => {
      draggedVariable = pill.dataset.variable;
    });
  });
}

function renderPill(variable) {
  return `<div class="variable-pill" draggable="true" data-variable="${escapeHtml(variable)}">${escapeHtml(variable)}</div>`;
}

function configureDropZone(element, target) {
  ["dragenter", "dragover"].forEach((eventName) => {
    element.addEventListener(eventName, (event) => {
      event.preventDefault();
      element.classList.add("drag-over");
    });
  });

  ["dragleave", "drop"].forEach((eventName) => {
    element.addEventListener(eventName, (event) => {
      event.preventDefault();
      element.classList.remove("drag-over");
    });
  });

  element.addEventListener("drop", () => {
    if (!draggedVariable) {
      return;
    }

    const selected = new Set(state.selectedVariables);

    if (target === "selected") {
      selected.add(draggedVariable);
    } else {
      selected.delete(draggedVariable);
    }

    state.selectedVariables = state.headers.filter((header) => selected.has(header));
    draggedVariable = null;
    renderVariableLists();
  });
}

async function runAnalysis() {
  if (!state.csvText) {
    showError("Upload a CSV file before running the analysis.");
    return;
  }

  if (state.selectedVariables.length < 3) {
    showError("Select at least three numeric variables for exploratory factor analysis.");
    return;
  }

  setRunningState(true);
  clearError();

  const payload = {
    fileName: state.fileName,
    csvText: state.csvText,
    selectedVariables: state.selectedVariables,
    options: {
      extractionMethod: document.getElementById("extractionMethod").value,
      retentionMethod: document.getElementById("retentionMethod").value,
      factorCount: Number(document.getElementById("factorCount").value || 0),
      rotationMethod: document.getElementById("rotationMethod").value,
      missingHandling: document.getElementById("missingHandling").value
    }
  };

  try {
    const response = await fetch("/api/efa", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || "Analysis failed.");
    }

    renderResults(data);
  } catch (error) {
    showError(error.message);
  } finally {
    setRunningState(false);
  }
}

function renderResults(data) {
  results.classList.remove("hidden");
  document.getElementById("factorsRetained").textContent = data.summary.factorsRetained;
  document.getElementById("observationsUsed").textContent = data.summary.observationsUsed;
  document.getElementById("kmoValue").textContent = data.summary.kmo;
  document.getElementById("bartlettValue").textContent = data.summary.bartlettPValue;

  document.getElementById("varianceTable").innerHTML = renderTable(data.variance);
  document.getElementById("loadingsTable").innerHTML = renderTable(data.loadings);
  document.getElementById("communalityTable").innerHTML = renderTable(data.communalities);
  document.getElementById("retentionTable").innerHTML = renderTable(data.retention);
}

function renderTable(rows) {
  if (!rows || !rows.length) {
    return "<p>No values returned.</p>";
  }

  const columns = Object.keys(rows[0]);
  const header = columns.map((column) => `<th>${escapeHtml(column)}</th>`).join("");
  const body = rows
    .map((row) => {
      const cells = columns
        .map((column) => `<td>${escapeHtml(formatValue(row[column]))}</td>`)
        .join("");
      return `<tr>${cells}</tr>`;
    })
    .join("");

  return `<table><thead><tr>${header}</tr></thead><tbody>${body}</tbody></table>`;
}

function formatValue(value) {
  if (value === null || value === undefined || value === "") {
    return "";
  }

  if (typeof value === "number") {
    return Number.isInteger(value) ? String(value) : value.toFixed(3);
  }

  return String(value);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

function setRunningState(isRunning) {
  runButton.disabled = isRunning;
  runButton.textContent = isRunning ? "Running..." : "Run analysis";
  runStatus.textContent = isRunning ? "Running in R" : "Ready";
  runStatus.classList.toggle("muted", !isRunning);
}

function showError(message) {
  errorBox.textContent = message;
  errorBox.classList.remove("hidden");
}

function clearError() {
  errorBox.textContent = "";
  errorBox.classList.add("hidden");
}
