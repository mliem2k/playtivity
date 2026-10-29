import Storage from "expo-sqlite/kv-store";
import type { Activity } from "./spotify";

const KEY = "activities_cache";

/** Last known feed, so the widget and a cold start have something to show before the network answers. */
export async function loadActivities(): Promise<Activity[]> {
  try {
    const raw = await Storage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Activity[]) : [];
  } catch {
    return [];
  }
}

export const saveActivities = (a: Activity[]) => Storage.setItem(KEY, JSON.stringify(a.slice(0, 50)));
