import * as SecureStore from "expo-secure-store";
import { create } from "zustand";
import { isSample, sampleUser } from "./sample";
import { initSecrets, refreshSecrets } from "./secrets";
import { fetchAccountProfile, fetchBearerToken, fetchProfile, userIdFromJwt, type User } from "./spotify";

const KEY = "sp_dc";

// The token and profile load in the background after the first screen; requests wait on this instead of the UI.
let booting: Promise<string | null> | null = null;

/**
 * The web token is not a JWT any more, so the user id comes from the account settings endpoint (sp_dc only),
 * with the token's own claim as a fallback. Name, picture and followers then come from the profile endpoint.
 */
async function loadUser(token: string, spDc: string): Promise<User | null> {
  const account = await fetchAccountProfile(spDc);
  const id = account?.username || userIdFromJwt(token);
  if (!id) return null;
  const profile = (await fetchProfile(token, id).catch(() => null)) ?? { id, displayName: id };
  // Debug only (screenshots): keep the account email out of the picture.
  const email = __DEV__ && process.env.EXPO_PUBLIC_DEV_HIDE_EMAIL ? undefined : account?.email;
  return { ...profile, email, country: account?.country };
}

type AuthState = {
  ready: boolean;
  spDc: string | null;
  token: string | null;
  user: User | null;
  init: () => Promise<void>;
  signIn: (spDc: string) => Promise<boolean>;
  /** Fresh bearer token from the stored sp_dc; signs out when Spotify says sp_dc expired. */
  refreshToken: () => Promise<string | null>;
  /** The current token, waiting for the startup load when it is still in flight. */
  whenToken: () => Promise<string | null>;
  signOut: () => Promise<void>;
  /** Retries the profile lookup, for a start where the network was not ready the first time. */
  reloadUser: () => Promise<void>;
};

export const useAuth = create<AuthState>((set, get) => ({
  ready: false,
  spDc: null,
  token: null,
  user: null,
  init: async () => {
    if (isSample) return set({ ready: true, spDc: "sample", token: "sample", user: sampleUser });
    await initSecrets(); // cache read only; the network refresh runs in the background
    // Debug only: lets a dev build sign in from the environment, for screenshots and manual tests.
    // The variable is read at bundle time and __DEV__ is false in release builds, so it never ships.
    const spDc = (__DEV__ && process.env.EXPO_PUBLIC_DEV_SP_DC) || (await SecureStore.getItemAsync(KEY));
    // The first screen no longer waits for the token and profile round trips.
    set({ spDc, ready: true });
    if (spDc) {
      booting = (async () => {
        const token = await get().refreshToken();
        if (token) set({ user: await loadUser(token, spDc) });
        return token;
      })();
    }
  },
  signIn: async (spDc) => {
    const token = await fetchBearerToken(spDc).catch(() => null);
    if (!token) return false;
    await SecureStore.setItemAsync(KEY, spDc);
    const user = await loadUser(token, spDc);
    set({ spDc, token, user });
    return true;
  },
  refreshToken: async () => {
    if (isSample) return "sample";
    const { spDc } = get();
    if (!spDc) return null;
    // A network error keeps the session; only Spotify refusing the cookie signs the user out.
    const attempt = () => fetchBearerToken(spDc).catch(() => undefined);
    let token = await attempt();
    if (token === undefined) return null;
    if (!token) {
      // The cookie may be fine and the secret table stale, so refresh the table and try once more.
      await refreshSecrets();
      token = await attempt();
      if (token === undefined) return null;
    }
    if (!token) {
      await get().signOut();
      return null;
    }
    set({ token });
    return token;
  },
  whenToken: async () => get().token ?? (booting ? await booting : null),
  reloadUser: async () => {
    const { token, spDc, user } = get();
    if (user || !token || !spDc) return;
    const loaded = await loadUser(token, spDc).catch(() => null);
    if (loaded) set({ user: loaded });
  },
  signOut: async () => {
    await SecureStore.deleteItemAsync(KEY);
    booting = null;
    set({ spDc: null, token: null, user: null });
  },
}));
