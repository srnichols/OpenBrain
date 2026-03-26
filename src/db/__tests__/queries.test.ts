/**
 * Unit tests for src/db/queries.ts
 * Uses mocked pg.Pool to test query construction and parameter passing.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";
import type pg from "pg";

import {
  insertThought,
  searchThoughts,
  listThoughts,
  getThoughtStats,
  updateThought,
  deleteThought,
  batchInsertThoughts,
  type ThoughtMetadata,
} from "../queries.js";

// ─── Mock Pool Factory ──────────────────────────────────────────────

function createMockPool() {
  const mockQuery = vi.fn();
  const mockRelease = vi.fn();
  const mockConnect = vi.fn().mockResolvedValue({
    query: mockQuery,
    release: mockRelease,
  });

  const pool = {
    query: mockQuery,
    connect: mockConnect,
  } as unknown as pg.Pool;

  return { pool, mockQuery, mockConnect, mockRelease };
}

// ─── insertThought ──────────────────────────────────────────────────

describe("insertThought", () => {
  it("inserts with project and supersedes params", async () => {
    const { pool, mockQuery } = createMockPool();
    const metadata: ThoughtMetadata = { type: "decision", source: "mcp" };
    const row = {
      id: "abc-123",
      content: "test content",
      metadata,
      project: "plan-forge",
      archived: false,
      supersedes: null,
      created_at: new Date(),
    };
    mockQuery.mockResolvedValueOnce({ rows: [row] });

    const result = await insertThought(
      pool, "test content", [0.1, 0.2], metadata, "plan-forge", undefined, undefined
    );

    expect(result.id).toBe("abc-123");
    expect(result.project).toBe("plan-forge");

    // Verify SQL includes project, supersedes, and created_by columns
    const sql = mockQuery.mock.calls[0]![0] as string;
    expect(sql).toContain("project");
    expect(sql).toContain("supersedes");
    expect(sql).toContain("created_by");

    // Verify params include project, null supersedes, and null created_by
    const params = mockQuery.mock.calls[0]![1] as unknown[];
    expect(params[3]).toBe("plan-forge");
    expect(params[4]).toBeNull();
    expect(params[5]).toBeNull();
  });

  it("inserts without project (backward compatible)", async () => {
    const { pool, mockQuery } = createMockPool();
    const metadata: ThoughtMetadata = { type: "observation" };
    const row = {
      id: "def-456",
      content: "old style",
      metadata,
      project: null,
      archived: false,
      supersedes: null,
      created_at: new Date(),
    };
    mockQuery.mockResolvedValueOnce({ rows: [row] });

    const result = await insertThought(pool, "old style", [0.3], metadata);

    expect(result.project).toBeNull();
    const params = mockQuery.mock.calls[0]![1] as unknown[];
    expect(params[3]).toBeNull(); // project
    expect(params[4]).toBeNull(); // supersedes
    expect(params[5]).toBeNull(); // created_by
  });

  it("inserts with created_by when provided", async () => {
    const { pool, mockQuery } = createMockPool();
    const metadata: ThoughtMetadata = { type: "observation" };
    const row = {
      id: "ghi-789",
      content: "user thought",
      metadata,
      project: "proj",
      created_by: "sarah",
      archived: false,
      supersedes: null,
      created_at: new Date(),
    };
    mockQuery.mockResolvedValueOnce({ rows: [row] });

    const result = await insertThought(pool, "user thought", [0.4], metadata, "proj", undefined, "sarah");

    expect(result.created_by).toBe("sarah");
    const params = mockQuery.mock.calls[0]![1] as unknown[];
    expect(params[5]).toBe("sarah");
  });
});

// ─── searchThoughts ─────────────────────────────────────────────────

describe("searchThoughts", () => {
  it("passes project and include_archived to match_thoughts RPC", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    await searchThoughts(pool, [0.1], 10, 0.5, {}, "plan-forge", false);

    const params = mockQuery.mock.calls[0]![1] as unknown[];
    // Params: embedding, threshold, limit, filter, project_filter, include_archived, user_filter
    expect(params[4]).toBe("plan-forge");
    expect(params[5]).toBe(false);
  });

  it("passes created_by as user_filter to match_thoughts RPC", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    await searchThoughts(pool, [0.1], 10, 0.5, {}, "plan-forge", false, "sarah");

    const params = mockQuery.mock.calls[0]![1] as unknown[];
    expect(params[6]).toBe("sarah");
  });

  it("passes type and topic as JSONB filter", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const filter = { type: "decision", topics: ["caching"] };
    await searchThoughts(pool, [0.1], 10, 0.5, filter);

    const params = mockQuery.mock.calls[0]![1] as unknown[];
    const jsonFilter = JSON.parse(params[3] as string);
    expect(jsonFilter.type).toBe("decision");
    expect(jsonFilter.topics).toEqual(["caching"]);
  });

  it("works without filters (backward compatible)", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    await searchThoughts(pool, [0.1]);

    const params = mockQuery.mock.calls[0]![1] as unknown[];
    expect(params[4]).toBeNull();  // project
    expect(params[5]).toBe(false); // include_archived
    expect(params[6]).toBeNull();  // created_by
  });
});

// ─── listThoughts ───────────────────────────────────────────────────

describe("listThoughts", () => {
  it("filters by project when provided", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    await listThoughts(pool, { project: "openbrain" });

    const sql = mockQuery.mock.calls[0]![0] as string;
    expect(sql).toContain("project =");
  });

  it("excludes archived by default", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    await listThoughts(pool, {});

    const sql = mockQuery.mock.calls[0]![0] as string;
    expect(sql).toContain("archived = false");
  });

  it("filters by created_by when provided", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    await listThoughts(pool, { created_by: "sarah" });

    const sql = mockQuery.mock.calls[0]![0] as string;
    expect(sql).toContain("created_by =");
  });

  it("includes archived when requested", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [] });

    await listThoughts(pool, { include_archived: true });

    const sql = mockQuery.mock.calls[0]![0] as string;
    expect(sql).not.toContain("archived = false");
  });
});

// ─── getThoughtStats ────────────────────────────────────────────────

describe("getThoughtStats", () => {
  const defaultMocks = (mockQuery: ReturnType<typeof vi.fn>) => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ count: "5" }] })       // total
      .mockResolvedValueOnce({ rows: [] })                       // types
      .mockResolvedValueOnce({ rows: [] })                       // topics
      .mockResolvedValueOnce({ rows: [] })                       // people
      .mockResolvedValueOnce({ rows: [{ earliest: null, latest: null }] }); // range
  };

  it("scopes by project when provided", async () => {
    const { pool, mockQuery } = createMockPool();
    defaultMocks(mockQuery);

    await getThoughtStats(pool, "plan-forge");

    // First call (count) should include project filter
    const countSql = mockQuery.mock.calls[0]![0] as string;
    expect(countSql).toContain("project =");
    const countParams = mockQuery.mock.calls[0]![1] as unknown[];
    expect(countParams[0]).toBe("plan-forge");
  });

  it("scopes by created_by when provided", async () => {
    const { pool, mockQuery } = createMockPool();
    defaultMocks(mockQuery);

    await getThoughtStats(pool, undefined, "sarah");

    const countSql = mockQuery.mock.calls[0]![0] as string;
    expect(countSql).toContain("created_by =");
    const countParams = mockQuery.mock.calls[0]![1] as unknown[];
    expect(countParams[0]).toBe("sarah");
  });

  it("does not filter by project when omitted", async () => {
    const { pool, mockQuery } = createMockPool();
    defaultMocks(mockQuery);

    await getThoughtStats(pool);

    const countSql = mockQuery.mock.calls[0]![0] as string;
    expect(countSql).not.toContain("project =");
  });
});

// ─── updateThought ──────────────────────────────────────────────────

describe("updateThought", () => {
  it("returns updated row", async () => {
    const { pool, mockQuery } = createMockPool();
    const row = {
      id: "abc-123",
      content: "updated",
      metadata: { type: "decision" },
      project: null,
      archived: false,
      supersedes: null,
      created_at: new Date(),
    };
    mockQuery.mockResolvedValueOnce({ rows: [row], rowCount: 1 });

    const result = await updateThought(
      pool, "abc-123", "updated", [0.1], { type: "decision" }
    );

    expect(result.id).toBe("abc-123");
    expect(result.content).toBe("updated");
  });

  it("throws when thought not found", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rows: [], rowCount: 0 });

    await expect(
      updateThought(pool, "nonexistent", "content", [0.1], {})
    ).rejects.toThrow("Thought not found");
  });
});

// ─── deleteThought ──────────────────────────────────────────────────

describe("deleteThought", () => {
  it("returns deletion confirmation", async () => {
    const { pool, mockQuery } = createMockPool();
    // First call: clear supersedes refs
    mockQuery.mockResolvedValueOnce({ rowCount: 0 });
    // Second call: delete
    mockQuery.mockResolvedValueOnce({ rowCount: 1 });

    const result = await deleteThought(pool, "abc-123");

    expect(result.deleted).toBe(true);
    expect(result.id).toBe("abc-123");
  });

  it("returns deleted=false when thought not found", async () => {
    const { pool, mockQuery } = createMockPool();
    mockQuery.mockResolvedValueOnce({ rowCount: 0 });
    mockQuery.mockResolvedValueOnce({ rowCount: 0 });

    const result = await deleteThought(pool, "nonexistent");

    expect(result.deleted).toBe(false);
  });
});

// ─── batchInsertThoughts ────────────────────────────────────────────

describe("batchInsertThoughts", () => {
  it("inserts all thoughts within a transaction", async () => {
    const { pool, mockQuery, mockConnect } = createMockPool();
    const clientQuery = (await mockConnect()).query;

    const row = (i: number) => ({
      id: `id-${i}`,
      content: `thought ${i}`,
      metadata: {},
      project: "proj",
      archived: false,
      supersedes: null,
      created_at: new Date(),
    });

    // BEGIN, INSERT x2, COMMIT
    clientQuery
      .mockResolvedValueOnce({})                     // BEGIN
      .mockResolvedValueOnce({ rows: [row(1)] })     // INSERT 1
      .mockResolvedValueOnce({ rows: [row(2)] })     // INSERT 2
      .mockResolvedValueOnce({});                     // COMMIT

    const results = await batchInsertThoughts(pool, [
      { content: "thought 1", embedding: [0.1], metadata: {}, project: "proj" },
      { content: "thought 2", embedding: [0.2], metadata: {}, project: "proj" },
    ]);

    expect(results).toHaveLength(2);

    // Verify transaction flow: BEGIN → INSERTs → COMMIT
    expect(clientQuery.mock.calls[0]![0]).toBe("BEGIN");
    expect(clientQuery.mock.calls[3]![0]).toBe("COMMIT");
  });

  it("rolls back on error", async () => {
    const { pool, mockConnect } = createMockPool();
    const client = await mockConnect();

    client.query
      .mockResolvedValueOnce({})                          // BEGIN
      .mockRejectedValueOnce(new Error("insert failed")); // INSERT fails

    await expect(
      batchInsertThoughts(pool, [
        { content: "fail", embedding: [0.1], metadata: {} },
      ])
    ).rejects.toThrow("insert failed");

    // Should have called ROLLBACK
    expect(client.query).toHaveBeenCalledWith("ROLLBACK");
  });
});
