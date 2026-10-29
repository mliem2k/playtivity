import { FlexWidget, ImageWidget, ListWidget, TextWidget } from "react-native-android-widget";
import type { Activity } from "@/lib/spotify";
import { spotifyUrl } from "@/lib/spotify";
import { sortForWidget, widgetTimeText } from "./logic";

// Same palette as the Flutter widget (res/values/colors.xml). The widget library reads 8 digit colors
// as CSS #RRGGBBAA, not Android's #AARRGGBB, so the Flutter values are written with the alpha last.
const BG = "#000000E6";
const ITEM_BG = "#0000004D";
const HEADER_BG = "#00000033";
const TEXT = "#FFFFFF";
const TEXT2 = "#FFFFFFE6";
const TEXT3 = "#FFFFFFB3";
const ACCENT = "#1DB954";

function Row({ a }: { a: Activity }) {
  const title = a.track?.name ?? a.playlist?.name ?? "";
  const sub = a.track ? a.track.artists.join(", ") : a.playlist?.ownerName ? a.playlist.ownerName : "Playlist";
  const art = a.track?.imageUrl ?? a.playlist?.imageUrl;
  const uri = a.track?.uri ?? a.playlist?.uri ?? "";
  return (
    <FlexWidget
      clickAction="OPEN_URI"
      clickActionData={{ uri: spotifyUrl(uri) }}
      style={{ flexDirection: "row", alignItems: "center", width: "match_parent", backgroundColor: ITEM_BG, borderRadius: 12, padding: 10, marginBottom: 4 }}
    >
      {a.user.imageUrl ? (
        <ImageWidget image={a.user.imageUrl as `https:${string}`} imageWidth={48} imageHeight={48} radius={24} style={{ marginRight: 12 }} />
      ) : (
        <FlexWidget style={{ width: 48, height: 48, borderRadius: 24, backgroundColor: ACCENT, alignItems: "center", justifyContent: "center", marginRight: 12 }}>
          <TextWidget text={(a.user.displayName[0] ?? "?").toUpperCase()} style={{ color: TEXT, fontSize: 19, fontWeight: "bold" }} />
        </FlexWidget>
      )}
      <FlexWidget style={{ flex: 1, flexDirection: "column" }}>
        <TextWidget text={a.user.displayName} maxLines={1} style={{ color: TEXT, fontSize: 15, fontWeight: "bold" }} />
        <TextWidget text={widgetTimeText(a)} maxLines={1} style={{ color: a.playing ? ACCENT : TEXT3, fontSize: 12, marginTop: 1 }} />
        <TextWidget text={title} maxLines={1} style={{ color: TEXT2, fontSize: 14, marginTop: 2 }} />
        <TextWidget text={sub} maxLines={1} style={{ color: TEXT3, fontSize: 12, marginTop: 1 }} />
      </FlexWidget>
      {art ? <ImageWidget image={art as `https:${string}`} imageWidth={52} imageHeight={52} radius={6} style={{ marginLeft: 10 }} /> : null}
    </FlexWidget>
  );
}

export function FriendActivityWidget({ activities }: { activities: Activity[] }) {
  const items = sortForWidget(activities);
  return (
    <FlexWidget style={{ flexDirection: "column", width: "match_parent", height: "match_parent", backgroundColor: BG, borderRadius: 16, padding: 8 }}>
      <FlexWidget style={{ flexDirection: "row", alignItems: "center", width: "match_parent", backgroundColor: HEADER_BG, borderRadius: 12, padding: 10, marginBottom: 6 }}>
        <FlexWidget clickAction="OPEN_APP" style={{ flex: 1 }}>
          <TextWidget text="Friend Activity" style={{ color: TEXT, fontSize: 16, fontWeight: "bold" }} />
        </FlexWidget>
        <TextWidget text="Refresh" clickAction="REFRESH" style={{ color: TEXT2, fontSize: 13 }} />
      </FlexWidget>
      {items.length ? (
        <ListWidget style={{ height: "match_parent", width: "match_parent" }}>
          {items.map((a) => (
            <Row key={a.user.id} a={a} />
          ))}
        </ListWidget>
      ) : (
        <FlexWidget style={{ flex: 1, width: "match_parent", alignItems: "center", justifyContent: "center", backgroundColor: ITEM_BG, borderRadius: 12, padding: 16 }}>
          <TextWidget text="No recent activities" style={{ color: TEXT, fontSize: 15, fontWeight: "bold" }} />
          <TextWidget text="Friends haven't been listening recently" style={{ color: TEXT2, fontSize: 12, marginTop: 4 }} />
        </FlexWidget>
      )}
    </FlexWidget>
  );
}
