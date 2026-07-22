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
OPENAI_API_KEY=your_key_here npm start
```

The app defaults to `http://127.0.0.1:8787`. Change the URL in Settings when testing on a physical device. The demo sign-in falls back to local mode when the server is unavailable; AI requests require the server.

## Security and production notes

The current `/auth/demo` endpoint creates an ephemeral identity. It is deliberately isolated behind `APIClient` so a production identity provider and persistent database can replace it without rewriting the SwiftUI views. Before a public deployment, add verified authentication, authorization by course/session, durable storage, rate limits, moderation policy, HTTPS, and signed media URLs.

Remote media is displayed by URL and should only be used with permission. The macOS terminal executes local shell commands with the app’s sandbox constraints; it is intentionally unavailable on iPhone and iPad.
