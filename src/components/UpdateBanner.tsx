import { MaterialIcons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useUpdate } from "@/lib/updateStore";
import { colors } from "@/theme";

/** Top banner like the Flutter one: orange for a nightly, green for a release, with download progress. */
export function UpdateBanner() {
  const { info, phase, progress, error, install, dismiss } = useUpdate();
  if (!info) return null;
  const busy = phase === "downloading";
  const label =
    phase === "downloading" ? `Downloading ${Math.round(progress * 100)}%`
    : phase === "installing" ? "Opening the installer"
    : phase === "error" ? `Update failed: ${error}`
    : info.isNightly ? `New nightly build available: ${info.version}` : `Update available: ${info.version}`;

  return (
    <View style={{ backgroundColor: info.isNightly ? "#F57C00" : colors.primary }}>
      <SafeAreaView edges={["top"]}>
        <View style={{ flexDirection: "row", alignItems: "center", paddingVertical: 8, paddingHorizontal: 16, gap: 8 }}>
          <MaterialIcons name={info.isNightly ? "science" : "system-update"} size={22} color="#fff" />
          <Text className="flex-1 font-mont-md text-white" style={{ fontSize: 12 }} numberOfLines={2}>{label}</Text>
          {!busy ? (
            <Pressable onPress={install} style={{ backgroundColor: "#ffffff33", borderRadius: 6, paddingHorizontal: 12, paddingVertical: 6 }}>
              <Text className="font-mont-sb text-white" style={{ fontSize: 12 }}>{phase === "error" ? "Retry" : "Update"}</Text>
            </Pressable>
          ) : null}
          <Pressable onPress={dismiss} hitSlop={8} accessibilityLabel="Dismiss">
            <MaterialIcons name="close" size={22} color="#fff" />
          </Pressable>
        </View>
        {busy ? <View style={{ height: 3, backgroundColor: "#ffffff33" }}><View style={{ height: 3, width: `${Math.round(progress * 100)}%`, backgroundColor: "#fff" }} /></View> : null}
      </SafeAreaView>
    </View>
  );
}
