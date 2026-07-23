import test from "node:test";
import assert from "node:assert/strict";
import { createLLMRouter } from "../llm/router.mjs";

const silentLogger = { info() {}, warn() {} };

test("falls back from a missing primary key and reports the serving provider", { concurrency: false }, async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async url => {
    assert.match(String(url), /anthropic\.com/);
    return new Response(JSON.stringify({ content: [{ type: "text", text: "served by Claude" }] }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const router = createLLMRouter({
      primary: "openai", fallbackOrder: ["anthropic"], providers: {
        openai: { apiKey: "", textModel: "openai-test", imageModel: "openai-image-test" },
        anthropic: { apiKey: "test-key", textModel: "anthropic-test", imageModel: "", version: "2023-06-01" },
        gemini: { apiKey: "", textModel: "gemini-test", imageModel: "" }
      }
    }, silentLogger);
    const result = await router.generateText({ system: "test", messages: [{ role: "user", content: "hello" }] });
    assert.equal(result.provider, "anthropic");
    assert.equal(result.text, "served by Claude");
    assert.equal(router.health().activeProvider, "anthropic");
  } finally { globalThis.fetch = originalFetch; }
});

test("falls back when the primary provider cannot generate images", { concurrency: false }, async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async url => {
    assert.match(String(url), /api\.openai\.com/);
    return new Response(JSON.stringify({ data: [{ b64_json: "aW1hZ2U=" }] }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const router = createLLMRouter({
      primary: "anthropic", fallbackOrder: ["openai"], providers: {
        openai: { apiKey: "test-key", textModel: "openai-test", imageModel: "openai-image-test" },
        anthropic: { apiKey: "test-key", textModel: "anthropic-test", imageModel: "", version: "2023-06-01" },
        gemini: { apiKey: "", textModel: "gemini-test", imageModel: "" }
      }
    }, silentLogger);
    const result = await router.generateImage({ prompt: "test image" });
    assert.equal(result.provider, "openai");
    assert.equal(result.mimeType, "image/png");
  } finally { globalThis.fetch = originalFetch; }
});

test("falls back after an authentication or quota response", { concurrency: false }, async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async url => {
    calls += 1;
    if (String(url).includes("api.openai.com")) {
      return new Response(JSON.stringify({ error: { message: "quota exceeded" } }), {
        status: 429, headers: { "content-type": "application/json" }
      });
    }
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: "Gemini fallback" }] } }] }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const router = createLLMRouter({
      primary: "openai", fallbackOrder: ["gemini"], providers: {
        openai: { apiKey: "test-key", textModel: "openai-test", imageModel: "" },
        anthropic: { apiKey: "", textModel: "anthropic-test", imageModel: "", version: "2023-06-01" },
        gemini: { apiKey: "test-key", textModel: "gemini-test", imageModel: "" }
      }
    }, silentLogger);
    const result = await router.generateText({ system: "test", messages: [{ role: "user", content: "hello" }] });
    assert.equal(result.provider, "gemini");
    assert.equal(result.text, "Gemini fallback");
    assert.equal(calls, 2);
  } finally { globalThis.fetch = originalFetch; }
});

test("health never exposes API key values", () => {
  const router = createLLMRouter({
    primary: "gemini", fallbackOrder: [], providers: {
      openai: { apiKey: "secret-openai", textModel: "o", imageModel: "" },
      anthropic: { apiKey: "secret-anthropic", textModel: "a", imageModel: "", version: "2023-06-01" },
      gemini: { apiKey: "secret-gemini", textModel: "g", imageModel: "" }
    }
  }, silentLogger);
  const serialized = JSON.stringify(router.health());
  assert.doesNotMatch(serialized, /secret-/);
  assert.equal(router.health().providers.gemini.keyLoaded, true);
});
