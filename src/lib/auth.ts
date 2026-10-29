import * as SecureStore from "expo-secure-store";
import { create } from "zustand";
import { isSample, sampleUser } from "./sample";
import { fetchAccountProfile, fetchBearerToken, fetchProfile, refreshSecrets, userIdFromJwt, type User } from "./spotify";

const KEY = "sp_dc";

/**
 * The web token is not a JWT any more, so the user id comes from the account settings endpoint (sp_dc only),
 * with the token's own claim as a fallback. Name, picture and followers then come from the profile endpoint.
 */
async function loadUser(token: string, spDc: string): Promise<User | null> {
  const account = await fetchAccountProfile(spDc);
  const id = account?.username || userIdFromJwt(token);
  if (!id) return null;
  const profile = (await fetchProfile(token, id).catch(() => null)) ?? { id, displayName: id };
  return { ...profile, email: account?.email, country: account?.country };
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
    await refreshSecrets();
    const spDc = await SecureStore.getItemAsync(KEY);
    set({ spDc });
    if (spDc && (await get().refreshToken())) {
      const user = await loadUser(get().token!, spDc);
      set({ user });
    }
    set({ ready: true });
  },
  signIn: async (spDc) => {
    const token = await fetchBearerToken(spDc);
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
    const token = await fetchBearerToken(spDc);
    if (!token) {
      await get().signOut();
      return null;
    }
    set({ token });
    return token;
  },
  reloadUser: async () => {
    const { token, spDc, user } = get();
    if (user || !token || !spDc) return;
    const loaded = await loadUser(token, spDc).catch(() => null);
    if (loaded) set({ user: loaded });
  },
  signOut: async () => {
    await SecureStore.deleteItemAsync(KEY);
    set({ spDc: null, token: null, user: null });
  },
}));
