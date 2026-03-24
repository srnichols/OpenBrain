/**
 * MCP Server for Open Brain.
 * Exposes seven tools: search_thoughts, list_thoughts, capture_thought, thought_stats,
 * update_thought, delete_thought, capture_thoughts (batch).
 *
 * Uses the official @modelcontextprotocol/sdk TypeScript SDK.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { getPool } from "../db/connection.js";
import {
  insertThought,
  searchThoughts,
  listThoughts,
  getThoughtStats,
  updateThought,
  deleteThought,
  batchInsertThoughts,
  type ListFilters,
  type BatchThoughtInput,
} from "../db/queries.js";
import { getEmbedder } from "../embedder/index.js";

export function createMcpServer(): Server {
  const server = new Server(
    { name: "open-brain", version: "1.0.0" },
    { capabilities: { tools: {} } }
  );

  const embedder = getEmbedder();
  const pool = getPool();

  // ─── List Tools ──────────────────────────────────────────────────

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      {
        name: "search_thoughts",
        description:
          "Search your brain for thoughts semantically related to a query. Returns results ranked by similarity score. Supports project scoping and metadata filters.",
        inputSchema: {
          type: "object" as const,
          properties: {
            query: {
              type: "string",
              description: "Natural language search query",
            },
            limit: {
              type: "integer",
              description: "Maximum results to return (default: 10)",
              default: 10,
            },
            threshold: {
              type: "number",
              description: "Minimum similarity score 0-1 (default: 0.5)",
              default: 0.5,
            },
            project: {
              type: "string",
              description: "Scope search to a specific project",
            },
            type: {
              type: "string",
              description:
                "Filter by thought type: observation, task, idea, reference, person_note, decision, meeting, architecture, pattern, postmortem, requirement, bug, convention",
            },
            topic: {
              type: "string",
              description: "Filter by topic tag",
            },
            include_archived: {
              type: "boolean",
              description: "Include archived thoughts (default: false)",
              default: false,
            },
          },
          required: ["query"],
        },
      },
      {
        name: "list_thoughts",
        description:
          "List thoughts filtered by type, topic, person mentioned, project, or time range.",
        inputSchema: {
          type: "object" as const,
          properties: {
            type: {
              type: "string",
              description:
                "Filter by thought type: observation, task, idea, reference, person_note, decision, meeting, architecture, pattern, postmortem, requirement, bug, convention",
            },
            topic: {
              type: "string",
              description: "Filter by topic tag",
            },
            person: {
              type: "string",
              description: "Filter by person mentioned",
            },
            days: {
              type: "integer",
              description: "Only return thoughts from the last N days",
            },
            project: {
              type: "string",
              description: "Scope to a specific project",
            },
            include_archived: {
              type: "boolean",
              description: "Include archived thoughts (default: false)",
              default: false,
            },
          },
        },
      },
      {
        name: "capture_thought",
        description:
          "Save a new thought to your brain. Automatically generates embedding and extracts metadata (type, topics, people, action items). Supports project scoping and provenance tracking.",
        inputSchema: {
          type: "object" as const,
          properties: {
            content: {
              type: "string",
              description: "The thought to capture (raw text)",
            },
            project: {
              type: "string",
              description: "Scope this thought to a project/workspace",
            },
            source: {
              type: "string",
              description: "Provenance tracking — where this thought came from (default: 'mcp')",
            },
            supersedes: {
              type: "string",
              description: "UUID of a prior thought this one replaces",
            },
          },
          required: ["content"],
        },
      },
      {
        name: "thought_stats",
        description:
          "Get statistics about your brain: total thoughts, type distribution, top topics, and top people mentioned. Optionally scoped to a project.",
        inputSchema: {
          type: "object" as const,
          properties: {
            project: {
              type: "string",
              description: "Scope stats to a specific project",
            },
          },
        },
      },
      {
        name: "update_thought",
        description:
          "Update an existing thought's content. Re-generates embedding and re-extracts metadata automatically.",
        inputSchema: {
          type: "object" as const,
          properties: {
            id: {
              type: "string",
              description: "UUID of the thought to update",
            },
            content: {
              type: "string",
              description: "New content for the thought",
            },
          },
          required: ["id", "content"],
        },
      },
      {
        name: "delete_thought",
        description:
          "Permanently delete a thought by ID. Deleted thoughts no longer appear in search or list results.",
        inputSchema: {
          type: "object" as const,
          properties: {
            id: {
              type: "string",
              description: "UUID of the thought to delete",
            },
          },
          required: ["id"],
        },
      },
      {
        name: "capture_thoughts",
        description:
          "Batch capture multiple thoughts in one call. Each thought gets independent embedding and metadata extraction. All share the same project and source.",
        inputSchema: {
          type: "object" as const,
          properties: {
            thoughts: {
              type: "array",
              description: "Array of thoughts to capture",
              items: {
                type: "object",
                properties: {
                  content: {
                    type: "string",
                    description: "The thought content (raw text)",
                  },
                },
                required: ["content"],
              },
            },
            project: {
              type: "string",
              description: "Scope all thoughts to a project/workspace",
            },
            source: {
              type: "string",
              description: "Provenance tracking (default: 'mcp')",
            },
          },
          required: ["thoughts"],
        },
      },
    ],
  }));

  // ─── Call Tool ───────────────────────────────────────────────────

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
      switch (name) {
        // ── search_thoughts ──
        case "search_thoughts": {
          const query = args?.query as string;
          const limit = (args?.limit as number) ?? 10;
          const threshold = (args?.threshold as number) ?? 0.5;
          const project = args?.project as string | undefined;
          const type = args?.type as string | undefined;
          const topic = args?.topic as string | undefined;
          const include_archived = (args?.include_archived as boolean) ?? false;

          // Build JSONB filter from type/topic
          const filter: Record<string, unknown> = {};
          if (type) filter.type = type;
          if (topic) filter.topics = [topic];

          const queryEmbedding = await embedder.generateEmbedding(query);
          const results = await searchThoughts(
            pool, queryEmbedding, limit, threshold, filter, project, include_archived
          );

          const formatted = results.map((r) => ({
            content: r.content,
            metadata: r.metadata,
            similarity: Math.round(r.similarity * 1000) / 1000,
            created_at: r.created_at.toISOString(),
          }));

          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify({ count: formatted.length, results: formatted }, null, 2),
              },
            ],
          };
        }

        // ── list_thoughts ──
        case "list_thoughts": {
          const filters: ListFilters = {
            type: args?.type as string | undefined,
            topic: args?.topic as string | undefined,
            person: args?.person as string | undefined,
            days: args?.days as number | undefined,
            project: args?.project as string | undefined,
            include_archived: (args?.include_archived as boolean) ?? false,
          };

          const results = await listThoughts(pool, filters);

          const formatted = results.map((r) => ({
            id: r.id,
            content: r.content,
            metadata: r.metadata,
            created_at: r.created_at.toISOString(),
          }));

          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify({ count: formatted.length, results: formatted }, null, 2),
              },
            ],
          };
        }

        // ── capture_thought ──
        case "capture_thought": {
          const content = args?.content as string;
          const project = args?.project as string | undefined;
          const source = (args?.source as string) ?? "mcp";
          const supersedes = args?.supersedes as string | undefined;

          // Generate embedding and extract metadata in parallel
          const [embedding, metadata] = await Promise.all([
            embedder.generateEmbedding(content),
            embedder.extractMetadata(content),
          ]);

          const fullMetadata = { ...metadata, source };
          const result = await insertThought(pool, content, embedding, fullMetadata, project, supersedes);

          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(
                  {
                    status: "captured",
                    id: result.id,
                    type: metadata.type,
                    topics: metadata.topics,
                    people: metadata.people,
                    action_items: metadata.action_items,
                    captured_at: result.created_at.toISOString(),
                  },
                  null,
                  2
                ),
              },
            ],
          };
        }

        // ── thought_stats ──
        case "thought_stats": {
          const project = args?.project as string | undefined;
          const stats = await getThoughtStats(pool, project);

          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(stats, null, 2),
              },
            ],
          };
        }

        // ── update_thought ──
        case "update_thought": {
          const id = args?.id as string;
          const content = args?.content as string;

          // Re-generate embedding and re-extract metadata
          const [embedding, metadata] = await Promise.all([
            embedder.generateEmbedding(content),
            embedder.extractMetadata(content),
          ]);

          const result = await updateThought(pool, id, content, embedding, metadata);

          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(
                  {
                    status: "updated",
                    id: result.id,
                    type: metadata.type,
                    topics: metadata.topics,
                    updated_at: result.created_at.toISOString(),
                  },
                  null,
                  2
                ),
              },
            ],
          };
        }

        // ── delete_thought ──
        case "delete_thought": {
          const id = args?.id as string;
          const result = await deleteThought(pool, id);

          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(result, null, 2),
              },
            ],
          };
        }

        // ── capture_thoughts (batch) ──
        case "capture_thoughts": {
          const thoughtInputs = args?.thoughts as Array<{ content: string }>;
          const project = args?.project as string | undefined;
          const source = (args?.source as string) ?? "mcp";

          // Process each thought: embed + extract metadata
          const processed: BatchThoughtInput[] = await Promise.all(
            thoughtInputs.map(async (t) => {
              const [embedding, metadata] = await Promise.all([
                embedder.generateEmbedding(t.content),
                embedder.extractMetadata(t.content),
              ]);
              return {
                content: t.content,
                embedding,
                metadata: { ...metadata, source },
                project,
              };
            })
          );

          const results = await batchInsertThoughts(pool, processed);

          const formatted = results.map((r) => ({
            id: r.id,
            content: r.content,
            metadata: r.metadata,
            captured_at: r.created_at.toISOString(),
          }));

          return {
            content: [
              {
                type: "text" as const,
                text: JSON.stringify({ count: formatted.length, results: formatted }, null, 2),
              },
            ],
          };
        }

        default:
          return {
            content: [{ type: "text" as const, text: `Unknown tool: ${name}` }],
            isError: true,
          };
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`[mcp] Tool "${name}" failed:`, message);
      return {
        content: [{ type: "text" as const, text: `Error: ${message}` }],
        isError: true,
      };
    }
  });

  return server;
}

/**
 * Start the MCP server on stdio transport.
 * Used when running as a standalone MCP process (e.g., `npx open-brain-mcp`).
 */
export async function startMcpStdio(): Promise<void> {
  const server = createMcpServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("[mcp] Server running on stdio transport");
}
