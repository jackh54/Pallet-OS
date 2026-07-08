import { describe, expect, it } from "vitest";
import { hashSecret, mergePolicy, isOnline } from "./crypto";

describe("crypto", () => {
  it("hashes secrets deterministically", async () => {
    const a = await hashSecret("test-key");
    const b = await hashSecret("test-key");
    expect(a).toBe(b);
    expect(a).toHaveLength(64);
  });

  it("merges nested policy", () => {
    const merged = mergePolicy(
      { version: 1, chromium: { HomepageLocation: "https://a.com" } } as import("./types").PalletPolicy,
      { chromium: { DeveloperToolsAvailability: 2 } }
    );
    expect(merged).toEqual({
      version: 1,
      chromium: {
        HomepageLocation: "https://a.com",
        DeveloperToolsAvailability: 2,
      },
    });
  });

  it("detects online devices", () => {
    const now = new Date().toISOString().replace("T", " ").slice(0, 19);
    expect(isOnline(now, 120)).toBe(true);
    expect(isOnline("2020-01-01 00:00:00", 120)).toBe(false);
  });
});
