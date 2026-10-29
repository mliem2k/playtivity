import * as Haptics from "expo-haptics";
import { usePrefs } from "./prefs";

// Every vibration in the app goes through here, so the Settings switch covers all of them.
const on = () => usePrefs.getState().haptics;

export const hapticLight = () => on() && Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
export const hapticMedium = () => on() && Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
export const hapticSelect = () => on() && Haptics.selectionAsync();
