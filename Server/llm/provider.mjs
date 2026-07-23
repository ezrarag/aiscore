import { ProviderError } from "./errors.mjs";

export class LLMProvider {
  constructor(name, config) {
    this.name = name;
    this.config = config;
  }

  get configured() { return Boolean(this.config.apiKey); }
  get supportsImageGeneration() { return false; }

  requireKey() {
    if (!this.configured) {
      throw new ProviderError(this.name, `${this.name.toUpperCase()}_API_KEY is not configured`, { fallbackEligible: true });
    }
  }

  async generateText(_request) { throw new Error("generateText must be implemented"); }

  async generateImage(_request) {
    throw new ProviderError(this.name, "image generation is not supported by this provider", { fallbackEligible: true });
  }
}

export function messageText(messages = []) {
  return messages.map(message => `${message.role || "user"}: ${message.content || ""}`).join("\n\n");
}
