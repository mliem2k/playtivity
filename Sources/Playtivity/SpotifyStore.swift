import Foundation
import Observation

/// Pure-Swift port of the activities-feed slice of `lib/providers/spotify_provider.dart`
/// (`SpotifyProvider`): constructor priming, `setBearer`/`clearBearer`, `loadFriendsActivities`,
/// this phase's narrowed `silentRefresh`, `reloadFriendsFromPersistedCache`, `fastInitialLoad`,
/// `clearError`/`clearData`/`clearAuthError`, and the `updateWidget` stub. The profile/currently-
/// playing loaders (`loadCurrentlyPlaying`, `loadTopTracks`, `loadTopArtists`) and the
/// four-loader `refreshData`/`refreshProfileData`/`fullRefresh` are Phase 4's scope and are
/// deliberately not ported here.
///
/// `@unchecked Sendable`: mirrors `BuddyActivityService`'s own reasoning, for the same mechanical
/// cause. Constructor-time priming (below) fires a `Task { [weak self] in ... }` to mirror the
/// Dart constructor's fire-and-forget `_buddyService.persistenceReady.then(...)`, and Swift 6
/// only allows a class to be captured that way if it is `Sendable`. Unlike `BuddyActivityService`,
/// this store's instance state IS protected against the specific hazard Task 2's review raised
/// (see `serialized(_:)` below): every method that touches `buddyService`, or mutates this
/// store's own observable properties as a result, funnels through a single `NSLock`-guarded task
/// chain, so at most one such operation is ever actually running at a time regardless of how many
/// external callers (a refresh button, an auto-refresh timer) fire concurrently. What remains
/// genuinely unguarded, matching every other `@Observable` store in this codebase (`AuthStore`
/// included), is a plain concurrent READ of a property (e.g. a UI layer reading
/// `friendsActivities` on one thread while a serialized operation is mid-write on another); that
/// is the same characteristic any mutable class instance shared across threads has in Swift
/// unless explicitly actor-isolated, it is not a new hazard this store introduces, and resolving
/// it store-wide is out of this task's scope (the hard requirement from Task 2's review is
/// specifically about concurrent, unsynchronized MUTATION of `BuddyActivityService`'s own
/// instance state from multiple overlapping callers, which `serialized(_:)` eliminates).
@Observable
final class SpotifyStore: @unchecked Sendable {
    private let buddyService: BuddyActivityService

    private var bearerToken: String?

    private(set) var friendsActivities: [Activity] = []
    private(set) var isLoading = false
    private(set) var isSkeletonLoading = false
    private(set) var error: String?
    private(set) var hasAuthError = false
    private(set) var authErrorMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false

    // MARK: - Diagnostics passthrough (ported from ref_spotify_provider.dart:67-74)

    var buddylistDiagnostic: String { BuddyActivityService.lastDiagnostic }
    var buddylistApiCount: Int { BuddyActivityService.lastApiFriendCount }

    /// Shows the merged count when accumulation added extra friends beyond a single live API
    /// response. Ported from `buddylistParsedCount` (lines 70-74) exactly.
    var buddylistParsedCount: Int {
        let merged = BuddyActivityService.lastMergedCount
        let parsed = BuddyActivityService.lastParsedCount
        return merged > parsed ? merged : parsed
    }

    // MARK: - Concurrency: single-flight serialization into `buddyService`

    // `BuddyActivityService` is `@unchecked Sendable` with unlocked instance state (its own doc
    // comment discloses this, safe only because every caller serializes its own access; Task 2's
    // review flagged this as unsafe against a genuine concurrent caller, parked pending this
    // task). This store is that caller, and it has more than one entry point that can reach the
    // same `buddyService` instance (a manual refresh action and an auto-refresh timer can both
    // fire `loadFriendsActivities`/`silentRefresh` at effectively the same moment), so every
    // method that touches `buddyService` routes through `serialized(_:)`: an `NSLock`-guarded
    // task chain, the same lock-backed idiom `TOTPGenerator`/`HeadlessReAuthSpikeCoordinator`
    // already use in this codebase, chosen over a Swift `actor` (untested against this project's
    // Kotlin transpile target and used nowhere else in it; a chained-Task approach is provably
    // just as sufficient here, since the property we need is "at most one operation touching
    // `buddyService` is ever actually running," not general actor-style isolation).
    //
    // Each call appends its own operation to the tail of the chain under the lock (a plain
    // synchronous read-and-replace, so there is no check-then-act race on `gateTail` itself), then
    // awaits a task that first awaits whatever was previously queued, then runs its own work. This
    // guarantees full FIFO serialization: a second caller's operation never starts until the
    // first's has completely finished, so `buddyService`'s unlocked instance state is never
    // mutated by two callers at once.
    // Cancellation limitation, harmless today since nothing calls this store from a SwiftUI
    // `.task { }` yet: each link is an unstructured `Task { }`, so it does not inherit the calling
    // Task's cancellation, and `Task<Void, Never>.value` cannot throw `CancellationError`. A
    // future caller that cancels mid-chain (e.g. a `.task { }` torn down by view disappearance)
    // will block until its queued operation actually finishes rather than being cancelled.
    private let gateLock = NSLock()
    private var gateTail: Task<Void, Never>?

    private func serialized(_ operation: @escaping @Sendable () async -> Void) async {
        let ticket: Task<Void, Never> = gateLock.withLock {
            let previous = gateTail
            let next = Task {
                if let previous { _ = await previous.value }
                await operation()
            }
            gateTail = next
            return next
        }
        await ticket.value
    }

    /// Constructor-time priming: mirrors the Dart constructor's
    /// `_buddyService.persistenceReady.then((_) { ... })` (lines 20-31), primed from any
    /// already-cached data without waiting for auth. This is the very first link in the
    /// `serialized(_:)` chain (`gateTail` starts as this task), so every other method call made
    /// after construction correctly waits for it to finish before running its own work.
    ///
    /// Guarantee this constructor actually provides: NONE that is synchronous. Like the Dart
    /// original's own fire-and-forget `.then()`, there is no guarantee this priming has completed
    /// by the time a caller first reads `friendsActivities` right after construction (matching
    /// `AuthStore`'s documented discipline: `Task { }` has no ordering guarantee against a plain
    /// synchronous caller in Swift, unlike Dart's single-threaded event loop). What IS guaranteed:
    /// any call into one of this store's own `serialized(_:)`-routed methods (`loadFriendsActivities`,
    /// `fastInitialLoad`, etc.) will always wait for this priming step to finish first, since it is
    /// queued immediately behind it in the same chain.
    init(buddyService: BuddyActivityService = BuddyActivityService()) {
        self.buddyService = buddyService
        gateTail = Task { [weak self] in
            guard let self else { return }
            await self.buddyService.waitUntilPersistenceReady()
            let cached = self.buddyService.cachedActivities
            if let cached, !cached.isEmpty, self.friendsActivities.isEmpty {
                self.friendsActivities = cached
            }
        }
    }

    // MARK: - Bearer token (ported from lines 76-83)

    func setBearer(_ token: String) {
        bearerToken = token
    }

    func clearBearer() {
        bearerToken = nil
        clearData()
    }

    // MARK: - Authentication error handling (ported from lines 86-114)

    /// Ported from `_isAuthenticationError` (lines 86-93) exactly.
    private func isAuthenticationError(_ error: String) -> Bool {
        error.contains("401") ||
            error.contains("403") ||
            error.contains("No Bearer token available") ||
            error.contains("Authentication expired") ||
            error.contains("Unauthorized") ||
            error.contains("Not authenticated")
    }

    /// Ported from `_handleAuthenticationError` (lines 96-107). The Dart original also clears
    /// `_topTracks`/`_topArtists`/`_currentlyPlaying`; those fields do not exist in this phase's
    /// slice (Phase 4's scope), so only `friendsActivities` is cleared here.
    private func handleAuthenticationError(_ error: String) {
        logger.error("Authentication error detected in store: \(error)")
        hasAuthError = true
        authErrorMessage = error
        friendsActivities = []
        self.error = "Authentication expired. Please login again."
    }

    /// Ported from `clearAuthError` (lines 109-114).
    func clearAuthError() {
        hasAuthError = false
        authErrorMessage = nil
    }

    // MARK: - loadFriendsActivities (ported from lines 212-289)

    func loadFriendsActivities(showLoading: Bool = false, showSkeleton: Bool = false) async {
        await serialized { [weak self] in
            await self?.performLoadFriendsActivities(showLoading: showLoading, showSkeleton: showSkeleton)
        }
    }

    /// The Dart original wraps this whole body in an outer try/catch (lines 232-282); nothing in
    /// this Swift port's call chain (property reads/writes plus the inner do/catch around the
    /// fetch below) can actually throw, so there is nothing for an outer catch to ever handle.
    private func performLoadFriendsActivities(showLoading: Bool, showSkeleton: Bool) async {
        guard let token = bearerToken else {
            error = "Not authenticated"
            if showLoading { isLoading = false }
            if showSkeleton { isSkeletonLoading = false }
            return
        }

        if showLoading {
            isLoading = true
            error = nil
        } else if showSkeleton {
            isSkeletonLoading = true
            error = nil
        }

        var activities: [Activity] = []
        var fetchSucceeded = false
        var authFailed = false

        do {
            activities = try await buddyService.getFriendActivity(bearerToken: token)
            fetchSucceeded = true
        } catch {
            logger.error("Failed to fetch friend activities: \(error)")
            let errorMessage = "\(error)"
            if isAuthenticationError(errorMessage) {
                authFailed = true
                logger.info("Authentication error detected, may need re-authentication")
                handleAuthenticationError(errorMessage)
            } else {
                self.error = "Failed to load friend activities: \(errorMessage)"
            }
        }

        // The home widget renders from the buddy service's accumulated cache, so the in-app list
        // must never show fewer friends than that cache. Prefer the live result when it is at
        // least as large; otherwise keep the accumulated cache (or the list already on screen if
        // it is larger).
        let cached = buddyService.cachedActivities
        let accumulated: [Activity]
        if let cached, !cached.isEmpty {
            accumulated = cached
        } else {
            accumulated = friendsActivities
        }

        if fetchSucceeded && !activities.isEmpty {
            friendsActivities = activities.count >= accumulated.count ? activities : accumulated
            lastUpdated = Date()
        } else if !authFailed {
            // Empty success or transient (non-auth) failure: never drop to zero cards. Spotify's
            // buddylist intermittently returns an empty feed even when friends are active, so an
            // empty result is not reliably "nothing to show". Keep the friends already on screen.
            if !accumulated.isEmpty {
                friendsActivities = accumulated
            }
        }

        if showLoading { isLoading = false }
        if showSkeleton { isSkeletonLoading = false }

        if !friendsActivities.isEmpty {
            await updateWidget(currentUser: nil)
        }
    }

    // MARK: - clearError / clearData (ported from lines 291-309)

    func clearError() {
        error = nil
    }

    func clearData() {
        friendsActivities = []
        isLoading = false
        isRefreshing = false
        isSkeletonLoading = false
        error = nil
        lastUpdated = nil
        hasAuthError = false
        authErrorMessage = nil
    }

    // MARK: - silentRefresh (this phase's narrowed version of lines 345-356)

    /// This phase's narrowed `silentRefresh`: calls only `loadFriendsActivities`, not the Dart
    /// `refreshData`'s four-loader `Future.wait` (`loadCurrentlyPlaying`/`loadTopTracks`/
    /// `loadTopArtists` are Phase 4's scope and are not ported here).
    func silentRefresh() async {
        isRefreshing = true
        await loadFriendsActivities(showLoading: false)
        isRefreshing = false
    }

    // MARK: - reloadFriendsFromPersistedCache (ported from lines 358-380)

    func reloadFriendsFromPersistedCache() async {
        await serialized { [weak self] in
            await self?.performReloadFriendsFromPersistedCache()
        }
    }

    /// The Dart original wraps this in try/catch, logging on error (lines 364, 377-379); nothing
    /// in this Swift port (`reloadPersistedCache`/`forceRefresh` are both non-throwing) can throw,
    /// so there is nothing for a catch to handle here.
    private func performReloadFriendsFromPersistedCache() async {
        await buddyService.reloadPersistedCache()
        // Reset the cache timer so the next loadFriendsActivities always hits the API instead of
        // returning the just-loaded stale disk data. Without this, the quiet-mode cache (5 min)
        // makes fresh disk data appear "recently fetched" for up to 4.5 minutes after a resume.
        buddyService.forceRefresh()
        if let cached = buddyService.cachedActivities, !cached.isEmpty {
            friendsActivities = cached
            lastUpdated = Date()
        }
    }

    // MARK: - fastInitialLoad (ported from lines 382-419)

    func fastInitialLoad() async {
        await serialized { [weak self] in
            await self?.performFastInitialLoad()
        }
    }

    /// The Dart original wraps this in try/catch, setting `_error`/clearing the skeleton on
    /// failure (lines 413-417); nothing in this Swift port's call chain can throw, so there is
    /// nothing for a catch to handle here. Calls `performReloadFriendsFromPersistedCache()` and
    /// `performLoadFriendsActivities(...)` directly (not the public `reloadFriendsFromPersistedCache()`/
    /// `loadFriendsActivities()` wrappers) since this method itself already runs inside
    /// `serialized(_:)`; routing back through the public wrappers here would enqueue a second link
    /// onto the chain that waits on this very call to finish, deadlocking.
    private func performFastInitialLoad() async {
        // Ensure persistence load is complete. In the common case it already finished as part of
        // the constructor's own priming step, so this await is a no-op.
        await buddyService.waitUntilPersistenceReady()

        // Sync with any merged historical data the widget wrote while backgrounded.
        await performReloadFriendsFromPersistedCache()

        // If the constructor (or the reload above) already primed the list, skip to the live
        // fetch. Otherwise show stale data now, or the skeleton if nothing is cached.
        //
        // Inherited Dart behavior, not a new bug: when nothing is cached, `isSkeletonLoading` is
        // set true here but this method never clears it back to false, faithfully matching the
        // Dart original (lines 401/408): the subsequent live fetch below is called with
        // `showSkeleton: false`, so `performLoadFriendsActivities`'s own `if showSkeleton {
        // isSkeletonLoading = false }` guard never fires for it. The flag stays true even after
        // real data has loaded. Whatever UI consumes this flag (a later phase) must derive
        // "show skeleton" from `isSkeletonLoading && friendsActivities.isEmpty`, not the flag
        // alone, exactly as the Dart original's own callers must.
        if friendsActivities.isEmpty {
            if let stale = buddyService.cachedActivities, !stale.isEmpty {
                friendsActivities = stale
            } else {
                isSkeletonLoading = true
            }
        }

        // Force a live fetch; merge result with whatever is already on screen.
        buddyService.forceRefresh()
        await performLoadFriendsActivities(showLoading: false, showSkeleton: false)

        lastUpdated = Date()
        await updateWidget(currentUser: nil)
    }

    // MARK: - updateWidget

    /// No-op stub pending Phase 5. The actual widget-writing implementation
    /// (`WidgetService.updateWidget` / `ref_widget_service.dart`) is not ported here; this method
    /// exists only so the two Dart call sites (end of `fastInitialLoad`, end of
    /// `loadFriendsActivities` when `friendsActivities` is non-empty) are already wired for
    /// Phase 5 to fill in.
    func updateWidget(currentUser: User?) async {
    }
}
