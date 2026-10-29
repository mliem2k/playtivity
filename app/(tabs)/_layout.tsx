import { Tabs } from "expo-router";

export default function TabsLayout() {
  return (
    <Tabs
      screenOptions={{
        headerStyle: { backgroundColor: "#121212" },
        headerTintColor: "#fff",
        tabBarStyle: { backgroundColor: "#181818", borderTopColor: "#282828" },
        tabBarActiveTintColor: "#1DB954",
        tabBarInactiveTintColor: "#A7A7A7",
      }}
    >
      <Tabs.Screen name="index" options={{ title: "Friends" }} />
      <Tabs.Screen name="profile" options={{ title: "Profile" }} />
      <Tabs.Screen name="settings" options={{ title: "Settings" }} />
    </Tabs>
  );
}
