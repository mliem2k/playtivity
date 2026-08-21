import SwiftUI

/// Port of `/tmp/ref_artist_tile.dart`'s `ArtistTile`: rank number, circular artist photo, artist
/// name, and (only once real stats have arrived) a monthly-listeners line. Text styling mirrors
/// `TrackTile`'s derivation from `/tmp/ref_theme.dart`'s `AppTheme.darkTheme` `TextTheme`
/// (bodyLarge: 14/w500 for rank/name, bodyMedium at the Dart original's `fontSize: 12` override
/// for the listeners line).
///
/// Deliberate substitution per this task's own interface (`AvatarView (circular, reused)`): the
/// Dart original builds a bespoke `CircleAvatar` whose no-photo fallback is a generic person icon
/// (ref_artist_tile.dart:37-53). This port uses the existing `AvatarView` component instead, whose
/// established fallback (Phase 3) is the artist's initial letter, not a person icon. This is a
/// visual difference from the Dart original in the no-photo case, not a parity gap: the task brief
/// explicitly calls for reusing `AvatarView` rather than rebuilding a second circular-avatar
/// component.
///
/// The monthly-listeners gate (`artist.monthlyListeners >= 0`) is the `-1` "not yet fetched"
/// sentinel check named in the phase's Global Constraints and established on `Artist.fromJson`,
/// not a null check (`monthlyListeners` is a non-optional `Int` on this port's `Artist`).
///
/// Pure display only: see `TrackTile`'s doc comment for why the Dart original's `InkWell(onTap:)`
/// (`SpotifyLauncher.launchSpotifyUri`) is not ported here.
struct ArtistTile: View {
    let artist: Artist
    let rank: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.appTextSubdued)
                .frame(width: 24, alignment: .center)

            AvatarView(imageUrl: artist.imageUrl, displayName: artist.name, radius: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)
                if artist.monthlyListeners >= 0 {
                    Text("\(Self.formatCount(artist.monthlyListeners)) monthly listeners")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Port of `_formatCount` (ref_artist_tile.dart:83-87): abbreviates to "X.YM"/"X.YK" above one
    /// million/one thousand, otherwise the plain count. Uses integer arithmetic (round-half-up on
    /// the tenths digit) rather than `Double` formatting (`String(format:)`/`NumberFormatter`),
    /// which has no established-safe precedent on this Skip Kotlin-transpile target; this mirrors
    /// `Track.duration`'s existing integer-division-and-modulo idiom in this codebase.
    static func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 {
            return "\(formatOneDecimal(n, unit: 1_000_000))M"
        }
        if n >= 1_000 {
            return "\(formatOneDecimal(n, unit: 1_000))K"
        }
        return "\(n)"
    }

    private static func formatOneDecimal(_ n: Int, unit: Int) -> String {
        let tenths = (n * 10 + unit / 2) / unit
        let whole = tenths / 10
        let decimal = tenths % 10
        return "\(whole).\(decimal)"
    }
}
