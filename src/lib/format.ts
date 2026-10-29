/** English strings and thresholds of the Dart timeago package, so feed times read as before. */
export function timeAgo(ms: number, now = Date.now()): string {
  const s = Math.max(0, Math.floor((now - ms) / 1000));
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  const d = Math.floor(h / 24);
  if (s < 45) return "a moment ago";
  if (s < 90) return "a minute ago";
  if (m < 45) return `${m} minutes ago`;
  if (m < 90) return "about an hour ago";
  if (h < 24) return `${h} hours ago`;
  if (h < 48) return "a day ago";
  if (d < 30) return `${d} days ago`;
  if (d < 60) return "about a month ago";
  if (d < 365) return `${Math.floor(d / 30)} months ago`;
  if (d < 730) return "about a year ago";
  return `${Math.floor(d / 365)} years ago`;
}

export function formatCount(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`;
  return String(n);
}

export function formatDuration(ms = 0): string {
  const total = Math.floor(ms / 1000);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}
