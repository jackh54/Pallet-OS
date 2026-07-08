"use client";

import { useState } from "react";
import { Check, Copy, KeyRound, Laptop, Terminal } from "lucide-react";
import { api } from "@/lib/api";
import { buildEnrollOnlyCommand, buildSetupCommand, copyText } from "@/lib/enroll";

interface EnrollPanelProps {
  authToken: string;
}

export function EnrollPanel({ authToken }: EnrollPanelProps) {
  const [label, setLabel] = useState("");
  const [enrollToken, setEnrollToken] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState<"token" | "setup" | "enroll" | null>(null);
  const [error, setError] = useState("");

  const setupCommand = enrollToken ? buildSetupCommand(enrollToken) : "";
  const enrollOnlyCommand = enrollToken ? buildEnrollOnlyCommand(enrollToken) : "";

  async function generateKey() {
    setLoading(true);
    setError("");
    setCopied(null);
    try {
      const out = await api<{ token: string }>(
        "/api/v1/admin/enrollment-tokens",
        {
          method: "POST",
          body: JSON.stringify({ label: label.trim() || "chromebook" }),
        },
        authToken
      );
      setEnrollToken(out.token);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to generate key");
    } finally {
      setLoading(false);
    }
  }

  async function handleCopy(kind: "token" | "setup" | "enroll", text: string) {
    const ok = await copyText(text);
    if (ok) {
      setCopied(kind);
      setTimeout(() => setCopied(null), 2000);
    }
  }

  return (
    <section className="card p-5 space-y-5">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <Laptop size={20} className="text-[color:var(--accent)]" />
            <h2 className="text-lg font-medium">Enroll a laptop</h2>
          </div>
          <p className="text-sm text-[color:var(--muted)] max-w-xl">
            Generate a one-time enrollment key, then paste the setup command on the Chromebook
            after Ubuntu is installed.
          </p>
        </div>
      </div>

      <div className="flex flex-wrap gap-3 items-end">
        <div className="flex-1 min-w-[200px]">
          <label className="text-xs text-[color:var(--muted)] block mb-1.5">
            Device label (optional)
          </label>
          <input
            className="input"
            placeholder="e.g. lab-chromebook-3"
            value={label}
            onChange={(e) => setLabel(e.target.value)}
          />
        </div>
        <button
          className="btn-primary flex items-center gap-2"
          onClick={generateKey}
          disabled={loading}
        >
          <KeyRound size={16} />
          {loading ? "Generating…" : "Generate enrollment key"}
        </button>
      </div>

      {error && <p className="text-rose-400 text-sm">{error}</p>}

      {enrollToken && (
        <div className="space-y-4">
          <div className="rounded-xl border border-[color:var(--accent)]/40 bg-[color:var(--accent)]/10 p-4">
            <div className="text-xs uppercase tracking-wide text-[color:var(--muted)] mb-2">
              Enrollment key · one-time use
            </div>
            <div className="flex items-center gap-3 flex-wrap">
              <code className="text-lg font-mono text-[color:var(--accent)] break-all flex-1">
                {enrollToken}
              </code>
              <CopyButton
                label="Copy key"
                copied={copied === "token"}
                onClick={() => handleCopy("token", enrollToken)}
              />
            </div>
          </div>

          <div className="rounded-xl border border-[color:var(--border)] bg-black/25 overflow-hidden">
            <div className="flex items-center justify-between px-4 py-3 border-b border-[color:var(--border)] bg-white/5">
              <div className="flex items-center gap-2 text-sm font-medium">
                <Terminal size={16} />
                Full setup command
              </div>
              <CopyButton
                label="Copy command"
                copied={copied === "setup"}
                onClick={() => handleCopy("setup", setupCommand)}
              />
            </div>
            <pre className="p-4 text-xs font-mono leading-relaxed overflow-x-auto text-emerald-200/90 whitespace-pre-wrap">
              {setupCommand}
            </pre>
            <div className="px-4 pb-4 text-xs text-[color:var(--muted)]">
              Run in Terminal on the Chromebook after Ubuntu Desktop is installed to internal disk.
            </div>
          </div>

          <details className="rounded-xl border border-[color:var(--border)] bg-black/15">
            <summary className="px-4 py-3 cursor-pointer text-sm text-[color:var(--muted)] hover:text-white">
              Already ran install? Enroll-only command
            </summary>
            <div className="border-t border-[color:var(--border)]">
              <div className="flex justify-end px-4 pt-3">
                <CopyButton
                  label="Copy"
                  copied={copied === "enroll"}
                  onClick={() => handleCopy("enroll", enrollOnlyCommand)}
                />
              </div>
              <pre className="px-4 pb-4 text-xs font-mono leading-relaxed overflow-x-auto text-emerald-200/90 whitespace-pre-wrap">
                {enrollOnlyCommand}
              </pre>
            </div>
          </details>

          <ol className="text-sm text-[color:var(--muted)] space-y-1 list-decimal list-inside">
            <li>Install Ubuntu 24.04 Desktop to internal disk → reboot</li>
            <li>Open Terminal → paste the full setup command above</li>
            <li>Wait for provision to finish → reboot when prompted</li>
            <li>Device appears online in the dashboard</li>
          </ol>
        </div>
      )}
    </section>
  );
}

function CopyButton({
  label,
  copied,
  onClick,
}: {
  label: string;
  copied: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="btn-ghost text-xs flex items-center gap-1.5 shrink-0"
    >
      {copied ? <Check size={14} className="text-emerald-400" /> : <Copy size={14} />}
      {copied ? "Copied!" : label}
    </button>
  );
}
