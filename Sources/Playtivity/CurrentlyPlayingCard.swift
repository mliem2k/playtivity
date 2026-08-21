import SwiftUI

/// Port of `/tmp/ref_currently_playing_card.dart`'s `CurrentlyPlayingCard`: small album art, track
/// name/artist, and an `EqualizerIcon` (Phase 3, reused) indicating live playback. Text styling
/// mirrors `TrackTile`'s derivation from `/tmp/ref_theme.dart`'s `AppTheme.darkTheme` `TextTheme`
/// (bodyLarge at the Dart original's `fontWeight: FontWeight.w600` override for the track name,
/// bodyMedium: 13/w400/textSecondary for the artist line), using the `Color.appX` tokens (Task 1)
/// in place of the Dart theme's named colors, and `Color.appSurfaceRaised` for the card background
/// matching `AppTheme.surfaceRaised`.
///
/// Pure display only: see `TrackTile`'s doc comment for why the Dart original's
/// `InkWell(onTap: () => SpotifyLauncher.launchSpotifyUri('spotify:'))` is not ported here.
struct CurrentlyPlayingCard: View {
    let track: Track

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AlbumArtView(imageUrl: track.imageUrl, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)
                Text(track.artistsString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            EqualizerIcon(size: 18)
        }
        .padding(12)
        .background(Color.appSurfaceRaised)
    }
}
