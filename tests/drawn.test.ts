import { expect, mock, test } from "bun:test";

mock.module("expo-application", () => ({ nativeBuildVersion: "100" }));
const store: Record<string, string> = {};
mock.module("expo-sqlite/kv-store", () => ({
  default: { getItem: async (k: string) => store[k] ?? null, setItem: async (k: string, v: string) => void (store[k] = v) },
}));
const { claimRedraw } = await import("../src/widget/drawn");

const t0 = 1_800_000_000_000;

test("repaints on first use, then only when something changes", async () => {
  expect(await claimRedraw("a", t0, "100")).toBe(true);
  expect(await claimRedraw("a", t0 + 60_000, "100")).toBe(false);
  expect(await claimRedraw("b", t0 + 120_000, "100")).toBe(true);
});

test("a new build repaints even when the content is identical", async () => {
  expect(await claimRedraw("b", t0 + 180_000, "100")).toBe(false);
  expect(await claimRedraw("b", t0 + 240_000, "101")).toBe(true);
  expect(await claimRedraw("b", t0 + 300_000, "101")).toBe(false);
});

test("an old paint is repeated after six hours", async () => {
  expect(await claimRedraw("b", t0 + 300_000 + 5 * 3_600_000, "101")).toBe(false);
  expect(await claimRedraw("b", t0 + 300_000 + 7 * 3_600_000, "101")).toBe(true);
});
