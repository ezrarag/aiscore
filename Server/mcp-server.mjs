import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import crypto from "node:crypto";

const scoreServerURL = process.env.SCORE_SERVER_URL || "http://127.0.0.1:8787";
const server = new McpServer({ name: "aiscore", version: "0.1.0" });

async function scoreRequest(path, options = {}) {
  const response = await fetch(`${scoreServerURL}${path}`, options);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || `Score returned HTTP ${response.status}`);
  return payload;
}

function normalizedTitle(title) {
  return String(title || "").toLowerCase()
    .replace(/^\s*slide\s+\d+\s*[-—:–]?\s*/u, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

server.registerTool("score_get_current", {
  description: "Read the current Score deck, blocks, slides, active selection, and course context before preparing or reconciling slides.",
  inputSchema: z.object({})
}, async () => {
  const state = await scoreRequest("/score/sync");
  return { content: [{ type: "text", text: JSON.stringify(state, null, 2) }] };
});

server.registerTool("score_get_slide_import_instructions", {
  description: "Get the rules Claude should follow when converting notes or a PDF into a non-duplicative Score slide manifest.",
  inputSchema: z.object({})
}, async () => ({
  content: [{ type: "text", text: [
    "Call score_get_current first.",
    "Match slides by purpose and meaning. Reuse the exact existing title for a match.",
    "Consolidate duplicates and add only necessary scaffolding, evidence, activity, transition, reflection, or closure.",
    "Keep audience text concise; place sources, timing, and facilitation in notes.",
    "Then call score_apply_slide_manifest with the complete reconciled manifest."
  ].join("\n") }]
}));

const slideSchema = z.object({
  title: z.string().min(1),
  body: z.string(),
  notes: z.string()
});

server.registerTool("score_apply_slide_manifest", {
  description: "Update matching slides and append genuinely new slides to the active Score. Call score_get_current first and ask the user to confirm before applying.",
  inputSchema: z.object({ slides: z.array(slideSchema).min(1).max(100) }),
  annotations: { title: "Apply Score slide manifest", destructiveHint: false, idempotentHint: true }
}, async ({ slides }) => {
  const state = await scoreRequest("/score/sync");
  const scores = state.scores || [];
  const scoreIndex = Math.max(0, scores.findIndex(score => score.id === state.activeScoreID));
  const score = scores[scoreIndex];
  if (!score) throw new Error("No active Score deck is available.");
  if (!score.blocks?.length) throw new Error("The active Score has no blocks to receive slides.");

  let updated = 0;
  let added = 0;
  for (const incoming of slides) {
    const key = normalizedTitle(incoming.title);
    let existing = null;
    for (const block of score.blocks) {
      const slide = block.slides?.find(candidate => normalizedTitle(candidate.title) === key);
      if (slide) { existing = slide; break; }
    }
    if (existing) {
      existing.title = incoming.title;
      existing.bodyText = incoming.body;
      existing.notes = incoming.notes;
      updated += 1;
    } else {
      score.blocks.at(-1).slides.push({
        id: crypto.randomUUID(), title: incoming.title, bodyText: incoming.body,
        mediaType: "none", approvalState: "pending", notes: incoming.notes,
        template: "Standard Minimal", layout: "Standard Text", slideLabel: "INFO", mediaItems: []
      });
      added += 1;
    }
  }
  await scoreRequest("/score/sync", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ ...state, scores })
  });
  return { content: [{ type: "text", text: `Applied manifest: updated ${updated}, added ${added}.` }] };
});

const transport = new StdioServerTransport();
await server.connect(transport);
