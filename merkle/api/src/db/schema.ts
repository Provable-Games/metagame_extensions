import {
  pgTable,
  text,
  integer,
  serial,
  timestamp,
  jsonb,
  uniqueIndex,
} from "drizzle-orm/pg-core";

export const trees = pgTable("trees", {
  id: integer("id").primaryKey(),
  name: text("name").notNull().default(""),
  description: text("description").notNull().default(""),
  root: text("root").notNull(),
  entryCount: integer("entry_count").notNull(),
  treeDump: jsonb("tree_dump").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const treeEntries = pgTable(
  "tree_entries",
  {
    id: serial("id").primaryKey(),
    treeId: integer("tree_id")
      .notNull()
      .references(() => trees.id),
    address: text("address").notNull(),
    count: integer("count").notNull(),
  },
  (table) => [
    uniqueIndex("tree_entries_tree_id_address_unique").on(
      table.treeId,
      table.address,
    ),
  ],
);
