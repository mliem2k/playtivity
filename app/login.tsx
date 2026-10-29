import { MaterialIcons } from "@expo/vector-icons";
import { Image } from "expo-image";
import { router } from "expo-router";
import { Pressable, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { colors } from "@/theme";
import { runUpdateCheck } from "@/lib/updateUi";

/** Landing screen: logo, tagline and a green stadium button that opens the Spotify web login. */
export default function Login() {
  return (
    <SafeAreaView className="flex-1" style={{ backgroundColor: colors.login }}>
      <View style={{ alignItems: "flex-end", padding: 8 }}>
        <Pressable onPress={runUpdateCheck} style={{ padding: 8 }} accessibilityLabel="Check for Updates">
          <MaterialIcons name="system-update" size={24} color={colors.textSecondary} />
        </Pressable>
      </View>
      <View style={{ flex: 1, paddingHorizontal: 32 }}>
        <View style={{ flex: 2 }} />
        <View style={{ alignItems: "center" }}>
          <Image source={require("../assets/images/playtivity_logo.png")} style={{ width: 120, height: 120, borderRadius: 20 }} contentFit="contain" />
        </View>
        <Text className="mt-8 text-center font-mont-xb text-white" style={{ fontSize: 32, letterSpacing: -0.5 }}>Playtivity</Text>
        <Text className="mt-3 text-center font-mont text-muted" style={{ fontSize: 16 }}>See what your friends are listening to</Text>
        <View style={{ flex: 3 }} />
        <Pressable
          onPress={() => router.push("/login-webview")}
          className="flex-row items-center justify-center rounded-full bg-primary"
          style={{ height: 56, gap: 10 }}
        >
          <Image source={require("../assets/images/playtivity_logo_button_icon.png")} style={{ width: 20, height: 20 }} tintColor={colors.onPrimary} />
          <Text className="font-mont-b" style={{ fontSize: 16, color: colors.onPrimary }}>Log in with Spotify</Text>
        </Pressable>
        <Text className="mt-6 text-center font-mont" style={{ fontSize: 12, color: colors.textSubdued }}>Playtivity uses your Spotify account</Text>
        <View style={{ flex: 1 }} />
      </View>
    </SafeAreaView>
  );
}
