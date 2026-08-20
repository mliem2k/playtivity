import SwiftUI

/// Thin `AsyncImage` wrapper porting `/tmp/ref_album_art_widget.dart`'s rounded-rect album/
/// playlist art convention: the artwork when `imageUrl` is non-empty and loads, otherwise a
/// muted square with a music-note glyph, matching the Dart original's `AppTheme.surfaceElevated`
/// background / `Icons.music_note` fallback. No `AppTheme` port exists in this codebase yet (not
/// listed among this task's files), so plain system-standard `Color.secondary`-derived colors are
/// used in place of the Dart theme's named tokens, matching `LoginScreen`'s own precedent of
/// using ad hoc SwiftUI system colors rather than inventing a design-system port.
struct AlbumArtView: View {
    let imageUrl: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 4

    var body: some View {
        Group {
            if let imageUrl, let url = Self.nonEmptyURL(imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "music.note")
                .foregroundStyle(Color.secondary)
                .font(.system(size: size * 0.4))
        }
    }

    /// Only accepts `http`/`https`: `imageUrl` comes from the buddylist API, another Spotify
    /// account's data crossing a real trust boundary, so a malicious/compromised friend entry
    /// pointing at a `file://` or `content://` URI must fall back to the placeholder rather than
    /// being handed to `AsyncImage`.
    private static func nonEmptyURL(_ raw: String) -> URL? {
        guard !raw.isEmpty, let url = URL(string: raw) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
