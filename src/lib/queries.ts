import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useAuth } from "./auth";
import { AuthError, fetchBuddyList, fetchTop, mergeActivities, parseFriends, type Activity } from "./spotify";

/** Runs `fn` with the current token; on an auth error refreshes once and retries. */
async function withToken<T>(fn: (t: string) => Promise<T>): Promise<T> {
  const { token, refreshToken } = useAuth.getState();
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
    queryFn: async () => {
      const body = await withToken(fetchBuddyList);
      // Empty responses must not wipe friends already known.
      const merged = mergeActivities(qc.getQueryData<Activity[]>(["activities"]) ?? [], parseFriends(body));
      return merged;
    },
  });
}

export const useTop = () => useQuery({ queryKey: ["top"], queryFn: () => withToken((t) => fetchTop(t)), staleTime: 5 * 60_000 });
