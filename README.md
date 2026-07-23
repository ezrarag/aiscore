# aiscore
# Score

A live, multiplatform teaching instrument for UWM’s **Crafting AI** studio seminar.

## What is running

- Editable week-by-week score with spreadsheet-style cumulative start times
- Instructor and student experiences
- Local JSON persistence in Application Support
- AI teaching copilot through a server-side OpenAI Responses API boundary
- AI-generated background images, HTTPS image/video imports, and local generative motion art
- A real process-backed studio terminal on macOS
- One shared SwiftUI codebase for macOS 14+, iOS/iPadOS 17+

## Open the app

```sh
xcodegen generate
open Score.xcodeproj
```

Choose the `Score` scheme and a Mac, iPhone, or iPad destination. Signing is intentionally left to your local Apple development team.

## Run the local server

Node 20+ is required. Keep the API key here—never in the Apple app:

```sh
cd Server
cp .env.example .env
# Edit .env and add your API credentials, then:
npm start
```

The app defaults to `http://127.0.0.1:8787`. Change the URL in Settings when testing on a physical device. The demo sign-in falls back to local mode when the server is unavailable; AI requests require the server.

### Choose an AI provider and fallbacks

Score supports OpenAI, Anthropic, and Gemini behind the same server interface. Configure the primary provider and optional fallback order in `Server/.env`:

```dotenv
LLM_PROVIDER=anthropic
LLM_FALLBACK_ORDER=gemini,openai

ANTHROPIC_API_KEY=your_key
ANTHROPIC_TEXT_MODEL=your_anthropic_model
GEMINI_API_KEY=your_key
GEMINI_TEXT_MODEL=your_gemini_model
OPENAI_API_KEY=your_key
OPENAI_TEXT_MODEL=your_openai_model
OPENAI_IMAGE_MODEL=your_openai_image_model
```

Restart `npm start` after changing `.env`. The router falls back only for missing keys, authentication failures, quota/billing failures, or an unsupported capability. It logs the provider that served each request without logging credentials. Anthropic does not provide image generation; leave `ANTHROPIC_IMAGE_MODEL` empty. Gemini image output requires a compatible model in `GEMINI_IMAGE_MODEL`; otherwise an image request can fall back to OpenAI when configured.

Inspect configuration without exposing secrets:

```sh
curl http://127.0.0.1:8787/health
```

The response identifies the primary, active, and fallback providers and reports only whether each key is loaded.

## Security and production notes

The current `/auth/demo` endpoint creates an ephemeral identity. It is deliberately isolated behind `APIClient` so a production identity provider and persistent database can replace it without rewriting the SwiftUI views. Before a public deployment, add verified authentication, authorization by course/session, durable storage, rate limits, moderation policy, HTTPS, and signed media URLs.

Remote media is displayed by URL and should only be used with permission. The macOS terminal executes local shell commands with the app’s sandbox constraints; it is intentionally unavailable on iPhone and iPad.
