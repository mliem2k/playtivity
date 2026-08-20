import Foundation

/// Pure, WebView-free logic extracted from `LoginScreen`, ported from
/// lib/widgets/spotify_webview_login.dart, so it is unit testable without a live WebView.
enum LoginScreenLogic {
    static let maxCookieRetries = 8
    static let cookieRetryInterval = Duration.seconds(1)

    /// The identity-fetch JS injection is polled rather than awaited on a single timer (see
    /// `LoginScreen.waitForIdentityMessage`), so its 15 second budget (matching the Dart
    /// original's `.timeout(const Duration(seconds: 15), ...)`) is expressed as a poll count and
    /// interval rather than a single `Duration`: 75 polls * 200ms = 15s.
    static let identityPollInterval = Duration.milliseconds(200)
    static let identityMaxPolls = 75

    /// Port of the `onLoadStop` URL gate (ref_spotify_webview_login.dart:129-138): only attempt
    /// token capture once navigation has landed on `open.spotify.com` and past its login/auth/
    /// challenge/error interstitials.
    static func isEligibleForCapture(url: URL) -> Bool {
        let s = url.absoluteString
        guard s.contains("open.spotify.com") else { return false }
        for blocked in ["/login", "/auth", "/challenge", "/error"] {
            if s.contains(blocked) { return false }
        }
        return true
    }

    enum RetryLoopResult: Equatable {
        case found(attempt: Int)
        case exhausted
        case cancelled
    }

    /// Port of `_scheduleCookieRetry`'s `Timer.periodic` loop
    /// (ref_spotify_webview_login.dart:41-63): calls `check` up to `maxRetries` times, `interval`
    /// apart, stopping the moment it reports the cookie found. `sleep` is injected so this is
    /// testable without a real timer or real wall-clock delay.
    static func runCookieRetryLoop(
        maxRetries: Int = maxCookieRetries,
        interval: Duration = cookieRetryInterval,
        sleep: (Duration) async throws -> Void,
        isCancelled: () -> Bool = { false },
        check: (_ attempt: Int) async -> Bool
    ) async -> RetryLoopResult {
        var attempt = 0
        while attempt < maxRetries {
            if isCancelled() { return .cancelled }
            do {
                try await sleep(interval)
            } catch {
                return .cancelled
            }
            if isCancelled() { return .cancelled }
            attempt += 1
            if await check(attempt) {
                return .found(attempt: attempt)
            }
        }
        return .exhausted
    }
}
