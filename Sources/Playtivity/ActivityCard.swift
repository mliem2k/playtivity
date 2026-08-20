import SwiftUI

/// Port of `/tmp/ref_activity_card.dart`'s `ActivityCard`: avatar (tap opens the friend's Spotify
/// profile) + info column (name, status line, title/subtitle) + album/playlist art (with an
/// active-playing border highlight). Tapping the row (outside the avatar) opens the content deep
/// link. Haptic feedback (`HapticFeedback.lightImpact()` on every tap in the Dart original) is
/// deliberately not ported: it is decorative polish with no correctness weight, not named in the
/// task brief, and SkipUI's `.sensoryFeedback` modifier was not otherwise needed by anything this
/// task builds, so adding it would be scope beyond what was asked.
struct ActivityCard: View {
    let activity: Activity

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                SpotifyDeepLink.open(SpotifyDeepLink.friendProfileTarget(userId: activity.user.id), using: openURL)
            } label: {
                AvatarView(imageUrl: activity.user.imageUrl, displayName: activity.user.displayName, radius: 22)
            }
            .buttonStyle(.plain)

            InfoColumn(activity: activity)
                .frame(maxWidth: .infinity, alignment: .leading)

            AlbumArtBadge(activity: activity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // SkipUI marks `.contentShape(_:eoFill:)` `@available(*, unavailable)` (confirmed via a
        // real transpile failure while writing this file), so the row relies on Compose's default
        // hit-testing (which already covers the full row bounds) instead.
        .onTapGesture {
            SpotifyDeepLink.open(SpotifyDeepLink.contentTarget(uri: activity.contentUri), using: openURL)
        }
    }
}

/// Port of `_AlbumArt` (ref_activity_card.dart:42-64): the art plus, only while currently playing,
/// a highlighted border overlay.
private struct AlbumArtBadge: View {
    let activity: Activity

    var body: some View {
        AlbumArtView(imageUrl: activity.contentImageUrl, size: 48)
            .overlay {
                if activity.isCurrentlyPlaying {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.green, lineWidth: 2)
                }
            }
    }
}

/// Port of `_InfoColumn` (ref_activity_card.dart:90-147): display name, status line, and (for a
/// track or playlist activity) a title/subtitle pair.
private struct InfoColumn: View {
    let activity: Activity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(activity.user.displayName)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)

            StatusLine(isCurrentlyPlaying: activity.isCurrentlyPlaying, timestamp: activity.timestamp)

            if let title = contentTitle {
                Text(title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .padding(.top, 4)
                Text(contentSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Port of `_contentRows` (ref_activity_card.dart:117-129): nil (no rows) when the activity
    /// has neither a track nor a playlist, matching the Dart original's `return const []`.
    private var contentTitle: String? {
        if activity.track != nil {
            return activity.track?.name
        }
        if activity.playlist != nil {
            return activity.contentName
        }
        return nil
    }

    private var contentSubtitle: String {
        if let track = activity.track {
            return "\(track.artistsString) · \(track.album)"
        }
        if let playlist = activity.playlist {
            return Self.playlistSubtitle(playlist)
        }
        return ""
    }

    /// Port of `_playlistSubtitle` (ref_activity_card.dart:139-146) exactly, including all four
    /// owner/count-presence branches.
    private static func playlistSubtitle(_ playlist: Playlist) -> String {
        let ownerName: String = playlist.ownerName
        let owner: String? = ownerName.isEmpty ? nil : ownerName
        let count: String? = playlist.trackCount > 0 ? "\(playlist.trackCount) tracks" : nil
        if let owner, let count {
            return "\(owner) · \(count)"
        }
        if let owner {
            return owner
        }
        if let count {
            return "Playlist · \(count)"
        }
        return "Playlist"
    }
}

/// Port of `_StatusLine` (ref_activity_card.dart:149-177): the animated equalizer + "Listening
/// now" while playing, or a relative-time string otherwise.
private struct StatusLine: View {
    let isCurrentlyPlaying: Bool
    let timestamp: Date

    var body: some View {
        HStack(spacing: 4) {
            if isCurrentlyPlaying {
                EqualizerIcon(color: .green, size: 12)
                Text("Listening now")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                Text(Self.relativeTimeString(from: timestamp))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    /// Relative-time string standing in for the Dart original's `timeago.format(timestamp)`
    /// (no exact wording match required, per the task brief). Fresh `RelativeDateTimeFormatter`
    /// per call rather than a cached static instance: not documented as thread-safe for
    /// concurrent formatting, matching `Activity.iso8601Formatter`'s and
    /// `SpotifyTokenService.parseHttpDate`'s established per-call-construction convention.
    private static func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
