import { Alert } from "react-native";
import { currentVersion, type UpdateInfo } from "./update";
import { useUpdate } from "./updateStore";

function offer(info: UpdateInfo) {
  const cur = currentVersion();
  const warn = info.isNightly ? "\n\nNightly builds may contain bugs or incomplete features." : "";
  Alert.alert(
    info.isNightly ? "Nightly Update Available" : "Update Available",
    `A new ${info.isNightly ? "nightly" : "release"} version is available!\n\nCurrent: ${cur.version}+${cur.buildNumber}\n${info.isNightly ? "Latest Nightly" : "Latest Release"}: ${info.version}+${info.buildNumber}${warn}`,
    [
      { text: "Later", style: "cancel" },
      { text: "Update Now", onPress: () => useUpdate.getState().install() },
    ],
  );
}

/** Forced update check with the same dialogs the Flutter app showed; the banner then shows the download. */
export async function runUpdateCheck() {
  const { info, error } = await useUpdate.getState().check();
  if (error) return Alert.alert("Error checking for updates", error);
  if (info) return offer(info);
  Alert.alert("Up to date", "You're running the latest version!");
}
