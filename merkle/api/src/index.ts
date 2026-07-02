import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { initialize, healthCheck, shutdown } from "./db/client.js";
import trees from "./routes/trees.js";

const app = new Hono();

// Allowed origins for write operations (POST/PUT/DELETE)
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ?? "")
  .split(",")
  .map((o) => o.trim())
  .filter(Boolean);

// Read endpoints: open CORS
// Write endpoints: restricted to allowed origins
app.use("/*", async (c, next) => {
  const method = c.req.method;

  if (method === "GET" || method === "HEAD" || method === "OPTIONS") {
    // Open CORS for reads
    return cors()(c, next);
  }

  // Write operations. The `Origin` header is only sent by browsers; headless
  // server-to-server callers (bots storing trees) send none. Writes are already
  // bound to on-chain state — POST /trees recomputes the root and rejects any
  // tree whose root != the on-chain root — so a missing Origin is safe to allow.
  // Only enforce the allowlist against a real browser Origin; otherwise setting
  // ALLOWED_ORIGINS silently 403s every headless store.
  const origin = c.req.header("origin");
  if (origin && ALLOWED_ORIGINS.length > 0 && !ALLOWED_ORIGINS.includes(origin)) {
    return c.json({ error: "Origin not allowed" }, 403);
  }

  return cors({ origin: ALLOWED_ORIGINS.length > 0 ? ALLOWED_ORIGINS : "*" })(
    c,
    next,
  );
});

app.get("/health", async (c) => {
  const dbOk = await healthCheck();
  if (!dbOk) {
    return c.json({ status: "unhealthy", db: false }, 503);
  }
  return c.json({ status: "healthy", db: true });
});

app.route("/trees", trees);

const port = parseInt(process.env.PORT ?? "3002");

async function start() {
  await initialize();
  console.log(`Merkle API starting on port ${port}`);
  serve({ fetch: app.fetch, port });
}

start().catch((err) => {
  console.error("Failed to start:", err);
  process.exit(1);
});

process.on("SIGTERM", async () => {
  console.log("Shutting down...");
  await shutdown();
  process.exit(0);
});
