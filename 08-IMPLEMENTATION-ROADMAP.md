# Open Brain - Implementation Roadmap

> Build order, milestones, and phased delivery plan.

---

## Overview

The Open Brain system can be built in **4 phases** over approximately **2-4 hours** of focused work. Each phase is independently functional — you get value after Phase 1.

```
Phase 1: Foundation (45 min)     → Database + MCP server + first AI client
Phase 2: Capture (30 min)        → Slack integration + capture pipeline
Phase 3: Migration (30 min)      → Import existing knowledge
Phase 4: Optimization (30 min)   → Multi-client + weekly review + habits
```

---

## Phase 1: Foundation (Core System)

**Goal**: A working database with MCP server connected to at least one AI client.

**Estimated Time**: 45 minutes

### Steps

| # | Task | Reference | Done? |
|---|---|---|---|
| 1.1 | Create Supabase project | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §1 | [ ] |
| 1.2 | Enable pgvector extension | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §2a | [ ] |
| 1.3 | Create `thoughts` table | [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) §2 | [ ] |
| 1.4 | Create auto-update trigger | [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) §2 | [ ] |
| 1.5 | Create indexes (HNSW, GIN, B-tree) | [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) §3 | [ ] |
| 1.6 | Create `match_thoughts()` function | [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) §4 | [ ] |
| 1.7 | Enable RLS | [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) §5 | [ ] |
| 1.8 | Get OpenRouter API key | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §3 | [ ] |
| 1.9 | Generate MCP access key | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §4 | [ ] |
| 1.10 | Set Supabase secrets | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §5 | [ ] |
| 1.11 | Create & deploy `open-brain-mcp` edge function | [03-EDGE-FUNCTIONS.md](03-EDGE-FUNCTIONS.md) §2, [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §6 | [ ] |
| 1.12 | Configure primary AI client (Claude recommended) | [04-MCP-SERVER.md](04-MCP-SERVER.md) client configs | [ ] |
| 1.13 | Test: capture a thought | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §9 | [ ] |
| 1.14 | Test: search for it | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §9 | [ ] |
| 1.15 | Test: check stats | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §9 | [ ] |

### Milestone: Phase 1 Complete

You can now:
- Capture thoughts from your primary AI tool
- Search your brain semantically
- List and filter thoughts by metadata
- View brain statistics

---

## Phase 2: Capture Pipeline (Slack Integration)

**Goal**: Add frictionless capture via Slack channel.

**Estimated Time**: 30 minutes

### Steps

| # | Task | Reference | Done? |
|---|---|---|---|
| 2.1 | Create Slack App | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §8a | [ ] |
| 2.2 | Configure bot permissions | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §8b | [ ] |
| 2.3 | Create & deploy `ingest-thought` edge function | [03-EDGE-FUNCTIONS.md](03-EDGE-FUNCTIONS.md) §1, [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §6 | [ ] |
| 2.4 | Enable Event Subscriptions with webhook URL | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §8c | [ ] |
| 2.5 | Set Slack secrets in Supabase | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §8d | [ ] |
| 2.6 | Add bot to capture channel | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §8e | [ ] |
| 2.7 | Test: post in Slack channel | [07-DEPLOYMENT.md](07-DEPLOYMENT.md) §9 | [ ] |
| 2.8 | Test: verify threaded confirmation reply | | [ ] |
| 2.9 | Test: search for Slack-captured thought from AI client | | [ ] |

### Milestone: Phase 2 Complete

You can now:
- Capture thoughts by typing in a Slack channel
- Automatic metadata extraction and classification
- Threaded confirmation replies
- Thoughts from Slack searchable alongside MCP captures

---

## Phase 3: Knowledge Migration

**Goal**: Import existing knowledge from AI platforms and note systems.

**Estimated Time**: 30-60 minutes (depends on volume)

### Steps

| # | Task | Reference | Done? |
|---|---|---|---|
| 3.1 | Run Memory Migration prompt on primary AI | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) §1 | [ ] |
| 3.2 | Run Memory Migration on secondary AI (if applicable) | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) §1 | [ ] |
| 3.3 | Export ChatGPT data (if applicable) | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) §1 | [ ] |
| 3.4 | Run Second Brain Migration for Obsidian/Notion/etc. | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) §2 | [ ] |
| 3.5 | Run Open Brain Spark interview | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) §3 | [ ] |
| 3.6 | Verify thought count with `thought_stats` | | [ ] |
| 3.7 | Test semantic search across migrated content | | [ ] |
| 3.8 | Reindex after bulk import | `REINDEX INDEX idx_thoughts_embedding;` | [ ] |

### Milestone: Phase 3 Complete

You can now:
- Search across all your accumulated knowledge
- AI tools have rich context about you from day one
- Existing notes are embedded and searchable by meaning
- Personalized use cases identified via Spark interview

---

## Phase 4: Optimization & Habits

**Goal**: Multi-client setup, weekly review habit, and ongoing optimization.

**Estimated Time**: 30 minutes

### Steps

| # | Task | Reference | Done? |
|---|---|---|---|
| 4.1 | Configure additional AI clients (ChatGPT, Cursor, etc.) | [04-MCP-SERVER.md](04-MCP-SERVER.md) client configs | [ ] |
| 4.2 | Practice Quick Capture Templates | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) §4 | [ ] |
| 4.3 | Schedule first Weekly Review | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) §5 | [ ] |
| 4.4 | Set up daily capture rhythm | [06-PROMPT-KIT.md](06-PROMPT-KIT.md) daily rhythm | [ ] |
| 4.5 | Review and adjust similarity thresholds | | [ ] |
| 4.6 | Consider context siloing (work vs personal tags) | [05-CAPTURE-PIPELINE.md](05-CAPTURE-PIPELINE.md) noise prevention | [ ] |

### Milestone: Phase 4 Complete

You can now:
- Access Open Brain from every AI tool you use
- Capture thoughts throughout your day effortlessly
- Run weekly reviews to surface patterns and priorities
- System compounds with daily use

---

## Extended Roadmap (Optional Enhancements)

### Enhancement 1: Multi-Source Connectors

Add ingestion from additional sources:

| Source | Effort | Value |
|---|---|---|
| Telegram | Medium | Auto-capture from messaging |
| Gmail (Google Takeout) | Medium | Email insights as thoughts |
| WhatsApp | Medium | Chat context preservation |
| Calendar events | Low | Meeting context auto-capture |
| Browser bookmarks | Low | Reference material indexing |

### Enhancement 2: Analytics Dashboard

Build a web dashboard (or add routes to existing Hono API):

- Thought count over time (line chart)
- Topic distribution (pie/bar chart)
- People network graph
- Trend detection (emerging/declining topics)
- Weekly report auto-generation

### Enhancement 3: Content Chunking

For long-form content support:

- Add `parent_id` and `chunk_index` columns
- Implement chunking logic in capture pipeline
- Enable reassembly of chunked thoughts
- See [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) §8

### Enhancement 4: Multi-User Support

Scale to multiple users:

- **Already done:** `created_by` column for provenance tracking and filtering
- Future: Add RLS policies for full user isolation
- Future: Add user auth flow to MCP server
- See [02-DATABASE-SCHEMA.md](02-DATABASE-SCHEMA.md) §7

### Enhancement 5: Visual Editing Interface

Build a frontend for browsing/editing thoughts:

- pgAdmin for direct table editing
- Build custom web app with Hono SSR or React frontend
- Connect to Obsidian as a UI layer
- REST API already available via Hono routes

### Enhancement 6: Self-Hosted Alternative

Replace Supabase with self-hosted stack (already done in this project):

| Supabase Component | Self-Hosted Alternative |
|---|---|
| PostgreSQL + pgvector | K8s StatefulSet: `pgvector/pgvector:pg17` |
| Edge Functions (Deno) | Node.js + Hono (TypeScript) |
| PostgREST | Hono REST routes (`src/api/routes.ts`) |
| Dashboard | pgAdmin (existing in cluster) |
| Secrets | K8s Secrets + .env file |
| Embeddings (OpenRouter) | Ollama GPU Bridge (local, free) |

See [09-SELF-HOSTED-K8S.md](09-SELF-HOSTED-K8S.md) for the full K8s deployment guide.
See [10-AZURE-DEPLOYMENT.md](10-AZURE-DEPLOYMENT.md) for the Azure cloud deployment (Container Apps + Azure OpenAI).
See [benclawbot/open-brain](https://github.com/benclawbot/open-brain) for an alternative Python/Docker implementation.

---

## Decision Log

Document key decisions as you build:

| Decision | Options Considered | Chosen | Why |
|---|---|---|---|
| Hosting | Supabase vs Self-hosted K8s | Self-hosted K8s | Already have 3-node cluster, $0/month, full privacy |
| Language | Python vs TypeScript vs C# | TypeScript | Same creator as C# (Hejlsberg), reference MCP SDK, Nate's original is TS |
| Web framework | Express vs Hono vs Fastify | Hono | Ultra-fast, 14KB, Deno-compatible, native TS |
| MCP SDK | Community vs Official TS | Official `@modelcontextprotocol/sdk` | Anthropic's reference implementation |
| Embeddings | OpenRouter vs Ollama local | Ollama (local) | Already running in cluster, free, private |
| Embed model | text-embedding-3-small vs nomic-embed-text | nomic-embed-text | Local GPU via Ollama, 768-dim, excellent quality |
| Metadata LLM | gpt-4o-mini vs llama3.2 | llama3.2 via Ollama | Already loaded, zero API cost |
| Embedding dimensions | 768 vs 1536 | 768 | Matches nomic-embed-text output, sufficient quality |
| Vector index | IVFFlat vs HNSW | HNSW | Better recall, no need for manual list tuning |
| Capture method | MCP only vs MCP + Slack | Both | Slack adds frictionless non-AI capture |
| Metadata extraction | Manual tags vs LLM auto-extract | Auto-extract | Zero friction, consistent classification |
| Capture method | MCP only vs MCP + Slack | Both | Slack adds frictionless non-AI capture |
| Metadata extraction | Manual tags vs LLM auto-extract | Auto-extract | Zero friction, consistent classification |

---

## Success Criteria

### Week 1
- [ ] Open Brain is deployed and accessible from at least one AI client
- [ ] At least 20 thoughts captured
- [ ] Semantic search returns relevant results
- [ ] Existing knowledge migrated from at least one source

### Month 1
- [ ] 100+ thoughts captured
- [ ] At least 2 AI clients connected
- [ ] Completed 2+ Weekly Reviews
- [ ] Established daily capture rhythm
- [ ] AI responses noticeably improved with persistent context

### Month 3
- [ ] 500+ thoughts captured
- [ ] All primary AI tools connected
- [ ] Weekly Review is a habit
- [ ] System is providing real value in daily work
- [ ] Considered/implemented at least one enhancement
