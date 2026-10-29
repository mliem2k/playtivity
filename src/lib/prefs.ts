import Storage from "expo-sqlite/kv-store";
import { create } from "zustand";

const KEY = "prefs";

type Prefs = {
  haptics: boolean;
  load: () => Promise<void>;
  setHaptics: (on: boolean) => void;
};

/** Small on device preferences. Haptics default to on, as in the Flutter app. */
export const usePrefs = create<Prefs>((set) => ({
  haptics: true,
  load: async () => {
    try {
      const raw = await Storage.getItem(KEY);
      if (raw) set({ haptics: JSON.parse(raw).haptics !== false });
    } catch {}
  },
  setHaptics: (on) => {
    set({ haptics: on });
    Storage.setItem(KEY, JSON.stringify({ haptics: on })).catch(() => {});
  },
}));
