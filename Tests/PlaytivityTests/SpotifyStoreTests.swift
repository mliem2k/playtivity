import Foundation
import XCTest
@testable import Playtivity

final class SpotifyStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BuddyActivityService.buddyListFetchOverride = nil
        BuddyActivityService.topContentFetchOverride = nil
        BuddyActivityService.artistDetailsFetchOverride = nil
        SpotifyTokenService.currentlyPlayingFetchOverride = nil
        ApiRetryService.sleepOverride = { _ in } // skip real backoff delays in retry tests
        resetDiagnostics()
    }

    override func tearDown() {
        BuddyActivityService.buddyListFetchOverride = nil
        BuddyActivityService.topContentFetchOverride = nil
        BuddyActivityService.artistDetailsFetchOverride = nil
        SpotifyTokenService.currentlyPlayingFetchOverride = nil
        ApiRetryService.sleepOverride = nil
        resetDiagnostics()
        super.tearDown()
    }

    private func resetDiagnostics() {
        BuddyActivityService.lastDiagnostic = "No fetch yet"
        BuddyActivityService.lastApiFriendCount = -1
        BuddyActivityService.lastParsedCount = -1
        BuddyActivityService.lastMergedCount = -1
    }

    private func freshUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SpotifyStoreTests.\(UUID().uuidString)")!
    }

    private func nowMsEpoch() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    /// Builds a flat buddylist API response body with one track-activity friend per tuple,
    /// matching `BuddyActivityServiceTests`'s own fixture builder.
    private func friendsBody(_ friends: [(id: String, ts: Int64, trackName: String)]) -> String {
        let entries = friends.map { friend in
            """
            {"timestamp":\(friend.ts),"user":{"uri":"spotify:user:\(friend.id)","name":"\(friend.id)","imageUrl":null},
             "track":{"uri":"spotify:track:\(friend.id)","name":"\(friend.trackName)","imageUrl":null,"album":{"name":"Album"},"artist":{"name":"Artist"}}}
            """
        }
        return "{\"friends\": [\(entries.joined(separator: ","))]}"
    }

    private func sampleUser(id: String = "u1") -> User {
        User(id: id, displayName: "Friend", email: "", imageUrl: nil, followers: 0, country: "")
    }

    /// Lock-guarded counter box. A plain captured `var` cannot be mutated from inside a closure
    /// passed directly to `Task { }` under Swift 6 (matches `TOTPGenerator`/
    /// `HeadlessReAuthSpikeCoordinator`'s own `NSLock`-backed reference-type idiom), so the
    /// counter used across a `Task { }` boundary (`runInBackground`/`awaitAll` below) lives behind
    /// a small reference type instead. This restriction is specific to `Task.init`'s closure, not
    /// a general Swift 6 rule: ordinary closures like `BuddyActivityService.buddyListFetchOverride`
    /// below mutate their own captured `var`s (`concurrentEntries`, `maxConcurrentEntries`)
    /// directly with no issue, since they are never themselves handed to `Task { }`.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        func read() -> Int { lock.withLock { value } }
    }

    /// Runs `operation` in the background and returns a poll-until-done handle. Deliberately built
    /// from a bare `Task { }` plus a lock-guarded counter polled with `Task.sleep(for:)`, not
    /// `async let`: `async let` fails to transpile on Skip's Kotlin target (confirmed by an actual
    /// unfiltered `swift test` run: `Initializer type mismatch: expected 'Unit', actual
    /// 'Task<Unit>'` plus `Unresolved reference 'value'` on Kotlin's side), matching
    /// `HeadlessReAuthSpikeLogicTests`'s own documented precedent for this exact concurrency idiom.
    private func runInBackground(_ operation: @escaping @Sendable () async -> Void) -> @Sendable () async -> Void {
        let counter = Counter()
        Task {
            await operation()
            counter.increment()
        }
        return {
            while counter.read() < 1 {
                try? await Task.sleep(for: Duration.milliseconds(5))
            }
        }
    }

    /// Runs every operation concurrently in the background and waits for all of them to finish.
    private func awaitAll(_ operations: [@Sendable () async -> Void]) async {
        let counter = Counter()
        for operation in operations {
            Task {
                await operation()
                counter.increment()
            }
        }
        while counter.read() < operations.count {
            try? await Task.sleep(for: Duration.milliseconds(5))
        }
    }

    private func makeActivity(userId: String, ts: Int64, trackName: String = "Song") -> Activity {
        Activity(
            user: sampleUser(id: userId),
            track: Track(id: "t-\(userId)", name: trackName, artists: ["Artist"], album: "Album", durationMs: 0, uri: "spotify:track:\(userId)"),
            timestamp: Date(timeIntervalSince1970: Double(ts) / 1000.0),
            isCurrentlyPlaying: false,
            type: ActivityType.track
        )
    }

    // MARK: - setBearer / clearBearer

    func testSetBearerThenLoadFriendsActivitiesSucceeds() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }

        await store.setBearer("tok")
        await store.loadFriendsActivities()

        XCTAssertEqual(store.friendsActivities.count, 1)
        XCTAssertNil(store.error)
    }

    func testClearBearerClearsAllData() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        await store.setBearer("tok")
        await store.loadFriendsActivities()
        XCTAssertFalse(store.friendsActivities.isEmpty)

        await store.clearBearer()

        XCTAssertTrue(store.friendsActivities.isEmpty)
        XCTAssertNil(store.lastUpdated)
    }

    func testLoadFriendsActivitiesWithoutBearerSetsNotAuthenticatedError() async {
        let store = SpotifyStore(buddyService: BuddyActivityService(userDefaults: freshUserDefaults()))
        await store.loadFriendsActivities(showLoading: true)
        XCTAssertEqual(store.error, "Not authenticated")
        XCTAssertFalse(store.isLoading, "showLoading must still be cleared on the no-token early return")
    }

    // MARK: - loadFriendsActivities: success

    func testLoadFriendsActivitiesSuccessPopulatesListAndLastUpdated() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }

        await store.loadFriendsActivities(showLoading: true)

        XCTAssertEqual(store.friendsActivities.count, 1)
        XCTAssertNotNil(store.lastUpdated)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.error)
    }

    // MARK: - loadFriendsActivities: never-zero-cards on empty success

    func testLoadFriendsActivitiesEmptySuccessNeverDropsAlreadyLoadedList() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        await store.loadFriendsActivities()
        XCTAssertEqual(store.friendsActivities.count, 1)

        service.forceRefresh()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: "{\"friends\": []}") }
        await store.loadFriendsActivities()

        XCTAssertEqual(store.friendsActivities.count, 1, "an empty fetch result must not clear an already-loaded list")
    }

    // MARK: - loadFriendsActivities: never-zero-cards on non-auth failure

    func testLoadFriendsActivitiesNonAuthFailureNeverDropsAlreadyLoadedList() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        await store.loadFriendsActivities()
        XCTAssertEqual(store.friendsActivities.count, 1)

        service.forceRefresh()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 500, body: "") }
        await store.loadFriendsActivities()

        XCTAssertEqual(store.friendsActivities.count, 1, "a persistent non-auth failure must not clear an already-loaded list")
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.hasAuthError)
    }

    // MARK: - loadFriendsActivities: auth failure DOES clear (deliberately, unlike the above)

    func testLoadFriendsActivitiesAuthFailureClearsListAndSetsAuthErrorFlag() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        await store.loadFriendsActivities()
        XCTAssertEqual(store.friendsActivities.count, 1)

        service.forceRefresh()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 401, body: "") }
        await store.loadFriendsActivities()

        XCTAssertTrue(store.friendsActivities.isEmpty, "an auth failure must clear the list, unlike a non-auth failure")
        XCTAssertTrue(store.hasAuthError)
        XCTAssertNotNil(store.authErrorMessage)
        XCTAssertEqual(store.error, "Authentication expired. Please login again.")
    }

    func testClearAuthErrorResetsFlagAndMessage() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 401, body: "") }
        await store.loadFriendsActivities()
        XCTAssertTrue(store.hasAuthError)

        await store.clearAuthError()

        XCTAssertFalse(store.hasAuthError)
        XCTAssertNil(store.authErrorMessage)
    }

    // MARK: - reloadFriendsFromPersistedCache: forced-refresh side effect

    func testReloadFriendsFromPersistedCacheAppliesForceRefreshSoNextLoadHitsNetwork() async throws {
        let ud = freshUserDefaults()
        let service = BuddyActivityService(userDefaults: ud)
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        let now = nowMsEpoch()

        // Seed the persisted merged cache directly (simulating data written by an earlier session
        // or the home-screen widget), then let a fresh instance pick it up.
        let seeded = [makeActivity(userId: "seed", ts: now)]
        let seededJson = try JSONSerialization.data(withJSONObject: seeded.map { $0.toJson() })
        ud.set(String(data: seededJson, encoding: .utf8), forKey: "buddy_list_merged_json")

        await store.reloadFriendsFromPersistedCache()
        XCTAssertEqual(store.friendsActivities.map { $0.user.id }, ["seed"])
        XCTAssertNotNil(store.lastUpdated)

        // Without forceRefresh, the cache just loaded would look "recently fetched" (quiet-mode 5
        // minute window) and the next loadFriendsActivities would skip the network entirely.
        var networkCalled = false
        BuddyActivityService.buddyListFetchOverride = { _ in
            networkCalled = true
            return (statusCode: 200, body: self.friendsBody([("live", now, "Live Song")]))
        }
        await store.loadFriendsActivities()
        XCTAssertTrue(networkCalled, "reloadFriendsFromPersistedCache must force the next loadFriendsActivities to hit the network")
    }

    // MARK: - fastInitialLoad: stale-then-live sequencing

    func testFastInitialLoadShowsStaleDataThenReplacesWithLiveFetch() async throws {
        let ud = freshUserDefaults()
        // Seed only the raw (not merged) persisted snapshot. Same user id ("u1") as the live fetch
        // below, matching a realistic "same friend, updated track" resume/refresh: mergeWithExisting
        // (BuddyActivityServiceTests already covers its own accumulate-distinct-users semantics
        // exhaustively) would otherwise legitimately keep both users' entries, which is not what
        // this test exists to check.
        let staleBody = friendsBody([("u1", nowMsEpoch() - 1000, "Stale Song")])
        ud.set(staleBody, forKey: "buddy_list_raw_json")

        let service = BuddyActivityService(userDefaults: ud)
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")

        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in
            try? await Task.sleep(for: Duration.milliseconds(120))
            return (statusCode: 200, body: self.friendsBody([("u1", now, "Live Song")]))
        }

        let waitForLoad = runInBackground { await store.fastInitialLoad() }
        try await Task.sleep(for: Duration.milliseconds(30))
        XCTAssertEqual(store.friendsActivities.map { $0.track?.name }, ["Stale Song"], "stale persisted data must be visible before the live fetch resolves")

        await waitForLoad()
        XCTAssertEqual(store.friendsActivities.map { $0.track?.name }, ["Live Song"], "the live fetch result must replace the stale data once it resolves")
        XCTAssertNotNil(store.lastUpdated)
    }

    func testFastInitialLoadShowsSkeletonWhenNothingIsCachedAtAll() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults()) // nothing persisted
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")

        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in
            try? await Task.sleep(for: Duration.milliseconds(120))
            return (statusCode: 200, body: self.friendsBody([("live", now, "Live Song")]))
        }

        let waitForLoad = runInBackground { await store.fastInitialLoad() }
        try await Task.sleep(for: Duration.milliseconds(30))
        XCTAssertTrue(store.isSkeletonLoading, "with nothing cached at all, fastInitialLoad must show the skeleton while the live fetch is in flight")
        XCTAssertTrue(store.friendsActivities.isEmpty)

        await waitForLoad()
        XCTAssertEqual(store.friendsActivities.map { $0.user.id }, ["live"])
        // Inherited Dart behavior (see performFastInitialLoad's doc comment), not overlooked:
        // fastInitialLoad never clears isSkeletonLoading back to false once set, even after the
        // live fetch has populated real data. Pinned here so a future reader can tell this is
        // known, not a bug this test failed to catch.
        XCTAssertTrue(store.isSkeletonLoading, "isSkeletonLoading is inherited-stuck true even though live data has now loaded")
    }

    func testFastInitialLoadDoesNotShowSkeletonWhenConstructorAlreadyPrimedTheList() async throws {
        let ud = freshUserDefaults()
        let now = nowMsEpoch()
        // Same user id ("u1") as the live fetch below (see the sibling stale-then-live test's
        // comment for why: mergeWithExisting legitimately keeps distinct users' entries, which
        // would make a 2-user fixture assert the wrong thing for this specific test's purpose).
        let primed = [makeActivity(userId: "u1", ts: now, trackName: "Primed Song")]
        let primedJson = try JSONSerialization.data(withJSONObject: primed.map { $0.toJson() })
        ud.set(String(data: primedJson, encoding: .utf8), forKey: "buddy_list_merged_json")

        let service = BuddyActivityService(userDefaults: ud)
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")

        BuddyActivityService.buddyListFetchOverride = { _ in
            try? await Task.sleep(for: Duration.milliseconds(120))
            return (statusCode: 200, body: self.friendsBody([("u1", now, "Live Song")]))
        }

        let waitForLoad = runInBackground { await store.fastInitialLoad() }
        try await Task.sleep(for: Duration.milliseconds(30))
        XCTAssertFalse(store.isSkeletonLoading, "the constructor already primed the list from cache, so the skeleton must never show")
        XCTAssertEqual(store.friendsActivities.map { $0.track?.name }, ["Primed Song"], "the constructor-primed data must already be visible before the live fetch resolves")

        await waitForLoad()
        XCTAssertEqual(store.friendsActivities.map { $0.track?.name }, ["Live Song"])
    }

    // MARK: - buddylistParsedCount: larger-of-merged-or-parsed

    func testBuddylistParsedCountReturnsParsedWhenMergedIsSmaller() {
        BuddyActivityService.lastMergedCount = 2
        BuddyActivityService.lastParsedCount = 5
        let store = SpotifyStore(buddyService: BuddyActivityService(userDefaults: freshUserDefaults()))
        XCTAssertEqual(store.buddylistParsedCount, 5)
    }

    func testBuddylistParsedCountReturnsMergedWhenMergedIsLarger() {
        BuddyActivityService.lastMergedCount = 7
        BuddyActivityService.lastParsedCount = 3
        let store = SpotifyStore(buddyService: BuddyActivityService(userDefaults: freshUserDefaults()))
        XCTAssertEqual(store.buddylistParsedCount, 7)
    }

    func testBuddylistDiagnosticAndApiCountPassThrough() {
        BuddyActivityService.lastDiagnostic = "some diagnostic string"
        BuddyActivityService.lastApiFriendCount = 9
        let store = SpotifyStore(buddyService: BuddyActivityService(userDefaults: freshUserDefaults()))
        XCTAssertEqual(store.buddylistDiagnostic, "some diagnostic string")
        XCTAssertEqual(store.buddylistApiCount, 9)
    }

    // MARK: - clearError / clearData

    func testClearErrorResetsOnlyErrorField() async {
        let store = SpotifyStore(buddyService: BuddyActivityService(userDefaults: freshUserDefaults()))
        await store.loadFriendsActivities() // no bearer -> sets error = "Not authenticated"
        XCTAssertNotNil(store.error)

        await store.clearError()
        XCTAssertNil(store.error)
    }

    func testClearDataResetsEverything() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        await store.loadFriendsActivities()
        XCTAssertFalse(store.friendsActivities.isEmpty)

        await store.clearData()

        XCTAssertTrue(store.friendsActivities.isEmpty)
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.isRefreshing)
        XCTAssertFalse(store.isSkeletonLoading)
        XCTAssertNil(store.error)
        XCTAssertNil(store.lastUpdated)
        XCTAssertFalse(store.hasAuthError)
        XCTAssertNil(store.authErrorMessage)
    }

    // MARK: - silentRefresh

    func testSilentRefreshSetsAndClearsIsRefreshing() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        BuddyActivityService.buddyListFetchOverride = { _ in
            try? await Task.sleep(for: Duration.milliseconds(120))
            return (statusCode: 200, body: "{\"friends\": []}")
        }

        XCTAssertFalse(store.isRefreshing)
        let waitForRefresh = runInBackground { await store.silentRefresh() }
        try await Task.sleep(for: Duration.milliseconds(30))
        XCTAssertTrue(store.isRefreshing, "isRefreshing must be true while silentRefresh is in flight, not only before/after")

        await waitForRefresh()
        XCTAssertFalse(store.isRefreshing, "isRefreshing must be cleared once silentRefresh completes")
    }

    func testSilentRefreshDoesNotShowLoadingOrSkeletonIndicators() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: "{\"friends\": []}") }

        await store.silentRefresh()

        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.isSkeletonLoading)
    }

    // MARK: - Constructor-time priming

    func testConstructorPrimesFriendsActivitiesFromPersistedCacheWithoutBearer() async throws {
        let ud = freshUserDefaults()
        let now = nowMsEpoch()
        let seeded = [makeActivity(userId: "seed", ts: now)]
        let seededJson = try JSONSerialization.data(withJSONObject: seeded.map { $0.toJson() })
        ud.set(String(data: seededJson, encoding: .utf8), forKey: "buddy_list_merged_json")

        let service = BuddyActivityService(userDefaults: ud)
        let store = SpotifyStore(buddyService: service)

        // No synchronous guarantee the priming Task has finished yet (matches the Dart original's
        // own fire-and-forget `.then()`), but any call that routes through the store's serialized
        // gate (here, loadFriendsActivities without a bearer) must wait for it first.
        await store.loadFriendsActivities()

        XCTAssertEqual(store.friendsActivities.map { $0.user.id }, ["seed"], "constructor priming must have populated the list from the persisted cache before this call ran")
    }

    // MARK: - Concurrency: hard requirement, no data race between overlapping callers

    func testConcurrentLoadFriendsActivitiesCallsNeverEnterTheBuddyServiceFetchSimultaneously() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")

        let lock = NSLock()
        var concurrentEntries = 0
        var maxConcurrentEntries = 0
        BuddyActivityService.buddyListFetchOverride = { _ in
            lock.withLock {
                concurrentEntries += 1
                maxConcurrentEntries = max(maxConcurrentEntries, concurrentEntries)
            }
            try? await Task.sleep(for: Duration.milliseconds(50))
            lock.withLock { concurrentEntries -= 1 }
            return (statusCode: 200, body: "{\"friends\": []}")
        }

        // Simulate a refresh button tap and an auto-refresh timer firing at effectively the same
        // moment: both call into the store's public API concurrently with no external
        // synchronization.
        await awaitAll([
            { await store.loadFriendsActivities() },
            { await store.silentRefresh() },
        ])

        XCTAssertEqual(maxConcurrentEntries, 1, "two overlapping SpotifyStore callers must never both be inside the buddy-list fetch at once")
    }

    func testConcurrentFastInitialLoadAndReloadFromPersistedCacheAreSerialized() async throws {
        let ud = freshUserDefaults()
        let service = BuddyActivityService(userDefaults: ud)
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")

        let lock = NSLock()
        var concurrentEntries = 0
        var maxConcurrentEntries = 0
        BuddyActivityService.buddyListFetchOverride = { _ in
            lock.withLock {
                concurrentEntries += 1
                maxConcurrentEntries = max(maxConcurrentEntries, concurrentEntries)
            }
            try? await Task.sleep(for: Duration.milliseconds(50))
            lock.withLock { concurrentEntries -= 1 }
            return (statusCode: 200, body: "{\"friends\": []}")
        }

        // reloadFriendsFromPersistedCache alone never enters buddyListFetchOverride (it only
        // reads UserDefaults), so pairing it only with fastInitialLoad would make this test pass
        // even with the serialization gate removed, since only one of the two operands could ever
        // increment concurrentEntries. loadFriendsActivities is added as a third operand
        // specifically so two genuinely competing entries into the override-instrumented fetch
        // exist to race, giving this test the power to actually fail without the gate.
        await awaitAll([
            { await store.fastInitialLoad() },
            { await store.reloadFriendsFromPersistedCache() },
            { await store.loadFriendsActivities() },
        ])

        XCTAssertEqual(maxConcurrentEntries, 1, "fastInitialLoad, reloadFriendsFromPersistedCache, and loadFriendsActivities must not race on the shared BuddyActivityService instance")
    }

    // MARK: - updateWidget: stub, callable, does not throw or crash

    func testUpdateWidgetIsACallableNoOp() async {
        let store = SpotifyStore(buddyService: BuddyActivityService(userDefaults: freshUserDefaults()))
        await store.updateWidget(currentUser: nil)
        // No assertion beyond "did not crash": this is a documented no-op stub pending Phase 5.
    }

    // MARK: - loadCurrentlyPlaying (Task 4)

    func testLoadCurrentlyPlayingParsesItemFromResponse() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        SpotifyTokenService.currentlyPlayingFetchOverride = { _ in
            let responseJson: [String: Any] = ["item": ["uri": "spotify:track:t1", "name": "Now Playing"]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { SpotifyTokenService.currentlyPlayingFetchOverride = nil }

        await store.loadCurrentlyPlaying()
        XCTAssertEqual(store.currentlyPlaying?.uri, "spotify:track:t1")
    }

    func testLoadCurrentlyPlayingReturns204AsNilWithoutSettingError() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        SpotifyTokenService.currentlyPlayingFetchOverride = { _ in (204, "") }
        defer { SpotifyTokenService.currentlyPlayingFetchOverride = nil }

        await store.loadCurrentlyPlaying()
        XCTAssertNil(store.currentlyPlaying)
        // Deliberate asymmetry: no auth-error UI state from this loader.
        XCTAssertFalse(store.hasAuthError)
        XCTAssertNil(store.error)
    }

    func testLoadCurrentlyPlaying401DoesNotSetHasAuthError() async throws {
        // Pins the deliberate Dart asymmetry: unlike loadTopTracks/loadTopArtists,
        // a 401 here must NOT trigger the auth-error UI state.
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        SpotifyTokenService.currentlyPlayingFetchOverride = { _ in (401, "") }
        defer { SpotifyTokenService.currentlyPlayingFetchOverride = nil }

        await store.loadCurrentlyPlaying()
        XCTAssertNil(store.currentlyPlaying)
        XCTAssertFalse(store.hasAuthError, "loadCurrentlyPlaying must not trigger the auth-error state on failure")
    }

    func testLoadTopArtists401SetsHasAuthErrorUnlikeCurrentlyPlaying() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        BuddyActivityService.topContentFetchOverride = { _ in (401, "") }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        await store.loadTopArtists()
        XCTAssertTrue(store.hasAuthError, "loadTopArtists, unlike loadCurrentlyPlaying, must set the auth-error state")
    }

    // MARK: - Critical 2 Part B regression: stale write-back after a mid-flight session change

    func testLoadTopTracksDiscardsStaleResultAfterBearerTokenChangesMidFlight() async throws {
        // Pins the review-round-1 Part B fix: a fetch already in flight when the session changes
        // underneath it (clearBearer here, on the OTHER gate, which is exactly why this race is
        // reachable at all: the two gates never block each other) must discard its result instead
        // of overwriting the freshly-cleared state. Non-vacuity verified by hand: temporarily
        // removing performLoadTopTracks's `guard bearerToken == token` re-check made this test
        // fail (topTracks ended up non-empty with the stale track); restoring the guard makes it
        // pass again. See the task report for the exact before/after output.
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        BuddyActivityService.topContentFetchOverride = { _ in
            try? await Task.sleep(for: .milliseconds(200))
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topTracks": ["items": [
                ["uri": "spotify:track:stale1", "name": "Stale Track"],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        let waitForLoad = runInBackground { await store.loadTopTracks() }
        try await Task.sleep(for: .milliseconds(50)) // ensure the fetch is in flight
        await store.clearBearer()
        await waitForLoad()

        XCTAssertEqual(store.topTracks, [Track](), "a fetch result for a since-cleared session must be discarded, not overwrite the clear")
    }

    func testRefreshProfileDataLoadsAllThreeWithoutDeadlocking() async throws {
        // Renamed from ...LoadsAllThreeConcurrently: after the review-fix round,
        // refreshProfileData awaits its three loaders SEQUENTIALLY inside one
        // serializedProfile{} block (concurrency inside the gate was itself the Critical 1
        // finding), so this test proves the sequence completes without deadlocking, not
        // concurrency, and carries no timing assertion.
        //
        // Discriminates the two topContentFetchOverride calls by ORDER, not by request shape:
        // getTopContent always sets both topTracksInput and topArtistsInput on every request
        // (BuddyActivityService's own design), so a `variables["topTracksInput"] != nil` check
        // is always true and can't tell the two calls apart. Since refreshProfileData is now
        // sequential, call order is deterministic: performLoadTopTracks's getTopTracks fires
        // first, performLoadTopArtists's getTopArtistsWithDetails fires second. The second
        // response carries a genuinely non-empty artist so this test can tell "topArtists was
        // actually parsed" apart from "topArtists is empty because of a shape mismatch".
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        SpotifyTokenService.currentlyPlayingFetchOverride = { _ in (204, "") }
        BuddyActivityService.artistDetailsFetchOverride = { _ in
            (200, "{\"data\":{\"artist\":{\"stats\":{\"followers\":10,\"monthlyListeners\":5}}}}")
        }
        var topContentCallCount = 0
        BuddyActivityService.topContentFetchOverride = { _ in
            topContentCallCount += 1
            if topContentCallCount == 1 {
                let responseJson: [String: Any] = ["data": ["me": ["profile": ["topTracks": ["items": [Any]()]]]]]
                let data = try! JSONSerialization.data(withJSONObject: responseJson)
                return (200, String(data: data, encoding: .utf8)!)
            }
            let artistItem: [String: Any] = [
                "data": [
                    "uri": "spotify:artist:a1",
                    "profile": ["name": "Artist One"],
                    "visuals": ["avatarImage": ["sources": [Any]()]],
                ],
            ]
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [artistItem]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer {
            SpotifyTokenService.currentlyPlayingFetchOverride = nil
            BuddyActivityService.artistDetailsFetchOverride = nil
            BuddyActivityService.topContentFetchOverride = nil
        }

        await store.refreshProfileData()
        await service.waitUntilArtistDetailsFanOutComplete()

        XCTAssertNil(store.currentlyPlaying)
        XCTAssertEqual(store.topTracks, [Track]())
        XCTAssertEqual(store.topArtists.map { $0.id }, ["a1"], "the second topContentFetchOverride call must have been genuinely parsed, not just an empty shape-mismatch fallback")
        XCTAssertEqual(topContentCallCount, 2, "exactly one getTopTracks call and one getTopArtists call, in sequence")
    }

    func testProfileLoadersDoNotBlockOnAConcurrentActivitiesFeedFetch() async throws {
        // Proves the second-gate design: a slow buddylist fetch must not delay
        // an unrelated profile-tab load. Mutation-testable claim: if
        // loadTopArtists were accidentally routed through the SAME gate as
        // loadFriendsActivities, this test's profile call would not resolve
        // until the artificially slow activities fetch finishes, and the
        // elapsed-time assertion below would fail.
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let store = SpotifyStore(buddyService: service)
        await store.setBearer("tok")
        BuddyActivityService.buddyListFetchOverride = { _ in
            try? await Task.sleep(for: .milliseconds(500))
            return (200, "{\"friends\": []}")
        }
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [Any]()]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer {
            BuddyActivityService.buddyListFetchOverride = nil
            BuddyActivityService.topContentFetchOverride = nil
        }

        let slowActivitiesLoad = runInBackground { await store.loadFriendsActivities() }
        let start = ContinuousClock.now
        await store.loadTopArtists()
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, Duration.milliseconds(400), "profile load must not wait on the concurrent slow activities fetch")
        await slowActivitiesLoad()
    }
}
