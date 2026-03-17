# Open Brain - MCP Server

> Model Context Protocol server implementation, tool definitions, and client configuration.

---

## What Is MCP?

**Model Context Protocol (MCP)** is Anthropic's open standard for connecting AI assistants to external tools and data sources. It enables any compatible AI client (Claude, ChatGPT, Gemini, Cursor) to call tools exposed by an MCP server over HTTP.

Open Brain's MCP server is a **Supabase Edge Function** that exposes four tools for reading and writing to your thoughts database.

---

## Server Architecture

```
AI Client (Claude, ChatGPT, etc.)
    ↓ HTTP POST (MCP protocol)
    ↓ Auth: x-brain-key header or ?key= param
    ↓
Edge Function: open-brain-mcp
    ├─ Hono web framework (routing)
    ├─ MCP protocol handler (tool dispatch)
    ├─ OpenRouter client (embeddings)
    └─ Supabase client (database)
    ↓
PostgreSQL + pgvector
```

### Technology Stack

| Component | Technology | Why |
|---|---|---|
| Runtime | Deno (Supabase Edge Functions) | Serverless, no infra to manage |
| Framework | Hono | Lightweight, fast, Deno-native |
| Protocol | MCP (HTTP+SSE transport) | Universal AI client compatibility |
| Database | Supabase JS Client | Auto-injected credentials |
| Embeddings | OpenRouter API | Model-agnostic gateway |

---

## Tool Definitions

### Tool 1: `search_thoughts`

**Purpose**: Semantic vector search — find thoughts by meaning, not exact keywords.

```json
{
    "name": "search_thoughts",
    "description": "Search your brain for thoughts semantically related to a query. Returns results ranked by similarity.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "Natural language search query"
            },
            "limit": {
                "type": "integer",
                "description": "Maximum results to return (default: 10)",
                "default": 10
            },
            "threshold": {
                "type": "number",
                "description": "Minimum similarity score 0-1 (default: 0.5)",
                "default": 0.5
            }
        },
        "required": ["query"]
    }
}
```

**Process:**
1. Embed the query string via OpenRouter (text-embedding-3-small)
2. Call `match_thoughts()` RPC with the query embedding
3. Return results with content, metadata, similarity score, and timestamp

**Example Call:**
```json
{
    "tool": "search_thoughts",
    "arguments": {
        "query": "What did we decide about the database migration?",
        "limit": 5,
        "threshold": 0.4
    }
}
```

---

### Tool 2: `list_thoughts`

**Purpose**: Filtered listing — browse thoughts by type, topic, person, or date range.

```json
{
    "name": "list_thoughts",
    "description": "List thoughts filtered by type, topic, person mentioned, or time range.",
    "inputSchema": {
        "type": "object",
        "properties": {
            "type": {
                "type": "string",
                "description": "Filter by thought type: observation, task, idea, reference, person_note, decision, meeting"
            },
            "topic": {
                "type": "string",
                "description": "Filter by topic tag"
            },
            "person": {
                "type": "string",
                "description": "Filter by person mentioned"
            },
            "days": {
                "type": "integer",
                "description": "Only return thoughts from the last N days"
            }
        }
    }
}
```

**Process:**
1. Build Supabase query with applied filters
2. Use JSONB containment (`@>`) for metadata filters
3. Use `>=` for date range filtering
4. Return ordered by `created_at DESC`, limit 50

**Example Call:**
```json
{
    "tool": "list_thoughts",
    "arguments": {
        "type": "decision",
        "days": 30
    }
}
```

---

### Tool 3: `capture_thought`

**Purpose**: Store a new thought with auto-generated embedding and metadata.

```json
{
    "name": "capture_thought",
    "description": "Save a new thought to your brain. Automatically generates embedding and extracts metadata (type, topics, people, action items).",
    "inputSchema": {
        "type": "object",
        "properties": {
            "content": {
                "type": "string",
                "description": "The thought to capture (raw text)"
            }
        },
        "required": ["content"]
    }
}
```

**Process:**
1. Run embedding generation and metadata extraction **in parallel**
2. Insert content + embedding + metadata into `thoughts` table
3. Tag with `source: "mcp"`
4. Return confirmation with extracted metadata

**Example Call:**
```json
{
    "tool": "capture_thought",
    "arguments": {
        "content": "Decision: Using PostgreSQL with pgvector instead of Pinecone. Reason: self-hosted, lower cost, simpler stack. Discussed with Mike."
    }
}
```

**Example Response:**
```json
{
    "id": "a1b2c3d4-...",
    "type": "decision",
    "topics": ["database", "infrastructure"],
    "people": ["Mike"],
    "captured_at": "2026-03-07T14:30:00Z"
}
```

---

### Tool 4: `thought_stats`

**Purpose**: Aggregate statistics about your brain's contents.

```json
{
    "name": "thought_stats",
    "description": "Get statistics about your brain: total thoughts, type distribution, top topics, and top people mentioned.",
    "inputSchema": {
        "type": "object",
        "properties": {}
    }
}
```

**Process:**
1. Count total thoughts
2. Aggregate by type
3. Rank top 10 topics and people mentioned
4. Calculate date range of captures

**Example Response:**
```json
{
    "total_thoughts": 247,
    "types": {
        "observation": 89,
        "decision": 45,
        "idea": 38,
        "task": 32,
        "person_note": 25,
        "reference": 18
    },
    "top_topics": [
        ["api-design", 34],
        ["architecture", 28],
        ["performance", 22]
    ],
    "top_people": [
        ["Sarah", 15],
        ["Mike", 12],
        ["Team", 8]
    ]
}
```

---

## Client Configuration

### Self-Hosted (K8s + Tailscale)

These configs connect to your self-hosted Open Brain running on your K8s cluster.

### URL Reference

| Network | Protocol | URL |
|---|---|---|
| On tailnet | HTTP | `http://openbrain.tailfb4202.ts.net:8080/sse?key=<KEY>` |
| Off tailnet (Funnel) | HTTPS | `https://openbrain.tailfb4202.ts.net/sse?key=<KEY>` |
| LAN only | HTTP | `http://192.168.68.120:8080/sse?key=<KEY>` |

#### Claude Desktop (any network — via Tailscale Funnel)

Claude Desktop does **not** support SSE transport directly. Use `mcp-remote` as a stdio-to-SSE bridge.

Add to `claude_desktop_config.json`:

**Off tailnet (Funnel — public HTTPS):**
```json
{
    "mcpServers": {
        "openbrain": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://openbrain.tailfb4202.ts.net/sse?key=<MCP_ACCESS_KEY>"]
        }
    }
}
```

**On tailnet (private):**
```json
{
    "mcpServers": {
        "openbrain": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "http://openbrain.tailfb4202.ts.net:8080/sse?key=<MCP_ACCESS_KEY>"]
        }
    }
}
```

> **Requires**: Node.js installed. `mcp-remote` is fetched automatically by `npx`.

#### Claude Code / VS Code Copilot

Add to `~/.claude/settings.json`:

**On tailnet:**
```json
{
    "mcpServers": {
        "openbrain": {
            "type": "sse",
            "url": "http://openbrain.tailfb4202.ts.net:8080/sse?key=<MCP_ACCESS_KEY>"
        }
    }
}
```

**Off tailnet (Funnel):**
```json
{
    "mcpServers": {
        "openbrain": {
            "type": "sse",
            "url": "https://openbrain.tailfb4202.ts.net/sse?key=<MCP_ACCESS_KEY>"
        }
    }
}
```

#### Cursor

Add to `.cursor/mcp.json`:

**On tailnet:**
```json
{
    "mcpServers": {
        "openbrain": {
            "url": "http://openbrain.tailfb4202.ts.net:8080/sse?key=<MCP_ACCESS_KEY>",
            "transport": "sse"
        }
    }
}
```

**Off tailnet (Funnel):**
```json
{
    "mcpServers": {
        "openbrain": {
            "url": "https://openbrain.tailfb4202.ts.net/sse?key=<MCP_ACCESS_KEY>",
            "transport": "sse"
        }
    }
}
```

#### ChatGPT

1. Enable **Developer Mode** in ChatGPT settings
2. Add MCP connector with URL (use Funnel URL — ChatGPT needs public access):
   ```
   https://openbrain.tailfb4202.ts.net/sse?key=<MCP_ACCESS_KEY>
   ```
3. Set authentication to **"none"** (key is in URL)
4. **Note**: ChatGPT disables its built-in memory when Developer Mode is active — Open Brain replaces this functionality

#### Gemini

Use Funnel URL (Gemini needs public access):
```
https://openbrain.tailfb4202.ts.net/sse?key=<MCP_ACCESS_KEY>
```

---

### Supabase Cloud (Original)

If using the Supabase-hosted version instead of self-hosted K8s:

#### Claude Desktop (Supabase)

```json
{
    "mcpServers": {
        "open-brain": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://<your-ref>.supabase.co/functions/v1/open-brain-mcp/sse?key=<your-64-char-hex-key>"]
        }
    }
}
```

#### Claude Code (Supabase)

```json
{
    "mcpServers": {
        "open-brain": {
            "type": "sse",
            "url": "https://<your-ref>.supabase.co/functions/v1/open-brain-mcp/sse?key=<your-64-char-hex-key>"
        }
    }
}
```

---

## Authentication Details

### MCP Access Key

- **Format**: 64-character hexadecimal string
- **Generation**: `openssl rand -hex 32`
- **Storage**: Supabase Edge Function secret (`MCP_ACCESS_KEY`)
- **Transmission**: `x-brain-key` header (preferred) OR `?key=` URL param (fallback)

### Auth Flow

```
1. Client connects to /sse with key (x-brain-key header or ?key= URL param)
2. Server validates key against MCP_ACCESS_KEY environment variable
3. 401 if invalid/missing → connection rejected
4. If valid → SSE session created, session ID issued
5. Subsequent /messages POSTs authenticated implicitly via session ID
   (no key required — having a valid sessionId proves prior authentication)
```

> **Note**: The `/messages` endpoint does NOT require the API key. This is intentional —
> `mcp-remote` and other SSE clients POST to `/messages?sessionId=xxx` without including
> the key. Authentication is enforced at connection time on `/sse`.

### Security Considerations

- URL parameter method exposes key in server logs and browser history — use header method when possible
- Rotate key periodically by updating the K8s secret and client configs
- Never commit the key to source control
- Each user/deployment should have a unique key

---

## Troubleshooting

### "Tool not found" in AI client
- Verify MCP server URL is correct
- Check that the server is running: `kubectl get pods -n openbrain`
- Test health: `curl https://openbrain.tailfb4202.ts.net/health`

### "No active session. Connect to /sse first."
- **Cause**: SSE connection and `/messages` POST are hitting different pods
- **Fix**: Enable session affinity on the ClusterIP service:
  ```bash
  kubectl patch svc openbrain-api -n openbrain \
    -p '{"spec":{"sessionAffinity":"ClientIP"}}'
  ```

### mcp-remote ServerError / OAuth errors
- **Cause**: The `/messages` endpoint is returning 401, triggering mcp-remote's OAuth flow
- **Fix**: Auth must only be enforced on `/sse`, not on `/messages`. The session ID on `/messages` already proves authentication. Check `src/index.ts`.

### Claude Desktop doesn't show OpenBrain tools
- Verify config file: `%APPDATA%\Claude\claude_desktop_config.json`
- Must have `mcpServers.openbrain` entry — Claude Desktop may overwrite on launch
- Fully quit (system tray → Quit) and relaunch after config changes
- Check MCP logs: `%APPDATA%\Claude\logs\mcp-server-openbrain.log`

### ChatGPT doesn't auto-use Open Brain tools
- ChatGPT is less intuitive than Claude at picking MCP tools automatically
- Explicitly instruct: "Use the Open Brain search_thoughts tool to find..."
- Usually becomes automatic after 1-2 demonstrations

### Search returns no results
- Check thought count with `thought_stats` tool
- Under 20-30 entries = sparse data, not broken
- Lower the similarity threshold (try 0.3 instead of 0.5)
- Test with exact captured terminology

### Capture works but search fails
- Verify `vector` extension is enabled: `CREATE EXTENSION IF NOT EXISTS vector;`
- Check that embeddings are being generated (look for null embedding column values)
- Verify `match_thoughts()` function exists in database
- Verify Ollama embedding model is pulled: `kubectl exec -n <ns> deploy/ollama-gpu-bridge -- ollama list`
