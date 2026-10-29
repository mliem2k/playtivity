import * as SecureStore from "expo-secure-store";
import { create } from "zustand";
import { fetchBearerToken, fetchProfile, refreshSecrets, type User } from "./spotify";

const KEY = "sp_dc";

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
    await refreshSecrets();
    const spDc = await SecureStore.getItemAsync(KEY);
    set({ spDc });
    if (spDc && (await get().refreshToken())) {
      const user = await fetchProfile(get().token!).catch(() => null);
      set({ user });
    }
    set({ ready: true });
  },
  signIn: async (spDc) => {
    const token = await fetchBearerToken(spDc);
    if (!token) return false;
    await SecureStore.setItemAsync(KEY, spDc);
    const user = await fetchProfile(token).catch(() => null);
    set({ spDc, token, user });
    return true;
  },
  refreshToken: async () => {
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
