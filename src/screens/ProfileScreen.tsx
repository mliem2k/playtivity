import { MaterialIcons } from "@expo/vector-icons";
import { LinearGradient } from "expo-linear-gradient";
import { router } from "expo-router";
import { forwardRef, useImperativeHandle, useRef } from "react";
import { Linking, Pressable, RefreshControl, ScrollView, type ScrollViewInstance, Text, View } from "react-native";
import type { SharedValue } from "react-native-reanimated";
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

/** Height of the tab bar, the part of the header that stays pinned once the rest scrolls away. */
export const TAB_BAR_H = 48;

/**
 * Gradient header, mini player and the Top Songs / Top Artists tab bar. It is drawn once, above the pager, so a
 * swipe between the two tabs moves only the list underneath it.
 */
export function ProfileHeader({ tab, onTab }: { tab: 0 | 1; onTab: (tab: 0 | 1) => void }) {
  const user = useAuth((s) => s.user);
  const playing = useCurrentlyPlaying().data;
  return (
    <View>
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

      <View style={{ flexDirection: "row", backgroundColor: colors.background, height: TAB_BAR_H }}>
        {TABS.map((label, i) => (
          <Pressable key={label} onPress={() => onTab(i as 0 | 1)} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
            <Text className={tab === i ? "font-mont-sb text-white" : "font-mont text-muted"} style={{ fontSize: 13 }}>{label}</Text>
            {tab === i ? <View style={{ position: "absolute", bottom: 0, height: 2, width: 72, backgroundColor: colors.primary }} /> : null}
          </Pressable>
        ))}
      </View>
    </View>
  );
}

/** One tab's list. It leaves room for the header above it and reports its scroll offset so the header can collapse. */
export const ProfileList = forwardRef<ScrollTop, { tab: 0 | 1; headerHeight: number; scrollY: SharedValue<number> }>(function ProfileList({ tab, headerHeight, scrollY }, ref) {
  const scroll = useRef<ScrollViewInstance>(null);
  useImperativeHandle(ref, () => ({
    scrollToTop: () => scroll.current?.scrollTo({ y: 0, animated: true }),
    scrollTo: (y: number) => scroll.current?.scrollTo({ y, animated: false }),
  }));
  const { data, isLoading, isRefetching, refetch, error } = useTop();
  const listeners = useArtistListeners(data?.artists).data;
  const items = tab === 0 ? data?.tracks : data?.artists;

  let content: React.ReactNode;
  if (isLoading) content = Array.from({ length: 10 }, (_, i) => <SkeletonRow key={i} />);
  else if (error && !items?.length) content = <StateDisplay icon="error-outline" title="Could not load" subtitle={error.message} buttonText="Try again" onAction={() => refetch()} />;
  else if (!items?.length) content = <StateDisplay icon={tab === 0 ? "music-note" : "person-outline"} title={tab === 0 ? "No top songs found" : "No top artists found"} buttonText="Refresh" onAction={() => refetch()} />;
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
    <ScrollView
      ref={scroll}
      overScrollMode="never"
      scrollEventThrottle={16}
      onScroll={(e) => {
        scrollY.value = e.nativeEvent.contentOffset.y;
      }}
      contentContainerStyle={{ paddingTop: headerHeight }}
      refreshControl={<RefreshControl refreshing={isRefetching} onRefresh={() => { refetch(); }} progressViewOffset={headerHeight} colors={[colors.primary]} progressBackgroundColor={colors.surfaceRaised} />}
    >
      {content}
    </ScrollView>
  );
});
