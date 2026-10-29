import type { Activity, Artist, Track, User } from "./spotify";

/**
 * Debug only: `EXPO_PUBLIC_SAMPLE=1 bunx expo start` swaps the network for fixtures so every screen can be
 * checked without a Spotify login. Metro inlines the flag, and `__DEV__` is false in release builds,
 * so none of this runs in a shipped APK.
 */
export const isSample = __DEV__ && process.env.EXPO_PUBLIC_SAMPLE === "1";

const img = (seed: string, n = 200) => `https://picsum.photos/seed/${seed}/${n}`;
const mk = (name: string, artist: string, album: string, seed: string): Track => ({
  name, artists: [artist], album, uri: `spotify:track:${seed}`, imageUrl: img(seed), durationMs: 150_000 + seed.length * 13_000,
});

export const sampleUser: User = { id: "me", displayName: "Michael Liem", followers: 42, country: "ID", email: "me@example.com", imageUrl: img("me") };

export function sampleActivities(now = Date.now()): Activity[] {
  const u = (id: string, displayName: string, withImage = true): User => ({ id, displayName, imageUrl: withImage ? img(id) : undefined });
  const m = 60_000;
  return [
    { user: u("a", "Alya Putri"), track: mk("Blinding Lights", "The Weeknd", "After Hours", "a1"), timestamp: now - m, playing: true },
    { user: u("b", "Budi Santoso", false), track: mk("Lose Yourself to Dance", "Daft Punk", "Random Access Memories", "b1"), timestamp: now - 3 * m, playing: true },
    { user: u("c", "Citra Dewi"), track: mk("Levitating", "Dua Lipa", "Future Nostalgia", "c1"), timestamp: now - 25 * m, playing: false },
    { user: u("d", "Dimas Prakoso"), playlist: { name: "Late Night Drive", imageUrl: img("d1"), trackCount: 64, uri: "spotify:playlist:d1", ownerName: "Dimas Prakoso" }, timestamp: now - 3 * 60 * m, playing: false },
    { user: u("e", "Eka Wijaya", false), track: mk("A Very Long Track Title That Needs To Be Truncated Nicely", "An Artist With A Long Name, Another Artist", "An Equally Long Album Name Here", "e1"), timestamp: now - 26 * 60 * m, playing: false },
    { user: u("f", "Fira Anggraini"), track: mk("Espresso", "Sabrina Carpenter", "Short n' Sweet", "f1"), timestamp: now - 5 * 24 * 60 * m, playing: false },
  ];
}

export const sampleNowPlaying = (): Track => mk("Midnight City", "M83", "Hurry Up, We're Dreaming", "np");

export const sampleTop = (): { tracks: Track[]; artists: Artist[] } => ({
  tracks: ["Starboy", "Dreams", "Time", "Holocene", "Nights", "Redbone", "Genesis", "Instant Crush", "Sunflower", "Ivy"].map((n, i) =>
    mk(n, ["The Weeknd", "Fleetwood Mac", "Pink Floyd", "Bon Iver", "Frank Ocean", "Childish Gambino", "Grimes", "Daft Punk", "Post Malone", "Frank Ocean"][i], "Album " + (i + 1), `t${i}`),
  ),
  artists: ["The Weeknd", "Daft Punk", "Frank Ocean", "Tame Impala", "Rex Orange County", "Mac DeMarco"].map((name, i) => ({ name, uri: `spotify:artist:ar${i}`, imageUrl: i === 4 ? undefined : img(`ar${i}`) })),
});

export const sampleListeners = (): Record<string, number> => ({ ar0: 84_500_000, ar1: 21_300_000, ar2: 9_800_000, ar3: 1_250_000, ar4: 640, ar5: 950_000 });
