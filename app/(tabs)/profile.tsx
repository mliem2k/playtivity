import { ScrollView, Text, View } from "react-native";
import { Art, Empty } from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { useTop } from "@/lib/queries";

export default function Profile() {
  const user = useAuth((s) => s.user);
  const { data, isLoading } = useTop();
  if (isLoading) return <Empty text="Loading" />;
  return (
    <ScrollView className="bg-bg" contentContainerClassName="p-4 gap-6">
      <View className="items-center gap-2">
        <Art uri={user?.imageUrl} size={96} round />
        <Text className="text-xl font-bold text-white">{user?.displayName ?? "You"}</Text>
      </View>
      <View className="gap-2">
        <Text className="text-lg font-bold text-white">Top tracks</Text>
        {data?.tracks.map((t, i) => (
          <View key={`${t.uri}${i}`} className="flex-row items-center gap-3">
            <Art uri={t.imageUrl} size={44} />
            <View className="flex-1">
              <Text className="text-white" numberOfLines={1}>{t.name}</Text>
              <Text className="text-xs text-muted" numberOfLines={1}>{t.artists.join(", ")}</Text>
            </View>
          </View>
        ))}
      </View>
      <View className="gap-2">
        <Text className="text-lg font-bold text-white">Top artists</Text>
        {data?.artists.map((a, i) => (
          <View key={`${a.uri}${i}`} className="flex-row items-center gap-3">
            <Art uri={a.imageUrl} size={44} round />
            <Text className="flex-1 text-white" numberOfLines={1}>{a.name}</Text>
          </View>
        ))}
      </View>
    </ScrollView>
  );
}
