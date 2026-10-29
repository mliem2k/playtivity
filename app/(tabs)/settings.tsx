import Constants from "expo-constants";
import { useEffect, useState } from "react";
import { Pressable, Switch, Text, View } from "react-native";
import { useAuth } from "@/lib/auth";
import { checkForUpdates, currentVersion, downloadAndInstall, getNightlyPref, setNightlyPref, type UpdateInfo } from "@/lib/update";

export default function Settings() {
  const { user, signOut } = useAuth();
  const [nightly, setNightly] = useState(false);
  const [status, setStatus] = useState("");
  const [update, setUpdate] = useState<UpdateInfo | null>(null);
  const [busy, setBusy] = useState(false);
  const v = currentVersion();

  useEffect(() => {
    getNightlyPref().then(setNightly);
  }, []);

  const check = async () => {
    setBusy(true);
    setStatus("Checking");
    const r = await checkForUpdates(true);
    setUpdate(r.info ?? null);
    setStatus(r.error ?? (r.hasUpdate ? `Update available: ${r.info?.version}` : "You are up to date"));
    setBusy(false);
  };

  const install = async () => {
    if (!update) return;
    setBusy(true);
    try {
      await downloadAndInstall(update, (p) => setStatus(`Downloading ${Math.round(p * 100)}%`));
      setStatus("Installer opened");
    } catch (e) {
      setStatus(String(e));
    }
    setBusy(false);
  };

  return (
    <View className="flex-1 gap-4 bg-bg p-4">
      <Text className="text-muted">Signed in as {user?.displayName ?? "unknown"}</Text>

      <View className="flex-row items-center justify-between">
        <Text className="text-white">Include nightly builds</Text>
        <Switch
          value={nightly}
          onValueChange={(on) => {
            setNightly(on);
            setNightlyPref(on);
          }}
          trackColor={{ true: "#1DB954" }}
        />
      </View>

      <Pressable disabled={busy} className="rounded-full bg-elevated py-3" onPress={check}>
        <Text className="text-center font-semibold text-white">Check for updates</Text>
      </Pressable>
      {status ? <Text className="text-muted">{status}</Text> : null}
      {update ? (
        <Pressable disabled={busy} className="rounded-full bg-primary py-3" onPress={install}>
          <Text className="text-center font-semibold text-black">Download and install</Text>
        </Pressable>
      ) : null}

      <Pressable className="rounded-full bg-danger py-3" onPress={signOut}>
        <Text className="text-center font-semibold text-white">Sign out</Text>
      </Pressable>
      <Text className="text-xs text-subdued">
        Playtivity {v.version} ({v.buildNumber}) · Expo {Constants.expoVersion ?? ""}
      </Text>
    </View>
  );
}
