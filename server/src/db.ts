import type { Env, PalletPolicy, DeviceTelemetry, CommandPayload } from "./types";
import { DEFAULT_POLICY, type CommandType } from "./types";
import { hashSecret, mergePolicy, parseJson, randomId, randomToken } from "./crypto";

export async function ensureSchema(db: D1Database): Promise<void> {
  const statements = [
    `CREATE TABLE IF NOT EXISTS enrollment_tokens (
      id TEXT PRIMARY KEY,
      token TEXT NOT NULL UNIQUE,
      label TEXT NOT NULL DEFAULT '',
      used INTEGER NOT NULL DEFAULT 0,
      used_by_device_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT
    )`,
    `CREATE TABLE IF NOT EXISTS devices (
      id TEXT PRIMARY KEY,
      hostname TEXT NOT NULL DEFAULT '',
      device_key_hash TEXT NOT NULL,
      enrolled_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_seen_at TEXT,
      last_ip TEXT,
      agent_version TEXT,
      uptime_seconds INTEGER DEFAULT 0,
      os_version TEXT DEFAULT '',
      locked INTEGER NOT NULL DEFAULT 0,
      wiped INTEGER NOT NULL DEFAULT 0,
      telemetry_json TEXT DEFAULT '{}',
      policy_override_json TEXT
    )`,
    `CREATE TABLE IF NOT EXISTS global_policy (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      policy_json TEXT NOT NULL DEFAULT '{}',
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )`,
    `INSERT OR IGNORE INTO global_policy (id, policy_json) VALUES (1, '{}')`,
    `CREATE TABLE IF NOT EXISTS commands (
      id TEXT PRIMARY KEY,
      device_id TEXT,
      command_type TEXT NOT NULL,
      payload_json TEXT DEFAULT '{}',
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      acknowledged_at TEXT,
      completed_at TEXT,
      result_json TEXT
    )`,
  ];
  for (const sql of statements) {
    await db.prepare(sql).run();
  }
}

export async function getGlobalPolicy(env: Env): Promise<PalletPolicy> {
  const row = await env.DB.prepare(
    "SELECT policy_json FROM global_policy WHERE id = 1"
  ).first<{ policy_json: string }>();
  const parsed = parseJson<Partial<PalletPolicy>>(row?.policy_json, {});
  return { ...DEFAULT_POLICY, ...parsed, version: parsed.version ?? 1 };
}

export async function setGlobalPolicy(env: Env, policy: PalletPolicy): Promise<void> {
  await env.DB.prepare(
    "UPDATE global_policy SET policy_json = ?, updated_at = datetime('now') WHERE id = 1"
  )
    .bind(JSON.stringify(policy))
    .run();
}

export async function getEffectivePolicy(
  env: Env,
  deviceId: string
): Promise<PalletPolicy> {
  const global = await getGlobalPolicy(env);
  const row = await env.DB.prepare(
    "SELECT policy_override_json FROM devices WHERE id = ?"
  )
    .bind(deviceId)
    .first<{ policy_override_json: string | null }>();
  const override = parseJson<Partial<PalletPolicy> | null>(
    row?.policy_override_json ?? null,
    null
  );
  return mergePolicy(global, override ?? undefined);
}

export async function createEnrollmentToken(
  env: Env,
  label = ""
): Promise<{ id: string; token: string }> {
  const id = randomId();
  const token = `plt_${randomToken()}`;
  await env.DB.prepare(
    "INSERT INTO enrollment_tokens (id, token, label) VALUES (?, ?, ?)"
  )
    .bind(id, token, label)
    .run();
  return { id, token };
}

export async function enrollDevice(
  env: Env,
  enrollmentToken: string,
  hostname: string,
  deviceKey: string
): Promise<{ deviceId: string; deviceToken: string } | { error: string }> {
  const tokenRow = await env.DB.prepare(
    "SELECT id, used FROM enrollment_tokens WHERE token = ?"
  )
    .bind(enrollmentToken)
    .first<{ id: string; used: number }>();

  if (!tokenRow) return { error: "invalid_enrollment_token" };
  if (tokenRow.used) return { error: "enrollment_token_already_used" };

  const deviceId = randomId();
  const deviceKeyHash = await hashSecret(deviceKey);
  await env.DB.prepare(
    `INSERT INTO devices (id, hostname, device_key_hash, last_seen_at)
     VALUES (?, ?, ?, datetime('now'))`
  )
    .bind(deviceId, hostname, deviceKeyHash)
    .run();

  await env.DB.prepare(
    "UPDATE enrollment_tokens SET used = 1, used_by_device_id = ? WHERE id = ?"
  )
    .bind(deviceId, tokenRow.id)
    .run();

  const { signDeviceJwt } = await import("./crypto");
  const deviceToken = await signDeviceJwt(
    deviceId,
    env.JWT_SECRET,
    env.JWT_ISSUER ?? "pallet-os"
  );

  return { deviceId, deviceToken };
}

export async function verifyDeviceKey(
  env: Env,
  deviceId: string,
  deviceKey: string
): Promise<boolean> {
  const row = await env.DB.prepare(
    "SELECT device_key_hash FROM devices WHERE id = ?"
  )
    .bind(deviceId)
    .first<{ device_key_hash: string }>();
  if (!row) return false;
  const hash = await hashSecret(deviceKey);
  return hash === row.device_key_hash;
}

export async function recordHeartbeat(
  env: Env,
  deviceId: string,
  telemetry: DeviceTelemetry,
  ip: string
): Promise<void> {
  await env.DB.prepare(
    `UPDATE devices SET
      hostname = ?,
      last_seen_at = datetime('now'),
      last_ip = ?,
      agent_version = ?,
      uptime_seconds = ?,
      os_version = ?,
      telemetry_json = ?
     WHERE id = ?`
  )
    .bind(
      telemetry.hostname,
      ip,
      telemetry.agent_version,
      telemetry.uptime_seconds,
      telemetry.os_version,
      JSON.stringify(telemetry),
      deviceId
    )
    .run();
}

export async function listDevices(env: Env) {
  const { results } = await env.DB.prepare(
    `SELECT id, hostname, enrolled_at, last_seen_at, last_ip, agent_version,
            uptime_seconds, os_version, locked, wiped, telemetry_json
     FROM devices ORDER BY last_seen_at DESC`
  ).all();
  return results ?? [];
}

export async function queueCommand(
  env: Env,
  deviceId: string | null,
  commandType: CommandType,
  payload: CommandPayload = {}
): Promise<string> {
  const id = randomId();
  await env.DB.prepare(
    `INSERT INTO commands (id, device_id, command_type, payload_json)
     VALUES (?, ?, ?, ?)`
  )
    .bind(id, deviceId, commandType, JSON.stringify(payload))
    .run();
  return id;
}

export async function fetchPendingCommands(env: Env, deviceId: string) {
  const { results } = await env.DB.prepare(
    `SELECT id, command_type, payload_json, created_at
     FROM commands
     WHERE (device_id = ? OR device_id IS NULL)
       AND status = 'pending'
     ORDER BY created_at ASC`
  )
    .bind(deviceId)
    .all<{
      id: string;
      command_type: string;
      payload_json: string;
      created_at: string;
    }>();

  if (!results?.length) return [];

  const ids = results.map((r) => r.id);
  const placeholders = ids.map(() => "?").join(",");
  await env.DB.prepare(
    `UPDATE commands SET status = 'acknowledged', acknowledged_at = datetime('now')
     WHERE id IN (${placeholders})`
  )
    .bind(...ids)
    .run();

  return results.map((r) => ({
    id: r.id,
    type: r.command_type,
    payload: parseJson(r.payload_json, {}),
    created_at: r.created_at,
  }));
}

export async function completeCommand(
  env: Env,
  deviceId: string,
  commandId: string,
  success: boolean,
  result: Record<string, unknown> = {}
): Promise<void> {
  await env.DB.prepare(
    `UPDATE commands SET
      status = ?,
      completed_at = datetime('now'),
      result_json = ?
     WHERE id = ? AND (device_id = ? OR device_id IS NULL)`
  )
    .bind(success ? "completed" : "failed", JSON.stringify(result), commandId, deviceId)
    .run();
}

export async function setDeviceLocked(
  env: Env,
  deviceId: string,
  locked: boolean
): Promise<void> {
  await env.DB.prepare("UPDATE devices SET locked = ? WHERE id = ?")
    .bind(locked ? 1 : 0, deviceId)
    .run();
}

export async function setDevicePolicyOverride(
  env: Env,
  deviceId: string,
  policy: PalletPolicy | null
): Promise<void> {
  await env.DB.prepare(
    "UPDATE devices SET policy_override_json = ? WHERE id = ?"
  )
    .bind(policy ? JSON.stringify(policy) : null, deviceId)
    .run();
}
