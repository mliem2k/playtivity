import Foundation
import SwiftUI

/// Pure-logic Spotify deep-link URI construction, ported from `/tmp/ref_spotify_launcher.dart`
/// (`SpotifyLauncher._convertUriToWebUrl`) and `/tmp/ref_friend_profile_launcher.dart`
/// (`FriendProfileLauncher._launchSpotifyProfile`'s `spotify:user:$userId` /
/// `https://open.spotify.com/user/$userId` pair). Both Dart launchers converge on the same
/// strategy this type implements: try the native `spotify:` URI first, fall back to the
/// `open.spotify.com` web URL if the OS reports no app handled it.
///
/// Deliberately not ported: `FriendProfileLauncher`'s native Android method-channel path
/// (`_channel.invokeMethod('openFriendProfile', ...)`) has no equivalent plumbing in this
/// codebase (no platform method channel infra exists here), and `SpotifyLauncher.launchSpotifyUri`
/// (the web-first "navigation, avoid autoplay" variant used nowhere by `ActivityCard`/the friend
/// avatar) is out of scope: both of `ActivitiesScreen`'s deep-link call sites (row tap, avatar tap)
/// use the app-first `launchSpotifyUriAndPlay`/profile-launch strategy this type implements.
enum SpotifyDeepLink {
    /// A resolved open target: the native `spotify:` URI to try first, and the
    /// `https://open.spotify.com/...` web URL to fall back to if the OS reports no app handled it.
    /// Both fields nil means there is nothing to open (`open(_:using:)` is then a no-op).
    struct Target: Equatable {
        let appURL: URL?
        let webURL: URL?
    }

    /// Builds a target from a full `spotify:...` content URI, e.g. `activity.contentUri`
    /// ("spotify:track:...", "spotify:playlist:..."). An empty URI (an activity whose track/
    /// playlist URI is missing) produces a target with both fields nil.
    static func contentTarget(uri: String) -> Target {
        let trimmedUri: String = uri
        return Target(
            appURL: trimmedUri.isEmpty ? nil : URL(string: trimmedUri),
            webURL: webURL(fromSpotifyUri: trimmedUri)
        )
    }

    /// Builds a target for a friend's Spotify profile from their user id, matching
    /// `FriendProfileLauncher`'s `spotify:user:$userId` / `https://open.spotify.com/user/$userId`
    /// pair (ref_friend_profile_launcher.dart:37,50).
    static func friendProfileTarget(userId: String) -> Target {
        contentTarget(uri: "spotify:user:\(userId)")
    }

    /// Port of `SpotifyLauncher._convertUriToWebUrl` (ref_spotify_launcher.dart:72-83): a
    /// `spotify:<type>:<id>` URI becomes `https://open.spotify.com/<type>/<id>`. Anything else
    /// (empty, no `spotify:` prefix, or fewer than 3 colon-separated parts) yields nil, exactly
    /// matching the Dart original's `startsWith`/`split`/`length >= 3` guard.
    static func webURL(fromSpotifyUri uri: String) -> URL? {
        guard uri.hasPrefix("spotify:") else { return nil }
        let parts = uri.components(separatedBy: ":")
        guard parts.count >= 3 else { return nil }
        let type = parts[1]
        let id = parts[2]
        return URL(string: "https://open.spotify.com/\(type)/\(id)")
    }

    /// Attempts to open `target.appURL` first; if the system reports it was not handled by an
    /// installed app (or there is no app URL at all), falls back to `target.webURL`. A target with
    /// neither URL is a no-op.
    ///
    /// `openURL` is the caller's `@Environment(\.openURL)` action, passed in rather than read
    /// here: `@Environment` only resolves inside a `View`'s own property/body, so every call site
    /// (`ActivityCard`'s row tap and avatar tap) reads it locally and hands it to this function.
    /// Passing it as a parameter also keeps this testable with a stand-in `OpenURLAction`, no live
    /// view hierarchy needed.
    static func open(_ target: Target, using openURL: OpenURLAction) {
        guard let appURL = target.appURL else {
            if let webURL = target.webURL {
                openURL(webURL)
            }
            return
        }
        openURL(appURL) { accepted in
            if !accepted, let webURL = target.webURL {
                openURL(webURL)
            }
        }
    }
}
