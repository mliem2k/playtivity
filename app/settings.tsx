import { MaterialIcons } from "@expo/vector-icons";
import * as Haptics from "expo-haptics";
import { LinearGradient } from "expo-linear-gradient";
import { router } from "expo-router";
import { useEffect, useState } from "react";
import { Alert, Linking, Pressable, ScrollView, Switch, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { Avatar, Divider, SectionHeader, type IconName } from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { currentVersion, getNightlyPref, setNightlyPref } from "@/lib/update";
import { runUpdateCheck } from "@/lib/updateUi";
import { colors } from "@/theme";

function Tile({ icon, title, subtitle, onPress, trailing, danger }: { icon: IconName; title: string; subtitle?: string; onPress?: () => void; trailing?: React.ReactNode; danger?: boolean }) {
  const right = trailing ?? (onPress && !danger ? <MaterialIcons name="chevron-right" size={20} color={colors.textSubdued} /> : null);
  return (
    <Pressable
      disabled={!onPress}
      android_ripple={{ color: "#ffffff14" }}
      onPress={() => {
        Haptics.selectionAsync();
        onPress?.();
      }}
      style={{ flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 12 }}
    >
      <MaterialIcons name={icon} size={22} color={danger ? colors.errorRed : colors.textSecondary} />
      <View style={{ flex: 1, marginLeft: 16 }}>
        <Text className={danger ? "font-mont-b" : "font-mont-md"} style={{ fontSize: 14, color: danger ? colors.errorRed : colors.textPrimary }}>{title}</Text>
        {subtitle ? <Text className="font-mont text-muted" style={{ fontSize: 13, marginTop: 2 }}>{subtitle}</Text> : null}
      </View>
      {right}
    </Pressable>
  );
}

export default function Settings() {
  const { user, signOut } = useAuth();
  const [nightly, setNightly] = useState<boolean | null>(null);
  useEffect(() => {
    getNightlyPref().then(setNightly);
  }, []);

  const toggleNightly = (on: boolean) => {
    setNightly(on);
    setNightlyPref(on);
    if (on)
      Alert.alert("Nightly Builds Enabled", "You will now be offered nightly builds, which can be unstable. Check for updates now?", [
        { text: "OK", style: "cancel" },
        { text: "Check Now", onPress: runUpdateCheck },
      ]);
  };

  const logout = () =>
    Alert.alert("Logout", "Are you sure you want to logout from your Spotify account?", [
      { text: "Cancel", style: "cancel" },
      { text: "Logout", style: "destructive", onPress: () => signOut() },
    ]);

  const v = currentVersion();

  return (
    <SafeAreaView edges={["top"]} className="flex-1 bg-bg">
      <View style={{ height: 56, flexDirection: "row", alignItems: "center", paddingHorizontal: 4 }}>
        <Pressable onPress={() => router.back()} style={{ padding: 12 }} accessibilityLabel="Back">
          <MaterialIcons name="arrow-back" size={24} color="#fff" />
        </Pressable>
        <Text className="font-mont-b text-white" style={{ fontSize: 22, marginLeft: 4 }}>Settings</Text>
      </View>
      <ScrollView overScrollMode="never">
        <LinearGradient colors={[colors.primary, colors.background]} locations={[0, 0.7]}>
          <View style={{ flexDirection: "row", alignItems: "center", padding: 24, paddingHorizontal: 16 }}>
            <Avatar uri={user?.imageUrl} name={user?.displayName ?? ""} radius={40} bg={colors.surfaceElevated} />
            <View style={{ flex: 1, marginLeft: 16 }}>
              <Text className="font-mont-xb text-white" style={{ fontSize: 20 }} numberOfLines={1}>{user?.displayName ?? "Unknown User"}</Text>
              {user?.email ? <Text className="font-mont text-muted" style={{ fontSize: 13, marginTop: 4 }} numberOfLines={1}>{user.email}</Text> : null}
            </View>
            {user ? (
              <Pressable onPress={() => Linking.openURL(`https://open.spotify.com/user/${user.id}`)} style={{ padding: 8 }} accessibilityLabel="Open Spotify profile">
                <MaterialIcons name="open-in-new" size={20} color={colors.textSecondary} />
              </Pressable>
            ) : null}
          </View>
        </LinearGradient>

        <SectionHeader label="ACCOUNT" />
        <Tile icon="public" title="Country" subtitle={user?.country} />
        <Divider indent={56} />

        <SectionHeader label="UPDATES" />
        <Tile
          icon={nightly ? "science" : "update"}
          title="Nightly Builds"
          subtitle="Get early access to new features (may be unstable)"
          trailing={nightly === null ? undefined : <Switch value={nightly} onValueChange={toggleNightly} trackColor={{ true: colors.primary }} />}
        />
        <Divider indent={56} />
        <Tile icon="system-update" title="Check for Updates" subtitle="Look for new versions of the app" onPress={runUpdateCheck} />

        <SectionHeader label="ABOUT" />
        <Tile icon="info-outline" title="Playtivity" subtitle={`Version ${v.version}`} />
        <Divider indent={56} />
        <Tile icon="open-in-browser" title="GitHub Releases" subtitle="View all releases and download APKs" onPress={() => Linking.openURL("https://github.com/mliem2k/playtivity/releases")} />
        <Divider indent={56} />
        <Tile icon="music-note" title="About" subtitle="See what your friends are listening to on Spotify" />

        <View style={{ height: 32 }} />
        <Tile icon="logout" title="Log Out" danger onPress={logout} />
        <View style={{ height: 16 }} />
      </ScrollView>
    </SafeAreaView>
  );
}
