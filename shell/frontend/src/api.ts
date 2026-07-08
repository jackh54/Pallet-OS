export interface ShellApp {
  id: string;
  name: string;
  icon?: string;
  exec: string;
  type: "web" | "native" | "android";
  pinned?: boolean;
  running?: boolean;
}

export interface ShellConfig {
  wallpaper: string;
  apps: ShellApp[];
  pinned: string[];
  running: string[];
  clock: string;
  wifi_ssid: string;
  battery_percent: number | null;
  locked: boolean;
}

export async function fetchConfig(): Promise<ShellConfig> {
  const res = await fetch("/api/config");
  if (!res.ok) throw new Error("config fetch failed");
  return res.json();
}

export async function launchApp(id: string): Promise<void> {
  await fetch("/api/launch", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ id }),
  });
}

export async function toggleLauncher(open: boolean): Promise<void> {
  await fetch("/api/launcher", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ open }),
  });
}
