import Foundation
import Observation

/// Pure-Swift port of the activities-feed and profile-data slices of
/// `lib/providers/spotify_provider.dart` (`SpotifyProvider`): constructor priming,
/// `setBearer`/`clearBearer`, `loadFriendsActivities`, this phase's narrowed `silentRefresh`,
/// `reloadFriendsFromPersistedCache`, `fastInitialLoad`, `clearError`/`clearData`/`clearAuthError`,
/// the `updateWidget` stub, and (Task 4) the profile/currently-playing loaders
/// (`loadCurrentlyPlaying`, `loadTopTracks`, `loadTopArtists`, `refreshProfileData`). Dart's
/// `refreshData`/`fullRefresh` (the four-loader combo that also includes `loadFriendsActivities`)
/// are a later task's scope and are deliberately not ported here.
///
/// `@unchecked Sendable`: mirrors `BuddyActivityService`'s own reasoning, for the same mechanical
/// cause. Constructor-time priming (below) fires a `Task { [weak self] in ... }` to mirror the
/// Dart constructor's fire-and-forget `_buddyService.persistenceReady.then(...)`, and Swift 6
/// only allows a class to be captured that way if it is `Sendable`. This store's instance state IS
/// protected against the specific hazard Task 2's review raised (see `serialized(_:)` below):
/// every method that touches `buddyService`, or mutates this store's own observable properties,
/// funnels through a single `NSLock`-guarded task chain, so at most one such operation is ever
/// actually running at a time regardless of how many external callers (a refresh button, an
/// auto-refresh timer, `ActivitiesScreen.handleReAuth()`, the root-wiring bearer-token bridge)
/// fire concurrently.
///
/// Corrected claim, previously wrong in this comment: this is genuinely true of every mutating
/// method now, not just the four originally wired through `serialized(_:)`
/// (`loadFriendsActivities`/`fastInitialLoad`/`reloadFriendsFromPersistedCache`/constructor
/// priming). `setBearer`/`clearBearer`/`clearData`/`clearError`/`clearAuthError` were plain
/// synchronous methods until this phase's whole-branch review caught it: since `ActivitiesScreen`
/// is implicitly `@MainActor` and a synchronous call performs no actor hop, `handleReAuth()`
/// (which calls several of these) wrote these `@Observable` properties directly on the main actor
/// while the async gate chain wrote the same properties off the main actor, the exact SpotifyStore
/// analogue of the race already fixed twice in `AuthStore`. All five are now `async` and route
/// through `serialized(_:)` like every other mutating method here; `silentRefresh()`'s
/// `isRefreshing` flag was also pulled inside its own gated operation for the same reason (see its
/// own doc comment). What remains genuinely unguarded, matching every other `@Observable` store in
/// this codebase (`AuthStore` included), is a plain concurrent READ of a property (e.g. a UI layer
/// reading `friendsActivities` on one thread while a serialized operation is mid-write on
/// another); that is the same characteristic any mutable class instance shared across threads has
/// in Swift unless explicitly actor-isolated, not a new hazard this store introduces.
///
/// **Corrected during Task 4's review-fix round**: the paragraph above describes ONE gate. Since
/// Task 4 there are TWO independent gates (`serialized(_:)` for the activities feed,
/// `serializedProfile(_:)` for profile data, see that method's own doc comment for why they are
/// kept separate). Each gate still guarantees full serialization of the OPERATIONS routed through
/// it (no two buddylist fetches race each other; no two profile fetches race each other), but the
/// two gates have zero mutual exclusion with each other. A small, explicit set of fields is
/// written from BOTH gates (`friendsActivities`, `topTracks`, `topArtists`, `currentlyPlaying`,
/// `hasAuthError`, `authErrorMessage`, `error`, plus `bearerToken` itself, which every staleness
/// check below reads), so those specific writes are additionally protected by `sharedFieldWriteLock`
/// (declared next to `profileGateLock` below), which is the only thing preventing torn/corrupted
/// concurrent writes to them from the two gates. `sharedFieldWriteLock` is a plain mutual-exclusion
/// lock, not a substitute for either gate: it is held only across the synchronous write
/// statements themselves, never across an `await`, and it says nothing about ordering, only
/// memory safety. Ordering (discarding a stale result that lands after the session that produced
/// it is no longer current) is handled separately, per write site, by re-checking `bearerToken`
/// against the token each loader captured at the start of its own operation.
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

    // MARK: - Profile data (Task 4)

    private(set) var currentlyPlaying: Track?
    private(set) var topTracks: [Track] = []
    private(set) var topArtists: [Artist] = []

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

    // MARK: - Concurrency: second, independent gate for profile-data mutations (Task 4)

    // Structural duplicate of `gateLock`/`gateTail`/`serialized(_:)` above, deliberately NOT
    // reusing that gate: `loadCurrentlyPlaying`/`loadTopTracks`/`loadTopArtists`/
    // `refreshProfileData` each need their OWN operations (a `getTopContent` fetch racing another
    // `getTopContent` fetch, or a buddylist fetch racing another buddylist fetch) serialized
    // against themselves, and coupling this gate to the activities-feed gate would introduce real
    // head-of-line blocking between unrelated concerns (a slow buddylist fetch delaying an
    // unrelated profile-tab load), contradicting Dart's own explicit design (`refreshProfileData`'s
    // doc comment there: it must not suppress concurrent friend-activity notifications). Every
    // method that touches `buddyService.getTop*` routes through `serializedProfile(_:)` here
    // instead of `serialized(_:)`, matching the "route every mutation through the gate"
    // discipline, applied to this second, independent gate. See `serialized(_:)` above for the
    // full FIFO-chaining rationale and the same cancellation limitation, which applies identically
    // here.
    //
    // **Corrected during Task 4's review-fix round**: this gate does NOT mean the two gates touch
    // disjoint state, a prior version of this comment claimed that and it was wrong.
    // `friendsActivities`/`topTracks`/`topArtists`/`currentlyPlaying`/`hasAuthError`/
    // `authErrorMessage`/`error` (plus `bearerToken`) are written from BOTH gates (activities-feed
    // auth failures and profile auth failures both clear all four cached-data fields, matching
    // Dart; `clearBearer()`/`clearData()` on gate A clear the same fields a profile loader on gate
    // B might be about to write). What the two gates actually guarantee independently is
    // OPERATION-level serialization within themselves; the shared FIELDS additionally need
    // `sharedFieldWriteLock` below, since the two gates have no mutual exclusion with each other.
    private let profileGateLock = NSLock()
    private var profileGateTail: Task<Void, Never>?

    private func serializedProfile(_ operation: @escaping @Sendable () async -> Void) async {
        let ticket: Task<Void, Never> = profileGateLock.withLock {
            let previous = profileGateTail
            let next = Task {
                if let previous { _ = await previous.value }
                await operation()
            }
            profileGateTail = next
            return next
        }
        await ticket.value
    }

    // MARK: - Concurrency: lock for fields written from both gates (Task 4 review-fix round)

    // `friendsActivities`, `topTracks`, `topArtists`, `currentlyPlaying`, `hasAuthError`,
    // `authErrorMessage`, `error`, and `bearerToken` are each written from operations on BOTH
    // `serialized(_:)` and `serializedProfile(_:)` (see the two gates' own doc comments above for
    // which operations and why). The two gates provide zero mutual exclusion with each other, so
    // without an additional lock two concurrent writes to the same field from the two different
    // gates would be a genuine data race (undefined behavior on Swift's memory model, not just a
    // logic bug). `sharedFieldWriteLock` is that additional lock: acquire it only around the
    // synchronous write statement(s) to one or more of these fields, NEVER across an `await`
    // (an `NSLock` is not reentrant and this codebase's `serialized(_:)`/`serializedProfile(_:)`
    // chains already run each operation on its own `Task`, so holding this lock across an `await`
    // would risk a different operation on the SAME gate deadlocking against it). Every write site
    // to these fields in this file must go through this lock; see each write site's own comment
    // for confirmation.
    //
    // This lock only prevents torn/corrupted writes (memory safety). It says nothing about WHICH
    // write should win when two land close together, an old queued write can still legitimately
    // overwrite a newer one purely by lock-acquisition order. That ordering problem (a stale
    // result from a since-ended session landing after that session was cleared) is handled
    // separately: every loader captures the bearer token it started with, and re-checks
    // `bearerToken == capturedToken` INSIDE this same locked section immediately before writing
    // its result, discarding the result instead of writing it if the session has since changed.
    // See `performLoadFriendsActivities`/`performLoadTopTracks`/`performLoadTopArtists`/
    // `performLoadCurrentlyPlaying`'s own final write-back blocks.
    private let sharedFieldWriteLock = NSLock()

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
            // `friendsActivities` is one of the fields shared with gate B (see
            // `sharedFieldWriteLock`'s doc comment); lock the write even though it is very
            // unlikely a profile operation lands in the same instant as construction.
            self.sharedFieldWriteLock.withLock {
                if let cached, !cached.isEmpty, self.friendsActivities.isEmpty {
                    self.friendsActivities = cached
                }
            }
        }
    }

    // MARK: - Bearer token (ported from lines 76-83)

    /// `async`, routed through `serialized(_:)`: see this class's own doc comment for why a plain
    /// synchronous write here raced the async gate chain.
    func setBearer(_ token: String) async {
        await serialized { [weak self] in
            guard let self else { return }
            // `bearerToken` is read (unlocked) by loaders on both gates for the staleness check
            // described on `sharedFieldWriteLock`; write it under that same lock so a concurrent
            // staleness check on the other gate never observes a torn value.
            self.sharedFieldWriteLock.withLock {
                self.bearerToken = token
            }
        }
    }

    /// `async`, routed through `serialized(_:)`. Also clears `BuddyActivityService`'s persisted
    /// buddylist cache, matching Dart's `AuthProvider.logout()` calling
    /// `_buddyService.clearActivityCache()` directly: this is where that call actually lands in
    /// this port (see `AuthStore.logout()`'s own doc comment for why it isn't done there instead).
    /// Without this, one account's friends could bleed into a different account's buddylist on the
    /// same device after a logout/re-login. Calls the private `performClearData()` directly, not
    /// the public `clearData()`, since the latter is itself routed through `serialized(_:)` and
    /// nesting a second `serialized(_:)` call from inside an already-running one would deadlock
    /// (the new link would wait for the current link, which is itself).
    func clearBearer() async {
        await serialized { [weak self] in
            guard let self else { return }
            self.sharedFieldWriteLock.withLock {
                self.bearerToken = nil
            }
            self.performClearData()
            self.buddyService.clearActivityCache()
        }
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

    /// Ported from `_handleAuthenticationError` (lines 96-107): clears every cached data field
    /// this store owns (`friendsActivities`, `topTracks`, `topArtists`, `currentlyPlaying`, all
    /// four together, matching Dart exactly), regardless of which loader detected the auth
    /// failure, plus sets `hasAuthError`/`authErrorMessage`/`error`, 7 fields total.
    ///
    /// **Corrected during Task 4's review-fix round**: this method's writes are genuinely racy
    /// against each other when called from the two different gates (an activities-feed 401 and a
    /// profile 401 landing at the same moment), and that is NOT a harmless "unguarded read"
    /// characteristic, unsynchronized concurrent WRITES to the same field from two threads are
    /// undefined behavior on Swift's memory model, a materially worse hazard than a stale read.
    /// The `loadCurrentlyPlaying` "exemption" this comment previously claimed was also wrong:
    /// that loader never calls this method, but it directly writes `currentlyPlaying`, one of the
    /// exact fields this method also writes, so it races this method's writes from the OTHER gate
    /// just the same.
    ///
    /// This is why this method does NOT acquire `sharedFieldWriteLock` itself: it must be called
    /// with that lock ALREADY held by the caller (every call site in this file wraps its call in
    /// `sharedFieldWriteLock.withLock { ... }` alongside that operation's own staleness check), so
    /// this method composes inside the caller's locked section instead of deadlocking against it
    /// (`NSLock` is not reentrant).
    private func writeAuthenticationErrorLocked(_ error: String) {
        logger.error("Authentication error detected in store: \(error)")
        hasAuthError = true
        authErrorMessage = error
        friendsActivities = []
        topTracks = []
        topArtists = []
        currentlyPlaying = nil
        self.error = "Authentication expired. Please login again."
    }

    /// Ported from `clearAuthError` (lines 109-114). `async`, routed through `serialized(_:)`: see
    /// this class's own doc comment for why a plain synchronous write here raced the async gate
    /// chain.
    func clearAuthError() async {
        await serialized { [weak self] in
            guard let self else { return }
            self.sharedFieldWriteLock.withLock {
                self.hasAuthError = false
                self.authErrorMessage = nil
            }
        }
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
    ///
    /// **Task 4 review-fix round**: `token` is captured once at the top (already the established
    /// shape) and reused as the staleness anchor for the final write-back below: if `bearerToken`
    /// no longer equals `token` by the time the fetch resolves (a `clearBearer()`/`setBearer()` on
    /// gate A, or the token changing for any other reason, happened while this fetch was in
    /// flight), the fetch result is discarded instead of written, since it belongs to a session
    /// that is no longer current. Every write into one of the 7 fields shared with gate B
    /// (`sharedFieldWriteLock`'s doc comment) is deferred into local variables during the
    /// do/catch, then applied together inside one `sharedFieldWriteLock.withLock { }` block guarded
    /// by that same staleness check, so this method's outcome, success, auth failure, or plain
    /// failure, is written atomically and only for the still-current session.
    private func performLoadFriendsActivities(showLoading: Bool, showSkeleton: Bool) async {
        guard let token = bearerToken else {
            sharedFieldWriteLock.withLock { error = "Not authenticated" }
            if showLoading { isLoading = false }
            if showSkeleton { isSkeletonLoading = false }
            return
        }

        if showLoading {
            isLoading = true
            sharedFieldWriteLock.withLock { error = nil }
        } else if showSkeleton {
            isSkeletonLoading = true
            sharedFieldWriteLock.withLock { error = nil }
        }

        var activities: [Activity] = []
        var fetchSucceeded = false
        var authFailed = false
        var caughtAuthErrorMessage: String?
        var caughtErrorMessage: String?

        do {
            activities = try await buddyService.getFriendActivity(bearerToken: token)
            fetchSucceeded = true
        } catch {
            logger.error("Failed to fetch friend activities: \(error)")
            let errorMessage = "\(error)"
            if isAuthenticationError(errorMessage) {
                authFailed = true
                logger.info("Authentication error detected, may need re-authentication")
                caughtAuthErrorMessage = errorMessage
            } else {
                caughtErrorMessage = "Failed to load friend activities: \(errorMessage)"
            }
        }

        // The home widget renders from the buddy service's accumulated cache, so the in-app list
        // must never show fewer friends than that cache. Prefer the live result when it is at
        // least as large; otherwise keep the accumulated cache (or the list already on screen if
        // it is larger). `buddyService.cachedActivities` is this service's own instance state, not
        // one of the 7 shared fields, so reading it here (outside the lock) is fine.
        let cached = buddyService.cachedActivities

        sharedFieldWriteLock.withLock {
            guard bearerToken == token else { return }

            if let caughtAuthErrorMessage {
                writeAuthenticationErrorLocked(caughtAuthErrorMessage)
            } else if let caughtErrorMessage {
                self.error = caughtErrorMessage
            }

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
                // Empty success or transient (non-auth) failure: never drop to zero cards.
                // Spotify's buddylist intermittently returns an empty feed even when friends are
                // active, so an empty result is not reliably "nothing to show". Keep the friends
                // already on screen.
                if !accumulated.isEmpty {
                    friendsActivities = accumulated
                }
            }
        }

        if showLoading { isLoading = false }
        if showSkeleton { isSkeletonLoading = false }

        if !friendsActivities.isEmpty {
            await updateWidget(currentUser: nil)
        }
    }

    // MARK: - clearError / clearData (ported from lines 291-309)

    /// `async`, routed through `serialized(_:)`: see this class's own doc comment for why a plain
    /// synchronous write here raced the async gate chain.
    func clearError() async {
        await serialized { [weak self] in
            guard let self else { return }
            self.sharedFieldWriteLock.withLock {
                self.error = nil
            }
        }
    }

    /// Since Task 4, also clears `topTracks`/`topArtists`/`currentlyPlaying`, matching Dart's
    /// `clearData()` exactly (it clears all four cached-data fields together).
    ///
    /// **Corrected during Task 4's review-fix round**: this runs under `serialized(_:)`, not
    /// `serializedProfile(_:)`, so a concurrently-running profile operation's own write to one of
    /// these fields is a genuine data race, not a merely-accepted characteristic; the 7 fields
    /// shared with gate B (`friendsActivities`/`topTracks`/`topArtists`/`currentlyPlaying`/
    /// `error`/`hasAuthError`/`authErrorMessage`) are written here under `sharedFieldWriteLock`.
    /// `isLoading`/`isRefreshing`/`isSkeletonLoading`/`lastUpdated` are not in the shared set (only
    /// gate A ever writes them) and stay unlocked.
    private func performClearData() {
        sharedFieldWriteLock.withLock {
            friendsActivities = []
            topTracks = []
            topArtists = []
            currentlyPlaying = nil
            error = nil
            hasAuthError = false
            authErrorMessage = nil
        }
        isLoading = false
        isRefreshing = false
        isSkeletonLoading = false
        lastUpdated = nil
    }

    /// `async`, routed through `serialized(_:)`: see this class's own doc comment for why a plain
    /// synchronous write here raced the async gate chain.
    func clearData() async {
        await serialized { [weak self] in
            self?.performClearData()
        }
    }

    // MARK: - silentRefresh (this phase's narrowed version of lines 345-356)

    /// This phase's narrowed `silentRefresh`: calls only `loadFriendsActivities`, not the Dart
    /// `refreshData`'s four-loader `Future.wait` (`loadCurrentlyPlaying`/`loadTopTracks`/
    /// `loadTopArtists` are Phase 4's scope and are not ported here).
    ///
    /// Routed through `serialized(_:)` with `isRefreshing` set/cleared *inside* the same gated
    /// operation as the load, not bracketing an `await` outside the gate: the previous shape set
    /// `isRefreshing = true`, awaited the (separately gated) public `loadFriendsActivities`, then
    /// set `isRefreshing = false`, which left a window where a second concurrent caller could read
    /// `isRefreshing` as `false` while this operation was still queued behind another one on the
    /// gate. Calls `performLoadFriendsActivities` directly (not the public `loadFriendsActivities`
    /// wrapper) for the same nesting-deadlock reason `performFastInitialLoad` does.
    func silentRefresh() async {
        await serialized { [weak self] in
            guard let self else { return }
            self.isRefreshing = true
            await self.performLoadFriendsActivities(showLoading: false, showSkeleton: false)
            self.isRefreshing = false
        }
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
            // `friendsActivities` is shared with gate B; lock the write (see
            // `sharedFieldWriteLock`'s doc comment). This method has no bearer token of its own to
            // stage a staleness check against (it reads persisted disk data, not a live fetch tied
            // to a session), so only Part A (the lock) applies here, not Part B (the token check).
            sharedFieldWriteLock.withLock {
                friendsActivities = cached
            }
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
                // Shared field, lock the write; no token to stage a staleness check against, same
                // reasoning as `performReloadFriendsFromPersistedCache` above.
                sharedFieldWriteLock.withLock {
                    friendsActivities = stale
                }
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
    ///
    /// Both current call sites are inside an already-gated `serialized(_:)` operation. Do NOT
    /// route Phase 5's real implementation through `serialized(_:)` itself, `serialized(_:)` is
    /// not reentrant and doing so would deadlock.
    func updateWidget(currentUser: User?) async {
    }

    // MARK: - loadCurrentlyPlaying (Task 4, ported from ref_spotify_provider.dart:116-143)

    /// Deliberately asymmetric, ported faithfully from Dart: unlike `loadTopTracks`/
    /// `loadTopArtists` below, this never routes a failure through `isAuthenticationError`/
    /// `writeAuthenticationErrorLocked`, and never throws out of its own gated operation. This is
    /// Dart's own deliberate choice for a frequently-polled endpoint, not a bug to fix. Routed
    /// through `serializedProfile(_:)`, the second, independent gate (see that method's doc
    /// comment): has no relationship to `BuddyActivityService` at all (a standalone
    /// `api.spotify.com` call), so it never touches the activities-feed gate either. It DOES still
    /// write `currentlyPlaying`, one of the fields shared with gate A (see `sharedFieldWriteLock`'s
    /// doc comment), so its own writes are locked and staleness-checked the same as the other
    /// three loaders, even though it never calls `writeAuthenticationErrorLocked` itself.
    func loadCurrentlyPlaying(showLoading: Bool = false) async {
        await serializedProfile { [weak self] in
            await self?.performLoadCurrentlyPlaying(showLoading: showLoading)
        }
    }

    /// Ported from `loadCurrentlyPlaying` (lines 116-143). The Dart original's own inner call
    /// (`_spotifyService.getCurrentlyPlaying`) never throws (it catches internally and returns
    /// `null`); `Self.fetchCurrentlyPlaying` below mirrors that for every HTTP outcome (200 no
    /// item, 204, any other status all resolve to `nil`, log only), so this `catch` only exists
    /// for a genuine transport-level failure (matching the Dart `try`/`catch`'s own remaining
    /// purpose), never an HTTP status.
    ///
    /// **Task 4 review-fix round**: same staleness-guarded, locked write-back shape as
    /// `performLoadTopTracks`/`performLoadTopArtists` below. `currentlyPlaying` legitimately can
    /// BE `nil` on a successful fetch (nothing playing), so a plain `Track?` local is not enough
    /// to distinguish "fetch happened, result is nil" from "fetch never ran/threw"; `didFetch`
    /// makes that explicit.
    private func performLoadCurrentlyPlaying(showLoading: Bool) async {
        if showLoading {
            isLoading = true
            sharedFieldWriteLock.withLock { error = nil }
        }

        if let token = bearerToken {
            var didFetch = false
            var fetchedTrack: Track?
            var caughtErrorMessage: String?

            do {
                fetchedTrack = try await Self.fetchCurrentlyPlaying(bearerToken: token)
                didFetch = true
            } catch {
                logger.error("Failed to load currently playing: \(error)")
                let errorMessage = "\(error)"
                if !errorMessage.contains("No Bearer token available") {
                    caughtErrorMessage = errorMessage
                }
            }

            sharedFieldWriteLock.withLock {
                guard bearerToken == token else { return }
                if didFetch {
                    currentlyPlaying = fetchedTrack
                } else {
                    currentlyPlaying = nil
                    if let caughtErrorMessage {
                        self.error = caughtErrorMessage
                    }
                }
            }
        } else {
            sharedFieldWriteLock.withLock { currentlyPlaying = nil }
        }

        if showLoading { isLoading = false }
        await updateWidget(currentUser: nil)
    }

    /// Fetches `GET https://api.spotify.com/v1/me/player/currently-playing` directly (confirmed
    /// exact endpoint via `/tmp/ref_api_constants.dart`). No relationship to `BuddyActivityService`
    /// at all, so this uses its own injectable seam (`SpotifyTokenService.currentlyPlayingFetchOverride`)
    /// rather than that service's overrides. Headers mirror the Dart original's own header set
    /// exactly (`/tmp/ref_spotify_service.dart:45-52`), not `getFriendActivity`'s WebPlayer-style
    /// headers: this is Dart's `SpotifyService.getCurrentlyPlaying`, a different real HTTP client
    /// than `SpotifyBuddyService`, with its own distinct header shape (`okhttp` user agent, an
    /// explicit `Host` header) worth porting faithfully rather than normalizing away.
    private static func fetchCurrentlyPlaying(bearerToken: String) async throws -> Track? {
        let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.setValue("api.spotify.com", forHTTPHeaderField: "Host")
        request.setValue("okhttp/4.9.2", forHTTPHeaderField: "User-Agent")

        let (statusCode, body) = try await SpotifyTokenService.performCurrentlyPlayingRequest(request)

        guard statusCode == 200 else {
            if statusCode != 204 {
                logger.warning("Failed to get currently playing: \(statusCode)")
            }
            return nil
        }
        guard let data = body.data(using: String.Encoding.utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = json["item"] as? [String: Any] else {
            return nil
        }
        return Track.fromJson(item)
    }

    // MARK: - loadTopTracks (Task 4, ported from ref_spotify_provider.dart:145-172)

    func loadTopTracks(timeRange: String = "medium_term", showLoading: Bool = false) async {
        await serializedProfile { [weak self] in
            await self?.performLoadTopTracks(timeRange: timeRange, showLoading: showLoading)
        }
    }

    /// Ported from `loadTopTracks` (lines 145-172). Note the early-return asymmetry versus
    /// `performLoadFriendsActivities`, faithfully preserved: the no-token branch here does NOT
    /// reset `isLoading`, matching Dart exactly (its null check runs before the `showLoading`
    /// block even touches `_isLoading`, so there is nothing to reset on that path).
    ///
    /// **Task 4 review-fix round**: `token` is captured once at the top and reused as the
    /// staleness anchor: the fetch result (success, auth failure, or plain failure) is only
    /// written if `bearerToken` still equals `token` by the time the fetch resolves, discarding it
    /// otherwise (the session that started this fetch is no longer current). See
    /// `sharedFieldWriteLock`'s doc comment for why this check runs inside the same locked block
    /// as the write, not before it.
    private func performLoadTopTracks(timeRange: String, showLoading: Bool) async {
        guard let token = bearerToken else {
            sharedFieldWriteLock.withLock { error = "Not authenticated" }
            return
        }

        if showLoading {
            isLoading = true
            sharedFieldWriteLock.withLock { error = nil }
        }

        var fetchedTracks: [Track]?
        var caughtAuthErrorMessage: String?
        var caughtErrorMessage: String?

        do {
            fetchedTracks = try await buddyService.getTopTracks(bearerToken: token, timeRange: timeRange)
        } catch {
            let errorMessage = "\(error)"
            if isAuthenticationError(errorMessage) {
                caughtAuthErrorMessage = errorMessage
            } else {
                caughtErrorMessage = errorMessage
            }
        }

        sharedFieldWriteLock.withLock {
            guard bearerToken == token else { return }
            if let caughtAuthErrorMessage {
                writeAuthenticationErrorLocked(caughtAuthErrorMessage)
            } else if let caughtErrorMessage {
                self.error = caughtErrorMessage
            } else if let fetchedTracks {
                topTracks = fetchedTracks
            }
        }

        if showLoading { isLoading = false }
    }

    // MARK: - loadTopArtists (Task 4, ported from ref_spotify_provider.dart:174-210)

    func loadTopArtists(timeRange: String = "medium_term", showLoading: Bool = false) async {
        await serializedProfile { [weak self] in
            await self?.performLoadTopArtists(timeRange: timeRange, showLoading: showLoading)
        }
    }

    /// Ported from `loadTopArtists` (lines 174-210), same no-token early-return asymmetry as
    /// `performLoadTopTracks` above, and the same staleness-anchor/locked-write-back shape (see
    /// that method's doc comment).
    ///
    /// `onArtistDetailsUpdate` mirrors Dart's progressive-disclosure callback (it directly
    /// mutates `_topArtists` and notifies on every incremental update), but `BuddyActivityService`
    /// invokes it from its own detached background fan-out `Task`, entirely outside this method's
    /// (and its enclosing `serializedProfile` operation's) own execution -- by the time the first
    /// incremental update arrives, `performLoadTopArtists` has typically already returned. Per
    /// Global Constraints ("every progressive artist-details update is its own `serialized(_:)`
    /// call on the second gate, not a single unguarded property write mid-operation"), each
    /// incremental update is queued as its own new `serializedProfile(_:)` operation rather than
    /// writing `topArtists` directly from the synchronous callback. This is not a nested-gate
    /// deadlock: `Task { }` here starts an independent, unstructured unit of work that this
    /// callback does not await, so it does not block (or get blocked by) the `serializedProfile`
    /// operation `performLoadTopArtists` itself is already running inside. `token` is captured by
    /// the closure (a `let String`, safe to capture by value) and re-checked under
    /// `sharedFieldWriteLock` the same way the final write-back below does, since a progressive
    /// update can land well after this method itself has returned, potentially after the session
    /// that started the fan-out is no longer current.
    private func performLoadTopArtists(timeRange: String, showLoading: Bool) async {
        guard let token = bearerToken else {
            sharedFieldWriteLock.withLock { error = "Not authenticated" }
            return
        }

        if showLoading {
            isLoading = true
            sharedFieldWriteLock.withLock { error = nil }
        }

        var fetchedArtists: [Artist]?
        var caughtAuthErrorMessage: String?
        var caughtErrorMessage: String?

        do {
            let artists = try await buddyService.getTopArtistsWithDetails(
                bearerToken: token,
                timeRange: timeRange,
                onArtistDetailsUpdate: { [weak self] updatedArtists in
                    guard let self else { return }
                    Task {
                        await self.serializedProfile { [weak self] in
                            guard let self else { return }
                            self.sharedFieldWriteLock.withLock {
                                guard self.bearerToken == token else { return }
                                self.topArtists = updatedArtists
                            }
                        }
                    }
                }
            )
            fetchedArtists = artists
        } catch {
            let errorMessage = "\(error)"
            if isAuthenticationError(errorMessage) {
                caughtAuthErrorMessage = errorMessage
            } else {
                caughtErrorMessage = errorMessage
            }
        }

        sharedFieldWriteLock.withLock {
            guard bearerToken == token else { return }
            if let caughtAuthErrorMessage {
                writeAuthenticationErrorLocked(caughtAuthErrorMessage)
            } else if let caughtErrorMessage {
                self.error = caughtErrorMessage
            } else if let fetchedArtists {
                topArtists = fetchedArtists
            }
        }

        if showLoading { isLoading = false }
    }

    // MARK: - refreshProfileData (Task 4, ported from ref_spotify_provider.dart:331-345)

    /// Loads only profile-related data (currently playing, top tracks, top artists), matching
    /// Dart's own doc comment: does NOT fetch friend activity (the home screen owns that call via
    /// the other gate), and runs the three loaders sequentially (see the correction below for why
    /// not concurrently) inside a SINGLE `serializedProfile(_:)` call rather than three separate
    /// ones. Calling the three PUBLIC gated wrappers here (each of which itself calls
    /// `serializedProfile(_:)`) would enqueue three more links behind this very operation on the
    /// same gate and self-deadlock, the identical hazard `performFastInitialLoad` already avoids
    /// on the other gate; instead this calls the three loaders' PRIVATE, non-gated `performX`
    /// implementations directly, mirroring how `silentRefresh()`/`fastInitialLoad()` do the same
    /// on `serialized(_:)`.
    ///
    /// **Corrected during Task 4's review-fix round**: this previously ran the three loaders via
    /// `withTaskGroup(of: Void.self)` for genuine concurrency, matching Dart's `Future.wait` shape
    /// on paper. That was wrong on two counts. First, it is not actually Dart parity: Dart's
    /// `Future.wait` runs on a single-threaded event loop with no true parallelism, each future
    /// only interleaves at its own `await` points, so it never races another future's writes.
    /// `withTaskGroup`'s tasks run genuinely concurrently on real threads. Second, and more
    /// seriously, that genuine concurrency defeated `serializedProfile(_:)`'s own purpose from
    /// INSIDE the gate: all three loaders write `error`/`isLoading` directly, and two of them can
    /// call `writeAuthenticationErrorLocked` (now lock-protected, but still logically racing each
    /// other for which one's outcome wins), so three loaders genuinely running in parallel inside
    /// one gated operation reintroduced the exact "two writers, no ordering" hazard the gate exists
    /// to prevent, just one level deeper.
    ///
    /// Fix: await the three loaders sequentially instead. This is simpler, does not need
    /// `withTaskGroup` at all, and costs nothing in this design: all three are already behind a
    /// single gate slot (no other caller is unblocked between one loader finishing and the next
    /// starting, since the whole sequence runs inside one `serializedProfile { }` operation), so
    /// sequential execution has no user-visible latency cost relative to true parallelism, only the
    /// removal of the intra-gate race.
    func refreshProfileData(showLoading: Bool = false) async {
        await serializedProfile { [weak self] in
            guard let self else { return }
            await self.performLoadCurrentlyPlaying(showLoading: showLoading)
            await self.performLoadTopTracks(timeRange: "medium_term", showLoading: showLoading)
            await self.performLoadTopArtists(timeRange: "medium_term", showLoading: showLoading)
            self.lastUpdated = Date()
        }
    }
}
