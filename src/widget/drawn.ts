import Storage from "expo-sqlite/kv-store";

const KEY = "widget_signature";

/** True when `signature` differs from what the widget last drew, and records it as drawn. */
export async function claimRedraw(signature: string): Promise<boolean> {
  try {
    if ((await Storage.getItem(KEY)) === signature) return false;
    await Storage.setItem(KEY, signature);
  } catch {}
  return true;
}
