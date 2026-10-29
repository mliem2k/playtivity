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

/**
 * What the widget would show, as a string. Redrawing identical content reloads every image and makes the
 * widget flicker, so callers redraw only when this changes. Times under an hour are bucketed to five minutes
 * so "5m ago" ticking to "6m ago" does not cause a redraw of its own.
 */
export function widgetSignature(list: Activity[], now = Date.now()): string {
  return sortForWidget(list)
    .map((a) => {
      const text = widgetTimeText(a, now);
      const minutes = Math.floor((now - a.timestamp) / 60_000);
      const bucketed = !a.playing && minutes >= 1 && minutes < 60 ? `${Math.floor(minutes / 5)}x5m` : text;
      return [a.user.id, a.user.displayName, a.user.imageUrl, a.track?.name ?? a.playlist?.name, a.track?.artists.join(",") ?? a.playlist?.ownerName, a.track?.imageUrl ?? a.playlist?.imageUrl, a.playing, bucketed].join("|");
    })
    .join("\n");
}
