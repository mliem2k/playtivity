import Storage from "expo-sqlite/kv-store";
import { applySecrets } from "./totp";

const URL = "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true";
const KEY = "totp_secrets";
const TTL_MS = 6 * 60 * 60 * 1000;

type Table = Record<string, number[]>;

const valid = (raw: unknown): raw is Table =>
  !!raw &&
  typeof raw === "object" &&
  Object.keys(raw).length > 0 &&
  Object.entries(raw).every(([k, v]) => /^\d+$/.test(k) && Array.isArray(v) && v.length > 0 && v.every(Number.isInteger));

/** Fetches the current TOTP secret table, applies it and caches it. False on any failure, keeping what is applied. */
export async function refreshSecrets(): Promise<boolean> {
  try {
    const r = await fetch(URL, { headers: { accept: "application/json" } });
    if (!r.ok) return false;
    const raw = await r.json();
    if (!valid(raw)) return false;
    applySecrets(raw);
    await Storage.setItem(KEY, JSON.stringify({ at: Date.now(), data: raw }));
    return true;
  } catch {
    return false;
  }
}

/**
 * Startup: apply the cached table at once, with no network wait, and refresh it in the background when it is
 * missing or older than six hours. Spotify rotates these secrets now and then, so the refresh must keep happening.
 */
export async function initSecrets(): Promise<void> {
  let stale = true;
  try {
    const raw = await Storage.getItem(KEY);
    if (raw) {
      const { at, data } = JSON.parse(raw) as { at: number; data: unknown };
      if (valid(data)) {
        applySecrets(data);
        stale = Date.now() - at > TTL_MS;
      }
    }
  } catch {}
  if (stale) void refreshSecrets();
}
