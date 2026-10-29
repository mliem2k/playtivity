import { expect, test } from "bun:test";
import { mock } from "bun:test";

mock.module("expo-application", () => ({}));
mock.module("expo-file-system/legacy", () => ({}));
mock.module("expo-intent-launcher", () => ({}));
mock.module("expo-sqlite/kv-store", () => ({ default: {} }));
const u = await import("../src/lib/update");

const nightly = {
  tag_name: "nightly-20260611-050901",
  published_at: "2026-06-11T05:09:01Z",
  body: "**Version**: `0.0.2-nightly-20260611-050901+1781212141`",
  assets: [{ name: "p.apk", browser_download_url: "https://x/p.apk", size: 5 }],
};

test("nightly body gives version and build number", () => {
  const i = u.infoFromRelease(nightly, true);
  expect(i.version).toBe("0.0.2-nightly-20260611-050901");
  expect(i.buildNumber).toBe("1781212141");
  expect(i.apkFileName).toBe("p.apk");
});

test("nightly to nightly compares the integer build", () => {
  const i = u.infoFromRelease(nightly, true);
  expect(u.shouldUpdateToNightly({ version: "0.0.2-nightly-x", buildNumber: "1781212140" }, i)).toBe(true);
  expect(u.shouldUpdateToNightly({ version: "0.0.2-nightly-x", buildNumber: "1781212141" }, i)).toBe(false);
});

test("stable user is offered a nightly of the same base only", () => {
  const i = u.infoFromRelease(nightly, true);
  expect(u.shouldUpdateToNightly({ version: "0.0.2", buildNumber: "1" }, i)).toBe(true);
  expect(u.shouldUpdateToNightly({ version: "0.0.3", buildNumber: "1" }, i)).toBe(false);
});

test("stable semver and nightly users", () => {
  expect(u.isNewerVersion("0.0.2", "0.0.3")).toBe(true);
  expect(u.isNewerVersion("0.0.3", "0.0.2")).toBe(false);
  expect(u.isNewerVersion("0.0.2-nightly-20260611-050901", "0.0.3")).toBe(true);
  expect(u.isNewerVersion("0.0.2", "0.0.3-nightly-20260611-050901")).toBe(false);
});

test("releases pick the newest published stable tag", () => {
  const r = u.checkRelease(
    [
      { tag_name: "v0.0.3", published_at: "2026-06-12T00:00:00Z", body: "", assets: [] },
      { tag_name: "v0.0.4", published_at: "2026-06-14T00:00:00Z", body: "", assets: [] },
      nightly,
    ],
    { version: "0.0.2", buildNumber: "1" },
  );
  expect(r.info?.version).toBe("0.0.4");
});
