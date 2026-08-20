import SwiftUI

/// Thin `AsyncImage` wrapper porting `/tmp/ref_avatar_widget.dart`'s circular-avatar convention:
/// the friend's photo when `imageUrl` is non-empty and loads successfully, otherwise a colored
/// circle with the first uppercase letter of `displayName` (`_buildFallbackAvatar`, "?" when
/// `displayName` is empty). No custom image-caching logic: `AsyncImage` already handles it (per
/// the phase design doc), matching this codebase's "no third-party image library needed" call.
///
/// Deliberate improvement over the Dart original: the Dart widget only falls back to the letter
/// avatar for a nil/empty `imageUrl`; a real load failure (bad URL, 404) sets
/// `backgroundImage` with no visible fallback (`onBackgroundImageError`'s own comment says the
/// fallback is "through child", but `child` is `null`, so that path renders nothing). Routing both
/// the empty-URL case and a real decode failure through `AsyncImage`'s `placeholder` closure fixes
/// this for free and is not a parity gap: no test or screen in this phase depends on the Dart
/// original's blank-on-error behavior.
struct AvatarView: View {
    let imageUrl: String?
    let displayName: String
    var radius: CGFloat = 20

    var body: some View {
        Group {
            if let imageUrl, let url = Self.nonEmptyURL(imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Color.green)
            Text(initial)
                .font(.system(size: radius * 0.8, weight: .bold))
                .foregroundStyle(Color.white)
        }
    }

    private var initial: String {
        let name: String = displayName
        return name.isEmpty ? "?" : String(name.prefix(1)).uppercased()
    }

    private static func nonEmptyURL(_ raw: String) -> URL? {
        raw.isEmpty ? nil : URL(string: raw)
    }
}
