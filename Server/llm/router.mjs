import { OpenAIProvider } from "./providers/openai.mjs";
import { AnthropicProvider } from "./providers/anthropic.mjs";
import { GeminiProvider } from "./providers/gemini.mjs";
import { ProviderError } from "./errors.mjs";

export function createLLMRouter(config, logger = console) {
  const providers = {
    openai: new OpenAIProvider(config.providers.openai),
    anthropic: new AnthropicProvider(config.providers.anthropic),
    gemini: new GeminiProvider(config.providers.gemini)
  };
  const configuredOrder = [config.primary, ...config.fallbackOrder];
  let activeProvider = configuredOrder.find(name => providers[name].configured) || config.primary;

  async function run(capability, request) {
    const order = [config.primary, ...config.fallbackOrder];
    const failures = [];
    for (const name of order) {
      const provider = providers[name];
      try {
        const result = capability === "image"
          ? await provider.generateImage(request)
          : await provider.generateText(request);
        activeProvider = name;
        logger.info(`[llm] ${capability} request served by ${name}`);
        return { ...result, provider: name };
      } catch (error) {
        const failure = error instanceof ProviderError
          ? error : new ProviderError(name, error.message || "request failed", { cause: error });
        failures.push(failure);
        logger.warn(`[llm] ${name} failed: ${failure.message}`);
        if (!failure.fallbackEligible) throw failure;
      }
    }
    const detail = failures.map(failure => failure.message).join("; ");
    throw new ProviderError(config.primary, `all configured providers failed: ${detail}`);
  }

  return {
    generateText: request => run("text", request),
    generateImage: request => run("image", request),
    health() {
      const statuses = Object.fromEntries(Object.entries(providers).map(([name, provider]) => [name, {
        keyLoaded: provider.configured,
        textModel: provider.config.textModel || null,
        imageModel: provider.config.imageModel || null,
        imageGeneration: provider.supportsImageGeneration
      }]));
      return {
        activeProvider,
        primaryProvider: config.primary,
        fallbackOrder: config.fallbackOrder,
        providers: statuses,
        ai: Object.values(statuses).some(status => status.keyLoaded)
      };
    }
  };
}
