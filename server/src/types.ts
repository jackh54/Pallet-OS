export interface Env {
  DB: D1Database;
  ADMIN_USERNAME: string;
  ADMIN_PASSWORD: string;
  JWT_SECRET: string;
  JWT_ISSUER?: string;
}

export interface ChromiumPolicy {
  HomepageLocation?: string;
  RestoreOnStartup?: number;
  RestoreOnStartupURLs?: string[];
  URLBlocklist?: string[];
  URLAllowlist?: string[];
  DeveloperToolsAvailability?: number;
  ExtensionInstallForcelist?: string[];
  ExtensionInstallBlocklist?: string[];
  IncognitoModeAvailability?: number;
  BookmarkBarEnabled?: boolean;
  DefaultSearchProviderEnabled?: boolean;
  [key: string]: unknown;
}

export interface PalletPolicy {
  version: number;
  wallpaper_url?: string;
  shelf_pinned_apps?: string[];
  chromium?: ChromiumPolicy;
  android?: {
    force_install?: string[];
    allowlist?: string[];
    blocklist?: string[];
  };
  shell?: {
    show_file_manager?: boolean;
    show_terminal?: boolean;
    launcher_apps?: LauncherApp[];
  };
}

export interface LauncherApp {
  id: string;
  name: string;
  icon?: string;
  exec: string;
  type: "web" | "native" | "android";
  pinned?: boolean;
}

export interface DeviceTelemetry {
  hostname: string;
  uptime_seconds: number;
  ip_addresses: string[];
  agent_version: string;
  os_version: string;
  installed_apps: InstalledApp[];
  battery_percent?: number;
  wifi_ssid?: string;
  locked?: boolean;
}

export interface InstalledApp {
  id: string;
  name: string;
  version?: string;
  type: "web" | "native" | "android";
  package?: string;
}

export type CommandType =
  | "lock"
  | "unlock"
  | "reboot"
  | "wipe"
  | "logout"
  | "restart_shell"
  | "install_app"
  | "remove_app"
  | "apply_policy";

export interface CommandPayload {
  app_id?: string;
  package?: string;
  apk_url?: string;
  policy?: PalletPolicy;
  [key: string]: unknown;
}

export const DEFAULT_POLICY: PalletPolicy = {
  version: 1,
  wallpaper_url: "https://storage.googleapis.com/chromeos-wallpaper/wallpaper.jpg",
  shelf_pinned_apps: ["chromium", "launcher"],
  chromium: {
    HomepageLocation: "https://www.google.com",
    RestoreOnStartup: 1,
    DeveloperToolsAvailability: 2,
    IncognitoModeAvailability: 1,
    BookmarkBarEnabled: true,
  },
  android: {
    force_install: [],
    allowlist: [],
  },
  shell: {
    show_file_manager: false,
    show_terminal: false,
    launcher_apps: [
      {
        id: "chromium",
        name: "Browser",
        exec: "chromium --new-window",
        type: "web",
        pinned: true,
      },
      {
        id: "files",
        name: "Files",
        exec: "nautilus",
        type: "native",
        pinned: false,
      },
    ],
  },
};
