import { Hono } from "hono";
import { eq, and } from "drizzle-orm";
import { db } from "../db/client.js";
import { trees, treeEntries } from "../db/schema.js";
import { buildTreeWithProofs } from "../merkle.js";

const app = new Hono();

/**
 * POST /trees
 * Create a new merkle tree from entries.
 * Body: { entries: [{ address: string, count: number }] }
 * Returns: { id, root, entryCount }
 */
app.post("/", async (c) => {
  const body = await c.req.json<{
    entries: Array<{ address: string; count: number }>;
  }>();

  if (!body.entries || !Array.isArray(body.entries) || body.entries.length === 0) {
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

  const result = buildTreeWithProofs(body.entries);

  const [tree] = await db
    .insert(trees)
    .values({
      root: result.root,
      entryCount: result.entries.length,
    })
    .returning();

  if (result.entries.length > 0) {
    await db.insert(treeEntries).values(
      result.entries.map((e) => ({
        treeId: tree.id,
        address: e.address.toLowerCase(),
        count: e.count,
        proof: e.proof,
      })),
    );
  }

  return c.json({
    id: tree.id,
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

  const [tree] = await db.select().from(trees).where(eq(trees.id, id)).limit(1);

  if (!tree) {
    return c.json({ error: "Tree not found" }, 404);
  }

  return c.json({
    id: tree.id,
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

  const entries = await db
    .select({
      address: treeEntries.address,
      count: treeEntries.count,
    })
    .from(treeEntries)
    .where(eq(treeEntries.treeId, id));

  return c.json({ data: entries, total: entries.length });
});

/**
 * GET /trees/:id/proof/:address
 * Get the proof for a specific address in a tree.
 * Returns: { address, count, proof, qualification }
 */
app.get("/:id/proof/:address", async (c) => {
  const id = parseInt(c.req.param("id"));
  const address = c.req.param("address").toLowerCase();

  if (isNaN(id)) {
    return c.json({ error: "Invalid tree ID" }, 400);
  }

  const [entry] = await db
    .select()
    .from(treeEntries)
    .where(and(eq(treeEntries.treeId, id), eq(treeEntries.address, address)))
    .limit(1);

  if (!entry) {
    return c.json({ error: "Address not found in tree" }, 404);
  }

  // Build qualification array: [count, ...proof]
  const qualification = [
    "0x" + entry.count.toString(16),
    ...entry.proof,
  ];

  return c.json({
    address: entry.address,
    count: entry.count,
    proof: entry.proof,
    qualification,
  });
});

export default app;
