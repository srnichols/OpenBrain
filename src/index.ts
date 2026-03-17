/**
 * Open Brain — Entry Point
 *
 * Starts both:
 * 1. Hono REST API server (port 8000)
 * 2. MCP SSE server via raw Node.js HTTP (port 8080)
 *
 * The REST API provides direct HTTP access for testing, Slack webhooks,
 * and any non-MCP integrations.
 *
 * The MCP server is the primary interface for AI tools (Claude, ChatGPT, etc).
 * It uses SSE transport over a raw Node.js HTTP server because
 * SSEServerTransport requires Node.js ServerResponse objects (not Web API).
 */

import http from "node:http";
import { serve } from "@hono/node-server";

import { initializeDatabase, closePool } from "./db/connection.js";
import { createApi } from "./api/routes.js";
import { createMcpServer } from "./mcp/server.js";
import { SSEServerTransport } from "@modelcontextprotocol/sdk/server/sse.js";

async function main(): Promise<void> {
  console.log("╔══════════════════════════════════════════╗");
  console.log("║           Open Brain v1.0.0              ║");
  console.log("║    Personal Semantic Memory System       ║");
  console.log("╚══════════════════════════════════════════╝");

  // Initialize database connection pool
  await initializeDatabase();

  // ── REST API Server (Hono) ──────────────────────────────────────

  const api = createApi();
  const apiPort = parseInt(process.env.API_PORT ?? "8000", 10);

  serve({ fetch: api.fetch, port: apiPort }, () => {
    console.log(`[api] REST API listening on http://0.0.0.0:${apiPort}`);
    console.log(`[api]   POST /memories         — capture thought`);
    console.log(`[api]   POST /memories/search   — semantic search`);
    console.log(`[api]   POST /memories/list     — filtered listing`);
    console.log(`[api]   GET  /stats             — brain statistics`);
    console.log(`[api]   GET  /health            — health check`);
  });

  // ── MCP Server (SSE over raw Node.js HTTP) ─────────────────────

  const mcpPort = parseInt(process.env.MCP_PORT ?? "8080", 10);
  const mcpAccessKey = process.env.MCP_ACCESS_KEY ?? "";

  // Track active SSE transports for cleanup
  const transports = new Map<string, SSEServerTransport>();

  const mcpHttpServer = http.createServer(async (req, res) => {
    // CORS headers
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, x-brain-key");

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    const url = new URL(req.url ?? "/", `http://localhost:${mcpPort}`);

    // Health check — no auth required
    if (url.pathname === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "healthy", service: "open-brain-mcp" }));
      return;
    }

    // SSE endpoint — AI clients connect here
    // Auth is checked here; /messages skips the key check because
    // having a valid sessionId proves the client already authenticated.
    if (url.pathname === "/sse" && req.method === "GET") {
      const key =
        (req.headers["x-brain-key"] as string | undefined) ??
        url.searchParams.get("key");
      if (mcpAccessKey && key !== mcpAccessKey) {
        res.writeHead(401, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Unauthorized" }));
        return;
      }

      const transport = new SSEServerTransport("/messages", res);
      const sessionId = transport.sessionId;
      transports.set(sessionId, transport);

      res.on("close", () => {
        transports.delete(sessionId);
        console.log(`[mcp] SSE session ${sessionId} closed`);
      });

      const server = createMcpServer();
      await server.connect(transport);
      console.log(`[mcp] SSE session ${sessionId} connected`);
      return;
    }

    // Messages endpoint — receives JSON-RPC calls from AI clients
    if (url.pathname === "/messages" && req.method === "POST") {
      const sessionId = url.searchParams.get("sessionId");
      const transport = sessionId ? transports.get(sessionId) : undefined;

      if (!transport) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(
          JSON.stringify({ error: "No active session. Connect to /sse first." })
        );
        return;
      }

      await transport.handlePostMessage(req, res);
      return;
    }

    // 404 fallback
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  });

  mcpHttpServer.listen(mcpPort, "0.0.0.0", () => {
    console.log(`[mcp] MCP SSE server listening on http://0.0.0.0:${mcpPort}`);
    console.log(`[mcp]   GET  /sse               — SSE connection`);
    console.log(`[mcp]   POST /messages           — JSON-RPC calls`);
    console.log(`[mcp]   GET  /health             — health check`);
    console.log("");
    console.log("[mcp] Connect AI clients to:");
    console.log(`[mcp]   http://<host>:${mcpPort}/sse?key=<MCP_ACCESS_KEY>`);
  });
}

// Graceful shutdown
process.on("SIGINT", async () => {
  console.log("\n[shutdown] Received SIGINT, closing...");
  await closePool();
  process.exit(0);
});

process.on("SIGTERM", async () => {
  console.log("\n[shutdown] Received SIGTERM, closing...");
  await closePool();
  process.exit(0);
});

main().catch((err) => {
  console.error("[fatal]", err);
  process.exit(1);
});
