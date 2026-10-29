import { create } from "zustand";
import { checkForUpdates, downloadAndInstall, getNightlyPref, type UpdateInfo } from "./update";

type Phase = "idle" | "downloading" | "installing" | "error";

type UpdateState = {
  info: UpdateInfo | null;
  phase: Phase;
  progress: number;
  error: string;
  /** Startup check: nightly users always check, others at most once a day. Resolves to the offer, if any. */
  checkOnStart: () => Promise<void>;
  /** Manual check from the UI. Always hits GitHub and reports the outcome. */
  check: () => Promise<{ info: UpdateInfo | null; error?: string }>;
  install: () => Promise<void>;
  dismiss: () => void;
};

export const useUpdate = create<UpdateState>((set, get) => ({
  info: null,
  phase: "idle",
  progress: 0,
  error: "",
  checkOnStart: async () => {
    const r = await checkForUpdates(await getNightlyPref());
    if (r.hasUpdate && r.info) set({ info: r.info, phase: "idle", error: "" });
  },
  check: async () => {
    const r = await checkForUpdates(true);
    if (r.hasUpdate && r.info) set({ info: r.info, phase: "idle", error: "" });
    return { info: r.hasUpdate ? (r.info ?? null) : null, error: r.error };
  },
  install: async () => {
    const { info, phase } = get();
    if (!info || phase === "downloading") return;
    set({ phase: "downloading", progress: 0, error: "" });
    try {
      await downloadAndInstall(info, (p) => set({ progress: p }));
      // The system installer takes over from here; keep the offer so a cancelled install can be retried.
      set({ phase: "installing", progress: 1 });
    } catch (e) {
      set({ phase: "error", error: String(e instanceof Error ? e.message : e) });
    }
  },
  dismiss: () => set({ info: null, phase: "idle", progress: 0, error: "" }),
}));
