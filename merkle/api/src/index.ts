import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { healthCheck, shutdown } from "./db/client.js";
import trees from "./routes/trees.js";

const app = new Hono();

app.use("/*", cors());

app.get("/health", async (c) => {
  const dbOk = await healthCheck();
  if (!dbOk) {
    return c.json({ status: "unhealthy", db: false }, 503);
  }
  return c.json({ status: "healthy", db: true });
});

app.route("/trees", trees);

const port = parseInt(process.env.PORT ?? "3002");

console.log(`Merkle API starting on port ${port}`);

serve({ fetch: app.fetch, port });

process.on("SIGTERM", async () => {
  console.log("Shutting down...");
  await shutdown();
  process.exit(0);
});
