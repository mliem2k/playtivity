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

    /// The id of the request `processOneRequest` is currently working on (or last worked on).
    /// Read only by `watchForNewRequests`'s own top-of-loop "is this a genuinely new id" check;
    /// deliberately never read by anything that resolves a request (see the fix note below).
    @State private var activeRequestID: UUID?

    /// Bumped by the WebView's own two navigation callbacks below, the only two places that
    /// touch it. Neither callback resolves anything itself, and neither reads `activeRequestID`:
    /// they just record "something happened" for whichever call is currently polling this count.
    /// FIX (review round 1): the original version had `onNavigationFinished`/`onNavigationFailed`
    /// read `activeRequestID` directly at callback-fire time to decide which request to resolve.
    /// Because `watchForNewRequests` could reassign `activeRequestID` to a NEW request before an
    /// OLD, slow-to-settle navigation's callback fired, a late callback belonging to the OLD
    /// request would resolve the NEW request with the OLD request's stale cookie data instead,
    /// the coordinator's own stale-id guard never seeing the mismatch because the wrong id had
    /// already been substituted before `resolve` was ever called. See the fix report appended to
    /// this task's report for the full trace. The fix below never lets that substitution happen:
    /// `processOneRequest` captures its id into a plain local parameter once, at the top, and
    /// every call it makes (including into `handleNavigationEvent`) threads that same captured
    /// value through explicitly; nothing downstream of it ever reads `activeRequestID` again.
    @State private var navigationEventCount = 0
    @State private var lastNavigationFailed = false

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
                navigationEventCount += 1
            },
            onNavigationFailed: {
                lastNavigationFailed = true
                navigationEventCount += 1
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

    /// Notices a new `HeadlessReAuthSpikeCoordinator` request and processes it fully,
    /// `await`ing `processOneRequest` to completion before ever looking for another one. This
    /// serialization is what makes the id-capture fix below actually work: `activeRequestID` can
    /// only ever move on to a different value once the request it currently names has already
    /// been fully handled (resolved, or its own wait budget below expired), so there is no window
    /// where a second `navigator.load(url:)` is in flight while a first one's callback could still
    /// land and be misattributed to it.
    private func watchForNewRequests() async {
        while !Task.isCancelled {
            if let id = HeadlessReAuthSpikeCoordinator.currentRequestID, id != activeRequestID {
                await processOneRequest(id: id)
            }
            try? await Task.sleep(for: Self.requestPollInterval)
        }
    }

    /// Owns one request end to end: issues the navigation, then waits for and consumes
    /// navigation events (there can be more than one per request, e.g. an `.ignore`d sub-resource
    /// load before the real `open.spotify.com` landing) up to the same 20 second/80 poll budget
    /// `HeadlessReAuthSpikeLogic.awaitResolution` uses, resolving `id` (the parameter captured
    /// once here, never re-read from `@State`) the moment a conclusive event arrives. If the
    /// budget expires with nothing conclusive, this simply returns without resolving:
    /// `attempt()`'s own `awaitResolution` is the authoritative timeout for `id` and will already
    /// have (or will shortly) time it out on its own; this loop just moves on to poll for the
    /// next coordinator request.
    ///
    /// A forced `navigator.load(url:)` is required on every request, not just the first:
    /// `WebViewNavigator`'s own `webEngine.didSet` only auto-loads `initialURL` when the
    /// (possibly reused, persistent) engine has no existing back/forward history yet, so a warm,
    /// already-navigated engine from a prior request would otherwise just sit on whatever page it
    /// last landed on.
    private func processOneRequest(id: UUID) async {
        activeRequestID = id
        lastNavigationFailed = false
        var baseline = navigationEventCount
        navigator.load(url: Self.targetURL)

        for _ in 0..<HeadlessReAuthSpikeLogic.overallTimeoutMaxPolls {
            if navigationEventCount != baseline {
                baseline = navigationEventCount
                if await handleNavigationEvent(id: id) {
                    return
                }
                // `.ignore`: keep waiting, a later event for this same request may still arrive.
                continue
            }
            try? await Task.sleep(for: HeadlessReAuthSpikeLogic.overallTimeoutPollInterval)
        }
    }

    // MARK: - Navigation handling (ref_auth_provider.dart:393-439)

    /// Returns `true` once `id` has been resolved (success or failure), `false` for `.ignore`
    /// (the caller should keep waiting for a later event on the same request). `id` is always
    /// the value `processOneRequest` captured at the top of its own call, never a fresh read of
    /// `activeRequestID`.
    private func handleNavigationEvent(id: UUID) async -> Bool {
        if lastNavigationFailed {
            lastNavigationFailed = false
            HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: nil)
            return true
        }
        guard let url = webViewState.url else { return false }
        switch HeadlessReAuthSpikeLogic.classifyNavigation(url: url) {
        case .sessionGone:
            HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: nil)
            return true
        case .ignore:
            return false
        case .checkCookiesNow:
            let spDc = await HeadlessReAuthSpikeLogic.checkWithSettleRetry(
                checkNow: { await self.readSpDcCookie() },
                sleep: { try await Task.sleep(for: $0) }
            )
            HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: spDc)
            return true
        }
    }

    /// Port of `checkForSpDc` (ref_auth_provider.dart:393-408).
    private func readSpDcCookie() async -> String? {
        let cookies = await navigator.cookies(for: Self.targetURL)
        return cookies.first(where: { $0.name == "sp_dc" && !$0.value.isEmpty })?.value
    }
}
#endif // SKIP || os(iOS)
