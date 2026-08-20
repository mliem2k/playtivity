import SwiftUI

/// Port of `/tmp/ref_activities_screen.dart`'s `ActivitiesScreen`: a header ("Friend Activity"
/// title with a mismatch-count badge and long-press-to-copy-diagnostic), pull-to-refresh, a
/// 30-second periodic auto-refresh throttled to a 5-second minimum spacing, and the four body
/// states (skeleton, error, empty, activity list) in `_ContentSlivers`'s exact branching order.
///
/// Constructor-injected stores (`let authStore`/`let spotifyStore`), matching `LoginScreen`'s own
/// precedent in this codebase rather than `@Environment`-based dependency injection.
///
/// Deliberate necessary deviation from the Dart original: `AuthStore.isAuthenticated` asserts
/// (traps) if read before `authStore.initialize()` has ever completed (a Phase 2 guard with no
/// Dart equivalent, since Dart's `AuthProvider.isAuthenticated` just reads as a normal false
/// pre-init). This view's `body` therefore checks `authStore.isInitialized` *before* ever reading
/// `isAuthenticated`, showing a minimal loading placeholder in the brief window before the app's
/// own `authStore.initialize()` call (wired outside this task's scope) completes; the Dart
/// original has no equivalent third state because it has no equivalent assert to avoid tripping.
struct ActivitiesScreen: View {
    let authStore: AuthStore
    let spotifyStore: SpotifyStore

    private static let autoRefreshInterval = Duration.seconds(30)
    private static let autoRefreshThrottleInterval = Duration.seconds(5)

    var body: some View {
        VStack(spacing: 0) {
            if authStore.isInitialized, authStore.isAuthenticated {
                header
            }
            Group {
                if !authStore.isInitialized {
                    initializingBody
                } else if !authStore.isAuthenticated {
                    unauthenticatedBody
                } else {
                    mainList
                }
            }
        }
        .task { await loadData() }
        .task { await runAutoRefreshLoop() }
        .onDisappear {
            DebouncedRefreshService.cancel(DebounceKeys.activitiesRefresh)
        }
    }

    // MARK: - Data loading (ported from `_loadData`/`_refreshData`, ref_activities_screen.dart:81-117)

    /// Port of `_loadData` (ref_activities_screen.dart:81-98): only calls `fastInitialLoad` once
    /// `authStore.isInitialized`, matching the Dart original's own guard exactly.
    private func loadData() async {
        guard authStore.isInitialized else {
            logger.warning("Authentication not yet initialized, skipping data load")
            return
        }
        if authStore.isAuthenticated {
            await spotifyStore.fastInitialLoad()
            await spotifyStore.updateWidget(currentUser: authStore.currentUser)
        } else {
            logger.warning("No authentication available - cannot load friend activities")
        }
    }

    /// Port of `_refreshData` (ref_activities_screen.dart:100-117).
    private func refreshData() async {
        guard authStore.isInitialized else {
            logger.warning("Authentication not yet initialized, skipping data refresh")
            return
        }
        if authStore.isAuthenticated {
            await spotifyStore.silentRefresh()
            await spotifyStore.updateWidget(currentUser: authStore.currentUser)
        } else {
            logger.warning("No authentication available - cannot refresh friend activities")
        }
    }

    /// Port of `_startAutoRefresh`'s `Timer.periodic` (ref_activities_screen.dart:69-79), replacing
    /// the Dart `Timer` + `dispose()` cancellation with a `.task { }`-scoped sleep loop: SwiftUI
    /// already cancels this automatically when the view disappears, matching
    /// `DebouncedRefreshService`'s own doc comment that the Dart `DebouncedRefreshMixin`'s
    /// dispose-time cleanup is deliberately not ported for exactly this reason.
    private func runAutoRefreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.autoRefreshInterval)
            guard !Task.isCancelled else { return }
            DebouncedRefreshService.throttle(DebounceKeys.activitiesRefresh, interval: Self.autoRefreshThrottleInterval) {
                Task { await refreshData() }
            }
        }
    }

    /// Port of `_onRetry`/the non-auth-error branch's `onAction` (ref_activities_screen.dart:
    /// 175-181, 334-338): clears the store's error, then re-fetches. The Dart original's
    /// `debouncedRefresh` (from the deliberately-unported `DebouncedRefreshMixin`, see
    /// `DebouncedRefreshService`'s doc comment) is replaced by a direct call; nothing here fires
    /// rapidly enough (a single button tap) to need debouncing.
    private func retry() {
        spotifyStore.clearError()
        Task { await refreshData() }
    }

    /// Port of `_handleReAuth` (ref_activities_screen.dart:119-129), adapted: the Dart original
    /// calls `AuthUtils.handleReAuthentication(context)`, a type that does not exist in this
    /// codebase (referenced only as future/deferred work in `SpotifyStore`'s own doc comment: "the
    /// Dart original, will react to it"). This binds "Login Again" to `AuthStore`'s already-built,
    /// already-tested `tryRecoverFromExpiredToken()` (the closest available equivalent capability)
    /// instead of leaving the button dead pending a type this phase does not build.
    ///
    /// The recovery-success sequence (push the new token into `SpotifyStore`, clear both its error
    /// flags, then reload) mirrors `AuthUtils.handleAuthenticationError`'s own successful-recovery
    /// path (ref_auth_utils.dart:118-127: `sp.clearAuthError(); sp.refreshData();`), the closest
    /// Dart analogue for a silent-recovery-then-reload flow. Both steps are required, not optional:
    /// `AuthStore.tryRecoverFromExpiredToken()` only updates its own `bearerToken`, nothing wires
    /// that into `SpotifyStore` automatically (no shared listener/provider bridge exists here), so
    /// without the explicit `setBearer` call `loadData()` would silently re-fetch with the stale
    /// token and 401 again; and `SpotifyStore.error`/`hasAuthError` are only cleared by
    /// `performLoadFriendsActivities` when called with `showLoading`/`showSkeleton` true, neither
    /// of which `loadData()` uses, so a successful reload would otherwise leave the old error
    /// banner rendered over the freshly-loaded list.
    private func handleReAuth() async {
        let recovered = await authStore.tryRecoverFromExpiredToken()
        guard recovered else { return }
        if let token = authStore.bearerToken, !token.isEmpty {
            spotifyStore.setBearer(token)
        }
        spotifyStore.clearAuthError()
        spotifyStore.clearError()
        await loadData()
    }

    // MARK: - Header (ported from `_HeaderAppBar`/`_HeaderTitle`/`_copyDiagnostic`, lines 231-290)

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(headerTitleColor)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            // `.contentShape` is unavailable on SkipUI (see ActivityCard.swift's comment on the
            // same point); the HStack's own bounds are enough for the long-press target here.
            .onLongPressGesture { copyDiagnostic() }

            if showProgress {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.green)
                    .frame(height: 2)
            }
        }
    }

    /// Port of `_HeaderTitle`'s mismatch-badge threshold (ref_activities_screen.dart:263-266) as
    /// a pure, directly testable function (see `ActivitiesScreenLogicTests`). `nonisolated`:
    /// `View`-conforming types are implicitly `@MainActor`-isolated under Swift 6, and this
    /// function does no UI work and has no reason to require a test (or any other caller) to hop
    /// onto the main actor just to call it.
    nonisolated static func mismatchBadgeText(apiCount: Int, parsedCount: Int) -> String? {
        guard apiCount > 0, parsedCount >= 0, parsedCount < apiCount else { return nil }
        return " (\(parsedCount)/\(apiCount))"
    }

    private var headerTitle: String {
        let badge = Self.mismatchBadgeText(apiCount: spotifyStore.buddylistApiCount, parsedCount: spotifyStore.buddylistParsedCount)
        return "Friend Activity" + (badge ?? "")
    }

    private var headerTitleColor: Color {
        let badge = Self.mismatchBadgeText(apiCount: spotifyStore.buddylistApiCount, parsedCount: spotifyStore.buddylistParsedCount)
        return badge != nil ? Color.orange : Color.primary
    }

    /// Stand-in for the Dart original's `isLoading && activities.isNotEmpty` (`_HeaderAppBar`'s
    /// `showProgress`, ref_activities_screen.dart:147). The Dart `isLoading` there comes from
    /// `ActivitiesScreenDataSelector`, a performance-selector file not in this phase's reference
    /// material (design doc's Reference material list omits it), so its exact composition is
    /// unknown; `isRefreshing` is `SpotifyStore`'s own directly-analogous "a refresh is in flight"
    /// flag (set by `silentRefresh()`, which both pull-to-refresh and the auto-refresh loop call),
    /// and `SpotifyStore.isLoading` is never actually set true by anything this phase's call graph
    /// reaches (`fastInitialLoad`/`silentRefresh` both call `loadFriendsActivities` with
    /// `showLoading: false`), so it would never show the bar at all if used literally.
    private var showProgress: Bool {
        spotifyStore.isRefreshing && !spotifyStore.friendsActivities.isEmpty
    }

    /// Port of `_copyDiagnostic` (ref_activities_screen.dart:282-290). `UIPasteboard` (SkipUI's
    /// cross-platform pasteboard shim) is only usable under `#if SKIP`: it is UIKit-shaped and
    /// this codebase's native `swift build`/`swift test` target is macOS, which has no UIKit, so
    /// referencing it unconditionally would fail to compile natively. On Android (the tested
    /// target) this performs a real clipboard write; natively, and on any future iOS build, it is
    /// a no-op, matching the "iOS best effort only" framing in the plan's Global Constraints. The
    /// Dart original's confirmation `SnackBar` ("Debug info copied") is not ported: no toast/
    /// snackbar component exists anywhere in this codebase yet, and building one is scope beyond
    /// what this task's file list asks for.
    private func copyDiagnostic() {
        #if SKIP
        UIPasteboard.general.string = spotifyStore.buddylistDiagnostic
        #endif
    }

    // MARK: - Body states (ported from `_ContentSlivers`, ref_activities_screen.dart:292-352)

    /// Port of `_ContentSlivers`'s skeleton check (`isLoading && activities.isEmpty`, line 309),
    /// using `isSkeletonLoading` per `SpotifyStore.performFastInitialLoad`'s own doc comment: "UI
    /// ... must derive 'show skeleton' from `isSkeletonLoading && friendsActivities.isEmpty`, not
    /// the flag alone." The additional `error == nil` guard is required beyond that doc comment's
    /// own formula: `isSkeletonLoading` is documented there as a flag `performFastInitialLoad`
    /// sets and then never clears back to `false` on the cold-start-with-nothing-cached path, so if
    /// the very first live fetch then fails, `friendsActivities` stays empty and
    /// `isSkeletonLoading` stays stuck `true` forever, permanently shadowing the error/auth-required
    /// branch below with an eternal shimmer and no visible "Login Again" button. Checking `error`
    /// first breaks that shadowing without touching `SpotifyStore`'s own documented behavior.
    private var showSkeleton: Bool {
        spotifyStore.isSkeletonLoading && spotifyStore.friendsActivities.isEmpty && spotifyStore.error == nil
    }

    /// Single `List`, matching the Dart original's single `RefreshIndicator`/`CustomScrollView`
    /// wrapping every content state (skeleton/error/empty/list) while authenticated, so
    /// pull-to-refresh works identically in all four.
    private var mainList: some View {
        List {
            if showSkeleton {
                ForEach(0..<6, id: \.self) { _ in
                    ActivitySkeleton()
                }
            } else if let error = spotifyStore.error {
                errorStateRow(for: error)
            } else if spotifyStore.friendsActivities.isEmpty {
                emptyStateRow
            } else {
                ForEach(spotifyStore.friendsActivities, id: \.user.id) { activity in
                    ActivityCard(activity: activity)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await refreshData() }
    }

    /// Port of `_ContentSlivers`'s error branch (ref_activities_screen.dart:313-340): the same
    /// `error.contains('Authentication expired')` string check the Dart original uses to pick
    /// between the auth-required layout (with re-auth + retry) and the plain error layout (retry
    /// only), rather than a separate boolean flag, for maximum fidelity to the ported branch.
    @ViewBuilder
    private func errorStateRow(for error: String) -> some View {
        let isAuthError = error.contains("Authentication expired")
        if isAuthError {
            StateDisplayView.authRequired(
                title: "Authentication Required",
                subtitle: error,
                buttonText: "Login Again",
                onAction: { Task { await handleReAuth() } },
                secondaryButtonText: "Retry",
                onSecondaryAction: { retry() }
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            StateDisplayView.error(
                title: "Could not load",
                error: error,
                buttonText: "Try again",
                onAction: { retry() }
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    /// Port of `_EmptyState`/`_DiagnosticEmpty` (ref_activities_screen.dart:427-490): an icon,
    /// "No friend activity" title, and a long-pressable, truncated, monospace diagnostic block.
    private var emptyStateRow: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary)
            Text("No friend activity")
                .font(.system(size: 16, weight: .semibold))
            Text(spotifyStore.buddylistDiagnostic)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
                .onLongPressGesture { copyDiagnostic() }
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Unauthenticated / initializing (ported from `build`'s `!isAuthenticated` branch, lines 135-144)

    /// Port of the top-level `!isAuthenticated` branch (ref_activities_screen.dart:135-144):
    /// no pull-to-refresh here, matching the Dart original's `_NoBounceScrollable` (no
    /// `RefreshIndicator`).
    private var unauthenticatedBody: some View {
        ScrollView {
            StateDisplayView.authRequired(
                title: "Authentication Required",
                subtitle: "Please log in to view friends' activities"
            )
            .frame(maxWidth: .infinity, minHeight: 400)
        }
    }

    /// No Dart equivalent; see this type's doc comment for why this third state exists.
    private var initializingBody: some View {
        ScrollView {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 400)
        }
    }
}
