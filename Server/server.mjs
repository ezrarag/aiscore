import http from "node:http";
import crypto from "node:crypto";

const port = Number(process.env.PORT || 8787);
const openAIKey = process.env.OPENAI_API_KEY;
const allowedOrigin = process.env.ALLOWED_ORIGIN || "*";
const generatedMedia = new Map();
let activeState = {
  activeScoreID: null,
  activeBlockID: null,
  activeSlideID: null,
  scores: [],
  pulses: [],
  constitution: null
};

function json(res, status, value) {
  res.writeHead(status, { "content-type": "application/json", "access-control-allow-origin": allowedOrigin });
  res.end(JSON.stringify(value));
}

async function readJSON(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const data = Buffer.concat(chunks);
  if (data.length > 1_000_000) throw new Error("Request too large");
  return JSON.parse(data.toString("utf8") || "{}");
}

async function openAI(path, body) {
  if (!openAIKey) throw new Error("OPENAI_API_KEY is not configured on the Score server");
  const response = await fetch(`https://api.openai.com/v1${path}`, {
    method: "POST",
    headers: { "authorization": `Bearer ${openAIKey}`, "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload?.error?.message || `OpenAI returned ${response.status}`);
  return payload;
}

function outputText(response) {
  return (response.output || []).flatMap(item => item.content || []).filter(item => item.type === "output_text").map(item => item.text).join("\n");
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") return json(res, 204, {});
  if (req.method === "GET" && req.url === "/health") return json(res, 200, { ok: true, ai: Boolean(openAIKey) });
  if (req.method === "GET" && req.url?.startsWith("/media/")) {
    const item = generatedMedia.get(req.url.slice(7));
    if (!item) return json(res, 404, { error: "Media expired" });
    res.writeHead(200, { "content-type": item.type, "cache-control": "public, max-age=86400" });
    return res.end(item.data);
  }
  if (req.method === "GET" && req.url === "/score/sync") return json(res, 200, activeState);
  if (req.method === "POST" && req.url === "/score/sync") {
    try {
      const body = await readJSON(req);
      if (body.activeScoreID !== undefined) activeState.activeScoreID = body.activeScoreID;
      if (body.activeBlockID !== undefined) activeState.activeBlockID = body.activeBlockID;
      if (body.activeSlideID !== undefined) activeState.activeSlideID = body.activeSlideID;
      if (body.scores !== undefined) activeState.scores = body.scores;
      if (body.pulses !== undefined) activeState.pulses = body.pulses;
      if (body.constitution !== undefined) activeState.constitution = body.constitution;
      return json(res, 200, activeState);
    } catch (e) {
      return json(res, 400, { error: e.message });
    }
  }
  try {
    if (req.method === "POST" && req.url === "/auth/demo") {
      const body = await readJSON(req);
      if (!body.name || !body.email || !["instructor", "student"].includes(body.role)) return json(res, 400, { error: "Invalid account" });
      return json(res, 200, { id: crypto.randomUUID(), name: body.name, email: body.email, role: body.role, token: crypto.randomBytes(24).toString("base64url") });
    }
    if (req.method === "POST" && req.url === "/ai/respond") {
      const body = await readJSON(req);
      const scoreContext = body.score ? `\nCurrent studio score JSON:\n${JSON.stringify(body.score)}` : "";
      const response = await openAI("/responses", {
        model: process.env.OPENAI_TEXT_MODEL || "gpt-5.4-mini",
        instructions: "You are Score, a concise but provocative studio-seminar teaching collaborator. Help instructors shape rhythm, questions, critique, and making. Never flatten uncertainty into generic lesson-plan language.",
        input: `${body.prompt}${scoreContext}`
      });
      return json(res, 200, { text: outputText(response) || "The model returned no text." });
    }
    if (req.method === "POST" && req.url === "/ai/image") {
      const body = await readJSON(req);
      const response = await openAI("/images/generations", {
        model: process.env.OPENAI_IMAGE_MODEL || "gpt-image-2",
        prompt: `Atmospheric widescreen background art for a graduate studio seminar. ${body.prompt}. No text, no logos, generous visual breathing room, presentation-safe composition.`,
        size: "1536x1024"
      });
      const item = response.data?.[0];
      if (item?.url) return json(res, 200, { url: item.url });
      if (item?.b64_json) {
        const id = crypto.randomUUID();
        generatedMedia.set(id, { type: "image/png", data: Buffer.from(item.b64_json, "base64") });
        const host = req.headers.host || `127.0.0.1:${port}`;
        return json(res, 200, { url: `http://${host}/media/${id}` });
      }
      throw new Error("Image generation returned no media");
    }
    return json(res, 404, { error: "Not found" });
  } catch (error) {
    console.error(error);
    return json(res, 500, { error: error.message || "Server error" });
  }
});

server.listen(port, "127.0.0.1", () => console.log(`Score server listening at http://127.0.0.1:${port}`));
