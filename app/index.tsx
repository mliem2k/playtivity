import { MaterialCommunityIcons, MaterialIcons } from "@expo/vector-icons";
import { useEffect, useRef, useState } from "react";
import { Pressable, Text, View } from "react-native";
import PagerView from "react-native-pager-view";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useAuth } from "@/lib/auth";
import { hapticSelect } from "@/lib/haptics";
import { useUpdate } from "@/lib/updateStore";
import { ActivitiesScreen, type ScrollTop } from "@/screens/ActivitiesScreen";
import { ProfileScreen } from "@/screens/ProfileScreen";
import { colors } from "@/theme";

const ITEMS = [{ label: "Activities" }, { label: "Profile" }];

/** Two swipeable pages with the Spotify style bottom bar; tapping the active item scrolls to top. */
export default function Main() {
  const pager = useRef<PagerView>(null);
  // Three flat pages: Activities, Top Songs, Top Artists. The two profile tabs share one bottom bar item.
  const pages = [useRef<ScrollTop>(null), useRef<ScrollTop>(null), useRef<ScrollTop>(null)];
  const [index, setIndex] = useState(0);
  const insets = useSafeAreaInsets();
  useEffect(() => {
    useUpdate.getState().checkOnStart().catch(() => {});
    useAuth.getState().reloadUser();
  }, []);

  const barIndex = index === 0 ? 0 : 1;

  const press = (i: number) => {
    hapticSelect();
    if (i === barIndex) pages[index].current?.scrollToTop();
    else pager.current?.setPage(i === 0 ? 0 : 1);
  };

  return (
    <View className="flex-1 bg-bg">
      <PagerView ref={pager} style={{ flex: 1 }} initialPage={0} onPageSelected={(e) => setIndex(e.nativeEvent.position)}>
        <View key="activities" style={{ flex: 1 }}><ActivitiesScreen ref={pages[0]} /></View>
        <View key="songs" style={{ flex: 1 }}><ProfileScreen ref={pages[1]} tab={0} onTab={(t) => pager.current?.setPage(1 + t)} /></View>
        <View key="artists" style={{ flex: 1 }}><ProfileScreen ref={pages[2]} tab={1} onTab={(t) => pager.current?.setPage(1 + t)} /></View>
      </PagerView>
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
