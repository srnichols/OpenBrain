# Open Brain

**Personal semantic memory system that gives every AI tool persistent, searchable memory.**

Open Brain solves the fundamental problem that every AI conversation starts from zero. Your context, decisions, preferences, and knowledge are locked inside individual chat sessions and platforms. Open Brain is a unified backend that any MCP-compatible AI client can read from and write to.

> Based on [Nate B Jones'](https://www.natebjones.com) Open Brain architecture. This is a self-hosted TypeScript implementation with local Ollama embeddings, PostgreSQL + pgvector, and Kubernetes deployment.

---

## How It Works

```
Any AI Tool (Claude, ChatGPT, Gemini, Cursor, etc.)
        |  MCP Protocol (SSE)
        v
   Open Brain MCP Server (:8080)
        |
        v
   PostgreSQL + pgvector
        |
   Your thoughts, searchable by meaning
```

You capture a thought from **any AI client**. Open Brain generates a vector embedding (via Ollama or OpenRouter), extracts metadata (type, topics, people mentioned), and stores it. Later, **any AI client** can semantically search your memories by meaning, not keywords.

---

## Features

- **Semantic Search** - Find thoughts by meaning using pgvector cosine similarity
- **Auto-Metadata Extraction** - LLM automatically classifies type, topics, people, action items on capture
- **MCP Protocol** - Works with Claude, ChatGPT, Gemini, Cursor, and any MCP-compatible client
- **REST API** - Direct HTTP access for integrations, webhooks, and non-MCP tools
- **Dual Embedder** - Choose between local Ollama (free, private) or OpenRouter (cloud)
- **Self-Hosted** - Your data never leaves your infrastructure
- **Docker & Kubernetes** - Deploy locally with docker-compose or to a K8s cluster

---

## Quick Start (Docker Compose)

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose
- [Ollama](https://ollama.com) running locally (or an OpenRouter API key)

### 1. Clone and configure

```bash
git clone https://github.com/srnichols/OpenBrain.git
cd OpenBrain

cp .env.example .env
# Edit .env — set your MCP_ACCESS_KEY and embedder settings
```

### 2. Pull the embedding model (if using Ollama)

```bash
ollama pull nomic-embed-text
ollama pull llama3.2
```

### 3. Start services

```bash
docker compose up -d
```

This starts:
- **PostgreSQL 17 + pgvector** on port 5432
- **Open Brain API** on port 8000 (REST) and port 8080 (MCP SSE)

### 4. Verify

```bash
# REST API health
curl http://localhost:8000/health
# {"status":"healthy","service":"open-brain-api"}

# MCP server health
curl http://localhost:8080/health
# {"status":"healthy","service":"open-brain-mcp"}
```

### 5. Connect an AI client

Add to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "mcpServers": {
    "openbrain": {
      "type": "sse",
      "url": "http://localhost:8080/sse?key=YOUR_MCP_ACCESS_KEY"
    }
  }
}
```

Restart Claude Code. You now have persistent memory across all sessions.

---

## MCP Tools

Open Brain exposes four tools via the Model Context Protocol:

### `capture_thought`

Save a new thought with auto-generated embedding and metadata extraction.

```
"Save this thought: We decided to use PostgreSQL with pgvector
instead of Pinecone. Reason: self-hosted, lower cost, simpler stack."
```

Returns:
```json
{
  "status": "captured",
  "id": "a1b2c3d4-...",
  "type": "decision",
  "topics": ["database", "infrastructure"],
  "people": [],
  "captured_at": "2026-03-07T14:30:00Z"
}
```

### `search_thoughts`

Semantic vector search — find thoughts by meaning, not exact keywords.

```
"Search my brain for database migration decisions"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `query` | string | *required* | Natural language search query |
| `limit` | integer | 10 | Maximum results |
| `threshold` | float | 0.5 | Minimum similarity score (0-1) |

### `list_thoughts`

Browse and filter thoughts by type, topic, person, or time range.

| Parameter | Type | Description |
|-----------|------|-------------|
| `type` | string | Filter: `observation`, `task`, `idea`, `reference`, `person_note`, `decision`, `meeting` |
| `topic` | string | Filter by topic tag |
| `person` | string | Filter by person mentioned |
| `days` | integer | Only thoughts from the last N days |

### `thought_stats`

Aggregate statistics: total thoughts, type distribution, top topics, top people.

---

## REST API

The REST API provides direct HTTP access (no MCP protocol needed).

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Health check |
| `POST` | `/memories` | Capture a thought |
| `POST` | `/memories/search` | Semantic search |
| `POST` | `/memories/list` | Filtered listing |
| `GET` | `/stats` | Brain statistics |

### Examples

**Capture a thought:**
```bash
curl -X POST http://localhost:8000/memories \
  -H "Content-Type: application/json" \
  -d '{"content": "Met with Sarah about the Q3 roadmap. Key decision: prioritize mobile app over desktop."}'
```

**Search by meaning:**
```bash
curl -X POST http://localhost:8000/memories/search \
  -H "Content-Type: application/json" \
  -d '{"query": "what did we decide about mobile?", "limit": 5}'
```

**List recent decisions:**
```bash
curl -X POST http://localhost:8000/memories/list \
  -H "Content-Type: application/json" \
  -d '{"type": "decision", "days": 30}'
```

**Get stats:**
```bash
curl http://localhost:8000/stats
```

---

## Client Configuration

### Claude Code

Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "openbrain": {
      "type": "sse",
      "url": "http://<host>:8080/sse?key=<YOUR_MCP_ACCESS_KEY>"
    }
  }
}
```

### Claude Desktop

Add to `claude_desktop_config.json`:

- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **Mac**: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "openbrain": {
      "type": "sse",
      "url": "http://<host>:8080/sse?key=<YOUR_MCP_ACCESS_KEY>"
    }
  }
}
```

### Cursor

Add to `.cursor/mcp.json` in your project:

```json
{
  "mcpServers": {
    "openbrain": {
      "url": "http://<host>:8080/sse?key=<YOUR_MCP_ACCESS_KEY>",
      "transport": "sse"
    }
  }
}
```

### ChatGPT

1. Enable **Developer Mode** in ChatGPT settings
2. Add MCP connector with URL: `http://<host>:8080/sse?key=<YOUR_MCP_ACCESS_KEY>`
3. Set authentication to **"none"** (key is in URL)

> **Note**: ChatGPT disables its built-in memory when Developer Mode is active. Open Brain replaces that functionality.

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `localhost` | PostgreSQL hostname |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `openbrain` | Database name |
| `DB_USER` | `openbrain` | Database user |
| `DB_PASSWORD` | `changeme` | Database password |
| `EMBEDDER_PROVIDER` | `ollama` | `ollama` (local, free) or `openrouter` (cloud) |
| `EMBEDDING_DIMENSIONS` | `768` | Vector dimensions (768 for Ollama, 1536 for OpenRouter) |
| `OLLAMA_ENDPOINT` | `http://localhost:11434` | Ollama API URL |
| `OLLAMA_EMBED_MODEL` | `nomic-embed-text` | Embedding model |
| `OLLAMA_LLM_MODEL` | `llama3.2` | Metadata extraction model |
| `OPENROUTER_API_KEY` | — | OpenRouter key (if using cloud embeddings) |
| `MCP_ACCESS_KEY` | — | MCP authentication key (generate with `openssl rand -hex 32`) |
| `API_PORT` | `8000` | REST API port |
| `MCP_PORT` | `8080` | MCP SSE server port |
| `LOG_LEVEL` | `info` | Logging level |

---

## Architecture

### Tech Stack

| Component | Technology | Why |
|-----------|------------|-----|
| **Runtime** | Node.js 22 + TypeScript | Type safety, MCP SDK support |
| **REST Framework** | Hono | Lightweight, fast, middleware support |
| **MCP Protocol** | `@modelcontextprotocol/sdk` | Official Anthropic MCP SDK |
| **Database** | PostgreSQL 17 + pgvector | Vector similarity search, JSONB metadata |
| **Embeddings** | Ollama (`nomic-embed-text`) | Local, free, private 768-dim vectors |
| **Metadata LLM** | Ollama (`llama3.2`) | Auto-classify thought type, topics, people |
| **Container** | Docker multi-stage (~60MB) | `node:22-alpine` base |

### Database Schema

```sql
CREATE TABLE thoughts (
    id         UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
    content    TEXT        NOT NULL,
    embedding  VECTOR(768),
    metadata   JSONB       DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);
```

**Indexes:**
- `HNSW` on `embedding` — fast approximate nearest neighbor search
- `GIN` on `metadata` — efficient JSONB containment queries
- `B-tree` on `created_at DESC` — ordered time queries

**Metadata JSONB structure** (auto-extracted by LLM):
```json
{
  "type": "decision",
  "topics": ["database", "infrastructure"],
  "people": ["Sarah", "Mike"],
  "action_items": ["Migrate by Friday"],
  "source": "mcp"
}
```

### Dual Server Architecture

Open Brain runs two servers in a single process:

| Server | Port | Transport | Purpose |
|--------|------|-----------|---------|
| REST API (Hono) | 8000 | HTTP/JSON | Direct access, webhooks, health checks |
| MCP Server | 8080 | HTTP/SSE | AI client connections via Model Context Protocol |

---

## Kubernetes Deployment

Open Brain includes production-ready K8s manifests for self-hosted deployment.

### Manifests

| File | Resource |
|------|----------|
| `k8s/namespace.yaml` | `openbrain` namespace |
| `k8s/postgres-statefulset.yaml` | PostgreSQL 17 + pgvector StatefulSet (10Gi PVC) |
| `k8s/openbrain-api-deployment.yaml` | API Deployment (2 replicas, anti-affinity) + ClusterIP Service |
| `k8s/openbrain-api-service-metallb.yaml` | MetalLB LoadBalancer (LAN access) |
| `k8s/openbrain-tailscale-service.yaml` | Tailscale LoadBalancer (access from anywhere via MagicDNS) |
| `k8s/openbrain-secrets.yaml` | Secrets template (copy, fill values, apply) |

### Deploy

```bash
# 1. Create namespace
kubectl create namespace openbrain

# 2. Create secrets (copy template, fill in real values, apply)
cp k8s/openbrain-secrets.yaml k8s/openbrain-secrets-actual.yaml
# Edit k8s/openbrain-secrets-actual.yaml with base64-encoded values
kubectl apply -f k8s/openbrain-secrets-actual.yaml

# 3. Deploy
kubectl apply -f k8s/postgres-statefulset.yaml
kubectl apply -f k8s/openbrain-api-deployment.yaml
kubectl apply -f k8s/openbrain-api-service-metallb.yaml

# 4. (Optional) Tailscale access from anywhere
kubectl apply -f k8s/openbrain-tailscale-service.yaml

# 5. Verify
kubectl get pods -n openbrain
```

### Networking Options

| Method | Access From | Setup |
|--------|-------------|-------|
| **ClusterIP** (default) | Within the K8s cluster | Included in api-deployment.yaml |
| **MetalLB** | Your local network (LAN) | Apply `openbrain-api-service-metallb.yaml` |
| **Tailscale** | Any device on your tailnet, anywhere | Apply `openbrain-tailscale-service.yaml` (requires Tailscale K8s Operator) |
| **Cloudflare Tunnel** | Public internet | Configure tunnel to ClusterIP service |

See [09-SELF-HOSTED-K8S.md](09-SELF-HOSTED-K8S.md) for the full deployment guide.

---

## Project Structure

```
OpenBrain/
├── src/
│   ├── index.ts              # Entry point — starts REST + MCP servers
│   ├── api/
│   │   └── routes.ts         # Hono REST API routes
│   ├── mcp/
│   │   └── server.ts         # MCP server with 4 tools
│   ├── db/
│   │   ├── connection.ts     # PostgreSQL connection pool
│   │   └── queries.ts        # Dapper-style SQL queries
│   └── embedder/
│       ├── index.ts           # Embedder factory (ollama/openrouter)
│       ├── ollama.ts          # Ollama embedding + metadata extraction
│       ├── openrouter.ts      # OpenRouter embedding + metadata extraction
│       └── types.ts           # Shared types
├── db/
│   └── init.sql              # Database schema (pgvector, HNSW index, match function)
├── k8s/                       # Kubernetes manifests
├── config/
│   └── settings.yaml         # Default configuration
├── Dockerfile                 # Multi-stage build (~60MB image)
├── docker-compose.yml         # Local development stack
├── .env.example               # Environment variable template
├── package.json
├── tsconfig.json
└── 00-09 *.md                 # Architecture and planning docs
```

---

## Development

### Local development (without Docker)

```bash
# Prerequisites: Node.js 22+, PostgreSQL with pgvector, Ollama

npm install
cp .env.example .env
# Edit .env with your settings

npm run dev    # Starts with tsx watch (hot reload)
```

### Build

```bash
npm run build         # Compile TypeScript to dist/
npm run typecheck     # Type check without emitting
npm run lint          # ESLint
```

### Docker build

```bash
docker build -t openbrain-api .
```

---

## Security

- **MCP Access Key** — All MCP endpoints require authentication via `?key=` parameter or `x-brain-key` header
- **No secrets in code** — All credentials via environment variables or K8s Secrets
- **Row Level Security** — RLS enabled on the `thoughts` table
- **Key rotation** — Generate new key with `openssl rand -hex 32`, update env and client configs

### Generate a new MCP key

```bash
openssl rand -hex 32
```

---

## Cost

### Self-Hosted (Ollama)

| Component | Cost |
|-----------|------|
| Ollama embeddings | **$0** (local GPU/CPU) |
| Ollama metadata extraction | **$0** (local) |
| PostgreSQL | **$0** (self-hosted) |
| **Total** | **$0/month** |

### Cloud (OpenRouter)

| Component | Cost |
|-----------|------|
| Embeddings (`text-embedding-3-small`) | ~$0.02/million tokens |
| Metadata extraction (`gpt-4o-mini`) | ~$0.15/million input tokens |
| **Total at 20 thoughts/day** | **~$0.10-$0.30/month** |

---

## Credits

- **[Scott Nichols](https://github.com/srnichols)** — Self-hosted TypeScript implementation with Ollama embeddings, PostgreSQL + pgvector, Docker, and Kubernetes deployment
- **[Nate B Jones](https://www.natebjones.com)** — Creator of the Open Brain concept and architecture
- **[Jon Edwards](https://x.com/limitededition)** (Limited Edition Jonathan) — Collaborator
- **[Open Brain Setup Guide](https://promptkit.natebjones.com/20260224_uq1_guide_main)** — Original guide
- **[benclawbot/open-brain](https://github.com/benclawbot/open-brain)** — Community implementation
- **[MonkeyRun Open Brain](https://github.com/MonkeyRun-com/monkeyrun-open-brain)** — Extended implementation

---

## License

MIT

---

## Documentation

| Document | Description |
|----------|-------------|
| [00-OVERVIEW.md](00-OVERVIEW.md) | Project overview and philosophy |
| [01-ARCHITECTURE.md](01-ARCHITECTURE.md) | System architecture and data flows |
| [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) | PostgreSQL + pgvector schema details |
| [03-EDGE-FUNCTIONS.md](03-EDGE-FUNCTIONS.md) | Edge Functions reference (Supabase variant) |
| [04-MCP-SERVER.md](04-MCP-SERVER.md) | MCP server implementation and tool definitions |
| [05-CAPTURE-PIPELINE.md](05-CAPTURE-PIPELINE.md) | Ingestion and capture workflows |
| [06-PROMPT-KIT.md](06-PROMPT-KIT.md) | Prompts and templates for AI clients |
| [07-DEPLOYMENT.md](07-DEPLOYMENT.md) | Deployment and configuration guide |
| [08-IMPLEMENTATION-ROADMAP.md](08-IMPLEMENTATION-ROADMAP.md) | Build order and milestones |
| [09-SELF-HOSTED-K8S.md](09-SELF-HOSTED-K8S.md) | Kubernetes self-hosted deployment guide |
