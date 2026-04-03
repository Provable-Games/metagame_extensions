import pg from "pg";

const MIGRATION_SQL = `
  DROP TABLE IF EXISTS tree_entries;
  DROP TABLE IF EXISTS trees;

  CREATE TABLE IF NOT EXISTS trees (
    id INTEGER PRIMARY KEY,
    root TEXT NOT NULL,
    entry_count INTEGER NOT NULL,
    created_at TIMESTAMP DEFAULT NOW() NOT NULL
  );

  CREATE TABLE IF NOT EXISTS tree_entries (
    id SERIAL PRIMARY KEY,
    tree_id INTEGER NOT NULL REFERENCES trees(id),
    address TEXT NOT NULL,
    count INTEGER NOT NULL,
    proof JSONB NOT NULL
  );

  CREATE UNIQUE INDEX IF NOT EXISTS tree_address_idx
    ON tree_entries(tree_id, address);
`;

export async function runMigrations(pool: pg.Pool): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query(MIGRATION_SQL);
    console.log("Migration complete");
  } finally {
    client.release();
  }
}

// Allow running as standalone script
const isMain = import.meta.url === `file://${process.argv[1]}`;
if (isMain) {
  const pool = new pg.Pool({
    connectionString:
      process.env.DATABASE_URL ??
      "postgres://postgres:postgres@localhost:5432/metagame_extensions",
  });
  runMigrations(pool)
    .then(() => pool.end())
    .catch(console.error);
}
