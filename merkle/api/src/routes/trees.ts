import { Hono } from "hono";
import { eq } from "drizzle-orm";
import { db } from "../db/client.js";
import { trees } from "../db/schema.js";
import { buildTree, findEntryInDump, getProofFromDump } from "../merkle.js";

const app = new Hono();

/**
 * GET /trees
 * List all trees with metadata (without entries/dump).
 */
app.get("/", async (c) => {
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
    .orderBy(trees.id);

  return c.json({
    data: rows.map((t) => ({
      id: t.id,
      name: t.name,
      description: t.description,
      root: t.root,
      entryCount: t.entryCount,
      createdAt: t.createdAt.toISOString(),
    })),
    total: rows.length,
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
      entries: body.entries,
      treeDump: result.dump,
    })
    .returning();

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
 * Get all entries for a tree.
 */
app.get("/:id/entries", async (c) => {
  const id = parseInt(c.req.param("id"));
  if (isNaN(id)) {
    return c.json({ error: "Invalid tree ID" }, 400);
  }

  const [tree] = await db
    .select({ entries: trees.entries, entryCount: trees.entryCount })
    .from(trees)
    .where(eq(trees.id, id))
    .limit(1);

  if (!tree) {
    return c.json({ error: "Tree not found" }, 404);
  }

  return c.json({ data: tree.entries, total: tree.entryCount });
});

/**
 * GET /trees/:id/proof/:address
 * Compute and return the proof for a specific address. Proof is generated on-demand.
 */
app.get("/:id/proof/:address", async (c) => {
  const id = parseInt(c.req.param("id"));
  const address = c.req.param("address");

  if (isNaN(id)) {
    return c.json({ error: "Invalid tree ID" }, 400);
  }

  const [tree] = await db
    .select({ entries: trees.entries, treeDump: trees.treeDump })
    .from(trees)
    .where(eq(trees.id, id))
    .limit(1);

  if (!tree) {
    return c.json({ error: "Tree not found" }, 404);
  }

  const entry = findEntryInDump(tree.treeDump, tree.entries, address);
  if (!entry) {
    return c.json({ error: "Address not found in tree" }, 404);
  }

  const proof = getProofFromDump(tree.treeDump, entry.address, entry.count);
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
