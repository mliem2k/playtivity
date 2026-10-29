import { MaterialIcons } from "@expo/vector-icons";
import { Image } from "expo-image";
import { Linking, Pressable, Text, View } from "react-native";
import { formatCount, formatDuration } from "@/lib/format";
import { spotifyUrl, type Artist, type Track } from "@/lib/spotify";
import { colors } from "@/theme";
import { Art, Equalizer, tap } from "./ui";

const Rank = ({ n }: { n?: number }) =>
  n ? (
    <>
      <Text className="font-mont-md text-center" style={{ width: 24, fontSize: 14, color: colors.textSubdued }}>{n}</Text>
      <View style={{ width: 12 }} />
    </>
  ) : null;

export function TrackTile({ track, rank }: { track: Track; rank?: number }) {
  return (
    <Pressable
      android_ripple={{ color: "#ffffff14" }}
      style={{ flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 10 }}
      onPress={() => {
        tap();
        Linking.openURL(spotifyUrl(track.uri));
      }}
    >
      <Rank n={rank} />
      <Art uri={track.imageUrl} size={48} />
      <View style={{ flex: 1, marginHorizontal: 12 }}>
        <Text className="font-mont-md text-white" style={{ fontSize: 14 }} numberOfLines={1}>{track.name}</Text>
        <Text className="font-mont text-muted" style={{ fontSize: 13, marginTop: 3 }} numberOfLines={1}>{track.artists.join(", ")}</Text>
      </View>
      <Text className="font-mont-md" style={{ fontSize: 11, color: colors.textSubdued }}>{formatDuration(track.durationMs)}</Text>
    </Pressable>
  );
}

export function ArtistTile({ artist, rank, listeners }: { artist: Artist; rank?: number; listeners?: number }) {
  return (
    <Pressable
      android_ripple={{ color: "#ffffff14" }}
      style={{ flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 10 }}
      onPress={() => {
        tap();
        Linking.openURL(spotifyUrl(artist.uri));
      }}
    >
      <Rank n={rank} />
      <View style={{ width: 48, height: 48, borderRadius: 24, backgroundColor: colors.surfaceElevated, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
        {artist.imageUrl ? (
          <Image source={{ uri: artist.imageUrl }} style={{ width: 48, height: 48 }} contentFit="cover" recyclingKey={artist.imageUrl} />
        ) : (
          <MaterialIcons name="person" size={24} color={colors.textSubdued} />
        )}
      </View>
      <View style={{ flex: 1, marginLeft: 12 }}>
        <Text className="font-mont-md text-white" style={{ fontSize: 14 }} numberOfLines={1}>{artist.name}</Text>
        {listeners !== undefined && listeners >= 0 ? (
          <Text className="font-mont text-muted" style={{ fontSize: 12, marginTop: 3 }}>{formatCount(listeners)} monthly listeners</Text>
        ) : null}
      </View>
    </Pressable>
  );
}

/** Compact mini player strip shown under the profile header while something is playing. */
export function CurrentlyPlayingCard({ track }: { track: Track }) {
  return (
    <Pressable
      onPress={() => Linking.openURL("spotify:")}
      style={{ flexDirection: "row", alignItems: "center", padding: 12, backgroundColor: colors.surfaceRaised }}
    >
      <Art uri={track.imageUrl} size={40} />
      <View style={{ flex: 1, marginHorizontal: 12 }}>
        <Text className="font-mont-sb text-white" style={{ fontSize: 14 }} numberOfLines={1}>{track.name}</Text>
        <Text className="font-mont text-muted" style={{ fontSize: 13, marginTop: 2 }} numberOfLines={1}>{track.artists.join(", ")}</Text>
      </View>
      <Equalizer size={18} />
    </Pressable>
  );
}
