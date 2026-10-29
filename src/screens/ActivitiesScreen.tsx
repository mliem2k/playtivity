import { forwardRef, useImperativeHandle, useRef } from "react";
import { FlatList, RefreshControl, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { ActivityCard } from "@/components/ActivityCard";
import { Divider, SkeletonRow, StateDisplay } from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { useActivities } from "@/lib/queries";
import { colors } from "@/theme";

export type ScrollTop = { scrollToTop: () => void; scrollTo?: (y: number) => void };

/** The "Friend Activity" feed: 52px header, pinned progress line, divider separated rows. */
export const ActivitiesScreen = forwardRef<ScrollTop>(function ActivitiesScreen(_, ref) {
  const list = useRef<FlatList>(null);
  useImperativeHandle(ref, () => ({ scrollToTop: () => list.current?.scrollToOffset({ offset: 0, animated: true }) }));
  const signOut = useAuth((s) => s.signOut);
  const { data, isLoading, isFetching, isRefetching, refetch, error } = useActivities();
  const hasData = !!data?.length;

  let body: React.ReactElement;
  if (isLoading && !hasData) {
    body = <View>{Array.from({ length: 6 }, (_, i) => <SkeletonRow key={i} />)}</View>;
  } else if (error && !hasData) {
    const expired = error.message.includes("Authentication");
    body = expired ? (
      <StateDisplay icon="lock-outline" title="Authentication Required" subtitle={error.message} buttonText="Login Again" onAction={signOut} secondaryText="Retry" onSecondary={() => refetch()} />
    ) : (
      <StateDisplay icon="error-outline" title="Could not load" subtitle={error.message} buttonText="Try again" onAction={() => refetch()} />
    );
  } else {
    body = <StateDisplay icon="people-outline" title="No friend activity" />;
  }

  return (
    <SafeAreaView edges={["top"]} className="flex-1 bg-bg">
      <View style={{ height: 52, justifyContent: "center", paddingHorizontal: 16 }}>
        <Text className="font-mont-b text-white" style={{ fontSize: 18 }}>Friend Activity</Text>
      </View>
      <View style={{ height: 2 }}>
        {isFetching && hasData ? <View style={{ height: 2, backgroundColor: colors.primary }} /> : null}
      </View>
      <FlatList
        ref={list}
        data={hasData ? data : []}
        keyExtractor={(a) => a.user.id}
        renderItem={({ item }) => <ActivityCard a={item} />}
        ItemSeparatorComponent={Divider}
        ListEmptyComponent={body}
        contentContainerStyle={hasData ? { paddingBottom: 8 } : { flexGrow: 1 }}
        refreshControl={<RefreshControl refreshing={isRefetching && hasData} onRefresh={() => { refetch(); }} colors={[colors.primary]} progressBackgroundColor={colors.surfaceRaised} />}
        overScrollMode="never"
      />
    </SafeAreaView>
  );
});
