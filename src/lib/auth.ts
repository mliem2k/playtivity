import * as SecureStore from "expo-secure-store";
import { create } from "zustand";
import { isSample, sampleUser } from "./sample";
import { fetchAccountProfile, fetchBearerToken, fetchProfile, refreshSecrets, type User } from "./spotify";

const KEY = "sp_dc";

/** Adds email and country to the profile; the spclient profile endpoint does not carry them. */
async function enrich(user: User | null, spDc: string): Promise<User | null> {
  if (!user || (user.email && user.country)) return user;
  const extra = await fetchAccountProfile(spDc);
  return extra ? { ...user, ...extra } : user;
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
      const user = await enrich(await fetchProfile(get().token!).catch(() => null), spDc);
      set({ user });
    }
    set({ ready: true });
  },
  signIn: async (spDc) => {
    const token = await fetchBearerToken(spDc);
    if (!token) return false;
    await SecureStore.setItemAsync(KEY, spDc);
    const user = await enrich(await fetchProfile(token).catch(() => null), spDc);
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
  signOut: async () => {
    await SecureStore.deleteItemAsync(KEY);
    set({ spDc: null, token: null, user: null });
  },
}));
