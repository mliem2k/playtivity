import Foundation

/// Pure, WebView-free logic and cross-mount coordination for `HeadlessReAuthSpike`, extracted the
/// same way `LoginScreenLogic` was extracted from `LoginScreen` in Task 4, so it is unit testable
/// without a live WebView or a real Android/Compose mount. Ports the decision points of
/// `_tryHeadlessWebViewReAuth` (`/tmp/ref_auth_provider.dart:387-471`).
enum HeadlessReAuthSpikeLogic {
    /// Matches the Dart original's single `Future.delayed(const Duration(seconds: 2))` retry
    /// (ref_auth_provider.dart:435).
    static let settleDelay = Duration.seconds(2)

    /// The 20 second overall budget (ref_auth_provider.dart:446, `Timer(const Duration(seconds:
    /// 20), ...)`) expressed as a poll count/interval rather than a single `Duration`, matching
    /// `LoginScreenLogic.identityMaxPolls`/`identityPollInterval`'s poll-over-Timer idiom for the
    /// same reason: 80 * 250ms = 20s.
    static let overallTimeoutPollInterval = Duration.milliseconds(250)
    static let overallTimeoutMaxPolls = 80

    /// The three outcomes of inspecting one `onLoadStop`-equivalent navigation event
    /// (ref_auth_provider.dart:422-432).
    enum NavigationOutcome: Equatable {
        /// Redirected to a login/auth surface: the underlying OAuth session is gone, resolve the
        /// whole attempt as a failure immediately.
        case sessionGone
        /// Landed on `open.spotify.com` past the login/auth patterns: eligible to check cookies.
        case checkCookiesNow
        /// Neither of the above (e.g. a sub-resource load on some other domain): wait for the
        /// next navigation event without resolving anything yet.
        case ignore
    }

    /// The state of one in-flight `HeadlessReAuthSpikeCoordinator` request.
    enum Outcome: Equatable {
        case pending
        case resolved(String?)
    }

    /// Port of the `onLoadStop` redirect/eligibility gate (ref_auth_provider.dart:422-432).
    /// Checks the redirect-to-login patterns BEFORE the `open.spotify.com` containment check,
    /// matching the Dart original's check order: a login URL that also embeds
    /// "open.spotify.com" in its own `continue=` query parameter (exactly the shape of the URL
    /// `LoginScreen` itself navigates to) must classify as `.sessionGone`, not `.checkCookiesNow`.
    static func classifyNavigation(url: URL) -> NavigationOutcome {
        let s = url.absoluteString
        if s.contains("accounts.spotify.com") || s.contains("/login") || s.contains("/auth/") {
            return .sessionGone
        }
        if !s.contains("open.spotify.com") {
            return .ignore
        }
        return .checkCookiesNow
    }

    /// Port of the "check immediately; if nothing found, wait `settleDelay` and check exactly
    /// once more" sequence (ref_auth_provider.dart:433-438). Unlike `LoginScreenLogic
    /// .runCookieRetryLoop`'s unbounded-attempts shape, this always checks BEFORE sleeping (not
    /// after) and gives up after a single retry rather than continuing, matching the Dart
    /// original's one `Future.delayed` retry exactly, not the visible login screen's 8-attempt
    /// cookie-capture loop. `checkNow`'s contract: return the `sp_dc` value when present and
    /// non-empty, `nil` otherwise (same contract as `LoginScreen`'s cookie lookup).
    static func checkWithSettleRetry(
        checkNow: () async -> String?,
        sleep: (Duration) async throws -> Void
    ) async -> String? {
        if let found = await checkNow() {
            return found
        }
        do {
            try await sleep(settleDelay)
        } catch {
            return nil
        }
        return await checkNow()
    }

    /// Port of the "resolve if a fresh sp_dc differs from the currently stored one" decision
    /// (ref_auth_provider.dart:451-458): empty/nil is always a failure, and a value identical to
    /// what's already stored is treated as "already tried this value" and rejected too, not
    /// retried.
    static func resolvedSpDc(newSpDc: String?, existingSpDc: String?) -> String? {
        guard let newSpDc, !newSpDc.isEmpty else { return nil }
        guard newSpDc != existingSpDc else { return nil }
        return newSpDc
    }

    /// Polls `poll` up to `maxPolls` times, `interval` apart, until it reports `.resolved`,
    /// implementing the 20 second overall budget backstop (ref_auth_provider.dart:446) as a poll
    /// loop rather than a `Task`/`Timer` race, mirroring `LoginScreen
    /// .waitForIdentityMessage`'s poll-over-continuation idiom for the same reason (avoiding a
    /// Skip Lite concurrency primitive not independently verified to transpile in this codebase).
    /// `sleep` throwing (task cancellation) ends the wait early and reports "not resolved", same
    /// convention as `LoginScreenLogic.runCookieRetryLoop`.
    static func awaitResolution(
        maxPolls: Int = overallTimeoutMaxPolls,
        interval: Duration = overallTimeoutPollInterval,
        poll: () async -> Outcome,
        sleep: (Duration) async throws -> Void
    ) async -> String? {
        for _ in 0..<maxPolls {
            if case .resolved(let value) = await poll() {
                return value
            }
            do {
                try await sleep(interval)
            } catch {
                return nil
            }
        }
        return nil
    }
}

/// Bridges `HeadlessReAuthSpike.attempt` (a plain async function) to whichever
/// `HeadlessReAuthSpikeHost` happens to be mounted in the live SwiftUI/Compose tree: a bare
/// `static func` cannot itself cause SwiftUI to compose a `View`, only something already mounted
/// can, so `attempt` and the host coordinate through this shared, request-scoped mailbox instead
/// of a direct call. `NSLock`-guarded `nonisolated(unsafe)` state, the same proven-transpilable
/// idiom `TOTPGenerator` already uses for shared mutable state written from production code
/// (Known Skip Lite transpilation quirk: a bare mutable static var is rejected by Swift 6's
/// strict concurrency mode with no exemption for one that is, in fact, manually synchronized
/// behind a lock; the lock is what makes it safe, not the attribute), chosen over a `@MainActor`
/// class so `attempt()` and its tests stay plain synchronous/async calls with no actor hops.
enum HeadlessReAuthSpikeCoordinator {
    private struct Resolution {
        let spDc: String?
    }

    private struct State {
        var currentRequestID: UUID?
        var resolutions: [UUID: Resolution] = [:]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _state = State()

    /// Called by `HeadlessReAuthSpike.attempt`. Returns the request id the host must resolve.
    static func start() -> UUID {
        lock.withLock {
            let id = UUID()
            _state.currentRequestID = id
            return id
        }
    }

    /// Polled by `HeadlessReAuthSpikeHost` to notice a new request worth driving a navigation
    /// for.
    static var currentRequestID: UUID? {
        lock.withLock { _state.currentRequestID }
    }

    /// Called by `HeadlessReAuthSpikeHost` once it determines an outcome for `id`. Ignored (not
    /// an error) when `id` is no longer the current request, or already resolved once, matching
    /// the Dart original's `Completer`'s own "first resolution wins" semantics
    /// (`if (!completer.isCompleted) completer.complete(...)` guards every resolution site in
    /// `_tryHeadlessWebViewReAuth`). The stale-id guard specifically closes a real race: a
    /// navigation event from an OLD, already-`finish`ed request landing after a NEW request has
    /// already started must not resolve (or re-insert state for) the old id.
    static func resolve(id: UUID, spDc: String?) {
        lock.withLock {
            guard _state.currentRequestID == id, _state.resolutions[id] == nil else { return }
            _state.resolutions[id] = Resolution(spDc: spDc)
        }
    }

    /// Polled by `HeadlessReAuthSpikeLogic.awaitResolution` from `attempt()`.
    ///
    /// Both return points are fully qualified (`HeadlessReAuthSpikeLogic.Outcome.resolved`/
    /// `.pending`, not the bare `.resolved`/`.pending` shorthand): Skip's Kotlin transpiler
    /// cannot infer the enum type for leading-dot shorthand returned from inside a generic
    /// closure (here, `NSLock.withLock<T>`'s body), the same known transpile quirk already hit
    /// and fixed in `LoginScreenLogicTests` (`XCTAssertEqual(result, .found(attempt: 1))`
    /// required the same fix, for the same reason, in Task 4).
    static func outcome(id: UUID) -> HeadlessReAuthSpikeLogic.Outcome {
        lock.withLock {
            if let resolution = _state.resolutions[id] {
                return HeadlessReAuthSpikeLogic.Outcome.resolved(resolution.spDc)
            }
            return HeadlessReAuthSpikeLogic.Outcome.pending
        }
    }

    /// Called by `attempt()` once it stops waiting (resolved or timed out), so a subsequent
    /// request starts from a clean slate.
    static func finish(id: UUID) {
        lock.withLock {
            _state.resolutions[id] = nil
            if _state.currentRequestID == id {
                _state.currentRequestID = nil
            }
        }
    }

    /// Test-only reset, mirrors `TOTPGenerator.clearRuntimeSecrets`'s purpose: isolate test cases
    /// from each other's leftover state.
    static func resetForTesting() {
        lock.withLock { _state = State() }
    }
}
