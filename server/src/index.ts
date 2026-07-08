import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env } from "./types";
import { DEFAULT_POLICY } from "./types";
import {
  ensureSchema,
  getGlobalPolicy,
  setGlobalPolicy,
  getEffectivePolicy,
  createEnrollmentToken,
  enrollDevice,
  verifyDeviceKey,
  recordHeartbeat,
  listDevices,
  queueCommand,
  fetchPendingCommands,
  completeCommand,
  setDeviceLocked,
  setDevicePolicyOverride,
} from "./db";
import {
  signAdminJwt,
  verifyAdminJwt,
  verifyDeviceJwt,
  isOnline,
  parseJson,
} from "./crypto";

type AppEnv = { Bindings: Env };

const app = new Hono<AppEnv>();

app.use(
  "*",
  cors({
    origin: (origin) => origin ?? "*",
    allowHeaders: ["Authorization", "Content-Type", "X-Device-Key"],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  })
);

app.use("*", async (c, next) => {
  await ensureSchema(c.env.DB);
  await next();
});

function jsonError(c: { json: (data: unknown, status?: number) => Response }, status: number, message: string) {
  return c.json({ error: message }, status);
}

async function requireAdmin(c: { req: { header: (name: string) => string | undefined }; env: Env }) {
  const auth = c.req.header("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const token = auth.slice(7);
  const claims = await verifyAdminJwt(
    token,
    c.env.JWT_SECRET,
    c.env.JWT_ISSUER ?? "pallet-os"
  );
  return claims;
}

async function requireDevice(c: { req: { header: (name: string) => string | undefined }; env: Env }) {
  const auth = c.req.header("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const token = auth.slice(7);
  const claims = await verifyDeviceJwt(
    token,
    c.env.JWT_SECRET,
    c.env.JWT_ISSUER ?? "pallet-os"
  );
  if (!claims) return null;
  const deviceKey = c.req.header("X-Device-Key");
  if (deviceKey) {
    const ok = await verifyDeviceKey(c.env, claims.sub, deviceKey);
    if (!ok) return null;
  }
  return claims;
}

app.get("/health", (c) =>
  c.json({ status: "ok", service: "pallet-os-server", version: "1.0.0" })
);

app.post("/api/v1/admin/login", async (c) => {
  const body = await c.req.json<{ username?: string; password?: string }>();
  const username = body.username ?? "";
  const password = body.password ?? "";
  if (
    username !== c.env.ADMIN_USERNAME ||
    password !== c.env.ADMIN_PASSWORD
  ) {
    return jsonError(c, 401, "invalid_credentials");
  }
  const token = await signAdminJwt(
    username,
    c.env.JWT_SECRET,
    c.env.JWT_ISSUER ?? "pallet-os"
  );
  return c.json({ token, expires_in: 86400 });
});

app.get("/api/v1/admin/devices", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const rows = await listDevices(c.env);
  const devices = rows.map((row) => {
    const r = row as Record<string, unknown>;
    const telemetry = parseJson(r.telemetry_json as string, {});
    return {
      id: r.id,
      hostname: r.hostname,
      enrolled_at: r.enrolled_at,
      last_seen_at: r.last_seen_at,
      last_ip: r.last_ip,
      agent_version: r.agent_version,
      uptime_seconds: r.uptime_seconds,
      os_version: r.os_version,
      locked: Boolean(r.locked),
      wiped: Boolean(r.wiped),
      online: isOnline(r.last_seen_at as string | null),
      telemetry,
    };
  });
  return c.json({ devices });
});

app.get("/api/v1/admin/devices/:id", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const id = c.req.param("id");
  const row = await c.env.DB.prepare(
    "SELECT * FROM devices WHERE id = ?"
  )
    .bind(id)
    .first();
  if (!row) return jsonError(c, 404, "device_not_found");
  const policy = await getEffectivePolicy(c.env, id);
  return c.json({
    device: {
      ...row,
      online: isOnline(row.last_seen_at as string | null),
      telemetry: parseJson(row.telemetry_json as string, {}),
    },
    policy,
  });
});

app.get("/api/v1/admin/policy", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const policy = await getGlobalPolicy(c.env);
  return c.json({ policy });
});

app.put("/api/v1/admin/policy", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const body = await c.req.json<{ policy: typeof DEFAULT_POLICY }>();
  const policy = { ...DEFAULT_POLICY, ...body.policy, version: Date.now() };
  await setGlobalPolicy(c.env, policy);
  await queueCommand(c.env, null, "apply_policy", { policy });
  return c.json({ policy });
});

app.put("/api/v1/admin/devices/:id/policy", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const id = c.req.param("id");
  const body = await c.req.json<{ policy: typeof DEFAULT_POLICY | null }>();
  await setDevicePolicyOverride(c.env, id, body.policy);
  await queueCommand(c.env, id, "apply_policy", { policy: body.policy ?? undefined });
  return c.json({ ok: true });
});

app.post("/api/v1/admin/enrollment-tokens", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const body = await c.req.json<{ label?: string }>().catch(() => ({ label: "" }));
  const token = await createEnrollmentToken(c.env, body.label ?? "");
  return c.json(token);
});

app.get("/api/v1/admin/enrollment-tokens", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const { results } = await c.env.DB.prepare(
    "SELECT id, token, label, used, used_by_device_id, created_at FROM enrollment_tokens ORDER BY created_at DESC"
  ).all();
  return c.json({ tokens: results ?? [] });
});

app.post("/api/v1/admin/devices/:id/commands", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const id = c.req.param("id");
  const body = await c.req.json<{ type: string; payload?: Record<string, unknown> }>();
  const allowed = [
    "lock",
    "unlock",
    "reboot",
    "wipe",
    "logout",
    "restart_shell",
    "install_app",
    "remove_app",
    "apply_policy",
    "check_updates",
  ];
  if (!allowed.includes(body.type)) return jsonError(c, 400, "invalid_command");
  if (body.type === "lock") await setDeviceLocked(c.env, id, true);
  if (body.type === "unlock") await setDeviceLocked(c.env, id, false);
  const commandId = await queueCommand(
    c.env,
    id,
    body.type as Parameters<typeof queueCommand>[2],
    body.payload ?? {}
  );
  return c.json({ command_id: commandId });
});

app.post("/api/v1/admin/commands/fleet", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const body = await c.req.json<{ type: string; payload?: Record<string, unknown> }>();
  const commandId = await queueCommand(
    c.env,
    null,
    body.type as Parameters<typeof queueCommand>[2],
    body.payload ?? {}
  );
  return c.json({ command_id: commandId });
});

app.get("/api/v1/admin/commands", async (c) => {
  if (!(await requireAdmin(c))) return jsonError(c, 401, "unauthorized");
  const { results } = await c.env.DB.prepare(
    `SELECT id, device_id, command_type, status, created_at, completed_at, result_json
     FROM commands ORDER BY created_at DESC LIMIT 200`
  ).all();
  return c.json({ commands: results ?? [] });
});

// Device API
app.post("/api/v1/device/enroll", async (c) => {
  const body = await c.req.json<{
    enrollment_token: string;
    hostname: string;
    device_key: string;
  }>();
  if (!body.enrollment_token || !body.hostname || !body.device_key) {
    return jsonError(c, 400, "missing_fields");
  }
  const result = await enrollDevice(
    c.env,
    body.enrollment_token,
    body.hostname,
    body.device_key
  );
  if ("error" in result) return jsonError(c, 400, result.error);
  return c.json({
    device_id: result.deviceId,
    device_token: result.deviceToken,
  });
});

app.post("/api/v1/device/heartbeat", async (c) => {
  const claims = await requireDevice(c);
  if (!claims) return jsonError(c, 401, "unauthorized");
  const telemetry = await c.req.json();
  const ip =
    c.req.header("CF-Connecting-IP") ??
    c.req.header("X-Forwarded-For") ??
    "unknown";
  await recordHeartbeat(c.env, claims.sub, telemetry, ip);
  const policy = await getEffectivePolicy(c.env, claims.sub);
  const device = await c.env.DB.prepare(
    "SELECT locked FROM devices WHERE id = ?"
  )
    .bind(claims.sub)
    .first<{ locked: number }>();
  const commands = await fetchPendingCommands(c.env, claims.sub);
  return c.json({
    policy,
    locked: Boolean(device?.locked),
    commands,
  });
});

app.post("/api/v1/device/commands/:id/complete", async (c) => {
  const claims = await requireDevice(c);
  if (!claims) return jsonError(c, 401, "unauthorized");
  const commandId = c.req.param("id");
  const body = await c.req.json<{ success?: boolean; result?: Record<string, unknown> }>();
  await completeCommand(
    c.env,
    claims.sub,
    commandId,
    body.success ?? true,
    body.result ?? {}
  );
  return c.json({ ok: true });
});

app.get("/api/v1/device/policy", async (c) => {
  const claims = await requireDevice(c);
  if (!claims) return jsonError(c, 401, "unauthorized");
  const policy = await getEffectivePolicy(c.env, claims.sub);
  return c.json({ policy });
});

// Shell reads policy without device key on localhost proxy
app.get("/api/v1/shell/config", async (c) => {
  const policy = await getGlobalPolicy(c.env);
  return c.json({ policy });
});

export default app;
