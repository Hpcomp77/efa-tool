export default async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const apiUrl = Netlify.env.get("R_ANALYSIS_API_URL");

  if (!apiUrl) {
    return json(
      {
        error:
          "R_ANALYSIS_API_URL is not configured. Deploy the R API separately and add its URL as a Netlify environment variable."
      },
      500
    );
  }

  try {
    const upstream = await fetch(apiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: await request.text()
    });

    const body = await upstream.text();

    return new Response(body, {
      status: upstream.status,
      headers: {
        "Content-Type": upstream.headers.get("content-type") || "application/json; charset=utf-8"
      }
    });
  } catch (error) {
    return json(
      {
        error: error.message || "Unable to reach the R analysis service."
      },
      502
    );
  }
};

export const config = {
  path: "/api/efa",
  method: ["POST"]
};

function json(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" }
  });
}
