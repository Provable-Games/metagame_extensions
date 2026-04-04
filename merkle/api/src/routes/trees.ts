import { Hono } from "hono";
import { eq, and, count } from "drizzle-orm";
import { db, pool } from "../db/client.js";
import { trees, treeEntries } from "../db/schema.js";
import { buildTree, getProofFromDump } from "../merkle.js";

const app = new Hono();

/**
 * GET /trees
 * List all trees with metadata.
 */
app.get("/", async (c) => {
  const page = Math.max(1, parseInt(c.req.query("page") ?? "1") || 1);
  const limit = Math.min(
    100,
    Math.max(1, parseInt(c.req.query("limit") ?? "20") || 20),
  );
  const offset = (page - 1) * limit;

  const [countResult] = await db
    .select({ count: count() })
    .from(trees);

  const total = countResult.count;

  const rows = await db
    .select({
      id: trees.id,
      name: trees.name,
      description: trees.description,
      root: trees.root,
      entryCount: trees.entryCount,
      createdAt: trees.createdAt,
    })
    .from(trees)
    .orderBy(trees.id)
    .limit(limit)
    .offset(offset);

  return c.json({
    data: rows.map((t) => ({
      id: t.id,
      name: t.name,
      description: t.description,
      root: t.root,
      entryCount: t.entryCount,
      createdAt: t.createdAt.toISOString(),
    })),
    total,
    page,
    limit,
    totalPages: Math.ceil(total / limit),
  });
});

/**
 * POST /trees
 * Store a merkle tree. The id must match the on-chain tree ID.
 * Body: { id: number, name?: string, description?: string, entries: [{ address: string, count: number }] }
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    id: number;
    name?: string;
    description?: string;
    entries: Array<{ address: string; count: number }>;
  }>();

  if (!body.id || typeof body.id !== "number") {
    return c.json(
      { error: "id is required and must match the on-chain tree ID" },
      400,
    );
  }

  if (
    !body.entries ||
    !Array.isArray(body.entries) ||
    body.entries.length === 0
  ) {
    return c.json({ error: "entries must be a non-empty array" }, 400);
  }

  for (const entry of body.entries) {
    if (!entry.address || typeof entry.count !== "number" || entry.count <= 0) {
      return c.json(
        { error: "Each entry must have a valid address and positive count" },
        400,
      );
    }
  }

  const [existing] = await db
    .select()
    .from(trees)
    .where(eq(trees.id, body.id))
    .limit(1);
  if (existing) {
    return c.json({ error: `Tree ${body.id} already exists` }, 409);
  }

  const result = buildTree(body.entries);

  const [tree] = await db
    .insert(trees)
    .values({
      id: body.id,
      name: body.name ?? "",
      description: body.description ?? "",
      root: result.root,
      entryCount: body.entries.length,
      treeDump: result.dump,
    })
    .returning();

  // Bulk insert into tree_entries for O(1) address lookups
  const addresses = body.entries.map((e) => e.address.toLowerCase());
  const counts = body.entries.map((e) => e.count);

  await pool.query(
    `INSERT INTO tree_entries (tree_id, address, count)
     SELECT $1, unnest($2::text[]), unnest($3::integer[])`,
    [body.id, addresses, counts],
  );

  return c.json({
    id: tree.id,
    name: tree.name,
    description: tree.description,
    root: tree.root,
    entryCount: tree.entryCount,
  });
});

/**
 * GET /trees/:id
 * Get tree metadata.
 */
app.get("/:id", async (c) => {
  const id = parseInt(c.req.param("id"));
  if (isNaN(id)) {
    return c.json({ error: "Invalid tree ID" }, 400);
  }

  const [tree] = await db
    .select({
      id: trees.id,
      name: trees.name,
      description: trees.description,
      root: trees.root,
      entryCount: trees.entryCount,
      createdAt: trees.createdAt,
    })
    .from(trees)
    .where(eq(trees.id, id))
    .limit(1);

  if (!tree) {
    return c.json({ error: "Tree not found" }, 404);
  }

  return c.json({
    id: tree.id,
    name: tree.name,
    description: tree.description,
    root: tree.root,
    entryCount: tree.entryCount,
    createdAt: tree.createdAt.toISOString(),
  });
});

/**
 * GET /trees/:id/entries
 * Get entries for a tree with pagination.
 * Query params: page (default 1), limit (default 50, max 1000)
 */
app.get("/:id/entries", async (c) => {
  const id = parseInt(c.req.param("id"));
  if (isNaN(id)) {
    return c.json({ error: "Invalid tree ID" }, 400);
  }

  const page = Math.max(1, parseInt(c.req.query("page") ?? "1") || 1);
  const limit = Math.min(
    1000,
    Math.max(1, parseInt(c.req.query("limit") ?? "50") || 50),
  );
  const offset = (page - 1) * limit;

  const [tree] = await db
    .select({ entryCount: trees.entryCount })
    .from(trees)
    .where(eq(trees.id, id))
    .limit(1);

  if (!tree) {
    return c.json({ error: "Tree not found" }, 404);
  }

  const rows = await db
    .select({ address: treeEntries.address, count: treeEntries.count })
    .from(treeEntries)
    .where(eq(treeEntries.treeId, id))
    .orderBy(treeEntries.id)
    .limit(limit)
    .offset(offset);

  return c.json({
    data: rows,
    total: tree.entryCount,
    page,
    limit,
    totalPages: Math.ceil(tree.entryCount / limit),
  });
});

/**
 * GET /trees/:id/entries/:address
 * Look up a single address entry.
 */
app.get("/:id/entries/:address", async (c) => {
  const id = parseInt(c.req.param("id"));
  const address = c.req.param("address");

  if (isNaN(id)) {
    return c.json({ error: "Invalid tree ID" }, 400);
  }

  const [entry] = await db
    .select({ address: treeEntries.address, count: treeEntries.count })
    .from(treeEntries)
    .where(
      and(eq(treeEntries.treeId, id), eq(treeEntries.address, address.toLowerCase())),
    )
    .limit(1);

  if (!entry) {
    return c.json({ error: "Address not found in tree" }, 404);
  }

  return c.json({ address: entry.address, count: entry.count });
});

/**
 * GET /trees/:id/proof/:address
 * Compute and return the proof for a specific address.
 */
app.get("/:id/proof/:address", async (c) => {
  const id = parseInt(c.req.param("id"));
  const address = c.req.param("address");

  if (isNaN(id)) {
    return c.json({ error: "Invalid tree ID" }, 400);
  }

  // O(1) address lookup via indexed table
  const [entry] = await db
    .select({ address: treeEntries.address, count: treeEntries.count })
    .from(treeEntries)
    .where(
      and(eq(treeEntries.treeId, id), eq(treeEntries.address, address.toLowerCase())),
    )
    .limit(1);

  if (!entry) {
    return c.json({ error: "Address not found in tree" }, 404);
  }

  // Load tree dump for proof generation
  const [tree] = await db
    .select({ treeDump: trees.treeDump })
    .from(trees)
    .where(eq(trees.id, id))
    .limit(1);

  if (!tree) {
    return c.json({ error: "Tree not found" }, 404);
  }

  // Use the original address format for leaf hashing (tree was built with original casing)
  // tree_entries stores lowercase, but we need to try the original form too
  const proof = getProofFromDump(id, tree.treeDump, address, entry.count)
    ?? getProofFromDump(id, tree.treeDump, entry.address, entry.count);

  if (!proof) {
    return c.json({ error: "Could not compute proof" }, 500);
  }

  const qualification = ["0x" + entry.count.toString(16), ...proof];

  return c.json({
    address: entry.address,
    count: entry.count,
    proof,
    qualification,
  });
});

export default app;
