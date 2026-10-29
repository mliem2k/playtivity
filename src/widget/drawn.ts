import * as Application from "expo-application";
import Storage from "expo-sqlite/kv-store";

const KEY = "widget_signature";
const STALE_MS = 6 * 60 * 60 * 1000;

/**
 * True when the widget must be painted: the content changed, the app was updated, or the last paint is old.
 * The build number is part of the marker because the launcher keeps showing the views an earlier APK drew, and
 * after an update those can no longer render (the widget turns blank or reports a loading error), so the first
 * update of every new build has to repaint even when the content is identical.
 */
export async function claimRedraw(signature: string, now = Date.now(), build = Application.nativeBuildVersion ?? "0"): Promise<boolean> {
  const marker = `${build}|${signature}`;
  try {
    const raw = await Storage.getItem(KEY);
    if (raw) {
      const { marker: last, at } = JSON.parse(raw) as { marker: string; at: number };
      if (last === marker && now - at < STALE_MS) return false;
    }
    await Storage.setItem(KEY, JSON.stringify({ marker, at: now }));
  } catch {}
  return true;
}
