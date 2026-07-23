import { LLMProvider } from "../provider.mjs";
import { classifyHTTPFailure, ProviderError } from "../errors.mjs";

export class GeminiProvider extends LLMProvider {
  constructor(config) { super("gemini", config); }
  get supportsImageGeneration() { return Boolean(this.config.imageModel); }

  async generate({ system, messages, model, generationConfig = {} }) {
    this.requireKey();
    const selectedModel = model || this.config.textModel;
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(selectedModel)}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": this.config.apiKey, "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: system ? { parts: [{ text: system }] } : undefined,
        contents: messages.map(message => ({
          role: message.role === "assistant" ? "model" : "user",
          parts: [{ text: String(message.content || "") }]
        })),
        generationConfig
      })
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw classifyHTTPFailure(this.name, response.status, payload);
    return payload;
  }

  async generateText({ system, messages, model, responseSchema }) {
    const generationConfig = responseSchema
      ? { responseMimeType: "application/json", responseJsonSchema: responseSchema } : {};
    const payload = await this.generate({ system, messages, model, generationConfig });
    const text = (payload.candidates?.[0]?.content?.parts || []).map(part => part.text || "").join("\n");
    if (!text) throw new ProviderError(this.name, "the model returned no text");
    return { text };
  }

  async generateImage({ prompt, model }) {
    if (!this.supportsImageGeneration) return super.generateImage({ prompt, model });
    const payload = await this.generate({
      system: "Generate a presentation-safe image from the user's description.",
      messages: [{ role: "user", content: prompt }],
      model: model || this.config.imageModel,
      generationConfig: { responseModalities: ["TEXT", "IMAGE"] }
    });
    const parts = payload.candidates?.[0]?.content?.parts || [];
    const image = parts.find(part => part.inlineData?.data);
    if (!image) throw new ProviderError(this.name, "the configured Gemini model returned no image");
    return { data: image.inlineData.data, mimeType: image.inlineData.mimeType || "image/png" };
  }
}
