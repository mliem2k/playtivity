import SwiftUI

/// Port of `/tmp/ref_track_tile.dart`'s `TrackTile`: rank number, album art (`AlbumArtView`,
/// reused from Phase 3), track name/artist string, duration. Text styling values (sizes, weights,
/// colors) are taken from `/tmp/ref_theme.dart`'s `AppTheme.darkTheme` `TextTheme` that the Dart
/// original's `tt.bodyLarge`/`tt.bodyMedium`/`tt.labelSmall` resolve to (bodyLarge: 14/w500,
/// bodyMedium: 13/w400/textSecondary, labelSmall: 11/w500/textSecondary, letterSpacing overridden
/// to 0 here matching the Dart original's own `.copyWith(letterSpacing: 0)`), using the
/// `Color.appX` tokens (Task 1) in place of the Dart theme's named colors.
///
/// Pure display only: the Dart original's `InkWell(onTap:)` (haptic + `SpotifyLauncher
/// .launchSpotifyUriAndPlay`) is deliberately not ported here. This task's own interface section
/// lists no `SpotifyDeepLink`/`openURL` dependency for this view, and row-tap wiring is left to
/// whichever screen embeds this tile, the same way the divider between rows is drawn by the
/// caller's list rather than by this view.
struct TrackTile: View {
    let track: Track
    let rank: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appTextSubdued)
                .frame(width: 24, alignment: .center)

            AlbumArtView(imageUrl: track.imageUrl, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)
                Text(track.artistsString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.duration)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.appTextSubdued)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
