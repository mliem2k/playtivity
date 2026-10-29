import "../global.css";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Redirect, Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
import { useAuth } from "@/lib/auth";

const client = new QueryClient();

export default function Root() {
  const { ready, spDc, init } = useAuth();
  useEffect(() => {
    init();
  }, [init]);

  if (!ready)
    return (
      <View className="flex-1 items-center justify-center bg-bg">
        <ActivityIndicator color="#1DB954" />
      </View>
    );

  return (
    <QueryClientProvider client={client}>
      <StatusBar style="light" />
      <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: "#121212" } }}>
        <Stack.Screen name="login" />
        <Stack.Screen name="(tabs)" />
      </Stack>
      <Redirect href={spDc ? "/(tabs)" : "/login"} />
    </QueryClientProvider>
  );
}
