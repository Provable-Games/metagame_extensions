import { pgTable, text, integer, timestamp, jsonb } from "drizzle-orm/pg-core";
import type { MerkleEntry } from "../merkle.js";

export const trees = pgTable("trees", {
  id: integer("id").primaryKey(),
  root: text("root").notNull(),
  entryCount: integer("entry_count").notNull(),
  entries: jsonb("entries").$type<MerkleEntry[]>().notNull(),
  treeDump: jsonb("tree_dump").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});
