import { applySecrets, generateParams } from "./totp";

export const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36";
const SPCLIENT = "https://guc-spclient.spotify.com";
const PARTNER = "https://api-partner.spotify.com/pathfinder/v2/query";
const TOP_HASH = "feb6d55177e2cbce2ac59214f9493f1ef2e4368eec01b3d4c3468fa1b97336e2";
const ARTIST_URL = "https://api-partner.spotify.com/pathfinder/v1/query";
const ARTIST_HASH = "d66221ea13998b2f81883c5187d174c8646e4041d67f5b1e103bc262d447e3a0";
const SECRETS_URL = "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true";
export const PLAYING_MS = 5 * 60 * 1000;

export class AuthError extends Error {}

export type User = { id: string; displayName: string; imageUrl?: string; followers?: number; country?: string; email?: string };
export type Track = { name: string; artists: string[]; album: string; imageUrl?: string; uri: string; durationMs?: number };
export type Playlist = { name: string; imageUrl?: string; trackCount: number; uri: string; ownerName: string };
export type Activity = { user: User; track?: Track; playlist?: Playlist; timestamp: number; playing: boolean };
export type Artist = { name: string; imageUrl?: string; uri: string; monthlyListeners?: number };

const webHeaders = (token: string) => ({
  Authorization: `Bearer ${token}`,
  "App-Platform": "WebPlayer",
  accept: "application/json",
  "accept-language": "en",
  origin: "https://open.spotify.com",
  referer: "https://open.spotify.com/",
  "User-Agent": UA,
});

const lastSegment = (uri: string) => uri.split(":").pop() ?? "";

/** Refreshes the TOTP secret table from the community mirror; keeps the fallback on any failure. */
export async function refreshSecrets(): Promise<void> {
  try {
    const r = await fetch(SECRETS_URL, { headers: { accept: "application/json" } });
    if (!r.ok) return;
    const raw = (await r.json()) as Record<string, unknown>;
    const ok = Object.entries(raw).every(
      ([k, v]) => /^\d+$/.test(k) && Array.isArray(v) && v.length > 0 && v.every(Number.isInteger),
    );
    if (ok && Object.keys(raw).length) applySecrets(raw as Record<string, number[]>);
  } catch {}
}

async function serverTimeMs(): Promise<number> {
  try {
    const r = await fetch("https://open.spotify.com/");
    const d = Date.parse(r.headers.get("date") ?? "");
    if (!Number.isNaN(d)) return d;
  } catch {}
  return Date.now();
}

/** sp_dc cookie -> bearer token. Null when sp_dc is expired (Spotify answers with an anonymous token). */
export async function fetchBearerToken(spDc: string): Promise<string | null> {
  const p = generateParams(await serverTimeMs());
  const qs = new URLSearchParams({ reason: "transport", productType: "web-player", ...p });
  const r = await fetch(`https://open.spotify.com/api/token?${qs}`, {
    headers: {
      Cookie: `sp_dc=${spDc}`,
      "User-Agent": UA,
      Accept: "application/json",
      "App-Platform": "WebPlayer",
      Referer: "https://open.spotify.com/",
      Origin: "https://open.spotify.com",
    },
    credentials: "omit", // keep RN's cookie jar from overriding the manual Cookie header
  });
  if (r.status !== 200) return null;
  const j = (await r.json().catch(() => null)) as { accessToken?: string; isAnonymous?: boolean } | null;
  return j && !j.isAnonymous && j.accessToken ? j.accessToken : null;
}

export function userIdFromJwt(token: string): string | null {
  const part = token.split(".")[1];
  if (!part) return null;
  try {
    const json = JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    const sub: string | undefined = json.sub;
    return sub ? sub.replace(/^spotify:user:/, "") : null;
  } catch {
    return null;
  }
}

export async function fetchProfile(token: string): Promise<User | null> {
  const id = userIdFromJwt(token);
  if (!id) return null;
  const r = await fetch(`${SPCLIENT}/user-profile-view/v3/profile/${id}`, { headers: webHeaders(token) });
  if (!r.ok) return null;
  const j = await r.json();
  return { id, displayName: j.name ?? id, imageUrl: j.image_url ?? undefined, followers: Number(j.followers_count) || 0 };
}

async function retry<T>(fn: () => Promise<T>, tries = 3): Promise<T> {
  for (let i = 0; ; i++) {
    try {
      return await fn();
    } catch (e) {
      if (e instanceof AuthError || i === tries - 1) throw e;
      const rate = String(e).includes("429");
      await new Promise((res) => setTimeout(res, (rate ? 5000 : 50) * 2 ** i));
    }
  }
}

function check(status: number, what: string) {
  if (status === 401 || status === 403) throw new AuthError(`Authentication error: ${status}`);
  if (status !== 200) throw new Error(`Failed to fetch ${what}: ${status}`);
}

/** Pure parse of a buddylist body; ordering and skip rules mirror the previous native app. */
export function parseFriends(body: string, now = Date.now()): Activity[] {
  let json: any;
  try {
    json = JSON.parse(body);
  } catch {
    return [];
  }
  if (!Array.isArray(json?.friends)) return [];
  const out: Activity[] = [];
  for (const entry of json.friends) {
    if (!entry) continue;
    const data = entry.friend?.user ? entry.friend : entry;
    const u = data.user;
    if (!u || typeof u !== "object") continue;
    const uri: string = u.uri ?? "";
    const user: User = { id: uri.replace(/^spotify:user:/, ""), displayName: u.name ?? "Unknown User", imageUrl: u.imageUrl };
    const ts = Number.isInteger(data.timestamp) ? data.timestamp : now;
    const live = now - ts >= 0 && now - ts < PLAYING_MS;

    if (data.playlist) {
      const p = data.playlist;
      out.push({
        user, timestamp: ts, playing: false,
        playlist: { name: p.name ?? "Unknown Playlist", imageUrl: p.imageUrl, trackCount: p.trackCount ?? 0, uri: p.uri ?? "", ownerName: p.owner?.name ?? "Unknown" },
      });
    } else if (data.track) {
      const t = data.track;
      out.push({
        user, timestamp: ts, playing: live,
        track: { name: t.name ?? "Unknown Track", artists: [t.artist?.name ?? "Unknown Artist"], album: t.album?.name ?? "Unknown Album", imageUrl: t.imageUrl ?? t.album?.imageUrl, uri: t.uri ?? "" },
      });
    } else if (data.episode) {
      const e = data.episode;
      const show = e.show?.name ?? "Unknown Podcast";
      out.push({
        user, timestamp: ts, playing: live,
        track: { name: e.name ?? "Unknown Episode", artists: [show], album: show, imageUrl: e.imageUrl ?? e.show?.imageUrl, uri: e.uri ?? "" },
      });
    } else if (data.context?.uri) {
      const c = data.context;
      out.push({
        user, timestamp: ts, playing: false,
        playlist: { name: c.name ?? "Spotify", imageUrl: c.imageUrl, trackCount: 0, uri: c.uri, ownerName: "" },
      });
    }
  }
  return out.sort((a, b) => b.timestamp - a.timestamp);
}

/** Fresh entries replace cached ones per user, so a friend missing from a response is not dropped. */
export function mergeActivities(existing: Activity[], fresh: Activity[], now = Date.now()): Activity[] {
  const byUser = new Map<string, Activity>();
  for (const a of [...existing, ...fresh]) byUser.set(a.user.id, a);
  return [...byUser.values()]
    .map((a) => ({ ...a, playing: !!a.track && now - a.timestamp >= 0 && now - a.timestamp < PLAYING_MS }))
    .sort((a, b) => b.timestamp - a.timestamp);
}

export const fetchBuddyList = (token: string) =>
  retry(async () => {
    const r = await fetch(`${SPCLIENT}/presence-view/v1/buddylist`, { headers: webHeaders(token) });
    check(r.status, "friend activity");
    return r.text();
  });

const bestImage = (sources: any[] = [], h: number): string | undefined =>
  (sources.find((s) => s.height === h) ?? [...sources].sort((a, b) => (b.height ?? 0) - (a.height ?? 0))[0])?.url;

export async function fetchTop(token: string, limit = 20): Promise<{ tracks: Track[]; artists: Artist[] }> {
  const range = { offset: 0, limit, sortBy: "AFFINITY", timeRange: "SHORT_TERM" };
  const j = await retry(async () => {
    const r = await fetch(PARTNER, {
      method: "POST",
      headers: { ...webHeaders(token), "content-type": "application/json;charset=UTF-8" },
      body: JSON.stringify({
        operationName: "userTopContent",
        variables: { includeTopTracks: true, topTracksInput: range, includeTopArtists: true, topArtistsInput: range },
        extensions: { persistedQuery: { version: 1, sha256Hash: TOP_HASH } },
      }),
    });
    check(r.status, "top content");
    return r.json();
  });
  const profile = j?.data?.me?.profile;
  const tracks: Track[] = (profile?.topTracks?.items ?? []).map((i: any) => {
    const t = i.data ?? i;
    return {
      name: t.name ?? "Unknown Track",
      artists: (t.artists?.items ?? []).map((a: any) => a.profile?.name ?? "Unknown Artist"),
      album: t.albumOfTrack?.name ?? "Unknown Album",
      imageUrl: bestImage(t.albumOfTrack?.coverArt?.sources, 300),
      uri: t.uri ?? "",
      durationMs: t.duration?.totalMilliseconds ?? 0,
    };
  });
  const artists: Artist[] = (profile?.topArtists?.items ?? []).map((i: any) => {
    const a = i.data ?? i;
    return { name: a.profile?.name ?? "Unknown Artist", imageUrl: bestImage(a.visuals?.avatarImage?.sources, 320), uri: a.uri ?? "" };
  });
  return { tracks, artists };
}

export const spotifyUrl = (uri: string) => {
  const [, type, id] = uri.split(":");
  return type && id ? `https://open.spotify.com/${type}/${id}` : "https://open.spotify.com/";
};

export { lastSegment };

/** What the signed in user is playing right now, or null when nothing is (HTTP 204) or on any failure. */
export async function fetchCurrentlyPlaying(token: string): Promise<Track | null> {
  const r = await fetch("https://api.spotify.com/v1/me/player/currently-playing", {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json, text/plain, */*", "User-Agent": "okhttp/4.9.2" },
  });
  if (r.status !== 200) return null;
  const item = (await r.json().catch(() => null))?.item;
  if (!item) return null;
  return {
    name: item.name ?? "",
    artists: (item.artists ?? []).map((a: any) => a.name).filter(Boolean),
    album: item.album?.name ?? "",
    imageUrl: item.album?.images?.[0]?.url,
    uri: item.uri ?? "",
    durationMs: item.duration_ms ?? 0,
  };
}

/** Monthly listeners for one artist id; -1 when the lookup fails so the tile hides the line. */
export async function fetchArtistListeners(token: string, artistId: string): Promise<number> {
  try {
    const qs = new URLSearchParams({
      operationName: "queryArtistOverview",
      variables: JSON.stringify({ uri: `spotify:artist:${artistId}`, locale: "", includePrerelease: true }),
      extensions: JSON.stringify({ persistedQuery: { version: 1, sha256Hash: ARTIST_HASH } }),
    });
    const j = await retry(async () => {
      const r = await fetch(`${ARTIST_URL}?${qs}`, { headers: webHeaders(token) });
      check(r.status, "artist details");
      return r.json();
    });
    return Number(j?.data?.artist?.stats?.monthlyListeners) || 0;
  } catch {
    return -1;
  }
}

/** Email and country from the account settings endpoint; needs only the sp_dc cookie and is not rate limited. */
export async function fetchAccountProfile(spDc: string): Promise<{ email: string; country: string } | null> {
  try {
    const r = await fetch("https://www.spotify.com/api/account-settings/v1/profile", {
      headers: { Cookie: `sp_dc=${spDc}`, "User-Agent": UA, Accept: "application/json", Referer: "https://www.spotify.com/account/overview/" },
      credentials: "omit",
    });
    if (r.status !== 200) return null;
    const p = (await r.json())?.profile;
    return p ? { email: p.email ?? "", country: p.country ?? "" } : null;
  } catch {
    return null;
  }
}
