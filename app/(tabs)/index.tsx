import { FlatList, Linking, Pressable, Text, View } from "react-native";
import { Art, Empty, ago } from "@/components/ui";
import { useActivities } from "@/lib/queries";
import { spotifyUrl, type Activity } from "@/lib/spotify";

function Row({ a }: { a: Activity }) {
  const title = a.track?.name ?? a.playlist?.name ?? "";
  const sub = a.track
    ? `${a.track.artists.join(", ")} · ${a.track.album}`
    : [a.playlist?.ownerName, a.playlist?.trackCount ? `${a.playlist.trackCount} tracks` : ""].filter(Boolean).join(" · ") || "Playlist";
  const uri = a.track?.uri ?? a.playlist?.uri ?? "";
  return (
    <Pressable className="flex-row items-center gap-3 px-4 py-3" onPress={() => Linking.openURL(spotifyUrl(uri))}>
      <Pressable onPress={() => Linking.openURL(spotifyUrl(`spotify:user:${a.user.id}`))}>
        <Art uri={a.user.imageUrl} size={44} round />
      </Pressable>
      <View className="flex-1">
        <Text className="text-base font-semibold text-white" numberOfLines={1}>{a.user.displayName}</Text>
        <Text className={`text-xs ${a.playing ? "text-primary" : "text-muted"}`}>{a.playing ? "Listening now" : ago(a.timestamp)}</Text>
        <Text className="mt-1 text-[15px] text-white" numberOfLines={1}>{title}</Text>
        <Text className="text-[13px] text-muted" numberOfLines={1}>{sub}</Text>
      </View>
      <View className={a.playing ? "rounded border-2 border-primary" : ""}>
        <Art uri={a.track?.imageUrl ?? a.playlist?.imageUrl} />
      </View>
    </Pressable>
  );
}

export default function Friends() {
  const { data, isLoading, isRefetching, refetch, error } = useActivities();
  if (isLoading) return <Empty text="Loading" />;
  if (error && !data?.length) return <Empty text={`Could not load friend activity.\n${String(error.message)}`} />;
  return (
    <FlatList
      className="bg-bg"
      data={data}
      keyExtractor={(a) => a.user.id}
      renderItem={({ item }) => <Row a={item} />}
      refreshing={isRefetching}
      onRefresh={refetch}
      ListEmptyComponent={<Empty text="No friend activity yet." />}
    />
  );
}
