import { Alert } from "react-native";
import { checkForUpdates, currentVersion, downloadAndInstall, type UpdateInfo } from "./update";

function offer(info: UpdateInfo) {
  const cur = currentVersion();
  const kind = info.isNightly ? "nightly" : "release";
  const warn = info.isNightly ? "\n\nNightly builds may contain bugs or incomplete features." : "";
  Alert.alert(
    info.isNightly ? "Nightly Update Available" : "Update Available",
    `A new ${kind} version is available!\n\nCurrent: ${cur.version}+${cur.buildNumber}\n${info.isNightly ? "Latest Nightly" : "Latest Release"}: ${info.version}+${info.buildNumber}${warn}`,
    [
      { text: "Later", style: "cancel" },
      {
        text: "Update Now",
        onPress: () =>
          downloadAndInstall(info).catch((e) => Alert.alert("Download failed", String(e))),
      },
    ],
  );
}

/** Forced update check with the same dialogs the Flutter app showed. */
export async function runUpdateCheck() {
  const r = await checkForUpdates(true);
  if (r.error) return Alert.alert("Error checking for updates", r.error);
  if (r.hasUpdate && r.info) return offer(r.info);
  Alert.alert("Up to date", "You're running the latest version!");
}
