import { MaterialIcons } from "@expo/vector-icons";
import { memo } from "react";
import { Linking, Pressable, Text, View } from "react-native";
import { timeAgo } from "@/lib/format";
import { spotifyUrl, type Activity, type Playlist } from "@/lib/spotify";
import { colors } from "@/theme";
import { Art, Avatar, Equalizer, tap } from "./ui";

function playlistSubtitle(p: Playlist) {
  const owner = p.ownerName || null;
  const count = p.trackCount > 0 ? `${p.trackCount} tracks` : null;
  if (owner && count) return `${owner} · ${count}`;
  return owner ?? (count ? `Playlist · ${count}` : "Playlist");
}

function ActivityCardView({ a }: { a: Activity }) {
  const title = a.track?.name ?? a.playlist?.name;
  const subtitle = a.track ? `${a.track.artists.join(", ")} · ${a.track.album}` : a.playlist ? playlistSubtitle(a.playlist) : "";
  const uri = a.track?.uri ?? a.playlist?.uri ?? "";

  return (
    <Pressable
      android_ripple={{ color: "#ffffff14" }}
      style={{ flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 12 }}
      onPress={() => {
        tap();
        Linking.openURL(spotifyUrl(uri));
      }}
    >
      <Pressable
        onPress={() => {
          tap();
          Linking.openURL(spotifyUrl(`spotify:user:${a.user.id}`));
        }}
      >
        <Avatar uri={a.user.imageUrl} name={a.user.displayName} radius={22} />
      </Pressable>

      <View style={{ flex: 1, marginHorizontal: 12 }}>
        <Text className="font-mont-sb text-white" style={{ fontSize: 14 }} numberOfLines={1}>{a.user.displayName}</Text>
        <View style={{ flexDirection: "row", alignItems: "center", marginTop: 2 }}>
          {a.playing ? (
            <>
              <Equalizer size={12} />
              <Text className="font-mont-md" style={{ marginLeft: 4, fontSize: 11, letterSpacing: 1, color: colors.primaryActive }}>Listening now</Text>
            </>
          ) : (
            <>
              <MaterialIcons name="history" size={12} color={colors.textSecondary} />
              <Text className="font-mont-md text-muted" style={{ marginLeft: 4, fontSize: 11, letterSpacing: 1 }}>{timeAgo(a.timestamp)}</Text>
            </>
          )}
        </View>
        {title ? (
          <>
            <Text className="font-mont-md text-white" style={{ fontSize: 14, marginTop: 4 }} numberOfLines={1}>{title}</Text>
            <Text className="font-mont text-muted" style={{ fontSize: 13, marginTop: 2 }} numberOfLines={1}>{subtitle}</Text>
          </>
        ) : null}
      </View>

      <View>
        <Art uri={a.track?.imageUrl ?? a.playlist?.imageUrl} size={48} />
        {a.playing ? (
          <View pointerEvents="none" style={{ position: "absolute", inset: 0, borderRadius: 4, borderWidth: 2, borderColor: colors.primaryActive }} />
        ) : null}
      </View>
    </Pressable>
  );
}

/** Rows are memoised: the feed refetches every 30 seconds and most entries come back unchanged. */
export const ActivityCard = memo(ActivityCardView);
