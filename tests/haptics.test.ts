import { expect, mock, test } from "bun:test";

const calls: string[] = [];
mock.module("expo-haptics", () => ({
  ImpactFeedbackStyle: { Light: "light", Medium: "medium" },
  impactAsync: (s: string) => calls.push(`impact:${s}`),
  selectionAsync: () => calls.push("selection"),
}));
const store: Record<string, string> = {};
mock.module("expo-sqlite/kv-store", () => ({
  default: { getItem: async (k: string) => store[k] ?? null, setItem: async (k: string, v: string) => void (store[k] = v) },
}));

const { hapticLight, hapticMedium, hapticSelect } = await import("../src/lib/haptics");
const { usePrefs } = await import("../src/lib/prefs");

test("every haptic fires while the setting is on, and none once it is off", () => {
  calls.length = 0;
  usePrefs.getState().setHaptics(true);
  hapticLight(); hapticMedium(); hapticSelect();
  expect(calls).toEqual(["impact:light", "impact:medium", "selection"]);

  calls.length = 0;
  usePrefs.getState().setHaptics(false);
  hapticLight(); hapticMedium(); hapticSelect();
  expect(calls).toEqual([]);
});

test("the choice survives a restart", async () => {
  usePrefs.getState().setHaptics(false);
  await Promise.resolve();
  usePrefs.setState({ haptics: true });
  await usePrefs.getState().load();
  expect(usePrefs.getState().haptics).toBe(false);
});
