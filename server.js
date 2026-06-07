const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn } = require("child_process");

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || "127.0.0.1";
const PUBLIC_DIR = path.join(__dirname, "public");
const R_SCRIPT = path.join(__dirname, "scripts", "run_efa.R");

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8"
};

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, { "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(payload));
}

function serveStatic(requestPath, response) {
  const normalizedPath = requestPath === "/" ? "/index.html" : requestPath;
  const targetPath = path.normalize(path.join(PUBLIC_DIR, normalizedPath));

  if (!targetPath.startsWith(PUBLIC_DIR)) {
    sendJson(response, 403, { error: "Forbidden" });
    return;
  }

  fs.readFile(targetPath, (error, content) => {
    if (error) {
      sendJson(response, 404, { error: "Not found" });
      return;
    }

    const extension = path.extname(targetPath).toLowerCase();
    response.writeHead(200, {
      "Content-Type": MIME_TYPES[extension] || "application/octet-stream"
    });
    response.end(content);
  });
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";

    request.on("data", (chunk) => {
      body += chunk;

      if (body.length > 10 * 1024 * 1024) {
        reject(new Error("Request body is too large."));
        request.destroy();
      }
    });

    request.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch (error) {
        reject(new Error("Invalid JSON payload."));
      }
    });

    request.on("error", reject);
  });
}

function runAnalysis(payload) {
  return new Promise((resolve, reject) => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "efa-app-"));
    const requestPath = path.join(tempDir, "request.json");
    const resultPath = path.join(tempDir, "result.json");

    fs.writeFileSync(requestPath, JSON.stringify(payload), "utf8");

    const child = spawn("Rscript", [R_SCRIPT, requestPath, resultPath], {
      cwd: __dirname
    });

    let stderr = "";

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });

    child.on("error", (error) => {
      cleanupTemp(tempDir);
      reject(error);
    });

    child.on("close", (code) => {
      if (code !== 0) {
        cleanupTemp(tempDir);
        reject(new Error(stderr.trim() || `R process failed with code ${code}`));
        return;
      }

      try {
        const raw = fs.readFileSync(resultPath, "utf8");
        const parsed = JSON.parse(raw);
        cleanupTemp(tempDir);
        resolve(parsed);
      } catch (error) {
        cleanupTemp(tempDir);
        reject(error);
      }
    });
  });
}

function cleanupTemp(tempDir) {
  fs.rmSync(tempDir, { recursive: true, force: true });
}

const server = http.createServer(async (request, response) => {
  if (request.method === "POST" && request.url === "/api/efa") {
    try {
      const payload = await readJsonBody(request);
      const result = await runAnalysis(payload);
      sendJson(response, 200, result);
    } catch (error) {
      sendJson(response, 400, { error: error.message || "Analysis failed." });
    }
    return;
  }

  if (request.method === "GET") {
    serveStatic(request.url, response);
    return;
  }

  sendJson(response, 405, { error: "Method not allowed" });
});

server.listen(PORT, HOST, () => {
  console.log(`EFA app running at http://${HOST}:${PORT}`);
});
