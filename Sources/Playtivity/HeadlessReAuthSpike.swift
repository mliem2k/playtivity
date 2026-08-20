import Foundation
import SwiftUI

/// Go/no-go spike for the slow path of `AuthStore.tryRecoverFromExpiredToken`
/// (`headlessReAuthOverride`, currently `nil`): can a hidden WebView, reusing a
/// `persistentWebViewID`-cached `WebEngine`, obtain a fresh `sp_dc` from Spotify's long-lived
/// browser OAuth session without hanging on Android? Ports `_tryHeadlessWebViewReAuth`
/// (`/tmp/ref_auth_provider.dart:387-471`).
///
/// **Not wired into `AuthStore` by this task.** `HeadlessReAuthSpike.attempt` is a standalone,
/// directly callable function so it can be exercised in isolation first, per the design doc's
/// go/no-go disposition: wiring only happens once a real Android emulator run (Step 2, this
/// task's report has the runbook) confirms the mounted-WebView approach actually works on device.
///
/// **Why `attempt()` alone cannot do anything without help.** SwiftUI only runs a `View`'s body
/// (and, on Android via Skip, only reaches SkipWeb's `AndroidView` factory/measure/layout path)
/// once something is actually composed into the live view tree; a bare `static func` cannot
/// cause that to happen by itself. `HeadlessReAuthSpikeHost`, defined below, is the real
/// mountable artifact: a tiny, invisible `WebView` reusing a `persistentWebViewID`-cached engine,
/// per the design doc's one candidate design (a raw, detached `PlatformWebView` is what SkipWeb's
/// own test suite already proves hangs on Android; going through the real `WebView` SwiftUI
/// struct is the one thing that's still genuinely open). `attempt()` and the host coordinate
/// through `HeadlessReAuthSpikeCoordinator` rather than a direct call, so the caller of
/// `attempt()` and whoever embeds the host in their view tree can be different code entirely.
/// See this task's report for exactly how to embed `HeadlessReAuthSpikeHost` for a manual Step 2
/// run.
enum HeadlessReAuthSpike {
    /// Runs one headless re-auth attempt and returns a fresh `sp_dc` (different from
    /// `existingSpDc`) on success, or `nil` on any failure: no `HeadlessReAuthSpikeHost` mounted
    /// anywhere (times out after the full budget), the OAuth session itself is gone (redirected
    /// to login), no cookie ever appeared, or the cookie that appeared is identical to
    /// `existingSpDc` (already tried, rejected the same way the Dart original rejects it at
    /// ref_auth_provider.dart:455-458).
    ///
    /// Does not persist the result or refresh the bearer token itself: that is `AuthStore`'s job
    /// once/if this is wired in (Step 3 of the task brief), matching `_tryHeadlessWebViewReAuth`
    /// only through the point where it obtains `newSpDc`, ref_auth_provider.dart:450-458; the
    /// `_spDc = newSpDc; await _prefs.setString(...); return await _trySilentRefresh();` tail
    /// (ref:461-463) is `AuthStore`'s existing `tryRecoverFromExpiredToken`/`trySilentRefresh`,
    /// not duplicated here.
    static func attempt(existingSpDc: String?) async -> String? {
        let id = HeadlessReAuthSpikeCoordinator.start()
        let found = await HeadlessReAuthSpikeLogic.awaitResolution(
            poll: { HeadlessReAuthSpikeCoordinator.outcome(id: id) },
            sleep: { try await Task.sleep(for: $0) }
        )
        HeadlessReAuthSpikeCoordinator.finish(id: id)
        return HeadlessReAuthSpikeLogic.resolvedSpDc(newSpDc: found, existingSpDc: existingSpDc)
    }
}

// SkipWeb's own `WebView`/`WebEngineConfiguration`/`WebViewNavigator`/`WebViewState` are gated
// `#if SKIP || os(iOS)` inside the library itself; `HeadlessReAuthSpikeHost` is the only piece of
// this file that touches them, so only it (not `HeadlessReAuthSpike.attempt` above, which is
// pure) needs the same gate. Mirrors `LoginScreen.swift`'s identical gating, same reasoning.
#if SKIP || os(iOS)
import SkipWeb

/// The real mountable spike artifact. Renders nothing visible: a 1x1, `opacity(0)` `WebView`
/// reusing a fixed `persistentWebViewID` so its `WebEngine` (and therefore its cookie jar and DOM
/// state) survives this host unmounting and remounting, per the design doc's verified
/// `WebView.persistentWebViewID` behavior (caches the literal same `WebEngine` object;
/// SwiftUI unmount/remount alone never tears it down, only an explicit
/// `WebView.removePersistentWebView(id:)` call does).
///
/// **Must be embedded somewhere in the live view tree for `HeadlessReAuthSpike.attempt` to
/// resolve to anything besides a 20 second timeout.** This host is not wired into `ContentView`
/// or anywhere else in the app by this task; see the task report's runbook for how to embed it
/// for a manual Step 2 verification pass. It watches `HeadlessReAuthSpikeCoordinator` for a new
/// request every 250ms (poll, not `@Observable` reactivity) rather than reacting instantly,
/// matching this codebase's established "poll rather than depend on an unverified Skip Lite
/// concurrency/observation primitive" idiom (see `LoginScreen.waitForIdentityMessage`'s identical
/// justification).
struct HeadlessReAuthSpikeHost: View {
    @State private var navigator = WebViewNavigator()
    @State private var webViewState = WebViewState()
    @State private var activeRequestID: UUID?

    private static let persistentID = "headless-reauth"
    private static let targetURL = URL(string: "https://open.spotify.com/")!
    private static let requestPollInterval = Duration.milliseconds(250)

    var body: some View {
        WebView(
            configuration: WebEngineConfiguration(
                javaScriptEnabled: true,
                customUserAgent: SpotifyTokenService.userAgent
            ),
            navigator: navigator,
            url: Self.targetURL,
            state: $webViewState,
            onNavigationFinished: {
                Task { await handleNavigationFinished() }
            },
            onNavigationFailed: {
                Task { await failActiveRequest() }
            },
            persistentWebViewID: Self.persistentID
        )
        .frame(width: 1, height: 1)
        .opacity(0.0)
        .task {
            await watchForNewRequests()
        }
    }

    // MARK: - Request watching

    /// Notices a new `HeadlessReAuthSpikeCoordinator` request and forces a fresh navigation to
    /// `open.spotify.com` for it. A forced `navigator.load(url:)` is required on every attempt,
    /// not just the first: `WebViewNavigator`'s own `webEngine.didSet` only auto-loads
    /// `initialURL` when the (possibly reused, persistent) engine has no existing back/forward
    /// history yet, so a warm, already-navigated engine from a prior attempt would otherwise just
    /// sit on whatever page it last landed on.
    private func watchForNewRequests() async {
        while !Task.isCancelled {
            if let id = HeadlessReAuthSpikeCoordinator.currentRequestID, id != activeRequestID {
                activeRequestID = id
                navigator.load(url: Self.targetURL)
            }
            try? await Task.sleep(for: Self.requestPollInterval)
        }
    }

    // MARK: - Navigation handling (ref_auth_provider.dart:393-439)

    private func handleNavigationFinished() async {
        guard let id = activeRequestID, let url = webViewState.url else { return }
        switch HeadlessReAuthSpikeLogic.classifyNavigation(url: url) {
        case .sessionGone:
            HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: nil)
        case .ignore:
            return
        case .checkCookiesNow:
            let spDc = await HeadlessReAuthSpikeLogic.checkWithSettleRetry(
                checkNow: { await self.readSpDcCookie() },
                sleep: { try await Task.sleep(for: $0) }
            )
            HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: spDc)
        }
    }

    /// Port of `onReceivedError` (ref_auth_provider.dart:440-442).
    private func failActiveRequest() async {
        guard let id = activeRequestID else { return }
        HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: nil)
    }

    /// Port of `checkForSpDc` (ref_auth_provider.dart:393-408).
    private func readSpDcCookie() async -> String? {
        let cookies = await navigator.cookies(for: Self.targetURL)
        return cookies.first(where: { $0.name == "sp_dc" && !$0.value.isEmpty })?.value
    }
}
#endif // SKIP || os(iOS)
