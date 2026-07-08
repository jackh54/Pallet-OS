import { SignJWT, jwtVerify } from "jose";

const encoder = new TextEncoder();

export async function hashSecret(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export function randomId(): string {
  return crypto.randomUUID();
}

export function randomToken(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function secretKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"]
  );
}

export async function signAdminJwt(
  username: string,
  secret: string,
  issuer: string,
  ttlSeconds = 86400
): Promise<string> {
  const key = await secretKey(secret);
  return new SignJWT({ role: "admin", sub: username })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer(issuer)
    .setIssuedAt()
    .setExpirationTime(`${ttlSeconds}s`)
    .sign(key);
}

export async function verifyAdminJwt(
  token: string,
  secret: string,
  issuer: string
): Promise<{ sub: string } | null> {
  try {
    const key = await secretKey(secret);
    const { payload } = await jwtVerify(token, key, { issuer });
    if (payload.role !== "admin" || typeof payload.sub !== "string") return null;
    return { sub: payload.sub };
  } catch {
    return null;
  }
}

export async function signDeviceJwt(
  deviceId: string,
  secret: string,
  issuer: string
): Promise<string> {
  const key = await secretKey(secret);
  return new SignJWT({ role: "device", sub: deviceId })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuer(issuer)
    .setIssuedAt()
    .setExpirationTime("30d")
    .sign(key);
}

export async function verifyDeviceJwt(
  token: string,
  secret: string,
  issuer: string
): Promise<{ sub: string } | null> {
  try {
    const key = await secretKey(secret);
    const { payload } = await jwtVerify(token, key, { issuer });
    if (payload.role !== "device" || typeof payload.sub !== "string") return null;
    return { sub: payload.sub };
  } catch {
    return null;
  }
}

export function parseJson<T>(raw: string | null | undefined, fallback: T): T {
  if (!raw) return fallback;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

import type { PalletPolicy } from "./types";

export function mergePolicy(
  globalPolicy: PalletPolicy,
  override?: Partial<PalletPolicy> | null
): PalletPolicy {
  if (!override) return globalPolicy;
  return deepMerge(
    globalPolicy as unknown as Record<string, unknown>,
    override as unknown as Record<string, unknown>
  ) as unknown as PalletPolicy;
}

function deepMerge(
  base: Record<string, unknown>,
  patch: Record<string, unknown>
): Record<string, unknown> {
  const out: Record<string, unknown> = { ...base };
  for (const [key, value] of Object.entries(patch)) {
    if (
      value &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      typeof out[key] === "object" &&
      out[key] !== null &&
      !Array.isArray(out[key])
    ) {
      out[key] = deepMerge(
        out[key] as Record<string, unknown>,
        value as Record<string, unknown>
      );
    } else {
      out[key] = value;
    }
  }
  return out;
}

export function isOnline(lastSeenAt: string | null, windowSeconds = 120): boolean {
  if (!lastSeenAt) return false;
  const last = Date.parse(lastSeenAt + "Z");
  if (Number.isNaN(last)) {
    const alt = Date.parse(lastSeenAt);
    if (Number.isNaN(alt)) return false;
    return Date.now() - alt < windowSeconds * 1000;
  }
  return Date.now() - last < windowSeconds * 1000;
}
