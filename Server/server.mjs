import http from "node:http";
import crypto from "node:crypto";
import { loadLLMConfig } from "./llm/config.mjs";
import { createLLMRouter } from "./llm/router.mjs";

const port = Number(process.env.PORT || 8787);
const allowedOrigin = process.env.ALLOWED_ORIGIN || "*";
const generatedMedia = new Map();
const llm = createLLMRouter(loadLLMConfig());
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

const slideSchema = {
  type: "object",
  properties: { slides: { type: "array", minItems: 1, maxItems: 60, items: {
    type: "object",
    properties: { title: { type: "string" }, body: { type: "string" }, notes: { type: "string" } },
    required: ["title", "body", "notes"], additionalProperties: false
  } } },
  required: ["slides"], additionalProperties: false
};

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") return json(res, 204, {});
  if (req.method === "GET" && req.url === "/health") return json(res, 200, { ok: true, ...llm.health() });
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
      const response = await llm.generateText({
        system: "You are Score, a concise but provocative studio-seminar teaching collaborator. Help instructors shape rhythm, questions, critique, and making. Never flatten uncertainty into generic lesson-plan language.",
        messages: [{ role: "user", content: `${body.prompt}${scoreContext}` }]
      });
      return json(res, 200, { text: response.text, provider: response.provider });
    }
    if (req.method === "POST" && req.url === "/ai/slides") {
      const body = await readJSON(req);
      if (!body.prompt?.trim()) return json(res, 400, { error: "A slide description is required" });
      const response = await llm.generateText({
        system: "Turn the requested teaching or presentation scope into a concise canonical sequence of slides. Reconcile against the current score context: reuse an existing slide title exactly when it serves the same purpose, consolidate duplicates, and add only missing scaffolding. Each slide needs an expressive title, concise audience-facing body text, and practical presenter notes with source-page references. Preserve useful uncertainty and citations; avoid generic filler.",
        messages: [{ role: "user", content: `${body.prompt}\n\nCurrent score context:\n${JSON.stringify(body.score || {})}` }],
        responseSchema: slideSchema
      });
      const parsed = JSON.parse(response.text.replace(/^```(?:json)?\s*|\s*```$/g, ""));
      return json(res, 200, { ...parsed, provider: response.provider });
    }
    if (req.method === "POST" && req.url === "/ai/image") {
      const body = await readJSON(req);
      const response = await llm.generateImage({
        prompt: `Atmospheric widescreen background art for a graduate studio seminar. ${body.prompt}. No text, no logos, generous visual breathing room, presentation-safe composition.`
      });
      if (response.url) return json(res, 200, { url: response.url, provider: response.provider });
      if (response.data) {
        const id = crypto.randomUUID();
        generatedMedia.set(id, { type: response.mimeType || "image/png", data: Buffer.from(response.data, "base64") });
        const host = req.headers.host || `127.0.0.1:${port}`;
        return json(res, 200, { url: `http://${host}/media/${id}`, provider: response.provider });
      }
      throw new Error("Image generation returned no media");
    }
    return json(res, 404, { error: "Not found" });
  } catch (error) {
    console.error(error.message || error);
    return json(res, 500, { error: error.message || "Server error", provider: error.provider || null });
  }
});

server.listen(port, "127.0.0.1", () => console.log(`Score server listening at http://127.0.0.1:${port}`));
