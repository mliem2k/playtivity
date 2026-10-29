import { MaterialCommunityIcons, MaterialIcons } from "@expo/vector-icons";
import { useEffect, useRef, useState } from "react";
import { Pressable, Text, useWindowDimensions, View } from "react-native";
import PagerView from "react-native-pager-view";
import Animated, { useAnimatedStyle, useSharedValue } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useAuth } from "@/lib/auth";
import { hapticSelect } from "@/lib/haptics";
import { useUpdate } from "@/lib/updateStore";
import { ActivitiesScreen, type ScrollTop } from "@/screens/ActivitiesScreen";
import { ProfileHeader, ProfileList, TAB_BAR_H } from "@/screens/ProfileScreen";
import { colors } from "@/theme";

const ITEMS = [{ label: "Activities" }, { label: "Profile" }];

/**
 * Three flat pages: Activities, Top Songs, Top Artists. The profile header is not part of those pages; it is drawn
 * once above the pager and slides in as you leave Activities, so a swipe between the two tabs moves only the list.
 */
export default function Main() {
  const pager = useRef<PagerView>(null);
  const pages = [useRef<ScrollTop>(null), useRef<ScrollTop>(null), useRef<ScrollTop>(null)];
  const [index, setIndex] = useState(0);
  const [headerH, setHeaderH] = useState(0);
  const { width } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const x = useSharedValue(0); // continuous pager position: 0 Activities, 1 Top Songs, 2 Top Artists
  const scrollY = useSharedValue(0); // vertical offset of the visible list
  const barIndex = index === 0 ? 0 : 1;
  const collapse = Math.max(0, headerH - TAB_BAR_H);

  useEffect(() => {
    useUpdate.getState().checkOnStart().catch(() => {});
    useAuth.getState().reloadUser();
  }, []);

  const press = (i: number) => {
    hapticSelect();
    if (i === barIndex) pages[index].current?.scrollToTop();
    else pager.current?.setPage(i === 0 ? 0 : 1);
  };

  const headerStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: width * Math.max(0, 1 - x.value) }, { translateY: -Math.min(scrollY.value, collapse) }],
  }));

  return (
    <View className="flex-1 bg-bg">
      <View style={{ flex: 1 }}>
        <PagerView
          ref={pager}
          style={{ flex: 1 }}
          initialPage={0}
          onPageScroll={(e) => {
            x.value = e.nativeEvent.position + e.nativeEvent.offset;
          }}
          onPageSelected={(e) => {
            const p = e.nativeEvent.position;
            setIndex(p);
            // The other list may sit at a different offset; match it to the header's collapse state.
            if (p > 0) pages[p].current?.scrollTo?.(Math.min(scrollY.value, collapse));
          }}
        >
          <View key="activities" style={{ flex: 1 }}><ActivitiesScreen ref={pages[0]} /></View>
          <View key="songs" style={{ flex: 1 }}><ProfileList ref={pages[1]} tab={0} headerHeight={headerH} scrollY={scrollY} /></View>
          <View key="artists" style={{ flex: 1 }}><ProfileList ref={pages[2]} tab={1} headerHeight={headerH} scrollY={scrollY} /></View>
        </PagerView>

        <Animated.View
          pointerEvents={index === 0 ? "none" : "box-none"}
          style={[{ position: "absolute", top: 0, left: 0, right: 0 }, headerStyle]}
          onLayout={(e) => setHeaderH(e.nativeEvent.layout.height)}
        >
          <ProfileHeader tab={index === 2 ? 1 : 0} onTab={(t) => pager.current?.setPage(1 + t)} />
        </Animated.View>
      </View>

      <View style={{ flexDirection: "row", backgroundColor: colors.login, paddingBottom: insets.bottom, height: 56 + insets.bottom }}>
        {ITEMS.map((it, i) => {
          const active = i === barIndex;
          const color = active ? colors.textPrimary : colors.textSecondary;
          return (
            <Pressable key={it.label} onPress={() => press(i)} style={{ flex: 1, alignItems: "center", justifyContent: "center", gap: 2 }}>
              {i === 0 ? (
                <MaterialCommunityIcons name={active ? "home" : "home-outline"} size={24} color={color} />
              ) : (
                <MaterialIcons name={active ? "person" : "person-outline"} size={24} color={color} />
              )}
              <Text className="font-mont-md" style={{ fontSize: 11, letterSpacing: 1, color }}>{it.label}</Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}
