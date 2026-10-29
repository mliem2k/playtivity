import * as Application from "expo-application";
import * as FileSystem from "expo-file-system/legacy";
import * as IntentLauncher from "expo-intent-launcher";
import Storage from "expo-sqlite/kv-store";

// 100 per page: nightlies pile up, and a stable release must not scroll off the first page.
const RELEASES_API = "https://api.github.com/repos/mliem2k/playtivity/releases?per_page=100";
const HOUR = 3_600_000;

export type AppVersion = { version: string; buildNumber: string };
export type UpdateInfo = {
  version: string;
  buildNumber: string;
  buildDate: number;
  apkUrl: string;
  apkFileName: string;
  changelog: string;
  isNightly: boolean;
  fileSizeBytes: number;
};
export type UpdateCheck = { hasUpdate: boolean; isNightly: boolean; info?: UpdateInfo; error?: string };

export const isNightlyVersion = (v: string) => v.includes("-nightly-");

export function extractBaseVersion(v: string): string {
  const noBuild = v.split("+")[0];
  return noBuild.includes("-nightly-") ? noBuild.split("-nightly-")[0] : noBuild;
}

/** 1 when `b` is newer than `a`, -1 when older, 0 when equal; a pre-release suffix sorts below its base. */
function compareBase(a: string, b: string): number {
  const [aMain, ...aPre] = a.split("+")[0].split("-");
  const [bMain, ...bPre] = b.split("+")[0].split("-");
  const pa = aMain.split(".").map((x) => parseInt(x, 10) || 0);
  const pb = bMain.split(".").map((x) => parseInt(x, 10) || 0);
  for (let i = 0; i < 3; i++) {
    const d = (pb[i] ?? 0) - (pa[i] ?? 0);
    if (d) return d > 0 ? 1 : -1;
  }
  if (!aPre.length && bPre.length) return -1;
  if (aPre.length && !bPre.length) return 1;
  if (aPre.length && bPre.length && aPre[0] !== bPre[0]) return bPre[0] > aPre[0] ? 1 : -1;
  return 0;
}

export function isNewerVersion(current: string, next: string): boolean {
  const cn = current.includes("nightly");
  const nn = next.includes("nightly");
  if (cn && nn) return false;
  if (!cn && nn) return false;
  if (cn) return compareBase(extractBaseVersion(current), extractBaseVersion(next)) > 0;
  return compareBase(current, next) > 0;
}

/** Last "nightly-YYYYMMDD-HHMMSS" stamp in the string, as epoch ms (UTC), or null. */
function nightlyStamp(v: string): number | null {
  let last: number | null = null;
  for (const m of v.matchAll(/nightly-(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})/g)) {
    last = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  }
  return last;
}

export function isNewerNightly(current: string, next: string): boolean {
  const c = nightlyStamp(current);
  const n = nightlyStamp(next);
  return c !== null && n !== null && n > c;
}

export function shouldUpdateToNightly(cur: AppVersion, nightly: UpdateInfo): boolean {
  if (!cur.version.includes("nightly")) {
    const cb = extractBaseVersion(cur.version);
    const nb = extractBaseVersion(nightly.version);
    return isNewerVersion(cb, nb) || cb === nb;
  }
  const c = parseInt(cur.buildNumber, 10);
  const n = parseInt(nightly.buildNumber, 10);
  if (!Number.isNaN(c) && !Number.isNaN(n)) return n > c;
  return isNewerNightly(cur.version, nightly.version);
}

/** Reads version and build from the release body that nightly.js writes ("**Version**: `x+build`"). */
export function infoFromRelease(json: any, isNightly: boolean): UpdateInfo {
  const tag: string = json.tag_name ?? "";
  const name: string = json.name ?? tag;
  const body: string = json.body ?? "";
  const lower = body.toLowerCase();
  const asset = (json.assets ?? []).find((a: any) => String(a.name).endsWith(".apk"));
  const apkUrl: string = asset?.browser_download_url ?? "";
  const buildDate = Date.parse(json.published_at ?? "") || Date.now();

  let version: string;
  let buildNumber = "";
  if (isNightly && tag.startsWith("nightly-")) {
    const full =
      lower.match(/\*\*version\*\*:\s*`([^`]+)`/)?.[1] ??
      lower.match(/version:\s*(\S+)/)?.[1] ??
      lower.slice(lower.indexOf("-") + 1).match(/\*\*version\*\*:\s*`([^`]+)`/)?.[1];
    if (full) {
      [version, buildNumber = ""] = full.split("+");
    } else {
      const base = lower.match(/\*\*base version\*\*:\s*`([^`]+)`/)?.[1] ?? "0.0.2";
      version = `${base}-nightly-${tag.slice("nightly-".length)}`;
      buildNumber = String(Math.floor(buildDate / 1000));
    }
  } else {
    version = tag.startsWith("v") ? tag.slice(1) : tag;
    const loose = lower.match(/version[:\s]+`?([^`\s]+)/)?.[1];
    if (loose && loose.length > version.length) version = loose;
    buildNumber = lower.match(/build number[:\s]+`?(\d+)/)?.[1] ?? name.toLowerCase().match(/build\s*(\d+)/)?.[1] ?? "";
  }
  return {
    version, buildNumber, buildDate, apkUrl,
    apkFileName: apkUrl.split("/").pop() ?? "",
    changelog: body, isNightly, fileSizeBytes: asset?.size ?? 0,
  };
}

const newest = (releases: any[], pick: (tag: string) => boolean) =>
  releases
    .filter((r) => pick(r.tag_name ?? "") && Date.parse(r.published_at))
    .sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at))[0];

export function checkRelease(releases: any[], cur: AppVersion): UpdateCheck {
  const r = newest(releases, (t) => (t.startsWith("v") || /^\d+\.\d+/.test(t)) && !t.includes("nightly"));
  if (!r) return { hasUpdate: false, isNightly: false, error: "No stable releases found" };
  const info = infoFromRelease(r, false);
  const hasUpdate = isNewerVersion(cur.version, info.version);
  return { hasUpdate, isNightly: false, info: hasUpdate ? info : undefined };
}

export function checkNightly(releases: any[], cur: AppVersion): UpdateCheck {
  const r = newest(releases, (t) => t.startsWith("nightly-"));
  if (!r) return { hasUpdate: false, isNightly: true, error: "No nightly releases found" };
  const info = infoFromRelease(r, true);
  const hasUpdate = shouldUpdateToNightly(cur, info);
  return { hasUpdate, isNightly: true, info: hasUpdate ? info : undefined };
}

export const currentVersion = (): AppVersion => ({
  version: Application.nativeApplicationVersion ?? "0.0.2",
  buildNumber: Application.nativeBuildVersion ?? "1",
});

let checking = false;

export async function checkForUpdates(force = false): Promise<UpdateCheck> {
  if (checking) return { hasUpdate: false, isNightly: false, error: "Update check already in progress" };
  checking = true;
  try {
    const last = Number((await Storage.getItem("last_update_check")) ?? 0);
    if (!force && Date.now() - last < 24 * HOUR) return { hasUpdate: false, isNightly: false, error: "Too soon since last check" };

    const cur = currentVersion();
    // A nightly install always follows nightlies unless the user explicitly turned them off.
    const stored = await Storage.getItem("enable_nightly");
    const useNightly = stored === null ? isNightlyVersion(cur.version) : stored === "1";

    const res = await fetch(RELEASES_API, { headers: { accept: "application/vnd.github+json" } });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const releases = await res.json();
    await Storage.setItem("last_update_check", String(Date.now()));

    const nightly = useNightly ? checkNightly(releases, cur) : undefined;
    if (nightly?.hasUpdate) return nightly;
    const stable = checkRelease(releases, cur);
    return stable.hasUpdate ? stable : { hasUpdate: false, isNightly: false };
  } catch (e) {
    return { hasUpdate: false, isNightly: false, error: `Error checking for updates: ${e}` };
  } finally {
    checking = false;
  }
}

export const getNightlyPref = async () => {
  const s = await Storage.getItem("enable_nightly");
  return s === null ? isNightlyVersion(currentVersion().version) : s === "1";
};
export const setNightlyPref = (v: boolean) => Storage.setItem("enable_nightly", v ? "1" : "0");

/** Downloads (reusing a complete earlier download) and opens the system installer. */
export async function downloadAndInstall(info: UpdateInfo, onProgress?: (p: number) => void): Promise<void> {
  const path = `${FileSystem.cacheDirectory}${info.apkFileName}`;
  const existing = await FileSystem.getInfoAsync(path);
  if (!(existing.exists && info.fileSizeBytes > 0 && existing.size === info.fileSizeBytes)) {
    const dl = FileSystem.createDownloadResumable(info.apkUrl, path, {}, (p) =>
      onProgress?.(p.totalBytesExpectedToWrite ? p.totalBytesWritten / p.totalBytesExpectedToWrite : 0),
    );
    const out = await dl.downloadAsync();
    if (!out || out.status !== 200) throw new Error(`Failed to download update: HTTP ${out?.status}`);
  }
  await IntentLauncher.startActivityAsync("android.intent.action.VIEW", {
    data: await FileSystem.getContentUriAsync(path),
    flags: 1,
    type: "application/vnd.android.package-archive",
  });
}
