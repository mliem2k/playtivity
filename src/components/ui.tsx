import { Image } from "expo-image";
import { Text, View } from "react-native";

export const Art = ({ uri, size = 48, round = false }: { uri?: string; size?: number; round?: boolean }) => (
  <Image
    source={uri ? { uri } : undefined}
    style={{ width: size, height: size, borderRadius: round ? size / 2 : 4 }}
    className="bg-elevated"
    contentFit="cover"
  />
);

export const Empty = ({ text }: { text: string }) => (
  <View className="flex-1 items-center justify-center p-8">
    <Text className="text-center text-muted">{text}</Text>
  </View>
);

export function ago(ms: number, now = Date.now()) {
  const m = Math.floor((now - ms) / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  if (m < 1440) return `${Math.floor(m / 60)}h ago`;
  return `${Math.floor(m / 1440)}d ago`;
}
