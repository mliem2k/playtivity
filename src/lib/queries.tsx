import { useQuery, useQueryClient } from "@tanstack/react-query";
import { requestWidgetUpdate } from "react-native-android-widget";
import { claimRedraw } from "@/widget/drawn";
import { FriendActivityWidget } from "@/widget/FriendActivityWidget";
import { widgetSignature } from "@/widget/logic";
import { saveActivities } from "./cache";
import { isSample, sampleActivities, sampleListeners, sampleNowPlaying, sampleTop } from "./sample";
import { useAuth } from "./auth";
import { AuthError, fetchArtistListeners, fetchBuddyList, fetchCurrentlyPlaying, fetchTop, lastSegment, mergeActivities, parseFriends, type Activity, type Artist } from "./spotify";

/** Runs `fn` with the current token; on an auth error refreshes once and retries. */
async function withToken<T>(fn: (t: string) => Promise<T>): Promise<T> {
  const { refreshToken, whenToken } = useAuth.getState();
  const token = await whenToken();
  if (!token) throw new AuthError("signed out");
  try {
    return await fn(token);
  } catch (e) {
    if (!(e instanceof AuthError)) throw e;
    const fresh = await refreshToken();
    if (!fresh) throw e;
    return fn(fresh);
  }
}

export function useActivities() {
  const qc = useQueryClient();
  return useQuery({
    queryKey: ["activities"],
    refetchInterval: 30_000,
    refetchOnMount: "always",
    queryFn: async () => {
      if (isSample) return sampleActivities();
      const body = await withToken(fetchBuddyList);
      // Empty responses must not wipe friends already known.
      const merged = mergeActivities(qc.getQueryData<Activity[]>(["activities"]) ?? [], parseFriends(body));
      if (merged.length) {
        saveActivities(merged);
        // Only repaint the widget when what it shows changed; identical repaints make it blink.
        claimRedraw(widgetSignature(merged)).then((changed) => {
          if (changed) requestWidgetUpdate({ widgetName: "FriendActivity", renderWidget: () => <FriendActivityWidget activities={merged} /> }).catch(() => {});
        });
      }
      return merged;
    },
  });
}

export const useTop = () => useQuery({ queryKey: ["top"], queryFn: async () => (isSample ? sampleTop() : withToken((t) => fetchTop(t))), staleTime: 5 * 60_000 });

export const useCurrentlyPlaying = () =>
  useQuery({ queryKey: ["now-playing"], queryFn: async () => (isSample ? sampleNowPlaying() : withToken(fetchCurrentlyPlaying)), refetchInterval: 30_000 });

/** Monthly listeners per artist id, fetched four at a time after the top list is known. */
export function useArtistListeners(artists: Artist[] | undefined) {
  const ids = (artists ?? []).map((a) => lastSegment(a.uri)).filter(Boolean);
  return useQuery({
    queryKey: ["listeners", ids.join(",")],
    enabled: ids.length > 0,
    staleTime: 60 * 60_000,
    queryFn: async () => {
      if (isSample) return sampleListeners();
      const out: Record<string, number> = {};
      for (let i = 0; i < ids.length; i += 4) {
        await Promise.all(
          ids.slice(i, i + 4).map(async (id) => {
            out[id] = await withToken((t) => fetchArtistListeners(t, id));
          }),
        );
      }
      return out;
    },
  });
}
