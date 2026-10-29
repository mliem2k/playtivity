import type { Activity } from "../lib/spotify";

/** Widget wording: Just now, 5m ago, 3h ago, 2d ago, then a short date. */
export function widgetTimeText(a: Activity, now = Date.now()): string {
  if (a.playing) return "Listening now";
  const m = Math.floor((now - a.timestamp) / 60_000);
  if (m < 1) return "Just now";
  if (m < 60) return `${m}m ago`;
  if (m < 1440) return `${Math.floor(m / 60)}h ago`;
  if (m < 10080) return `${Math.floor(m / 1440)}d ago`;
  return new Date(a.timestamp).toLocaleDateString("en-US", { month: "short", day: "2-digit" });
}

/** Listening friends first, then newest first. */
export const sortForWidget = (list: Activity[]) =>
  [...list].sort((a, b) => Number(b.playing) - Number(a.playing) || b.timestamp - a.timestamp);
