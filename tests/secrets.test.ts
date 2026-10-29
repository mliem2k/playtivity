import { expect, mock, test } from "bun:test";

const store: Record<string, string> = {};
mock.module("expo-sqlite/kv-store", () => ({
  default: { getItem: async (k: string) => store[k] ?? null, setItem: async (k: string, v: string) => void (store[k] = v) },
}));
const { initSecrets, refreshSecrets } = await import("../src/lib/secrets");
const { activeVersion, clearSecrets } = await import("../src/lib/totp");

let fetches = 0;
const realFetch = globalThis.fetch;
const serve = (body: unknown, ok = true) => {
  globalThis.fetch = (async () => {
    fetches++;
    return { ok, json: async () => body };
  }) as unknown as typeof fetch;
};

test("a fresh cache is applied with no network call", async () => {
  clearSecrets();
  store.totp_secrets = JSON.stringify({ at: Date.now(), data: { "70": [1, 2, 3] } });
  fetches = 0;
  serve({ "99": [9] });
  await initSecrets();
  expect(activeVersion()).toBe("70");
  expect(fetches).toBe(0);
});

test("a stale cache is applied at once and refreshed in the background", async () => {
  clearSecrets();
  store.totp_secrets = JSON.stringify({ at: Date.now() - 7 * 3_600_000, data: { "70": [1, 2, 3] } });
  fetches = 0;
  serve({ "71": [4, 5, 6] });
  await initSecrets();
  expect(activeVersion()).toBe("70"); // the old table is usable immediately
  await new Promise((r) => setTimeout(r, 10));
  expect(fetches).toBe(1);
  expect(activeVersion()).toBe("71");
});

test("a malformed table is rejected and the applied one stays", async () => {
  clearSecrets();
  serve({ abc: [1], "72": [] });
  expect(await refreshSecrets()).toBe(false);
  serve({}, false);
  expect(await refreshSecrets()).toBe(false);
  expect(activeVersion()).toBe("61");
  globalThis.fetch = realFetch;
});
