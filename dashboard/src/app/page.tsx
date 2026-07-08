"use client";

import { useEffect, useState } from "react";
import {
  Cpu,
  KeyRound,
  Laptop,
  Lock,
  LogOut,
  Power,
  RefreshCw,
  Shield,
  Trash2,
  Unlock,
} from "lucide-react";
import { api, Device, Policy } from "@/lib/api";

export default function HomePage() {
  const [token, setToken] = useState<string | null>(null);
  const [username, setUsername] = useState("admin");
  const [password, setPassword] = useState("");
  const [devices, setDevices] = useState<Device[]>([]);
  const [policyText, setPolicyText] = useState("");
  const [enrollToken, setEnrollToken] = useState<string | null>(null);
  const [selected, setSelected] = useState<Device | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const saved = localStorage.getItem("pallet_admin_token");
    if (saved) setToken(saved);
  }, []);

  useEffect(() => {
    if (!token) return;
    refresh(token);
    const id = setInterval(() => refresh(token), 15000);
    return () => clearInterval(id);
  }, [token]);

  async function refresh(auth = token) {
    if (!auth) return;
    try {
      const [{ devices }, { policy }] = await Promise.all([
        api<{ devices: Device[] }>("/api/v1/admin/devices", {}, auth),
        api<{ policy: Policy }>("/api/v1/admin/policy", {}, auth),
      ]);
      setDevices(devices);
      setPolicyText(JSON.stringify(policy, null, 2));
      setError("");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load");
    }
  }

  async function login(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      const { token: t } = await api<{ token: string }>("/api/v1/admin/login", {
        method: "POST",
        body: JSON.stringify({ username, password }),
      });
      localStorage.setItem("pallet_admin_token", t);
      setToken(t);
    } catch (e) {
      setError("Invalid credentials");
    } finally {
      setLoading(false);
    }
  }

  async function savePolicy() {
    if (!token) return;
    const policy = JSON.parse(policyText);
    await api("/api/v1/admin/policy", { method: "PUT", body: JSON.stringify({ policy }) }, token);
    await refresh(token);
  }

  async function createEnrollToken() {
    if (!token) return;
    const out = await api<{ token: string }>(
      "/api/v1/admin/enrollment-tokens",
      { method: "POST", body: JSON.stringify({ label: "dashboard" }) },
      token
    );
    setEnrollToken(out.token);
  }

  async function sendCommand(type: string, deviceId?: string) {
    if (!token) return;
    if (type === "wipe" && !confirm("Wipe device user data?")) return;
    if (deviceId) {
      await api(
        `/api/v1/admin/devices/${deviceId}/commands`,
        { method: "POST", body: JSON.stringify({ type }) },
        token
      );
    } else {
      await api(
        "/api/v1/admin/commands/fleet",
        { method: "POST", body: JSON.stringify({ type }) },
        token
      );
    }
    await refresh(token);
  }

  if (!token) {
    return (
      <main className="min-h-screen flex items-center justify-center p-6">
        <form onSubmit={login} className="card w-full max-w-md p-8 space-y-4">
          <div className="flex items-center gap-3 mb-2">
            <div className="h-12 w-12 rounded-2xl bg-[color:var(--accent)] flex items-center justify-center">
              <Shield size={24} />
            </div>
            <div>
              <h1 className="text-2xl font-semibold">Pallet OS</h1>
              <p className="text-sm text-[color:var(--muted)]">Fleet control plane</p>
            </div>
          </div>
          <input className="input" placeholder="Username" value={username} onChange={(e) => setUsername(e.target.value)} />
          <input className="input" type="password" placeholder="Password" value={password} onChange={(e) => setPassword(e.target.value)} />
          {error && <p className="text-rose-400 text-sm">{error}</p>}
          <button className="btn-primary w-full" disabled={loading}>{loading ? "Signing in..." : "Sign in"}</button>
        </form>
      </main>
    );
  }

  const online = devices.filter((d) => d.online).length;

  return (
    <main className="min-h-screen p-6 max-w-7xl mx-auto space-y-6">
      <header className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-semibold tracking-tight">Pallet OS Console</h1>
          <p className="text-[color:var(--muted)]">Self-hosted managed Chromebook fleet</p>
        </div>
        <div className="flex items-center gap-2">
          <button className="btn-ghost" onClick={() => refresh(token!)}><RefreshCw size={16} className="inline mr-2" />Refresh</button>
          <button
            className="btn-ghost"
            onClick={() => {
              localStorage.removeItem("pallet_admin_token");
              setToken(null);
            }}
          >
            <LogOut size={16} className="inline mr-2" />Logout
          </button>
        </div>
      </header>

      <section className="grid md:grid-cols-3 gap-4">
        <StatCard icon={<Laptop />} label="Devices" value={String(devices.length)} />
        <StatCard icon={<Cpu />} label="Online" value={String(online)} />
        <StatCard icon={<Shield />} label="Locked" value={String(devices.filter((d) => d.locked).length)} />
      </section>

      {error && <div className="card p-4 text-rose-300">{error}</div>}

      <section className="grid lg:grid-cols-2 gap-6">
        <div className="card p-5 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-medium">Devices</h2>
            <button className="btn-ghost text-sm" onClick={createEnrollToken}>
              <KeyRound size={14} className="inline mr-1" />New enroll token
            </button>
          </div>
          {enrollToken && (
            <div className="rounded-xl bg-black/30 p-3 text-sm break-all">
              Enrollment token: <code className="text-[color:var(--accent)]">{enrollToken}</code>
            </div>
          )}
          <div className="space-y-2 max-h-[28rem] overflow-auto">
            {devices.map((d) => (
              <button
                key={d.id}
                onClick={() => setSelected(d)}
                className={`w-full text-left rounded-xl border px-4 py-3 transition ${
                  selected?.id === d.id ? "border-[color:var(--accent)] bg-white/5" : "border-[color:var(--border)] hover:bg-white/5"
                }`}
              >
                <div className="flex items-center justify-between gap-2">
                  <div>
                    <div className="font-medium">{d.hostname || d.id.slice(0, 8)}</div>
                    <div className="text-xs text-[color:var(--muted)]">{d.last_ip || "no IP"} · {d.os_version || "unknown OS"}</div>
                  </div>
                  <span className={`text-xs px-2 py-1 rounded-full ${d.online ? "bg-emerald-500/20 text-emerald-300" : "bg-white/10 text-[color:var(--muted)]"}`}>
                    {d.online ? "online" : "offline"}
                  </span>
                </div>
              </button>
            ))}
            {devices.length === 0 && <p className="text-[color:var(--muted)] text-sm">No enrolled devices yet.</p>}
          </div>
        </div>

        <div className="card p-5 space-y-4">
          <h2 className="text-lg font-medium">Device actions</h2>
          {!selected ? (
            <p className="text-[color:var(--muted)] text-sm">Select a device to send commands.</p>
          ) : (
            <>
              <div className="text-sm text-[color:var(--muted)]">
                Target: <span className="text-white">{selected.hostname}</span> · uptime {Math.floor(selected.uptime_seconds / 60)}m
              </div>
              <div className="flex flex-wrap gap-2">
                <ActionButton icon={<Lock size={14} />} label="Lock" onClick={() => sendCommand("lock", selected.id)} />
                <ActionButton icon={<Unlock size={14} />} label="Unlock" onClick={() => sendCommand("unlock", selected.id)} />
                <ActionButton icon={<Power size={14} />} label="Reboot" onClick={() => sendCommand("reboot", selected.id)} />
                <ActionButton icon={<RefreshCw size={14} />} label="Restart shell" onClick={() => sendCommand("restart_shell", selected.id)} />
                <ActionButton icon={<Trash2 size={14} />} label="Wipe" danger onClick={() => sendCommand("wipe", selected.id)} />
              </div>
            </>
          )}
          <h3 className="text-sm font-medium pt-2">Fleet-wide</h3>
          <div className="flex flex-wrap gap-2">
            <ActionButton icon={<RefreshCw size={14} />} label="Apply policy to all" onClick={() => sendCommand("apply_policy")} />
          </div>
        </div>
      </section>

      <section className="card p-5 space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-medium">Global policy (Chromium + shell + Android)</h2>
          <button className="btn-primary" onClick={savePolicy}>Save & push</button>
        </div>
        <textarea
          className="input font-mono text-xs min-h-[320px]"
          value={policyText}
          onChange={(e) => setPolicyText(e.target.value)}
        />
      </section>
    </main>
  );
}

function StatCard({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="card p-5 flex items-center gap-4">
      <div className="h-11 w-11 rounded-xl bg-white/5 flex items-center justify-center text-[color:var(--accent)]">{icon}</div>
      <div>
        <div className="text-sm text-[color:var(--muted)]">{label}</div>
        <div className="text-2xl font-semibold">{value}</div>
      </div>
    </div>
  );
}

function ActionButton({
  icon,
  label,
  onClick,
  danger,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
  danger?: boolean;
}) {
  return (
    <button className={danger ? "btn-danger text-sm" : "btn-ghost text-sm"} onClick={onClick}>
      <span className="inline-flex items-center gap-1">{icon}{label}</span>
    </button>
  );
}
