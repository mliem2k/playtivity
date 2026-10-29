import CookieManager from "@preeternal/react-native-cookie-manager";
import { router } from "expo-router";
import { useRef, useState } from "react";
import { ActivityIndicator, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { WebView, type WebViewNavigation } from "react-native-webview";
import { useAuth } from "@/lib/auth";
import { UA } from "@/lib/spotify";

const LOGIN = "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F";
const BLOCKED = ["/login", "/auth", "/challenge", "/error"];
const eligible = (url: string) => url.includes("open.spotify.com") && !BLOCKED.some((b) => url.includes(b));

export default function Login() {
  const signIn = useAuth((s) => s.signIn);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const done = useRef(false);

  // sp_dc is httpOnly, so it is read from the native cookie store. The SPA may commit it a moment
  // after navigation, hence the bounded retry.
  const capture = async () => {
    for (let i = 0; i < 8 && !done.current; i++) {
      const cookies = await CookieManager.get("https://open.spotify.com", true);
      const spDc = cookies.sp_dc?.value;
      if (spDc) {
        done.current = true;
        setBusy(true);
        if (await signIn(spDc)) router.dismissAll();
        else {
          done.current = false;
          setBusy(false);
          setError("Spotify rejected the session. Try again.");
        }
        return;
      }
      await new Promise((r) => setTimeout(r, 1000));
    }
  };

  const onNav = (n: WebViewNavigation) => {
    if (!n.loading && eligible(n.url)) capture();
  };

  return (
    <SafeAreaView className="flex-1 bg-bg">
      {busy ? (
        <View className="flex-1 items-center justify-center gap-3">
          <ActivityIndicator color="#1DB954" />
          <Text className="text-muted">Signing in</Text>
        </View>
      ) : (
        <>
          {error ? <Text className="p-3 text-danger">{error}</Text> : null}
          <WebView source={{ uri: LOGIN }} userAgent={UA} onNavigationStateChange={onNav} sharedCookiesEnabled thirdPartyCookiesEnabled />
        </>
      )}
    </SafeAreaView>
  );
}
