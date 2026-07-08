import { useEffect, useState, type ReactNode } from "react";
import {
  ArrowLeft,
  Download,
  Info,
  Monitor,
  RefreshCw,
  Settings as SettingsIcon,
  Tv,
} from "lucide-react";
import {
  fetchSettings,
  saveSettings,
  triggerUpdateCheck,
  SettingsData,
} from "./api";

type Section = "about" | "updates" | "device" | "display";

export function SettingsPanel({ onClose }: { onClose: () => void }) {
  const [section, setSection] = useState<Section>("display");
  const [data, setData] = useState<SettingsData | null>(null);
  const [saving, setSaving] = useState(false);
  const [checking, setChecking] = useState(false);
  const [displayOutput, setDisplayOutput] = useState("");
  const [displayMode, setDisplayMode] = useState("");
  const [displayScale, setDisplayScale] = useState(1);
  const [displayAuto, setDisplayAuto] = useState(true);

  const load = async () => {
    try {
      const s = await fetchSettings();
      setData(s);
      setDisplayAuto(s.display_auto ?? true);
      setDisplayOutput(s.display_output || s.display_current?.output || "");
      setDisplayMode(s.display_mode || s.display_current?.mode || "");
      setDisplayScale(s.display_scale || 1);
    } catch {
      /* retry */
    }
  };

  useEffect(() => {
    load();
    const id = setInterval(load, 8000);
    return () => clearInterval(id);
  }, []);

  const onToggleAuto = async () => {
    if (!data) return;
    setSaving(true);
    try {
      await saveSettings({ auto_updates: !data.auto_updates });
      await load();
    } finally {
      setSaving(false);
    }
  };

  const onCheckNow = async () => {
    setChecking(true);
    try {
      await triggerUpdateCheck();
      setTimeout(load, 2000);
    } finally {
      setChecking(false);
    }
  };

  const connectedOutputs = data?.display_outputs?.filter((o) => o.connected) ?? [];
  const selectedOutput =
    connectedOutputs.find((o) => o.name === displayOutput) ?? connectedOutputs[0];
  const availableModes = selectedOutput?.modes ?? [];

  const onApplyDisplay = async () => {
    setSaving(true);
    try {
      await saveSettings({
        display_auto: displayAuto,
        display_output: displayOutput,
        display_mode: displayMode,
        display_scale: displayScale,
      });
      await load();
    } finally {
      setSaving(false);
    }
  };

  const nav: { id: Section; label: string; icon: ReactNode }[] = [
    { id: "display", label: "Display", icon: <Tv size={18} /> },
    { id: "updates", label: "Software updates", icon: <Download size={18} /> },
    { id: "about", label: "About Pallet OS", icon: <Info size={18} /> },
    { id: "device", label: "Device", icon: <Monitor size={18} /> },
  ];

  return (
    <div className="absolute inset-0 z-40 bg-black/60 backdrop-blur-md flex">
      <div className="m-auto w-[min(920px,95vw)] h-[min(620px,90vh)] rounded-3xl bg-chrome-surface border border-white/10 shadow-2xl flex overflow-hidden">
        <aside className="w-56 bg-black/20 border-r border-white/10 p-4 flex flex-col gap-1">
          <div className="flex items-center gap-2 px-2 py-3 mb-2">
            <SettingsIcon size={20} className="text-chrome-accent" />
            <span className="font-medium">Settings</span>
          </div>
          {nav.map((item) => (
            <button
              key={item.id}
              onClick={() => setSection(item.id)}
              className={`flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm text-left transition ${
                section === item.id ? "bg-white/15 text-white" : "hover:bg-white/8 text-chrome-muted"
              }`}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
          <button
            onClick={onClose}
            className="mt-auto flex items-center gap-2 rounded-xl px-3 py-2.5 text-sm hover:bg-white/8 text-chrome-muted"
          >
            <ArrowLeft size={18} />
            Close
          </button>
        </aside>

        <main className="flex-1 p-8 overflow-y-auto">
          {!data ? (
            <p className="text-chrome-muted">Loading settings…</p>
          ) : section === "display" ? (
            <div className="space-y-6 max-w-lg">
              <div>
                <h2 className="text-2xl font-medium mb-1">Display</h2>
                <p className="text-chrome-muted text-sm">
                  Configure panel resolution and scaling. Use manual mode if auto-detect fails.
                </p>
              </div>

              <div className="rounded-2xl bg-white/5 border border-white/10 p-5 space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-medium">Automatic detection</div>
                    <div className="text-sm text-chrome-muted">Use native panel resolution from hardware</div>
                  </div>
                  <button
                    onClick={() => setDisplayAuto(!displayAuto)}
                    className={`w-12 h-7 rounded-full transition relative ${
                      displayAuto ? "bg-chrome-accent" : "bg-white/20"
                    }`}
                  >
                    <span
                      className={`absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition ${
                        displayAuto ? "left-5" : "left-0.5"
                      }`}
                    />
                  </button>
                </div>

                {!displayAuto && (
                  <>
                    <div className="space-y-2">
                      <label className="text-sm text-chrome-muted">Output</label>
                      <select
                        value={displayOutput}
                        onChange={(e) => {
                          setDisplayOutput(e.target.value);
                          const out = connectedOutputs.find((o) => o.name === e.target.value);
                          if (out?.modes?.[0]) setDisplayMode(out.modes[0]);
                        }}
                        className="w-full rounded-xl bg-black/30 border border-white/10 px-3 py-2.5 text-sm"
                      >
                        {connectedOutputs.length === 0 && (
                          <option value="">No outputs detected</option>
                        )}
                        {connectedOutputs.map((o) => (
                          <option key={o.name} value={o.name}>
                            {o.name}
                            {o.current_mode ? ` (${o.current_mode})` : ""}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="space-y-2">
                      <label className="text-sm text-chrome-muted">Resolution</label>
                      <select
                        value={displayMode}
                        onChange={(e) => setDisplayMode(e.target.value)}
                        className="w-full rounded-xl bg-black/30 border border-white/10 px-3 py-2.5 text-sm"
                      >
                        {availableModes.length === 0 && (
                          <option value={displayMode}>{displayMode || "—"}</option>
                        )}
                        {availableModes.map((m) => (
                          <option key={m} value={m}>
                            {m}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="space-y-2">
                      <label className="text-sm text-chrome-muted">Scale ({displayScale.toFixed(2)}×)</label>
                      <input
                        type="range"
                        min={0.75}
                        max={2}
                        step={0.05}
                        value={displayScale}
                        onChange={(e) => setDisplayScale(parseFloat(e.target.value))}
                        className="w-full"
                      />
                      <div className="flex gap-2 text-xs text-chrome-muted">
                        {[0.75, 1, 1.25, 1.5, 2].map((s) => (
                          <button
                            key={s}
                            onClick={() => setDisplayScale(s)}
                            className="rounded-lg px-2 py-1 bg-white/10 hover:bg-white/15"
                          >
                            {s}×
                          </button>
                        ))}
                      </div>
                    </div>
                  </>
                )}

                <div className="text-sm space-y-2 pt-2 border-t border-white/10">
                  <div className="flex justify-between">
                    <span className="text-chrome-muted">Current</span>
                    <span>
                      {data.display_current?.output || "—"}{" "}
                      {data.display_current?.mode || ""}
                    </span>
                  </div>
                </div>

                <button
                  onClick={onApplyDisplay}
                  disabled={saving}
                  className="flex items-center gap-2 rounded-xl bg-chrome-accent text-black px-4 py-2.5 font-medium hover:opacity-90 disabled:opacity-50"
                >
                  <RefreshCw size={16} className={saving ? "animate-spin" : ""} />
                  {saving ? "Applying…" : "Apply display settings"}
                </button>
              </div>
            </div>
          ) : section === "updates" ? (
            <div className="space-y-6 max-w-lg">
              <div>
                <h2 className="text-2xl font-medium mb-1">Software updates</h2>
                <p className="text-chrome-muted text-sm">
                  Pallet OS checks GitHub Releases for new agent and shell builds.
                </p>
              </div>

              <div className="rounded-2xl bg-white/5 border border-white/10 p-5 space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-medium">Automatic updates</div>
                    <div className="text-sm text-chrome-muted">Download and install from GitHub</div>
                  </div>
                  <button
                    onClick={onToggleAuto}
                    disabled={saving}
                    className={`w-12 h-7 rounded-full transition relative ${
                      data.auto_updates ? "bg-chrome-accent" : "bg-white/20"
                    }`}
                  >
                    <span
                      className={`absolute top-0.5 h-6 w-6 rounded-full bg-white shadow transition ${
                        data.auto_updates ? "left-5" : "left-0.5"
                      }`}
                    />
                  </button>
                </div>

                <div className="text-sm space-y-2 pt-2 border-t border-white/10">
                  <div className="flex justify-between">
                    <span className="text-chrome-muted">Status</span>
                    <span>{data.last_message || "—"}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-chrome-muted">Installed</span>
                    <span>
                      agent {data.current_agent} · shell {data.current_shell}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-chrome-muted">Latest</span>
                    <span>{data.latest_version ? `v${data.latest_version}` : "—"}</span>
                  </div>
                  {data.update_available && (
                    <div className="text-emerald-300 font-medium">Update available</div>
                  )}
                  {data.last_error && (
                    <div className="text-rose-300 text-xs">{data.last_error}</div>
                  )}
                </div>

                <button
                  onClick={onCheckNow}
                  disabled={checking}
                  className="flex items-center gap-2 rounded-xl bg-chrome-accent text-black px-4 py-2.5 font-medium hover:opacity-90 disabled:opacity-50"
                >
                  <RefreshCw size={16} className={checking ? "animate-spin" : ""} />
                  {checking ? "Checking…" : "Check for updates"}
                </button>
              </div>
            </div>
          ) : section === "about" ? (
            <div className="space-y-4 max-w-lg">
              <h2 className="text-2xl font-medium">About Pallet OS</h2>
              <p className="text-chrome-muted">
                Self-hosted ChromeOS-style managed desktop. Policy and commands from your
                Pallet control server; software updates from GitHub Releases.
              </p>
              <div className="rounded-2xl bg-white/5 border border-white/10 p-5 text-sm space-y-2">
                <div className="flex justify-between">
                  <span className="text-chrome-muted">Pallet agent</span>
                  <span>{data.current_agent}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-chrome-muted">Pallet shell</span>
                  <span>{data.current_shell}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-chrome-muted">Hostname</span>
                  <span>{data.hostname}</span>
                </div>
              </div>
            </div>
          ) : (
            <div className="space-y-4 max-w-lg">
              <h2 className="text-2xl font-medium">Device</h2>
              <div className="rounded-2xl bg-white/5 border border-white/10 p-5 text-sm space-y-2">
                <div className="flex justify-between">
                  <span className="text-chrome-muted">Hostname</span>
                  <span>{data.hostname}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-chrome-muted">Wi‑Fi</span>
                  <span>{data.wifi_ssid || "Not connected"}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-chrome-muted">Battery</span>
                  <span>{data.battery_percent != null ? `${data.battery_percent}%` : "—"}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-chrome-muted">Last update check</span>
                  <span>{data.checked_at ? new Date(data.checked_at).toLocaleString() : "—"}</span>
                </div>
              </div>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
