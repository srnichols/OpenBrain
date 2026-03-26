# Open Brain - Project Overview

> Based on Nate B Jones' Open Brain architecture — a personal, database-backed AI knowledge system that gives every AI tool persistent memory.

---

## What Is Open Brain?

Open Brain is a **self-hosted personal knowledge system** where AI agents can save, search, and retrieve "thoughts" using semantic vector search. It solves the fundamental problem that every AI conversation starts from zero — your context, decisions, preferences, and knowledge are locked inside individual chat sessions and platforms.

### The Core Problem

- ChatGPT memories are locked to ChatGPT
- Claude conversations don't persist across sessions
- Switching AI tools means losing all accumulated context
- Your knowledge is scattered across platforms with no unified access

### The Solution

One PostgreSQL database + one MCP server = every AI tool has access to your persistent memory.

```
Any AI Tool (Claude, ChatGPT, Gemini, Grok)
        ↓ MCP Protocol
   Open Brain MCP Server
        ↓
   Supabase (PostgreSQL + pgvector)
        ↓
   Your thoughts, searchable by meaning
```

---

## Philosophy

### Your Memory Is Yours

- **Portable**: Not locked to any AI vendor
- **Self-hosted**: You own the database and infrastructure
- **Open protocol**: MCP works with any compatible AI client
- **Compounding**: Every thought captured makes the system smarter

### Design Principles

1. **One row = one retrievable idea** (Zettelkasten-style atomic notes)
2. **Vector search = associative retrieval** (search by meaning, not keywords)
3. **Metadata extraction is automatic** (LLM classifies and tags on ingest)
4. **Backend, not frontend** — Open Brain is the storage/retrieval layer; use any UI on top
5. **Minimal cost** — $0.10-$0.30/month for typical usage

---

## What Open Brain Is NOT

| Open Brain IS | Open Brain IS NOT |
|---|---|
| A database backend with vector search | A note-taking app like Obsidian or Notion |
| An MCP server for AI tool integration | A replacement for your writing workflow |
| A semantic retrieval engine | A file storage system |
| A persistent memory layer | A chatbot or AI assistant |

**Obsidian, Notion, etc. are frontends.** Open Brain is the backend. They can coexist — use Open Brain for retrieval and storage, keep your preferred tool for composition.

---

## Cost Breakdown

| Component | Cost |
|---|---|
| Supabase (Free Tier) | $0/month |
| OpenRouter Embeddings (text-embedding-3-small) | ~$0.02/million tokens |
| OpenRouter Metadata Extraction (gpt-4o-mini) | ~$0.15/million input tokens |
| **Total at 20 thoughts/day** | **~$0.10-$0.30/month** |

---

## Key Capabilities

### Capture
- Save thoughts from any AI tool via MCP `capture_thought` tool
- Slack webhook integration for frictionless capture
- Bulk import from existing systems (Notion, Obsidian, Apple Notes)
- Memory migration from ChatGPT, Claude, etc.
- Optional `created_by` user tracking for multi-developer teams

### Search
- **Semantic search**: Find thoughts by meaning, not exact keywords
- **Metadata filtering**: Filter by type, topic, person, date range
- **User scoping**: Filter search and stats by `created_by` user
- **Stats**: Aggregate counts, topic distribution, people mentioned

### Retrieval
- Any MCP-connected AI can query your brain
- Results ranked by cosine similarity
- Configurable similarity thresholds and result limits

---

## Who Built This

- **Nate B Jones** ([natebjones.com](https://www.natebjones.com)) — Creator and architect
- **Jon Edwards** (Limited Edition Jonathan) — Collaborator
- Community implementations on GitHub extend the core concept

---

## Related Documents

| Document | Description |
|---|---|
| [01-ARCHITECTURE.md](01-ARCHITECTURE.md) | System architecture and data flows |
| [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) | PostgreSQL + pgvector schema |
| [03-EDGE-FUNCTIONS.md](03-EDGE-FUNCTIONS.md) | Supabase Edge Functions |
| [04-MCP-SERVER.md](04-MCP-SERVER.md) | MCP server implementation |
| [05-CAPTURE-PIPELINE.md](05-CAPTURE-PIPELINE.md) | Ingestion and capture workflows |
| [06-PROMPT-KIT.md](06-PROMPT-KIT.md) | Prompts and templates |
| [07-DEPLOYMENT.md](07-DEPLOYMENT.md) | Deployment and configuration |
| [08-IMPLEMENTATION-ROADMAP.md](08-IMPLEMENTATION-ROADMAP.md) | Build order and milestones |
| [09-SELF-HOSTED-K8S.md](09-SELF-HOSTED-K8S.md) | Kubernetes self-hosted deployment |
| [10-AZURE-DEPLOYMENT.md](10-AZURE-DEPLOYMENT.md) | Azure cloud deployment (Container Apps + Azure OpenAI) |

---

## Sources & References

- [Nate B Jones - Open Brain Setup Guide](https://promptkit.natebjones.com/20260224_uq1_guide_main)
- [Open Brain FAQ](https://promptkit.natebjones.com/20260224_uq1_guide_02)
- [Open Brain Prompt Kit](https://promptkit.natebjones.com/20260224_uq1_promptkit_1)
- [Nate's Substack - "Every AI You Use Forgets You"](https://natesnewsletter.substack.com/p/every-ai-you-use-forgets-you-heres)
- [benclawbot/open-brain (GitHub)](https://github.com/benclawbot/open-brain) — Community implementation
- [MonkeyRun Open Brain (GitHub)](https://github.com/MonkeyRun-com/monkeyrun-open-brain) — Extended implementation
