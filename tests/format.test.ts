import { expect, test } from "bun:test";
import { formatCount, formatDuration, timeAgo } from "../src/lib/format";

const now = 1_800_000_000_000;
test("timeAgo follows the timeago package thresholds", () => {
  expect(timeAgo(now - 10_000, now)).toBe("a moment ago");
  expect(timeAgo(now - 60_000, now)).toBe("a minute ago");
  expect(timeAgo(now - 5 * 60_000, now)).toBe("5 minutes ago");
  expect(timeAgo(now - 60 * 60_000, now)).toBe("about an hour ago");
  expect(timeAgo(now - 3 * 3_600_000, now)).toBe("3 hours ago");
  expect(timeAgo(now - 30 * 3_600_000, now)).toBe("a day ago");
  expect(timeAgo(now - 5 * 86_400_000, now)).toBe("5 days ago");
});

test("counts and durations", () => {
  expect(formatCount(999)).toBe("999");
  expect(formatCount(1500)).toBe("1.5K");
  expect(formatCount(2_500_000)).toBe("2.5M");
  expect(formatDuration(185_000)).toBe("3:05");
  expect(formatDuration(undefined)).toBe("0:00");
});

import { sortForWidget, widgetTimeText } from "../src/widget/logic";
import type { Activity } from "../src/lib/spotify";

const act = (id: string, timestamp: number, playing = false): Activity => ({ user: { id, displayName: id }, timestamp, playing, track: { name: "t", artists: [], album: "", uri: "" } });

test("widget wording and ordering match the Flutter widget", () => {
  expect(widgetTimeText(act("a", now - 10_000), now)).toBe("Just now");
  expect(widgetTimeText(act("a", now - 5 * 60_000), now)).toBe("5m ago");
  expect(widgetTimeText(act("a", now - 3 * 3_600_000), now)).toBe("3h ago");
  expect(widgetTimeText(act("a", now - 2 * 86_400_000), now)).toBe("2d ago");
  expect(widgetTimeText(act("a", now, true), now)).toBe("Listening now");
  expect(sortForWidget([act("old", 1), act("new", 5), act("live", 2, true)]).map((a) => a.user.id)).toEqual(["live", "new", "old"]);
});
