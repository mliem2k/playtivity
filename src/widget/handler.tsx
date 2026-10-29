import * as SecureStore from "expo-secure-store";
import type { WidgetTaskHandlerProps } from "react-native-android-widget";
import { loadActivities, saveActivities } from "@/lib/cache";
import { fetchBearerToken, fetchBuddyList, mergeActivities, parseFriends } from "@/lib/spotify";
import { claimRedraw } from "./drawn";
import { FriendActivityWidget } from "./FriendActivityWidget";
import { widgetSignature } from "./logic";

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

  // A resize or a first draw has to paint something, and that comes from the cache so it is instant.
  // Otherwise the launcher keeps showing what was drawn last, so an update only paints when the content differs:
  // repainting identical content reloads every image and makes the widget blink.
  const forced = widgetAction === "WIDGET_ADDED" || widgetAction === "WIDGET_RESIZED";
  const refresh = widgetAction === "WIDGET_UPDATE" || widgetAction === "WIDGET_CLICK";
  const activities = refresh ? await freshActivities() : await loadActivities();
  if (forced || (await claimRedraw(widgetSignature(activities)))) {
    if (forced) await claimRedraw(widgetSignature(activities));
    renderWidget(<FriendActivityWidget activities={activities} />);
  }
}
