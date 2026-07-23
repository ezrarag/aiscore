import { LLMProvider } from "../provider.mjs";
import { classifyHTTPFailure, ProviderError } from "../errors.mjs";

export class OpenAIProvider extends LLMProvider {
  constructor(config) { super("openai", config); }
  get supportsImageGeneration() { return Boolean(this.config.imageModel); }

  async request(path, body) {
    this.requireKey();
    const response = await fetch(`https://api.openai.com/v1${path}`, {
      method: "POST",
      headers: { authorization: `Bearer ${this.config.apiKey}`, "content-type": "application/json" },
      body: JSON.stringify(body)
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw classifyHTTPFailure(this.name, response.status, payload);
    return payload;
  }

  async generateText({ system, messages, model, responseSchema }) {
    const body = {
      model: model || this.config.textModel,
      instructions: system,
      input: messages.map(message => ({ role: message.role === "assistant" ? "assistant" : "user", content: message.content }))
    };
    if (responseSchema) body.text = { format: { type: "json_schema", name: "score_response", strict: true, schema: responseSchema } };
    const payload = await this.request("/responses", body);
    const text = (payload.output || []).flatMap(item => item.content || [])
      .filter(item => item.type === "output_text").map(item => item.text).join("\n");
    if (!text) throw new ProviderError(this.name, "the model returned no text");
    return { text };
  }

  async generateImage({ prompt, model }) {
    if (!this.supportsImageGeneration) return super.generateImage({ prompt, model });
    const payload = await this.request("/images/generations", {
      model: model || this.config.imageModel, prompt, size: "1536x1024"
    });
    const item = payload.data?.[0];
    if (item?.url) return { url: item.url };
    if (item?.b64_json) return { data: item.b64_json, mimeType: "image/png" };
    throw new ProviderError(this.name, "image generation returned no media");
  }
}
