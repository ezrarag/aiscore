import { LLMProvider, messageText } from "../provider.mjs";
import { classifyHTTPFailure, ProviderError } from "../errors.mjs";

export class AnthropicProvider extends LLMProvider {
  constructor(config) { super("anthropic", config); }

  async generateText({ system, messages, model, responseSchema }) {
    this.requireKey();
    const schemaInstruction = responseSchema
      ? `\n\nReturn only valid JSON matching this JSON Schema:\n${JSON.stringify(responseSchema)}` : "";
    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": this.config.apiKey,
        "anthropic-version": this.config.version,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        model: model || this.config.textModel,
        max_tokens: 8192,
        system: `${system || ""}${schemaInstruction}`,
        messages: messages.map(message => ({
          role: message.role === "assistant" ? "assistant" : "user",
          content: String(message.content || "")
        }))
      })
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw classifyHTTPFailure(this.name, response.status, payload);
    const text = (payload.content || []).filter(item => item.type === "text").map(item => item.text).join("\n");
    if (!text) throw new ProviderError(this.name, "the model returned no text");
    return { text };
  }
}
