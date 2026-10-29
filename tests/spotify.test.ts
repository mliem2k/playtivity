import { expect, test } from "bun:test";
import { mergeActivities, parseFriends, userIdFromJwt } from "../src/lib/spotify";

const now = 1_800_000_000_000;
const body = JSON.stringify({
  friends: [
    null,
    { timestamp: now - 1000, user: { uri: "spotify:user:a", name: "A" }, track: { name: "T", artist: { name: "Ar" }, album: { name: "Al" }, uri: "spotify:track:1" } },
    { friend: { timestamp: now - 9e6, user: { uri: "spotify:user:b", name: "B" }, context: { uri: "spotify:album:9", name: "Alb" } } },
    { user: { uri: "spotify:user:c" } },
  ],
});

test("parses track, envelope context, skips entries without activity", () => {
  const a = parseFriends(body, now);
  expect(a.map((x) => x.user.id)).toEqual(["a", "b"]);
  expect(a[0].playing).toBe(true);
  expect(a[1].playlist?.name).toBe("Alb");
});

test("merge keeps friends absent from the fresh response and recomputes playing", () => {
  const old = parseFriends(body, now);
  const merged = mergeActivities(old, [], now + 10 * 60 * 1000);
  expect(merged).toHaveLength(2);
  expect(merged[0].playing).toBe(false);
});

test("jwt sub strips the user prefix", () => {
  const p = btoa(JSON.stringify({ sub: "spotify:user:xyz" }));
  expect(userIdFromJwt(`h.${p}.s`)).toBe("xyz");
});
