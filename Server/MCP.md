# Score MCP server for Claude Desktop

This optional stdio MCP server lets Claude Desktop read the current Score and apply a reconciled slide manifest. Claude supplies the model reasoning, so these tools do not use `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `GEMINI_API_KEY`. The local Score HTTP server must still be running because it owns the live in-memory class state.

Install dependencies:

```sh
cd "/Users/ehauga/Desktop/local dev/aiscore/Server"
npm install
```

Add this entry to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "aiscore": {
      "command": "/usr/local/bin/node",
      "args": [
        "/Users/ehauga/Desktop/local dev/aiscore/Server/mcp-server.mjs"
      ],
      "env": {
        "SCORE_SERVER_URL": "http://127.0.0.1:8787"
      }
    }
  }
}
```

Replace `/usr/local/bin/node` with the output of `which node`. Restart Claude Desktop after editing its configuration.

Suggested Claude request:

> Read the attached PDF, call `score_get_slide_import_instructions`, then call `score_get_current`. Prepare a reconciled manifest with no duplicate slide purposes. Show me the proposed updates and additions for confirmation. Only after I confirm, call `score_apply_slide_manifest`.

Available tools:

- `score_get_current` - read-only current deck context.
- `score_get_slide_import_instructions` - read-only reconciliation rules.
- `score_apply_slide_manifest` - updates exact normalized-title matches and adds unmatched slides as pending drafts.
