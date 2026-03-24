# Open Brain - Edge Functions

> Supabase Edge Functions for the capture pipeline and MCP server.

---

## Overview

Open Brain uses two Supabase Edge Functions (Deno runtime):

| Function | Purpose | Trigger |
|---|---|---|
| `ingest-thought` | Captures thoughts from Slack webhooks | Slack webhook POST |
| `open-brain-mcp` | MCP server for AI tool integration | MCP protocol calls |

Both functions run serverlessly on Supabase's infrastructure — nothing runs on your machine.

---

## Shared Dependencies

### OpenRouter Client

Both edge functions call OpenRouter for embeddings and LLM operations:

```typescript
// Shared: Generate embedding via OpenRouter
async function generateEmbedding(content: string): Promise<number[]> {
    const response = await fetch("https://openrouter.ai/api/v1/embeddings", {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${Deno.env.get("OPENROUTER_API_KEY")}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            model: "openai/text-embedding-3-small",
            input: content,
        }),
    });

    const data = await response.json();
    return data.data[0].embedding; // 1536-dimensional vector
}
```

### Metadata Extraction

```typescript
// Shared: Extract structured metadata via LLM
async function extractMetadata(content: string): Promise<object> {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${Deno.env.get("OPENROUTER_API_KEY")}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            model: "openai/gpt-4o-mini",
            messages: [
                {
                    role: "system",
                    content: `Extract metadata from the following thought. Return JSON with:
                        - type: one of "observation", "task", "idea", "reference", "person_note", "decision", "meeting", "architecture", "pattern", "postmortem", "requirement", "bug", "convention"
                        - topics: array of 1-3 topic tags (lowercase, hyphenated)
                        - people: array of people mentioned (proper names)
                        - action_items: array of implied action items
                        - dates: array of dates mentioned (YYYY-MM-DD format)
                        Return ONLY valid JSON, no explanation.`,
                },
                { role: "user", content: content },
            ],
            response_format: { type: "json_object" },
        }),
    });

    const data = await response.json();
    return JSON.parse(data.choices[0].message.content);
}
```

### Supabase Client

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function getSupabaseClient() {
    return createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
}
```

---

## Edge Function 1: `ingest-thought`

Receives Slack webhook events and processes thoughts into the database.

### Request Flow

```
Slack Webhook POST
  ↓
Validate channel whitelist
  ↓
PARALLEL:
  ├─ Generate embedding (OpenRouter)
  └─ Extract metadata (OpenRouter / gpt-4o-mini)
  ↓
INSERT into thoughts table
  ↓
Post threaded Slack reply (confirmation)
```

### Implementation Skeleton

```typescript
// supabase/functions/ingest-thought/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req: Request) => {
    // 1. Parse Slack webhook payload
    const payload = await req.json();

    // Handle Slack URL verification challenge
    if (payload.type === "url_verification") {
        return new Response(JSON.stringify({ challenge: payload.challenge }), {
            headers: { "Content-Type": "application/json" },
        });
    }

    // 2. Validate channel
    const channelId = payload.event?.channel;
    const allowedChannel = Deno.env.get("SLACK_CAPTURE_CHANNEL");
    if (channelId !== allowedChannel) {
        return new Response("Ignored: wrong channel", { status: 200 });
    }

    // 3. Extract message text
    const content = payload.event?.text;
    if (!content) {
        return new Response("No content", { status: 200 });
    }

    // 4. Process in parallel: embedding + metadata extraction
    const [embedding, metadata] = await Promise.all([
        generateEmbedding(content),
        extractMetadata(content),
    ]);

    // 5. Store in Supabase
    const supabase = getSupabaseClient();
    const { data, error } = await supabase
        .from("thoughts")
        .insert({
            content: content,
            embedding: embedding,
            metadata: { ...metadata, source: "slack" },
        })
        .select()
        .single();

    if (error) {
        console.error("Insert error:", error);
        return new Response("Error storing thought", { status: 500 });
    }

    // 6. Post threaded reply in Slack
    const slackToken = Deno.env.get("SLACK_BOT_TOKEN");
    await fetch("https://slack.com/api/chat.postMessage", {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${slackToken}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            channel: channelId,
            thread_ts: payload.event?.ts,
            text: `Captured: ${metadata.type} — topics: ${metadata.topics?.join(", ")}`,
        }),
    });

    return new Response("OK", { status: 200 });
});
```

### Slack App Setup

1. Create a Slack App at [api.slack.com/apps](https://api.slack.com/apps)
2. Enable **Event Subscriptions**
3. Set Request URL to: `https://<your-ref>.supabase.co/functions/v1/ingest-thought`
4. Subscribe to `message.channels` event
5. Add bot to your capture channel
6. Copy the Bot Token (`xoxb-...`) to Supabase secrets

---

## Edge Function 2: `open-brain-mcp`

The MCP server — built with Hono web framework on Deno.

### Authentication

```typescript
// Middleware: validate MCP access key
function validateAccessKey(req: Request): boolean {
    const key =
        req.headers.get("x-brain-key") ||
        new URL(req.url).searchParams.get("key");
    return key === Deno.env.get("MCP_ACCESS_KEY");
}
```

**Access Key Details:**
- 64-character hex string (generate with `openssl rand -hex 32`)
- Accepted via `x-brain-key` HTTP header OR `?key=` URL parameter
- Returns 401 on invalid/missing key
- URL parameter method needed for Claude Desktop, ChatGPT (can't send custom headers)

### MCP Tool Implementations

#### Tool: `search_thoughts`

```typescript
// Semantic vector search
async function searchThoughts(query: string, limit = 10, threshold = 0.5) {
    // 1. Embed the search query
    const queryEmbedding = await generateEmbedding(query);

    // 2. Call match_thoughts RPC
    const supabase = getSupabaseClient();
    const { data, error } = await supabase.rpc("match_thoughts", {
        query_embedding: queryEmbedding,
        match_threshold: threshold,
        match_count: limit,
        filter: {},
    });

    if (error) throw error;

    // 3. Format results
    return data.map((thought: any) => ({
        content: thought.content,
        metadata: thought.metadata,
        similarity: thought.similarity.toFixed(3),
        created_at: thought.created_at,
    }));
}
```

#### Tool: `list_thoughts`

```typescript
// Filtered listing (no vector search, just metadata/date filters)
async function listThoughts(filters: {
    type?: string;
    topic?: string;
    person?: string;
    days?: number;
}) {
    const supabase = getSupabaseClient();
    let query = supabase
        .from("thoughts")
        .select("id, content, metadata, created_at")
        .order("created_at", { ascending: false });

    // Apply filters
    if (filters.type) {
        query = query.contains("metadata", { type: filters.type });
    }
    if (filters.topic) {
        query = query.contains("metadata", { topics: [filters.topic] });
    }
    if (filters.person) {
        query = query.contains("metadata", { people: [filters.person] });
    }
    if (filters.days) {
        const since = new Date();
        since.setDate(since.getDate() - filters.days);
        query = query.gte("created_at", since.toISOString());
    }

    const { data, error } = await query.limit(50);
    if (error) throw error;
    return data;
}
```

#### Tool: `capture_thought`

```typescript
// Store a new thought with auto-generated embedding and metadata
async function captureThought(content: string) {
    // 1. Generate embedding and extract metadata in parallel
    const [embedding, metadata] = await Promise.all([
        generateEmbedding(content),
        extractMetadata(content),
    ]);

    // 2. Insert into database
    const supabase = getSupabaseClient();
    const { data, error } = await supabase
        .from("thoughts")
        .insert({
            content: content,
            embedding: embedding,
            metadata: { ...metadata, source: "mcp" },
        })
        .select()
        .single();

    if (error) throw error;

    // 3. Return confirmation
    return {
        id: data.id,
        type: metadata.type,
        topics: metadata.topics,
        people: metadata.people,
        captured_at: data.created_at,
    };
}
```

#### Tool: `thought_stats`

```typescript
// Aggregate statistics about the brain
async function thoughtStats() {
    const supabase = getSupabaseClient();

    // Total count
    const { count } = await supabase
        .from("thoughts")
        .select("*", { count: "exact", head: true });

    // Type distribution
    const { data: thoughts } = await supabase
        .from("thoughts")
        .select("metadata");

    const typeCount: Record<string, number> = {};
    const topicCount: Record<string, number> = {};
    const peopleCount: Record<string, number> = {};

    for (const t of thoughts || []) {
        const type = t.metadata?.type || "unknown";
        typeCount[type] = (typeCount[type] || 0) + 1;

        for (const topic of t.metadata?.topics || []) {
            topicCount[topic] = (topicCount[topic] || 0) + 1;
        }
        for (const person of t.metadata?.people || []) {
            peopleCount[person] = (peopleCount[person] || 0) + 1;
        }
    }

    return {
        total_thoughts: count,
        types: typeCount,
        top_topics: Object.entries(topicCount)
            .sort(([, a], [, b]) => b - a)
            .slice(0, 10),
        top_people: Object.entries(peopleCount)
            .sort(([, a], [, b]) => b - a)
            .slice(0, 10),
    };
}
```

---

## Deployment

### Deploy Edge Functions via Supabase CLI

```bash
# Install Supabase CLI
npm install -g supabase

# Login
supabase login

# Link to your project
supabase link --project-ref <your-project-ref>

# Deploy ingest-thought
supabase functions deploy ingest-thought --no-verify-jwt

# Deploy open-brain-mcp
supabase functions deploy open-brain-mcp --no-verify-jwt
```

**Note**: `--no-verify-jwt` is required because these functions handle their own auth (MCP key / Slack webhook).

### Set Secrets

```bash
supabase secrets set OPENROUTER_API_KEY=sk-or-...
supabase secrets set SLACK_BOT_TOKEN=xoxb-...
supabase secrets set SLACK_CAPTURE_CHANNEL=C0123456789
supabase secrets set MCP_ACCESS_KEY=$(openssl rand -hex 32)
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are auto-injected by Supabase — do not set manually.

---

## Debugging

### Check Edge Function Logs

```bash
# Stream logs
supabase functions logs ingest-thought --follow
supabase functions logs open-brain-mcp --follow
```

### Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| 401 Unauthorized | Invalid MCP_ACCESS_KEY | Verify key matches in secrets and client config |
| Capture works, search fails | Vector extension not enabled | Run `CREATE EXTENSION IF NOT EXISTS vector;` |
| Empty search results | Too few thoughts (< 20-30) | Add more data; search quality improves with scale |
| Slack not triggering | Wrong channel ID | Verify `SLACK_CAPTURE_CHANNEL` matches actual channel ID |
| Metadata extraction fails | OpenRouter API key issue | Check `OPENROUTER_API_KEY` in secrets |

### Pre-Help Checklist

1. Follow the guide step-by-step
2. Check Edge Function logs (Supabase Dashboard → Edge Functions → Logs)
3. Verify URL format with embedded key
4. Use Supabase AI assistant for diagnostics
5. **Don't rewrite working code** for configuration issues
