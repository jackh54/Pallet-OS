const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:8787";

export function getApiUrl() {
  return API_URL.replace(/\/$/, "");
}

export async function api<T>(
  path: string,
  options: RequestInit = {},
  token?: string | null
): Promise<T> {
  const headers = new Headers(options.headers);
  headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);
  const res = await fetch(`${getApiUrl()}${path}`, { ...options, headers, cache: "no-store" });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || res.statusText);
  }
  return res.json();
}

export interface Device {
  id: string;
  hostname: string;
  enrolled_at: string;
  last_seen_at: string | null;
  last_ip: string | null;
  agent_version: string | null;
  uptime_seconds: number;
  os_version: string;
  locked: boolean;
  wiped: boolean;
  online: boolean;
  telemetry: Record<string, unknown>;
}

export interface Policy {
  version: number;
  wallpaper_url?: string;
  chromium?: Record<string, unknown>;
  android?: {
    force_install?: string[];
    allowlist?: string[];
  };
  shell?: Record<string, unknown>;
}
