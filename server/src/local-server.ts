import { serve } from "@hono/node-server";
import app from "./index.js";
import { ensureSchema } from "./db.js";
import type { Env } from "./types.js";
import Database from "better-sqlite3";
import { LocalD1Database } from "./local-d1.js";

const port = Number(process.env.PORT ?? 8787);

const sqlite = new Database(process.env.PALLET_DB_PATH ?? "/data/pallet.db");
sqlite.pragma("journal_mode = WAL");

const env: Env = {
  DB: new LocalD1Database(sqlite) as unknown as Env["DB"],
  ADMIN_USERNAME: process.env.ADMIN_USERNAME ?? "admin",
  ADMIN_PASSWORD: process.env.ADMIN_PASSWORD ?? "pallet-dev-secret",
  JWT_SECRET: process.env.JWT_SECRET ?? "dev-jwt-secret",
  JWT_ISSUER: process.env.JWT_ISSUER ?? "pallet-os",
};

await ensureSchema(env.DB);

serve({ fetch: (request) => app.fetch(request, env), port }, () => {
  console.log(`Pallet OS API listening on http://0.0.0.0:${port}`);
});
