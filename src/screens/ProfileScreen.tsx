import { MaterialIcons } from "@expo/vector-icons";
import { Image } from "expo-image";
import { LinearGradient } from "expo-linear-gradient";
import { router } from "expo-router";
import { forwardRef, useImperativeHandle, useRef, useState } from "react";
import { Linking, Pressable, RefreshControl, ScrollView, type ScrollViewInstance, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { ArtistTile, CurrentlyPlayingCard, TrackTile } from "@/components/Tiles";
import { Avatar, Divider, SkeletonRow, StateDisplay } from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { hapticMedium } from "@/lib/haptics";
import { useArtistListeners, useCurrentlyPlaying, useTop } from "@/lib/queries";
import { lastSegment } from "@/lib/spotify";
import { colors } from "@/theme";
import type { ScrollTop } from "./ActivitiesScreen";

const TABS = ["Top Songs", "Top Artists"] as const;

/** Gradient header, mini player, and a pinned Top Songs / Top Artists tab bar. */
export const ProfileScreen = forwardRef<ScrollTop>(function ProfileScreen(_, ref) {
  const scroll = useRef<ScrollViewInstance>(null);
  useImperativeHandle(ref, () => ({ scrollToTop: () => scroll.current?.scrollTo({ y: 0, animated: true }) }));
  const user = useAuth((s) => s.user);
  const [tab, setTab] = useState(0);
  const { data, isLoading, isRefetching, refetch, error } = useTop();
  const playing = useCurrentlyPlaying().data;
  const listeners = useArtistListeners(data?.artists).data;

  const refresh = () => { refetch(); };
  const list = tab === 0 ? data?.tracks : data?.artists;

  let content: React.ReactNode;
  if (isLoading) content = Array.from({ length: 10 }, (_, i) => <SkeletonRow key={i} />);
  else if (error && !list?.length) content = <StateDisplay icon="error-outline" title="Could not load" subtitle={error.message} buttonText="Try again" onAction={() => refetch()} />;
  else if (!list?.length) content = <StateDisplay icon={tab === 0 ? "music-note" : "person-outline"} title={tab === 0 ? "No top songs found" : "No top artists found"} buttonText="Refresh" onAction={() => refetch()} />;
  else
    content = (
      <View style={{ paddingTop: 8, paddingBottom: 16 }}>
        {tab === 0
          ? data!.tracks.map((t, i) => (
              <View key={`${t.uri}${i}`}>
                {i > 0 ? <Divider /> : null}
                <TrackTile track={t} rank={i + 1} />
              </View>
            ))
          : data!.artists.map((a, i) => (
              <View key={`${a.uri}${i}`}>
                {i > 0 ? <Divider /> : null}
                <ArtistTile artist={a} rank={i + 1} listeners={listeners?.[lastSegment(a.uri)]} />
              </View>
            ))}
      </View>
    );

  return (
    <View className="flex-1 bg-bg">
      <ScrollView
        ref={scroll}
        stickyHeaderIndices={[1]}
        overScrollMode="never"
        refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={refresh} colors={[colors.primary]} progressBackgroundColor={colors.surfaceRaised} />}
      >
        <LinearGradient colors={[colors.primary, colors.background]} locations={[0, 0.7]}>
          <SafeAreaView edges={["top"]}>
            <View style={{ alignItems: "flex-end" }}>
              <Pressable
                style={{ padding: 12 }}
                onPress={() => {
                  hapticMedium();
                  router.push("/settings");
                }}
              >
                <MaterialIcons name="settings" size={24} color="#fff" />
              </Pressable>
            </View>
            <View style={{ alignItems: "center" }}>
              <Pressable onPress={() => user && Linking.openURL(`https://open.spotify.com/user/${user.id}`)}>
                <View style={{ borderRadius: 46, borderWidth: 2, borderColor: "#ffffff33" }}>
                  <Avatar uri={user?.imageUrl} name={user?.displayName ?? ""} radius={44} bg={colors.surfaceElevated} />
                </View>
              </Pressable>
              <Text className="mt-3 font-mont-xb text-white" style={{ fontSize: 24 }}>{user?.displayName ?? "Unknown User"}</Text>
              <Text className="mt-1 font-mont text-muted" style={{ fontSize: 13 }}>{user?.followers ?? 0} followers</Text>
            </View>
            {playing ? (
              <View style={{ paddingHorizontal: 16, marginTop: 16 }}>
                <CurrentlyPlayingCard track={playing} />
              </View>
            ) : null}
            <View style={{ height: 16 }} />
          </SafeAreaView>
        </LinearGradient>

        {/* The sticky header wrapper replaces its child's style, so the row lives one level down. */}
        <View style={{ backgroundColor: colors.background }}>
          <View style={{ flexDirection: "row" }}>
            {TABS.map((label, i) => (
              <Pressable key={label} onPress={() => setTab(i)} style={{ flex: 1, height: 48, alignItems: "center", justifyContent: "center" }}>
                <Text className={tab === i ? "font-mont-sb text-white" : "font-mont text-muted"} style={{ fontSize: 13 }}>{label}</Text>
                {tab === i ? <View style={{ position: "absolute", bottom: 0, height: 2, width: 72, backgroundColor: colors.primary }} /> : null}
              </Pressable>
            ))}
          </View>
        </View>

        {content}
      </ScrollView>
    </View>
  );
});
