import * as SecureStore from "expo-secure-store";
import type { WidgetTaskHandlerProps } from "react-native-android-widget";
import { loadActivities, saveActivities } from "@/lib/cache";
import { fetchBearerToken, fetchBuddyList, mergeActivities, parseFriends } from "@/lib/spotify";
import { FriendActivityWidget } from "./FriendActivityWidget";

export const WIDGET_NAME = "FriendActivity";

/** Cached feed refreshed from Spotify when a session exists; falls back to the cache on any failure. */
async function freshActivities() {
  const cached = await loadActivities();
  try {
    const spDc = await SecureStore.getItemAsync("sp_dc");
    if (!spDc) return cached;
    const token = await fetchBearerToken(spDc);
    if (!token) return cached;
    const merged = mergeActivities(cached, parseFriends(await fetchBuddyList(token)));
    if (merged.length) await saveActivities(merged);
    return merged.length ? merged : cached;
  } catch {
    return cached;
  }
}

export async function widgetTaskHandler({ widgetInfo, widgetAction, clickAction, renderWidget }: WidgetTaskHandlerProps) {
  if (widgetInfo.widgetName !== WIDGET_NAME) return;
  if (widgetAction === "WIDGET_DELETED") return;
  if (widgetAction === "WIDGET_CLICK" && clickAction !== "REFRESH") return;
  // Resizes and first draws are served from the cache so they stay instant; updates and refresh hit the network.
  const refresh = widgetAction === "WIDGET_UPDATE" || widgetAction === "WIDGET_CLICK";
  const activities = refresh ? await freshActivities() : await loadActivities();
  renderWidget(<FriendActivityWidget activities={activities} />);
}
