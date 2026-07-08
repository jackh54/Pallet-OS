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

export interface DisplayOutput {
  name: string;
  connected: boolean;
  primary: boolean;
  current_mode?: string;
  modes: string[];
}

export interface DisplayCurrent {
  output?: string;
  mode?: string;
  scale?: number;
}

export interface SettingsData {
  current_agent: string;
  current_shell: string;
  latest_version: string;
  update_available: boolean;
  last_message: string;
  last_error?: string;
  auto_updates: boolean;
  checked_at: string;
  hostname: string;
  wifi_ssid: string;
  battery_percent: number | null;
  display_auto: boolean;
  display_output?: string;
  display_mode?: string;
  display_scale: number;
  display_outputs: DisplayOutput[];
  display_current: DisplayCurrent;
}

export type SettingsPatch = Partial<{
  auto_updates: boolean;
  display_auto: boolean;
  display_output: string;
  display_mode: string;
  display_scale: number;
}>;

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

export async function fetchSettings(): Promise<SettingsData> {
  const res = await fetch("/api/settings");
  if (!res.ok) throw new Error("settings fetch failed");
  return res.json();
}

export async function saveSettings(patch: SettingsPatch): Promise<void> {
  await fetch("/api/settings", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
}

export async function triggerUpdateCheck(): Promise<void> {
  await fetch("/api/settings/check-updates", { method: "POST" });
}
