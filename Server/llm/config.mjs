export const PROVIDER_NAMES = ["openai", "anthropic", "gemini"];

// Centralized, behavior-preserving defaults. Override every value in Server/.env.
export const MODEL_DEFAULTS = Object.freeze({
  openai: { text: "gpt-5.4-mini", image: "gpt-image-2" },
  anthropic: { text: "claude-sonnet-4-5", image: "" },
  gemini: { text: "gemini-2.5-flash", image: "" }
});

function providerName(value, fallback = "openai") {
  const normalized = String(value || fallback).trim().toLowerCase();
  if (!PROVIDER_NAMES.includes(normalized)) {
    throw new Error(`Unsupported LLM_PROVIDER '${normalized}'. Expected ${PROVIDER_NAMES.join(", ")}.`);
  }
  return normalized;
}

function fallbackOrder(value, primary) {
  const requested = String(value || "").split(",").map(item => item.trim().toLowerCase()).filter(Boolean);
  for (const name of requested) providerName(name);
  return [...new Set(requested.filter(name => name !== primary))];
}

export function loadLLMConfig(env = process.env) {
  const primary = providerName(env.LLM_PROVIDER);
  return {
    primary,
    fallbackOrder: fallbackOrder(env.LLM_FALLBACK_ORDER, primary),
    providers: {
      openai: {
        apiKey: env.OPENAI_API_KEY || "",
        textModel: env.OPENAI_TEXT_MODEL || MODEL_DEFAULTS.openai.text,
        imageModel: env.OPENAI_IMAGE_MODEL || MODEL_DEFAULTS.openai.image
      },
      anthropic: {
        apiKey: env.ANTHROPIC_API_KEY || "",
        textModel: env.ANTHROPIC_TEXT_MODEL || MODEL_DEFAULTS.anthropic.text,
        imageModel: env.ANTHROPIC_IMAGE_MODEL || MODEL_DEFAULTS.anthropic.image,
        version: env.ANTHROPIC_VERSION || "2023-06-01"
      },
      gemini: {
        apiKey: env.GEMINI_API_KEY || "",
        textModel: env.GEMINI_TEXT_MODEL || MODEL_DEFAULTS.gemini.text,
        imageModel: env.GEMINI_IMAGE_MODEL || MODEL_DEFAULTS.gemini.image
      }
    }
  };
}
