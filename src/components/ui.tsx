import { MaterialIcons } from "@expo/vector-icons";
import { Image } from "expo-image";
import { hapticLight } from "@/lib/haptics";
import { useEffect } from "react";
import { Pressable, Text, View } from "react-native";
import Animated, { Easing, useAnimatedStyle, useSharedValue, withDelay, withRepeat, withTiming } from "react-native-reanimated";
import { colors } from "@/theme";

export type IconName = React.ComponentProps<typeof MaterialIcons>["name"];

export const tap = () => hapticLight();

/** Rounded album art; a music note on elevated grey while there is no image. */
export const Art = ({ uri, size = 48 }: { uri?: string; size?: number }) => (
  <View style={{ width: size, height: size, borderRadius: 4, backgroundColor: colors.surfaceElevated, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
    {uri ? (
      <Image source={{ uri }} style={{ width: size, height: size }} contentFit="cover" cachePolicy="memory-disk" recyclingKey={uri} />
    ) : (
      <MaterialIcons name="music-note" size={size / 2} color={colors.textSubdued} />
    )}
  </View>
);

/** Round avatar; the first letter on Spotify green when the user has no picture. */
export function Avatar({ uri, name, radius = 22, bg = colors.primary }: { uri?: string; name: string; radius?: number; bg?: string }) {
  const size = radius * 2;
  return (
    <View style={{ width: size, height: size, borderRadius: radius, backgroundColor: bg, overflow: "hidden", alignItems: "center", justifyContent: "center" }}>
      {uri ? (
        <Image source={{ uri }} style={{ width: size, height: size }} contentFit="cover" cachePolicy="memory-disk" recyclingKey={uri} />
      ) : (
        <Text className="font-mont-b text-white" style={{ fontSize: radius * 0.8 }}>
          {name ? name[0].toUpperCase() : "?"}
        </Text>
      )}
    </View>
  );
}

/** Three bars with staggered offsets, the "listening now" marker. */
export function Equalizer({ size = 14, color = colors.primaryActive }: { size?: number; color?: string }) {
  const barWidth = (size - 4) / 3;
  return (
    <View style={{ width: size, height: size, flexDirection: "row", justifyContent: "space-between", alignItems: "flex-end" }}>
      {[0, 200, 100].map((delay, i) => (
        <Bar key={i} delay={delay} width={barWidth} size={size} color={color} />
      ))}
    </View>
  );
}

function Bar({ delay, width, size, color }: { delay: number; width: number; size: number; color: string }) {
  const v = useSharedValue(0.3);
  useEffect(() => {
    v.value = withDelay(delay, withRepeat(withTiming(1, { duration: 600, easing: Easing.inOut(Easing.ease) }), -1, true));
  }, [delay, v]);
  const style = useAnimatedStyle(() => ({ height: size * v.value }));
  return <Animated.View style={[{ width, borderRadius: 1, backgroundColor: color }, style]} />;
}

export const Divider = ({ indent = 0 }: { indent?: number }) => <View style={{ height: 1, backgroundColor: colors.divider, marginLeft: indent }} />;

export const SectionHeader = ({ label }: { label: string }) => (
  <Text className="font-mont-md text-muted" style={{ fontSize: 11, letterSpacing: 1.5, paddingLeft: 16, paddingTop: 20, paddingBottom: 8 }}>
    {label}
  </Text>
);

/** Centered icon, title, subtitle and up to two buttons, for empty, error and sign in states. */
export function StateDisplay({
  icon, title, subtitle, buttonText, onAction, secondaryText, onSecondary,
}: { icon?: IconName; title: string; subtitle?: string; buttonText?: string; onAction?: () => void; secondaryText?: string; onSecondary?: () => void }) {
  return (
    <View className="flex-1 items-center justify-center" style={{ padding: 32 }}>
      {icon ? <MaterialIcons name={icon} size={48} color={colors.textSubdued} /> : null}
      <Text className="mt-4 text-center font-mont-sb text-white" style={{ fontSize: 16 }}>{title}</Text>
      {subtitle ? <Text className="mt-2 text-center font-mont text-muted" style={{ fontSize: 13 }}>{subtitle}</Text> : null}
      {buttonText ? (
        <Pressable onPress={onAction} className="mt-6 items-center justify-center rounded-full bg-primary" style={{ height: 48, paddingHorizontal: 32 }}>
          <Text className="font-mont-b text-black" style={{ fontSize: 14 }}>{buttonText}</Text>
        </Pressable>
      ) : null}
      {secondaryText ? (
        <Pressable onPress={onSecondary} className="mt-3 items-center justify-center" style={{ height: 40, paddingHorizontal: 24 }}>
          <Text className="font-mont-sb text-muted" style={{ fontSize: 14 }}>{secondaryText}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

/** Pulsing placeholder row shaped like a feed card. */
export function SkeletonRow() {
  const o = useSharedValue(0.4);
  useEffect(() => {
    o.value = withRepeat(withTiming(0.8, { duration: 1500, easing: Easing.inOut(Easing.ease) }), -1, true);
  }, [o]);
  const style = useAnimatedStyle(() => ({ opacity: o.value }));
  const block = (w: number | string, h: number, round = false, r = 4) => (
    <View style={{ width: w as number, height: h, backgroundColor: colors.surfaceElevated, borderRadius: round ? h / 2 : r }} />
  );
  return (
    <Animated.View style={[{ flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 12 }, style]}>
      {block(44, 44, true)}
      <View style={{ flex: 1, marginLeft: 16, gap: 6 }}>
        {block(120, 12)}
        {block(80, 10)}
        {block("100%", 12)}
        {block(160, 10)}
      </View>
      <View style={{ marginLeft: 12 }}>{block(48, 48)}</View>
    </Animated.View>
  );
}
