import pg from "pg";

const pool = new pg.Pool({
  connectionString:
    process.env.DATABASE_URL ??
    "postgres://postgres:postgres@localhost:5432/metagame_extensions",
});

async function migrate() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS trees (
        id SERIAL PRIMARY KEY,
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
    `);
    console.log("Migration complete");
  } finally {
    client.release();
    await pool.end();
  }
}

migrate().catch(console.error);
