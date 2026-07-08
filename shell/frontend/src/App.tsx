import { useEffect, useMemo, useState } from "react";
import {
  Battery,
  BatteryCharging,
  Grid3x3,
  Search,
  Settings,
  Wifi,
  WifiOff,
} from "lucide-react";
import { fetchConfig, launchApp, ShellApp, ShellConfig } from "./api";
import { SettingsPanel } from "./Settings";

const defaultConfig: ShellConfig = {
  wallpaper: "",
  apps: [],
  pinned: [],
  running: [],
  clock: "",
  wifi_ssid: "",
  battery_percent: null,
  locked: false,
};

function AppIcon({ app, size = "md" }: { app: ShellApp; size?: "sm" | "md" | "lg" }) {
  const dim = size === "lg" ? "h-16 w-16" : size === "sm" ? "h-8 w-8" : "h-10 w-10";
  const text = size === "lg" ? "text-2xl" : size === "sm" ? "text-sm" : "text-lg";
  const colors: Record<string, string> = {
    chromium: "bg-sky-500",
    files: "bg-amber-500",
    android: "bg-emerald-500",
    web: "bg-sky-500",
    native: "bg-violet-500",
  };
  const bg = colors[app.id] ?? colors[app.type] ?? "bg-chrome-surface";
  return (
    <div
      className={`${dim} ${bg} rounded-2xl flex items-center justify-center shadow-lg ring-1 ring-white/10`}
    >
      <span className={`${text} font-medium text-white`}>{app.name.charAt(0)}</span>
    </div>
  );
}

export default function App() {
  const [config, setConfig] = useState<ShellConfig>(defaultConfig);
  const [launcherOpen, setLauncherOpen] = useState(false);
  const [quickSettingsOpen, setQuickSettingsOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [query, setQuery] = useState("");

  useEffect(() => {
    const load = async () => {
      try {
        setConfig(await fetchConfig());
      } catch {
        /* retry next tick */
      }
    };
    load();
    const id = setInterval(load, 5000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    const tick = () => {
      const now = new Date();
      const clock = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      setConfig((c) => ({ ...c, clock }));
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);

  const apps = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return config.apps;
    return config.apps.filter((a) => a.name.toLowerCase().includes(q));
  }, [config.apps, query]);

  const shelfApps = useMemo(() => {
    const ids = new Set([...config.pinned, ...config.running]);
    return config.apps.filter((a) => ids.has(a.id));
  }, [config.apps, config.pinned, config.running]);

  const onLaunch = async (app: ShellApp) => {
    await launchApp(app.id);
    setLauncherOpen(false);
    setConfig((c) => ({
      ...c,
      running: Array.from(new Set([...c.running, app.id])),
    }));
  };

  return (
    <div className="h-screen w-screen relative overflow-hidden">
      <div
        className="wallpaper absolute inset-0"
        style={{
          backgroundImage: config.wallpaper
            ? `url(${config.wallpaper})`
            : "linear-gradient(135deg, #1a73e8 0%, #174ea6 50%, #0d274f 100%)",
        }}
      />

      {launcherOpen && (
        <div className="absolute inset-0 z-30 bg-black/55 backdrop-blur-xl flex flex-col">
          <div className="px-8 pt-8 pb-4 flex items-center gap-3 max-w-3xl mx-auto w-full">
            <Search className="text-chrome-muted" size={20} />
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search apps"
              className="flex-1 bg-transparent text-2xl outline-none placeholder:text-chrome-muted"
            />
          </div>
          <div className="launcher-grid flex-1 overflow-y-auto px-8 pb-32">
            <div className="grid grid-cols-4 sm:grid-cols-6 gap-8 max-w-5xl mx-auto">
              {apps.map((app) => (
                <button
                  key={app.id}
                  onClick={() => onLaunch(app)}
                  className="flex flex-col items-center gap-3 hover:scale-105 transition-transform"
                >
                  <AppIcon app={app} size="lg" />
                  <span className="text-sm text-chrome-text">{app.name}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {settingsOpen && <SettingsPanel onClose={() => setSettingsOpen(false)} />}

      {quickSettingsOpen && (
        <div className="absolute bottom-14 right-3 z-40 w-80 rounded-2xl bg-chrome-surface/95 backdrop-blur border border-white/10 shadow-2xl p-4">
          <h3 className="text-sm font-medium mb-3">Quick settings</h3>
          <div className="grid grid-cols-2 gap-2 text-sm">
            <button className="rounded-xl bg-white/5 px-3 py-3 text-left hover:bg-white/10">
              Wi‑Fi: {config.wifi_ssid || "Not connected"}
            </button>
            <button className="rounded-xl bg-white/5 px-3 py-3 text-left hover:bg-white/10">
              Battery: {config.battery_percent ?? "—"}%
            </button>
            <button className="rounded-xl bg-white/5 px-3 py-3 text-left hover:bg-white/10">
              Bluetooth
            </button>
            <button
              className="rounded-xl bg-white/5 px-3 py-3 text-left hover:bg-white/10 col-span-2"
              onClick={() => {
                setQuickSettingsOpen(false);
                setSettingsOpen(true);
              }}
            >
              Open Settings →
            </button>
          </div>
        </div>
      )}

      <div className="absolute bottom-0 inset-x-0 z-50 h-12 bg-chrome-shelf/95 backdrop-blur border-t border-white/10 shadow-shelf flex items-center px-2">
        <button
          onClick={() => setLauncherOpen((v) => !v)}
          className={`h-10 w-10 ml-1 rounded-full flex items-center justify-center hover:bg-white/10 ${
            launcherOpen ? "bg-white/15" : ""
          }`}
          title="Launcher"
        >
          <Grid3x3 size={20} />
        </button>

        <div className="flex items-center gap-1 ml-2">
          {shelfApps.map((app) => (
            <button
              key={app.id}
              onClick={() => onLaunch(app)}
              className={`h-10 w-10 rounded-xl flex items-center justify-center hover:bg-white/10 ${
                config.running.includes(app.id) ? "bg-white/10" : ""
              }`}
              title={app.name}
            >
              <AppIcon app={app} size="sm" />
            </button>
          ))}
        </div>

        <div className="ml-auto flex items-center gap-1 pr-2">
          <button
            onClick={() => setQuickSettingsOpen((v) => !v)}
            className="h-10 px-2 rounded-xl hover:bg-white/10 flex items-center gap-2 text-sm"
          >
            {config.wifi_ssid ? <Wifi size={16} /> : <WifiOff size={16} />}
            {config.battery_percent != null && (
              <>
                {config.battery_percent < 100 ? (
                  <Battery size={16} />
                ) : (
                  <BatteryCharging size={16} />
                )}
                <span>{config.battery_percent}%</span>
              </>
            )}
            <span className="tabular-nums min-w-[4.5rem] text-right">{config.clock}</span>
          </button>
          <button
            onClick={() => setSettingsOpen(true)}
            className="h-10 w-10 rounded-full hover:bg-white/10 flex items-center justify-center"
            title="Settings"
          >
            <Settings size={18} />
          </button>
        </div>
      </div>
    </div>
  );
}
