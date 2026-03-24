# Open Brain - System Architecture

> Complete system architecture, component relationships, and data flows.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AI CLIENTS (Consumers)                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │  Claude   │  │ ChatGPT  │  │  Gemini  │  │  Cursor  │  ...     │
│  │ Desktop   │  │   Web    │  │   Web    │  │   IDE    │           │
│  └────┬──────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       │              │              │              │                │
│       └──────────────┴──────────────┴──────────────┘                │
│                              │                                      │
│                     MCP Protocol (HTTP/SSE)                         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────┴──────────────────────────────────────┐
│                     SUPABASE PLATFORM                               │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              Edge Functions (Deno Runtime)                   │    │
│  │                                                              │    │
│  │  ┌──────────────────┐    ┌──────────────────┐               │    │
│  │  │  open-brain-mcp  │    │  ingest-thought  │               │    │
│  │  │  (MCP Server)    │    │  (Slack Capture)  │               │    │
│  │  │                  │    │                   │               │    │
│  │  │  Tools:          │    │  - Webhook recv   │               │    │
│  │  │  - search        │    │  - Embed content  │               │    │
│  │  │  - list          │    │  - Extract meta   │               │    │
│  │  │  - capture       │    │  - Store thought  │               │    │
│  │  │  - stats         │    │  - Reply in Slack │               │    │
│  │  └────────┬─────────┘    └────────┬──────────┘               │    │
│  │           │                       │                          │    │
│  └───────────┼───────────────────────┼──────────────────────────┘    │
│              │                       │                               │
│  ┌───────────┴───────────────────────┴──────────────────────────┐   │
│  │                    PostgreSQL + pgvector                      │   │
│  │                                                               │   │
│  │  ┌─────────────────────────────────────────────────────────┐  │   │
│  │  │                    thoughts table                        │  │   │
│  │  │                                                          │  │   │
│  │  │  id          UUID (PK)                                   │  │   │
│  │  │  content     TEXT (raw thought)                          │  │   │
│  │  │  embedding   VECTOR(1536) (semantic representation)     │  │   │
│  │  │  metadata    JSONB (people, topics, type, etc.)         │  │   │
│  │  │  created_at  TIMESTAMPTZ                                │  │   │
│  │  │  updated_at  TIMESTAMPTZ                                │  │   │
│  │  └─────────────────────────────────────────────────────────┘  │   │
│  │                                                               │   │
│  │  Indexes:                                                     │   │
│  │  - HNSW on embedding (cosine similarity)                     │   │
│  │  - GIN on metadata (structured queries)                      │   │
│  │  - B-tree on created_at DESC (date range)                    │   │
│  │                                                               │   │
│  │  Functions:                                                   │   │
│  │  - match_thoughts() (vector similarity search)               │   │
│  │                                                               │   │
│  │  Security:                                                    │   │
│  │  - RLS enabled                                                │   │
│  │  - Service role access only                                   │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
                               │
┌──────────────────────────────┴──────────────────────────────────────┐
│                     EXTERNAL SERVICES                               │
│                                                                     │
│  ┌──────────────────┐    ┌──────────────────┐                      │
│  │    OpenRouter     │    │      Slack       │                      │
│  │                   │    │                  │                      │
│  │  - Embeddings     │    │  - Webhook src   │                      │
│  │    (text-embed-   │    │  - Bot replies   │                      │
│  │     3-small)      │    │  - Capture       │                      │
│  │  - LLM calls      │    │    channel       │                      │
│  │    (gpt-4o-mini)  │    │                  │                      │
│  └──────────────────┘    └──────────────────┘                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. AI Clients (Consumers)

Any MCP-compatible AI tool can connect to Open Brain:

| Client | Connection Method | Auth |
|---|---|---|
| Claude Desktop | MCP config in `claude_desktop_config.json` | Header or URL param |
| Claude Code | MCP config in settings | Header |
| ChatGPT | Developer Mode MCP connector | URL param |
| Gemini | MCP connector | URL param |
| Cursor | MCP config in settings | Header |
| Custom apps | HTTP to MCP endpoint | Header or URL param |

**Important**: Claude Code and Cursor support custom headers (`x-brain-key`). Claude Desktop/Web and ChatGPT require the key embedded in the URL as a query parameter (`?key=`).

### 2. MCP Server (Edge Function: `open-brain-mcp`)

The MCP server is the central gateway. It's a Supabase Edge Function built with **Deno** and the **Hono** web framework.

**Responsibilities:**
- Authenticate incoming requests via `MCP_ACCESS_KEY`
- Route tool calls to appropriate handlers
- Generate embeddings for search queries
- Return structured results to AI clients

**Seven MCP Tools Exposed:**

| Tool | Purpose | Key Parameters |
|---|---|---|
| `search_thoughts` | Semantic vector search | `query`, `limit`, `threshold`, `project`, `type`, `topic`, `include_archived` |
| `list_thoughts` | Filtered listing | `type`, `topic`, `person`, `days`, `project`, `include_archived` |
| `capture_thought` | Store new thought | `content`, `project`, `source`, `supersedes` |
| `thought_stats` | Aggregate statistics | `project` |
| `update_thought` | Update existing thought | `id`, `content` |
| `delete_thought` | Delete thought by ID | `id` |
| `capture_thoughts` | Batch capture | `thoughts[]`, `project`, `source` |

### 3. Capture Pipeline (Edge Function: `ingest-thought`)

Handles incoming thoughts from Slack webhooks.

**Processing Pipeline (parallel):**
1. Generate 1536-dimensional embedding via OpenRouter
2. Extract metadata via gpt-4o-mini (people, topics, type, action items, dates)
3. Store content + embedding + metadata in `thoughts` table
4. Post threaded confirmation reply in Slack

### 4. Database (PostgreSQL + pgvector)

Single table design with rich JSONB metadata.

**Vector Search**: HNSW index on `embedding` column using cosine distance operator (`<=>`), wrapped in `match_thoughts()` RPC function.

### 5. External Services

| Service | Role | Free Tier? |
|---|---|---|
| **OpenRouter** | AI gateway — embeddings + LLM | Yes |
| **Slack** | Capture channel + webhook | Yes |
| **Supabase** | Database + Edge Functions + Auth | Yes |

---

## Data Flows

### Flow 1: AI Agent Searches Memory

```
1. User asks Claude: "What did I decide about the API redesign?"
2. Claude calls MCP tool: search_thoughts(query="API redesign decision")
3. MCP Edge Function:
   a. Validates MCP_ACCESS_KEY
   b. Sends query to OpenRouter → gets 1536-dim embedding
   c. Calls match_thoughts() RPC with embedding vector
   d. PostgreSQL performs HNSW cosine similarity search
   e. Returns top-N results ranked by similarity
4. Claude receives thoughts with metadata and similarity scores
5. Claude synthesizes answer using retrieved context
```

### Flow 2: AI Agent Captures Thought

```
1. User tells Claude: "Remember that we chose GraphQL over REST for the admin API"
2. Claude calls MCP tool: capture_thought(content="Chose GraphQL over REST for admin API")
3. MCP Edge Function:
   a. Validates MCP_ACCESS_KEY
   b. PARALLEL:
      - OpenRouter embedding: content → 1536-dim vector
      - OpenRouter gpt-4o-mini: content → metadata extraction
        {type: "decision", topics: ["api", "graphql"], people: [], action_items: []}
   c. INSERT into thoughts table (content, embedding, metadata)
   d. Returns confirmation with extracted metadata
4. Claude confirms to user what was captured
```

### Flow 3: Slack Capture

```
1. User types in Slack #brain channel: "Met with Sarah, she wants to delay launch to Q2"
2. Slack webhook fires → ingest-thought Edge Function
3. Edge Function:
   a. Validates Slack channel whitelist
   b. PARALLEL:
      - Generate embedding via OpenRouter
      - Extract metadata via gpt-4o-mini:
        {type: "person_note", people: ["Sarah"], topics: ["launch", "timeline"],
         action_items: ["delay launch to Q2"], dates: ["Q2"]}
   c. INSERT into thoughts table
   d. Post threaded reply: "Captured: person_note about Sarah, launch, timeline"
4. Thought is now searchable from any AI tool
```

### Flow 4: Weekly Review

```
1. User runs Weekly Review prompt in Claude
2. Prompt instructs Claude to:
   a. search_thoughts() for past 7 days
   b. list_thoughts(days=7) grouped by type
   c. thought_stats() for activity overview
3. Claude synthesizes:
   - Themes and patterns
   - Unresolved action items
   - Forgotten follow-ups
   - Emerging priorities
4. User reviews and captures new insights back to Open Brain
```

---

## Security Model

```
┌─────────────────────────────────────┐
│           Security Layers           │
├─────────────────────────────────────┤
│ 1. MCP_ACCESS_KEY (64-char hex)     │ ← Application layer auth
│    - Checked via x-brain-key header │
│    - OR via ?key= URL parameter     │
│    - 401 on invalid/missing         │
├─────────────────────────────────────┤
│ 2. Supabase Service Role Key        │ ← Database access
│    - Full CRUD on thoughts table    │
│    - Anon key access DISABLED       │
├─────────────────────────────────────┤
│ 3. Row Level Security (RLS)         │ ← Database enforcement
│    - Service role bypasses RLS      │
│    - No public/anon access          │
├─────────────────────────────────────┤
│ 4. Supabase Edge Function Secrets   │ ← Secret management
│    - OPENROUTER_API_KEY             │
│    - SLACK_BOT_TOKEN                │
│    - MCP_ACCESS_KEY                 │
│    - Auto-injected SUPABASE_URL     │
│    - Auto-injected SERVICE_ROLE_KEY │
└─────────────────────────────────────┘
```

---

## Scaling Considerations

| Scale | Architecture Notes |
|---|---|
| < 1,000 thoughts | Single table, no optimization needed |
| 1,000 - 100,000 | HNSW index handles this well |
| 100,000+ | Consider chunking strategies, metadata partitioning |
| Multi-user | Add `user_id` column, extend RLS policies |
| Multi-context | Separate "silos" via metadata tags (work, personal, coding) |

**pgvector HNSW index keeps search fast regardless of scale.** Postgres handles millions of rows comfortably.
