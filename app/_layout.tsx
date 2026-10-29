import "../global.css";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { useAuth } from "@/lib/auth";
import { usePrefs } from "@/lib/prefs";
import { colors } from "@/theme";

const client = new QueryClient();

export default function Root() {
  const { ready, spDc, init } = useAuth();
  useEffect(() => {
    init();
    usePrefs.getState().load();
  }, [init]);

  if (!ready)
    return (
      <View className="flex-1 items-center justify-center bg-bg">
        <ActivityIndicator color={colors.primary} />
      </View>
    );

  return (
    <QueryClientProvider client={client}>
      <StatusBar style="light" />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: colors.background } }}>
        <Stack.Protected guard={!!spDc}>
          <Stack.Screen name="index" />
          <Stack.Screen name="settings" />
        </Stack.Protected>
        <Stack.Protected guard={!spDc}>
          <Stack.Screen name="login" options={{ contentStyle: { backgroundColor: colors.login } }} />
          <Stack.Screen name="login-webview" />
        </Stack.Protected>
      </Stack>
    </QueryClientProvider>
  );
}
