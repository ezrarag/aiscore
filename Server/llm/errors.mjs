export class ProviderError extends Error {
  constructor(provider, message, { status = null, fallbackEligible = false, cause = null } = {}) {
    super(`[${provider}] ${message}`, { cause });
    this.name = "ProviderError";
    this.provider = provider;
    this.status = status;
    this.fallbackEligible = fallbackEligible;
  }
}

export function classifyHTTPFailure(provider, status, payload) {
  const message = payload?.error?.message || payload?.error?.status || payload?.message || `${provider} returned HTTP ${status}`;
  const normalized = String(message).toLowerCase();
  const fallbackEligible = status === 401 || status === 403 || status === 429 ||
    normalized.includes("quota") || normalized.includes("billing") || normalized.includes("credit") || normalized.includes("api key");
  return new ProviderError(provider, message, { status, fallbackEligible });
}
