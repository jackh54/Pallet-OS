-- Pallet OS Control Plane schema (Cloudflare D1 / SQLite)

CREATE TABLE IF NOT EXISTS enrollment_tokens (
  id TEXT PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL DEFAULT '',
  used INTEGER NOT NULL DEFAULT 0,
  used_by_device_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT
);

CREATE TABLE IF NOT EXISTS devices (
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
);

CREATE TABLE IF NOT EXISTS global_policy (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  policy_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO global_policy (id, policy_json) VALUES (1, '{}');

CREATE TABLE IF NOT EXISTS commands (
  id TEXT PRIMARY KEY,
  device_id TEXT,
  command_type TEXT NOT NULL,
  payload_json TEXT DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  acknowledged_at TEXT,
  completed_at TEXT,
  result_json TEXT,
  FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_commands_device_status ON commands(device_id, status);
CREATE INDEX IF NOT EXISTS idx_enrollment_token ON enrollment_tokens(token);
