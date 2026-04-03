import {
  pgTable,
  serial,
  text,
  integer,
  timestamp,
  jsonb,
  uniqueIndex,
} from "drizzle-orm/pg-core";

export const trees = pgTable("trees", {
  id: serial("id").primaryKey(),
  root: text("root").notNull(),
  entryCount: integer("entry_count").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const treeEntries = pgTable(
  "tree_entries",
  {
    id: serial("id").primaryKey(),
    treeId: integer("tree_id")
      .references(() => trees.id)
      .notNull(),
    address: text("address").notNull(),
    count: integer("count").notNull(),
    proof: jsonb("proof").$type<string[]>().notNull(),
  },
  (table) => [uniqueIndex("tree_address_idx").on(table.treeId, table.address)],
);
