import { expect, test } from "bun:test";
import { activeVersion, generateCode } from "../src/lib/totp";

test("matches vectors from the Dart and Swift implementations", () => {
  expect(activeVersion()).toBe("61");
  for (const [ts, code] of [
    [0, "204513"],
    [1_000_000_000_000, "371947"],
    [1_750_000_000_000, "848996"],
    [1_752_300_000_000, "345437"],
  ] as const) {
    expect(generateCode(ts)).toBe(code);
  }
});
