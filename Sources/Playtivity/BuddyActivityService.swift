import Foundation

// Internal (not `private`) rather than the file-scoped visibility every other error type in this
// file historically used: `testGetTopArtistsAuthErrorThrowsOn401` needs to catch this type by name
// and read `.message` directly (via `@testable import`, which only unlocks `internal`+
// declarations), unlike the older buddy-list tests, which only ever asserted on the error's string
// description.
struct BuddyActivityServiceError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Pure-Swift port of the buddylist fetch/parse/cache/merge/persistence slice of
/// `lib/services/spotify_buddy_service.dart` (`SpotifyBuddyService`, roughly lines 1-680;
/// `getTopContent` and the artist-details `LRUCache` starting around line 850 are Phase 4's scope
/// and are deliberately not ported here).
///
/// Deliberate deviation from the Dart original: Dart's `SpotifyBuddyService` is a process-wide
/// singleton (`SpotifyBuddyService.instance` / `factory SpotifyBuddyService()`). This port is a
/// plain, directly-instantiable class instead, matching how `AuthStore` is owned and injected
/// elsewhere in this codebase; the singleton machinery (Dart lines 30-46) is not ported.
///
/// `parseFriendsJson` (and the diagnostic counters it maintains) uses raw `[String: Any]`/`[Any]`
/// via `JSONSerialization`, never `Decodable` container decoding: Skip's Kotlin transpile target
/// silently mis-decodes an array of a nested custom struct through `Decoder`, confirmed across
/// multiple failure modes while building Task 1's models. The Dart original's dynamic-typing
/// per-field defaults (`_str`, `is Map`, `is int` checks) are mirrored with `as?` casts throughout.
///
/// `@unchecked Sendable`: `persistenceReady`'s `Task` (below) captures `self` internally, which
/// Swift 6 only allows for a `Sendable` type. This class's instance state (`cachedActivities`,
/// the fetch timestamp) is not lock-protected, matching the Dart original's own complete lack of
/// synchronization; that was safe there only because Dart's event loop serializes execution.
/// Here it is safe in practice because every real caller awaits this instance's async methods
/// sequentially (mirroring `AuthStore`'s own single-owner usage pattern), not because concurrent
/// access has been made genuinely safe. A future caller that fans out concurrent calls onto the
/// same instance would need a real lock; none of this phase's callers do.
final class BuddyActivityService: @unchecked Sendable {
    private static let baseUrl = "https://guc-spclient.spotify.com"
    private static let buddyListRawKey = "buddy_list_raw_json"
    private static let buddyListMergedKey = "buddy_list_merged_json"

    // 90 days: maximum age of a persisted friend activity kept on load. The in-memory merge path
    // (mergeWithExisting) never evicts by age; this cutoff only discards ancient entries when
    // reading the merged copy back from disk, matching the Dart original's `_persistenceMaxAge`.
    private static let persistenceMaxAgeSeconds: TimeInterval = 90.0 * 24 * 60 * 60

    // 5 minutes: matches `_currentlyPlayingThresholdMs`. If elapsed time since a friend started a
    // track/episode is under this, they read as "currently playing"; no duration API call needed.
    private static let currentlyPlayingThresholdMs: Int64 = 5 * 60 * 1000

    // Adaptive cache TTL, matching the Dart original's `_activeCacheDuration`/`_quietCacheDuration`
    // exactly. Plain TimeInterval (seconds) rather than Swift's `Duration`: every use compares
    // directly against a `Date`-difference `TimeInterval`, so `Duration` would only add a
    // conversion step with no benefit (unlike `ApiRetryService`/`DebouncedRefreshService`, which
    // hand these values straight to `Task.sleep`).
    private static let activeCacheDurationSeconds: TimeInterval = 30
    private static let quietCacheDurationSeconds: TimeInterval = 5.0 * 60

    // MARK: - Top content / artist details (Phase 4)

    private static let topContentUrl = "https://api-partner.spotify.com/pathfinder/v2/query"
    private static let artistDetailsUrl = "https://api-partner.spotify.com/pathfinder/v1/query"
    private static let topContentSha256Hash = "feb6d55177e2cbce2ac59214f9493f1ef2e4368eec01b3d4c3468fa1b97336e2"
    private static let artistDetailsSha256Hash = "d66221ea13998b2f81883c5187d174c8646e4041d67f5b1e103bc262d447e3a0"
    private static let artistDetailsCacheKey = "artist_details_cache"
    private static let artistDetailsCacheMaxSize = 200
    // 7 days: artist follower/monthly-listener counts don't change often enough to justify
    // re-fetching more frequently, matching the Dart original's `_loadArtistDetailsCache` cutoff.
    private static let artistDetailsCacheTtlSeconds: TimeInterval = 7.0 * 24 * 60 * 60

    // Injectable seam for tests: `URLProtocol` does not transpile on Skip Lite (confirmed in
    // Phase 2), so a closure per real network boundary is the standard technique here, mirroring
    // `SpotifyTokenService`'s override closures. `nonisolated(unsafe)` because Swift 6 rejects a
    // plain mutable static var as unsynchronized global state; production code only reads this,
    // only tests write it, matching the established, reviewed precedent.
    nonisolated(unsafe) static var buddyListFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?

    // Same rationale as `buddyListFetchOverride` above, one closure per real network boundary:
    // `getTopContent` (shared by `getTopTracks`/`getTopArtists`) POSTs to the GraphQL endpoint,
    // and artist-details enrichment GETs a separate query-string endpoint, so each needs its own
    // seam rather than reusing `buddyListFetchOverride` (which would make a test's override
    // ambiguous about which endpoint it is stubbing).
    nonisolated(unsafe) static var topContentFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?
    nonisolated(unsafe) static var artistDetailsFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?

    // MARK: - Diagnostics (ported from the Dart original's static fields on the singleton; the
    // Activities screen header reads these for its mismatch-count badge and long-press debug
    // copy). `nonisolated(unsafe)` for the same reason as `buddyListFetchOverride` above; unlike
    // that override, these ARE written by production code (every parseFriendsJson/getFriendActivity
    // call), mirroring the Dart original's own unsynchronized static-field design (safe there only
    // because Dart's event loop serializes execution; this port keeps the same shape rather than
    // adding a lock the Dart original never had, since these values only ever back a debug display,
    // not app logic).
    nonisolated(unsafe) static var lastDiagnostic = "No fetch yet"
    nonisolated(unsafe) static var lastRawSnippet = ""
    nonisolated(unsafe) static var lastApiBytes = 0
    nonisolated(unsafe) static var lastApiFriendCount = -1
    nonisolated(unsafe) static var lastParsedCount = -1
    nonisolated(unsafe) static var lastMergedCount = -1
    nonisolated(unsafe) static var lastSkipNull = 0
    nonisolated(unsafe) static var lastSkipNoUser = 0
    nonisolated(unsafe) static var lastSkipNoActivity = 0
    nonisolated(unsafe) static var lastSkipException = 0
    nonisolated(unsafe) static var lastSkippedEntryKeys = ""

    private let userDefaults: UserDefaults
    private var cachedBuddyActivitiesStorage: [Activity]?
    private var lastBuddyListFetch: Date?

    // Artist-details enrichment cache, keyed by artist id. Loaded synchronously in `init` (unlike
    // `persistenceReady` below, a plain `UserDefaults.string(forKey:)` read has no async I/O, so
    // there is no need for the lazy-`Task` workaround the buddy-list persistence load uses to
    // dodge Swift's "self used before all stored properties are initialized" ordering rule).
    private let artistDetailsCache: LRUCache<String, [String: Any]>
    // Handle to the most recently spawned background enrichment fan-out (see
    // `getTopArtistsWithDetails`), so tests can await its completion deterministically instead of
    // sleeping a fixed duration. Mirrors `waitUntilPersistenceReady()`'s already-proven
    // `Task<Void, Never>.value` access pattern below.
    private var artistDetailsFanOutTask: Task<Void, Never>?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.artistDetailsCache = Self.loadArtistDetailsCache(from: userDefaults)
    }

    /// Lets a test await the background artist-details fan-out spawned by the most recent
    /// `getTopArtistsWithDetails` call, instead of sleeping a fixed duration. A no-op if no
    /// fan-out has been started yet.
    func waitUntilArtistDetailsFanOutComplete() async {
        await artistDetailsFanOutTask?.value
    }

    /// Completes when the persisted buddy list JSON has been loaded from disk. Deliberate
    /// deviation from the Dart original: Dart's constructor fires `_loadPersistedBuddyList()`
    /// eagerly, assigning the resulting `Future` to `_persistenceReady`. A `lazy var` here defers
    /// the equivalent `Task` to first access instead of firing inside `init`, sidestepping
    /// Swift's "self used before all stored properties are initialized" rule for a stored property
    /// whose own initializer captures `self`. Every real caller (`getFriendActivity` below;
    /// `SpotifyStore`'s constructor-time priming in a later task) touches `persistenceReady` as
    /// its first action anyway, so this is behaviorally equivalent to Dart's eager firing on every
    /// path that matters. Unlike `AuthStore.initialize()`, the loader this awaits reads no
    /// override closures, so there is no analogous "test sets an override after construction, the
    /// async body already read the old value" race to guard against.
    private(set) lazy var persistenceReady: Task<Void, Never> = Task { [weak self] in
        await self?.loadPersistedBuddyList(force: false)
    }

    /// In-memory cached activities (may be stale persisted data on first launch).
    var cachedActivities: [Activity]? { cachedBuddyActivitiesStorage }

    /// Lets an external caller (`SpotifyStore`'s constructor-time priming) await persistence
    /// readiness without touching the `persistenceReady` property directly.
    /// Needed because Skip's Kotlin transpiler fails to resolve `Task<Void, Never>.value` when
    /// accessed on an external instance's property from outside the declaring class, even though
    /// the identical access from inside this class (`getFriendActivity` above) compiles fine.
    func waitUntilPersistenceReady() async {
        _ = await persistenceReady.value
    }

    /// Re-reads the persisted buddy list from disk into memory. Ported from the Dart original's
    /// doc comment (lines 71-77): the home-screen widget writes merged historical friend data to
    /// storage during background updates, but this in-app instance keeps its own in-memory copy;
    /// call this before reading `cachedActivities` to pick up anything written while backgrounded.
    func reloadPersistedCache() async {
        await loadPersistedBuddyList(force: true)
    }

    // MARK: - Cache invalidation

    /// Clears the buddy list cache to force a fresh fetch on next request.
    func clearBuddyListCache() {
        cachedBuddyActivitiesStorage = nil
        lastBuddyListFetch = nil
        logger.info("Cleared buddy list cache, next request will fetch fresh data")
    }

    /// Marks the cache as expired so the next call fetches fresh data, but keeps existing
    /// activities in memory so they can be merged with the fresh response.
    func forceRefresh() {
        lastBuddyListFetch = nil
    }

    func clearActivityCache() {
        clearBuddyListCache()
    }

    // MARK: - Adaptive cache duration

    private var buddyListCacheDuration: TimeInterval {
        guard let activities: [Activity] = cachedBuddyActivitiesStorage, !activities.isEmpty else {
            return Self.activeCacheDurationSeconds
        }
        let hasActive = activities.contains { $0.type == ActivityType.track && $0.isCurrentlyPlaying }
        return hasActive ? Self.activeCacheDurationSeconds : Self.quietCacheDurationSeconds
    }

    /// Checks whether the buddy list cache should be refreshed, based on cache expiration or a
    /// currently-playing track having crossed the 5-minute threshold. Ported from
    /// `_shouldRefreshBuddyList` (lines 291-320).
    func shouldRefreshBuddyList() -> Bool {
        guard let activities: [Activity] = cachedBuddyActivitiesStorage, let lastFetch = lastBuddyListFetch else {
            logger.info("Cache refresh needed: No cached data")
            return true
        }

        let cacheAge = Date().timeIntervalSince(lastFetch)
        if cacheAge >= buddyListCacheDuration {
            logger.info("Cache refresh needed: age exceeded duration")
            return true
        }

        for activity in activities where activity.type == ActivityType.track && activity.isCurrentlyPlaying {
            let elapsedMs = Date().timeIntervalSince(activity.timestamp) * 1000
            if elapsedMs >= Double(Self.currentlyPlayingThresholdMs) {
                logger.info("Cache refresh needed: track by \(activity.user.displayName) exceeded threshold")
                return true
            }
        }

        logger.info("Cache still valid")
        return false
    }

    // MARK: - Status recompute / merge

    /// Recomputes `isCurrentlyPlaying` for `activity` against the current clock. A playlist-type
    /// activity currently marked as playing flips to not-playing (playlists never stay "currently
    /// playing" past the moment they were observed); a track activity's playing flag is recomputed
    /// against the 5-minute threshold. Ported from `_recomputeStatus` (lines 131-145). Reuses
    /// `Activity.computeIsCurrentlyPlaying`, which already implements this exact formula (false
    /// for any non-track type, threshold check otherwise) for `Activity.fromJson`'s own decode-time
    /// recompute.
    func recomputeStatus(_ activity: Activity) -> Activity {
        let computed = Activity.computeIsCurrentlyPlaying(type: activity.type, timestamp: activity.timestamp)
        if computed == activity.isCurrentlyPlaying { return activity }
        return Activity(
            user: activity.user, track: activity.track, playlist: activity.playlist,
            timestamp: activity.timestamp, isCurrentlyPlaying: computed, type: activity.type
        )
    }

    /// Merges `fresh` activities with the existing in-memory cache, keeping the most recent
    /// activity per user. No time-based eviction is applied here (a friend who has not listened
    /// recently must never disappear from the list); fresh data always overrides a stale entry for
    /// the same user. Every merged entry's `isCurrentlyPlaying` is recomputed so a friend who
    /// stopped playing (and is no longer present in the fresh response) flips to false once 5
    /// minutes have elapsed. Ported from `_mergeWithExisting` (lines 152-178).
    func mergeWithExisting(_ fresh: [Activity]) -> [Activity] {
        guard let existing: [Activity] = cachedBuddyActivitiesStorage, !existing.isEmpty else {
            return fresh
        }

        var merged: [String: Activity] = [:]
        for activity in existing {
            merged[activity.user.id] = activity
        }
        for activity in fresh {
            merged[activity.user.id] = activity
        }

        let result = merged.values.map { recomputeStatus($0) }.sorted { $0.timestamp > $1.timestamp }

        let carried = result.count - fresh.count
        if carried > 0 {
            logger.info("Carried over \(carried) friends from cache, total=\(result.count)")
        }
        return result
    }

    // MARK: - Network fetch

    /// Fetches friend activity, cache-checking first via `shouldRefreshBuddyList`. On a cache hit,
    /// returns the cached list with no network request. On a miss, GETs the buddylist endpoint,
    /// parses and merges the response, and only overwrites the in-memory cache/persists to disk
    /// when the merged result is non-empty (an empty or failed fetch must never wipe already-known
    /// friends: the fetch timestamp is still recorded unconditionally so cache-expiry logic
    /// doesn't hammer the API). Ported from `getFriendActivity` (lines 323-390).
    func getFriendActivity(bearerToken: String) async throws -> [Activity] {
        // Await the initial persistence load before checking the cache or merging, mirroring the
        // Dart original's `await _persistenceReady;` (line 331): without this, a fresh instance's
        // in-memory cache is still nil at merge time and the merge would discard every
        // previously-accumulated friend.
        _ = await persistenceReady.value

        if !shouldRefreshBuddyList() {
            logger.info("Using cached buddy list data")
            return cachedBuddyActivitiesStorage ?? []
        }

        return try await ApiRetryService.retryApiCall({
            let url = URL(string: "\(Self.baseUrl)/presence-view/v1/buddylist")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            request.setValue("en", forHTTPHeaderField: "accept-language")
            request.setValue("https://open.spotify.com", forHTTPHeaderField: "origin")
            request.setValue("https://open.spotify.com/", forHTTPHeaderField: "referer")
            request.setValue(SpotifyTokenService.userAgent, forHTTPHeaderField: "User-Agent")

            let (statusCode, body) = try await Self.performBuddyListRequest(request)

            if statusCode == 401 || statusCode == 403 {
                throw BuddyActivityServiceError(message: "Authentication error: \(statusCode)")
            }
            if statusCode != 200 {
                throw BuddyActivityServiceError(message: "Failed to fetch friend activity: \(statusCode)")
            }

            Self.lastApiBytes = body.utf8.count
            Self.lastRawSnippet = String(body.prefix(300))

            let fresh = Self.parseFriendsJson(body)
            let merged = self.mergeWithExisting(fresh)
            Self.lastMergedCount = merged.count
            if merged.count > fresh.count {
                Self.lastDiagnostic += " | merged=\(merged.count)"
            }
            // Always record the fetch time so the cache-expiry logic doesn't hammer the API on
            // every call when the result is empty.
            self.lastBuddyListFetch = Date()
            // Only overwrite the in-memory cache and persistence when the merged result is
            // non-empty: saving [] would wipe the last-known-good data and cause the next launch
            // to show 0 cards even though older friends are still known.
            if !merged.isEmpty {
                self.cachedBuddyActivitiesStorage = merged
                self.saveBuddyListRaw(body)
                await self.saveMergedActivities(merged)
            }
            return merged
        }, operation: "Get Friend Activity")
    }

    private static func performBuddyListRequest(_ request: URLRequest) async throws -> (statusCode: Int, body: String) {
        if let override = buddyListFetchOverride {
            return try await override(request)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: String.Encoding.utf8) ?? ""
        return (statusCode, body)
    }

    // MARK: - Top content (tracks / artists)

    /// Gets the user's top tracks via the shared GraphQL `userTopContent` query. `timeRange` is
    /// accepted for interface parity with the Dart original's public signature, but per the
    /// Global Constraints note it is never threaded into the request body: the real GraphQL schema
    /// only supports `SHORT_TERM`. Ported from `getTopTracks` (`/tmp/ref_spotify_buddy_service_full.dart`
    /// lines 756-835), reading fields directly off each `items` element rather than through an
    /// `item['data']` indirection layer (see `getTopContent`'s doc comment for why).
    func getTopTracks(bearerToken: String, timeRange: String = "medium_term", limit: Int = 20) async throws -> [Track] {
        let data = try await getTopContent(bearerToken: bearerToken, limit: limit)
        let items = Self.topContentItems(data, contentKey: "topTracks")
        return items.compactMap { Self.makeTopTrack(from: $0) }
    }

    /// Gets the user's basic top-artists list (no follower/monthly-listener stats; every returned
    /// `Artist` carries the `-1` not-yet-fetched sentinel). Callers that need enriched stats use
    /// `getTopArtistsWithDetails` instead, which fetches this list first and then fans the
    /// per-artist detail lookups out in the background. Ported from `getTopArtists` (lines
    /// 838-924), deliberately not porting that method's own `_artistDetailsCache` lookup: this
    /// port's `getTopArtists` is unconditionally cache-blind, matching the plan brief's explicit
    /// "(basic list, `-1` sentinel stats)" interface note. Only `getTopArtistsWithDetails`'s
    /// background fan-out consults the cache.
    func getTopArtists(bearerToken: String, timeRange: String = "medium_term", limit: Int = 20) async throws -> [Artist] {
        let data = try await getTopContent(bearerToken: bearerToken, limit: limit)
        let items = Self.topContentItems(data, contentKey: "topArtists")
        return items.compactMap { Self.makeTopArtist(from: $0) }
    }

    /// Gets the basic top-artists list, then spawns a background fan-out that fetches each
    /// artist's missing follower/monthly-listener stats one at a time (never all at once, to avoid
    /// a burst of concurrent requests), invoking `onArtistDetailsUpdate` with the updated full list
    /// after each artist's details arrive (from the network or the cache). Returns the basic list
    /// immediately; the enrichment happens fully in the background. Ported from
    /// `getTopArtistsWithDetails` (lines 927-940).
    func getTopArtistsWithDetails(
        bearerToken: String,
        timeRange: String = "medium_term",
        limit: Int = 20,
        onArtistDetailsUpdate: (@Sendable ([Artist]) -> Void)? = nil
    ) async throws -> [Artist] {
        let artists = try await getTopArtists(bearerToken: bearerToken, timeRange: timeRange, limit: limit)

        // Same `[weak self]` shape as `persistenceReady`'s Task above: the closure only calls a
        // method on self, never mutates a captured var directly (the Skip Kotlin-transpile quirk
        // that rules out capturing a mutable `var` in a `@Sendable` closure doesn't apply here).
        artistDetailsFanOutTask = Task { [weak self] in
            await self?.fetchMissingArtistDetails(bearerToken: bearerToken, artists: artists, onUpdate: onArtistDetailsUpdate)
        }

        return artists
    }

    /// Fetches the GraphQL `userTopContent` payload underlying both `getTopTracks` and
    /// `getTopArtists`: a single request always asks for both `topTracksInput` and
    /// `topArtistsInput` (the verified real endpoint shape has no `includeTopTracks`/
    /// `includeTopArtists` toggle, unlike the Dart original's `getTopContent`), and each caller
    /// reads only the slice it needs from the shared response. `limit` is applied to both input
    /// blocks; splitting it into separate tracks/artists limits (as Dart's internal defaults of
    /// 4/10 do) is not worth the extra parameter for a value the other caller never reads. Ported
    /// from `getTopContent` (lines 669-753), but throws on failure (auth errors distinguishable,
    /// matching `getFriendActivity`'s pattern) instead of Dart's catch-and-return-null: this port's
    /// public methods propagate failures to the caller rather than silently degrading to `[]`,
    /// confirmed by `testGetTopArtistsAuthErrorThrowsOn401`.
    private func getTopContent(bearerToken: String, limit: Int) async throws -> [String: Any] {
        try await ApiRetryService.retryApiCall({
            let url = URL(string: Self.topContentUrl)!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            request.setValue("en", forHTTPHeaderField: "accept-language")
            request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "content-type")
            request.setValue("https://open.spotify.com", forHTTPHeaderField: "origin")
            request.setValue("https://open.spotify.com/", forHTTPHeaderField: "referer")
            request.setValue(SpotifyTokenService.userAgent, forHTTPHeaderField: "User-Agent")

            let requestBody: [String: Any] = [
                "operationName": "userTopContent",
                "variables": [
                    "topTracksInput": [
                        "offset": 0,
                        "limit": limit,
                        "sortBy": "AFFINITY",
                        "timeRange": "SHORT_TERM",
                    ],
                    "topArtistsInput": [
                        "offset": 0,
                        "limit": limit,
                        "sortBy": "AFFINITY",
                        "timeRange": "SHORT_TERM",
                    ],
                ],
                "extensions": [
                    "persistedQuery": [
                        "version": 1,
                        "sha256Hash": Self.topContentSha256Hash,
                    ],
                ],
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (statusCode, body) = try await Self.performTopContentRequest(request)

            if statusCode == 401 || statusCode == 403 {
                throw BuddyActivityServiceError(message: "Authentication error: \(statusCode)")
            }
            if statusCode != 200 {
                throw BuddyActivityServiceError(message: "Failed to fetch top content: \(statusCode)")
            }

            guard let data = body.data(using: String.Encoding.utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BuddyActivityServiceError(message: "Failed to parse top content response")
            }
            return decoded
        }, operation: "Get Top Content")
    }

    private static func performTopContentRequest(_ request: URLRequest) async throws -> (statusCode: Int, body: String) {
        if let override = topContentFetchOverride {
            return try await override(request)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: String.Encoding.utf8) ?? ""
        return (statusCode, body)
    }

    // Navigates `data["data"]["me"]["profile"][contentKey]["items"]`, returning `[]` on any shape
    // mismatch (matches Dart's `as List? ?? []` fallback chain).
    private static func topContentItems(_ data: [String: Any], contentKey: String) -> [Any] {
        guard let dataField = data["data"] as? [String: Any],
              let me = dataField["me"] as? [String: Any],
              let profile = me["profile"] as? [String: Any],
              let content = profile[contentKey] as? [String: Any],
              let items = content["items"] as? [Any] else {
            return []
        }
        return items
    }

    /// Builds a `Track` directly from one `topTracks.items` element. Ported from `getTopTracks`'s
    /// inline parsing loop (lines 778-827), field-by-field like `makeTrack` above rather than
    /// through `Track.fromJson`, since this live GraphQL shape (`albumOfTrack`, `artists.items`,
    /// `duration.totalMilliseconds`) differs from both shapes `Track.fromJson` handles.
    private static func makeTopTrack(from itemAny: Any) -> Track? {
        guard let trackData = itemAny as? [String: Any] else { return nil }
        let albumData = (trackData["albumOfTrack"] as? [String: Any]) ?? [:]
        let artistItems = (trackData["artists"] as? [String: Any])?["items"] as? [Any] ?? []
        let artistNames: [String] = artistItems.map { element in
            guard let artistDict = element as? [String: Any],
                  let profile = artistDict["profile"] as? [String: Any],
                  let name = profile["name"] as? String else {
                return "Unknown Artist"
            }
            return name
        }
        let coverArt = (albumData["coverArt"] as? [String: Any])?["sources"] as? [Any] ?? []
        let imageUrl = bestImageUrl(from: coverArt, preferredHeight: 300)
        let trackUri = (trackData["uri"] as? String) ?? ""
        let durationMs = intValue(from: (trackData["duration"] as? [String: Any])?["totalMilliseconds"]) ?? 0

        return Track(
            id: lastUriSegment(trackUri),
            name: (trackData["name"] as? String) ?? "Unknown Track",
            artists: artistNames,
            album: (albumData["name"] as? String) ?? "Unknown Album",
            albumUri: albumData["uri"] as? String,
            imageUrl: imageUrl,
            durationMs: durationMs,
            uri: trackUri
        )
    }

    /// Builds an `Artist` directly from one `topArtists.items` element, always with the `-1`
    /// not-yet-fetched stats sentinel (see `getTopArtists`'s doc comment). Ported from
    /// `getTopArtists`'s inline parsing loop (lines 865-914), minus the cache lookup this port
    /// deliberately doesn't perform here.
    private static func makeTopArtist(from itemAny: Any) -> Artist? {
        guard let artistData = itemAny as? [String: Any] else { return nil }
        let avatarSources = ((artistData["visuals"] as? [String: Any])?["avatarImage"] as? [String: Any])?["sources"] as? [Any] ?? []
        let imageUrl = bestImageUrl(from: avatarSources, preferredHeight: 320)
        let artistUri = (artistData["uri"] as? String) ?? ""
        let name = (artistData["profile"] as? [String: Any])?["name"] as? String ?? "Unknown Artist"

        return Artist(
            id: lastUriSegment(artistUri),
            name: name,
            imageUrl: imageUrl,
            followers: -1,
            monthlyListeners: -1,
            uri: artistUri
        )
    }

    // Shared by `makeTopTrack`/`makeTopArtist`: prefers an image at exactly `preferredHeight`,
    // falls back to the highest-resolution image found, falls back to the first image in the
    // list. Ported from the identical inline logic duplicated in `getTopTracks` (lines 792-813)
    // and `getTopArtists` (lines 871-892) in the Dart original.
    private static func bestImageUrl(from sources: [Any], preferredHeight: Int) -> String? {
        var preferredUrl: String?
        var maxHeightUrl: String?
        var maxHeight = 0
        for sourceAny in sources {
            guard let source = sourceAny as? [String: Any] else { continue }
            let height = intValue(from: source["height"])
            let url = source["url"] as? String
            if let height, height == preferredHeight, preferredUrl == nil {
                preferredUrl = url
            }
            if let height, height > maxHeight {
                maxHeight = height
                maxHeightUrl = url
            }
        }
        if let preferredUrl { return preferredUrl }
        if let maxHeightUrl { return maxHeightUrl }
        if let first = sources.first as? [String: Any] {
            return first["url"] as? String
        }
        return nil
    }

    // MARK: - Artist details enrichment

    /// Iterates `artists` sequentially (never all at once, to avoid a burst of concurrent
    /// requests), checking `artistDetailsCache` first (including a `failed` entry, which skips
    /// re-querying a known-bad id entirely) before each network call, and invoking `onUpdate` with
    /// the updated full list after each successful network fetch or valid cache hit. Ported from
    /// `_fetchMissingArtistDetails` (lines 943-1009), including the Dart original's "ensure at
    /// least one notification fires even if all fetches failed" fallback (lines 999-1000).
    ///
    /// Deliberate deviation from Dart: staleness (the 7-day TTL) is checked here, at read time, on
    /// every lookup. The Dart original only ever filters stale entries once, when loading the
    /// cache from disk at startup (`_loadArtistDetailsCache`); an entry already in the in-memory
    /// `LRUCache` is treated as valid forever for the rest of that process's lifetime. Checking at
    /// read time here means a long-running instance re-fetches an artist whose cached details have
    /// aged past 7 days, which the Dart original would not do until its next cold start.
    private func fetchMissingArtistDetails(
        bearerToken: String,
        artists: [Artist],
        onUpdate: (@Sendable ([Artist]) -> Void)?
    ) async {
        let missingIds = artists.filter { $0.monthlyListeners == -1 }.map { $0.id }
        guard !missingIds.isEmpty else { return }

        var updatedArtists = artists
        var notified = false
        var cacheModified = false
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        for artistId in missingIds {
            if let cached = artistDetailsCache.get(artistId) {
                if (cached["failed"] as? Bool) == true {
                    continue
                }
                let fetchedAt = Self.int64Value(from: cached["fetchedAt"]) ?? 0
                let ageMs = nowMs - fetchedAt
                if ageMs < Int64(Self.artistDetailsCacheTtlSeconds * 1000) {
                    let followers = Self.intValue(from: cached["followers"]) ?? -1
                    let monthlyListeners = Self.intValue(from: cached["monthlyListeners"]) ?? -1
                    if let idx = updatedArtists.firstIndex(where: { $0.id == artistId }) {
                        updatedArtists[idx] = Self.withStats(updatedArtists[idx], followers: followers, monthlyListeners: monthlyListeners)
                        if let onUpdate {
                            onUpdate(updatedArtists)
                            notified = true
                        }
                    }
                    continue
                }
                // Cache entry is stale: fall through and re-fetch from the network.
            }

            do {
                let details = try await fetchArtistDetails(bearerToken: bearerToken, artistId: artistId)
                artistDetailsCache.put(artistId, [
                    "followers": details.followers,
                    "monthlyListeners": details.monthlyListeners,
                    "fetchedAt": nowMs,
                ])
                cacheModified = true
                if let idx = updatedArtists.firstIndex(where: { $0.id == artistId }) {
                    updatedArtists[idx] = Self.withStats(updatedArtists[idx], followers: details.followers, monthlyListeners: details.monthlyListeners)
                    if let onUpdate {
                        onUpdate(updatedArtists)
                        notified = true
                    }
                }
            } catch {
                logger.warning("Failed to fetch details for artist \(artistId): \(error)")
                artistDetailsCache.put(artistId, ["failed": true, "fetchedAt": nowMs])
                cacheModified = true
            }
        }

        if !notified, let onUpdate {
            onUpdate(updatedArtists)
        }

        if cacheModified {
            saveArtistDetailsCache()
        }
    }

    private static func withStats(_ artist: Artist, followers: Int, monthlyListeners: Int) -> Artist {
        Artist(id: artist.id, name: artist.name, imageUrl: artist.imageUrl, followers: followers, monthlyListeners: monthlyListeners, uri: artist.uri)
    }

    /// Fetches one artist's follower/monthly-listener stats via the api-partner pathfinder GET
    /// endpoint (query-string `variables`/`extensions`, not a POST body). Ported from
    /// `_getArtistDetails` (lines 1013-1055); checks 401/403 before 200 like every other network
    /// call in this file, which Dart's version does not (it only checks for a bare 200 and throws
    /// a generic exception otherwise).
    private func fetchArtistDetails(bearerToken: String, artistId: String) async throws -> (followers: Int, monthlyListeners: Int) {
        try await ApiRetryService.retryApiCall({
            let variablesJson: [String: Any] = ["uri": "spotify:artist:\(artistId)", "locale": ""]
            let extensionsJson: [String: Any] = [
                "persistedQuery": [
                    "version": 1,
                    "sha256Hash": Self.artistDetailsSha256Hash,
                ],
            ]
            let variablesString = String(data: try JSONSerialization.data(withJSONObject: variablesJson), encoding: String.Encoding.utf8) ?? "{}"
            let extensionsString = String(data: try JSONSerialization.data(withJSONObject: extensionsJson), encoding: String.Encoding.utf8) ?? "{}"

            var components = URLComponents(string: Self.artistDetailsUrl)!
            components.queryItems = [
                URLQueryItem(name: "operationName", value: "queryArtistOverview"),
                URLQueryItem(name: "variables", value: variablesString),
                URLQueryItem(name: "extensions", value: extensionsString),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            request.setValue("https://open.spotify.com", forHTTPHeaderField: "origin")
            request.setValue("https://open.spotify.com/", forHTTPHeaderField: "referer")
            request.setValue(SpotifyTokenService.userAgent, forHTTPHeaderField: "User-Agent")

            let (statusCode, body) = try await Self.performArtistDetailsRequest(request)

            if statusCode == 401 || statusCode == 403 {
                throw BuddyActivityServiceError(message: "Authentication error: \(statusCode)")
            }
            if statusCode != 200 {
                throw BuddyActivityServiceError(message: "queryArtistOverview failed: \(statusCode)")
            }

            guard let data = body.data(using: String.Encoding.utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BuddyActivityServiceError(message: "Failed to parse artist details response")
            }
            let artistField = decoded["data"] as? [String: Any]
            let stats = (artistField?["artist"] as? [String: Any])?["stats"] as? [String: Any]
            let followers = Self.intValue(from: stats?["followers"]) ?? 0
            let monthlyListeners = Self.intValue(from: stats?["monthlyListeners"]) ?? 0
            return (followers: followers, monthlyListeners: monthlyListeners)
        }, operation: "Get Artist Details")
    }

    private static func performArtistDetailsRequest(_ request: URLRequest) async throws -> (statusCode: Int, body: String) {
        if let override = artistDetailsFetchOverride {
            return try await override(request)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: String.Encoding.utf8) ?? ""
        return (statusCode, body)
    }

    // MARK: - Artist details cache persistence

    /// Loads the artist-details cache from `UserDefaults`, called synchronously from `init` (see
    /// that property's doc comment for why this can be synchronous while buddy-list persistence
    /// cannot). Unlike the Dart original's `_loadArtistDetailsCache` (lines 1058-1087), stale and
    /// `failed` entries are NOT filtered out here: `failed` entries must survive a restart to keep
    /// skipping a known-bad id (their entire purpose), and staleness is checked at read time
    /// instead (see `fetchMissingArtistDetails`'s doc comment).
    private static func loadArtistDetailsCache(from userDefaults: UserDefaults) -> LRUCache<String, [String: Any]> {
        let cache = LRUCache<String, [String: Any]>(maxSize: artistDetailsCacheMaxSize)
        guard let raw = userDefaults.string(forKey: artistDetailsCacheKey),
              let data = raw.data(using: String.Encoding.utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return cache
        }
        for (artistId, value) in decoded {
            if let details = value as? [String: Any] {
                cache.put(artistId, details)
            }
        }
        return cache
    }

    /// Saves the artist-details cache to `UserDefaults` (fire-and-forget-free: `UserDefaults`
    /// writes are synchronous, matching `saveBuddyListRaw`'s reasoning above). Ported from
    /// `_saveArtistDetailsCache` (lines 1090-1099).
    private func saveArtistDetailsCache() {
        guard let data = try? JSONSerialization.data(withJSONObject: artistDetailsCache.snapshot),
              let encoded = String(data: data, encoding: String.Encoding.utf8) else {
            logger.warning("Failed to save artist details cache: could not encode JSON")
            return
        }
        userDefaults.set(encoded, forKey: Self.artistDetailsCacheKey)
    }

    // MARK: - Persistence

    /// Saves the merged, cross-session-accumulated activity list so it survives restarts. Must be
    /// awaited by `getFriendActivity` (fire-and-forget would risk losing data if the process were
    /// killed before the write completed), matching the Dart original's `_saveMergedActivities`.
    private func saveMergedActivities(_ activities: [Activity]) async {
        let jsonArray = activities.map { $0.toJson() }
        guard let data = try? JSONSerialization.data(withJSONObject: jsonArray),
              let encoded = String(data: data, encoding: String.Encoding.utf8) else {
            logger.warning("Failed to save merged activities: could not encode JSON")
            return
        }
        userDefaults.set(encoded, forKey: Self.buddyListMergedKey)
    }

    /// Saves the raw API response JSON (fire-and-forget, matching the Dart original: UserDefaults
    /// writes are synchronous and cannot fail the way a SharedPreferences platform-channel call
    /// can, so there is no error path to guard here).
    private func saveBuddyListRaw(_ raw: String) {
        userDefaults.set(raw, forKey: Self.buddyListRawKey)
    }

    /// Loads the last-known buddy list from storage, preferring the merged activities (accumulated
    /// across sessions, covers more friends than a single API call) over the raw API snapshot.
    /// When `force` is true, the in-memory cache is overwritten even if already populated (used
    /// after a background widget update may have written newer merged data to disk). Ported from
    /// `_loadPersistedBuddyList` (lines 199-246).
    func loadPersistedBuddyList(force: Bool = false) async {
        if let mergedJson = userDefaults.string(forKey: Self.buddyListMergedKey),
           cachedBuddyActivitiesStorage == nil || force,
           let data = mergedJson.data(using: String.Encoding.utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            let cutoff = Date().addingTimeInterval(-Self.persistenceMaxAgeSeconds)
            var activities: [Activity] = []
            for element in list {
                do {
                    guard let dict = element as? [String: Any] else {
                        throw BuddyActivityServiceError(message: "entry is not an object")
                    }
                    let activity = try Activity.fromJson(dict)
                    if activity.timestamp > cutoff {
                        activities.append(activity)
                    }
                } catch {
                    logger.warning("Skipped corrupted activity entry during load: \(error)")
                }
            }
            activities.sort { $0.timestamp > $1.timestamp }
            if !activities.isEmpty {
                cachedBuddyActivitiesStorage = activities
                lastBuddyListFetch = Date().addingTimeInterval(-25)
                logger.info("Loaded \(activities.count) merged buddy activities")
                return
            }
        }

        // Fallback: raw JSON from the last API response.
        if let raw = userDefaults.string(forKey: Self.buddyListRawKey),
           cachedBuddyActivitiesStorage == nil || force {
            // updateDiagnostics: false, persistence loads must not stomp lastApiBytes/
            // lastRawSnippet with values that belong to the live-HTTP path.
            let activities = Self.parseFriendsJson(raw, updateDiagnostics: false)
            if !activities.isEmpty {
                cachedBuddyActivitiesStorage = activities
                lastBuddyListFetch = Date().addingTimeInterval(-25)
                logger.info("Loaded \(activities.count) persisted buddy activities (raw)")
            }
        }
    }

    // MARK: - parseFriendsJson

    /// Pure JSON parser for the Spotify buddylist API response. Converts `responseBody` into a
    /// sorted list of `Activity` objects with no network calls or caching side effects. `nowMs`
    /// overrides the current timestamp for `isCurrentlyPlaying` calculations, for deterministic
    /// tests. Ported from `parseFriendsJson` (lines 403-629) with the same no-simplification
    /// discipline as the Phase 1 TOTP crypto port: every branch here exists because a real API
    /// response shape needed it.
    static func parseFriendsJson(
        _ responseBody: String,
        nowMs: Int64? = nil,
        updateDiagnostics: Bool = true
    ) -> [Activity] {
        guard let data = responseBody.data(using: String.Encoding.utf8),
              let rawJson = try? JSONSerialization.jsonObject(with: data) else {
            if updateDiagnostics {
                lastDiagnostic = "\(lastApiBytes)b | parse error: invalid JSON | snippet: \(lastRawSnippet)"
            }
            return []
        }

        guard let jsonDict = rawJson as? [String: Any] else {
            if updateDiagnostics {
                lastDiagnostic = "\(lastApiBytes)b | parse error: response is not an object | snippet: \(lastRawSnippet)"
            }
            return []
        }

        let friendsValue = jsonDict["friends"]
        if friendsValue == nil || friendsValue is NSNull {
            if updateDiagnostics {
                lastApiFriendCount = 0
                lastParsedCount = 0
                lastDiagnostic = "\(lastApiBytes)b, no friends key, snippet: \(lastRawSnippet)"
            }
            return []
        }
        guard let friends = friendsValue as? [Any] else {
            // Mirrors Dart's `data['friends'] as List?` throwing a CastError (caught by the outer
            // try/catch) when the key is present but not a List.
            if updateDiagnostics {
                lastDiagnostic = "\(lastApiBytes)b | parse error: friends is not an array | snippet: \(lastRawSnippet)"
            }
            return []
        }

        if updateDiagnostics {
            lastApiFriendCount = friends.count
            lastSkipNull = 0
            lastSkipNoUser = 0
            lastSkipNoActivity = 0
            lastSkipException = 0
            lastSkippedEntryKeys = ""
        }

        let now = nowMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        var activities: [Activity] = []

        for friendAny in friends {
            if friendAny is NSNull {
                if updateDiagnostics { lastSkipNull += 1 }
                continue
            }
            if let activity = parseOneFriendActivity(friendAny, now: now, updateDiagnostics: updateDiagnostics) {
                activities.append(activity)
            }
        }

        if updateDiagnostics {
            lastParsedCount = activities.count
            var skips: [String] = []
            if lastSkipNull > 0 { skips.append("null x \(lastSkipNull)") }
            if lastSkipNoUser > 0 { skips.append("noUser x \(lastSkipNoUser)") }
            if lastSkipNoActivity > 0 { skips.append("noActivity x \(lastSkipNoActivity)") }
            if lastSkipException > 0 { skips.append("exception x \(lastSkipException)") }
            if skips.isEmpty {
                lastDiagnostic = "\(lastApiBytes)b | api=\(friends.count) | parsed=\(activities.count) | snippet: \(lastRawSnippet)"
            } else {
                lastDiagnostic = "\(lastApiBytes)b | api=\(friends.count) | parsed=\(activities.count)" +
                    " | skip: \(skips.joined(separator: ",")) | \(lastSkippedEntryKeys)" +
                    " | snippet: \(lastRawSnippet)"
            }
        }

        activities.sort { $0.timestamp > $1.timestamp }
        return activities
    }

    /// Parses a single buddylist entry into an `Activity`, or returns `nil` if it should be
    /// skipped (recording the specific skip reason via the diagnostic counters, matching the Dart
    /// original's per-branch bookkeeping). `updateDiagnostics` gates only the counter writes.
    private static func parseOneFriendActivity(_ friendAny: Any, now: Int64, updateDiagnostics: Bool) -> Activity? {
        let friendDict = friendAny as? [String: Any]

        // Support both flat {"user":...,"track":...} and envelope-wrapped
        // {"friend":{"user":...,"track":...}} formats from the spclient API. Only treat
        // friend['friend'] as the envelope when it actually carries a user field, an empty {}
        // placeholder must not shadow top-level data.
        let envelopeCandidate = friendDict?["friend"] as? [String: Any]
        let friendData: [String: Any]
        if let envelopeCandidate, let userVal = envelopeCandidate["user"], !(userVal is NSNull) {
            friendData = envelopeCandidate
        } else {
            friendData = friendDict ?? [:]
        }

        let userInfoValue = friendData["user"]
        guard let userInfoValue, !(userInfoValue is NSNull) else {
            if updateDiagnostics {
                lastSkipNoUser += 1
                if lastSkippedEntryKeys.isEmpty {
                    // Not `friendDict.map { ... } ?? "?"`: Skip's Kotlin transpile resolves
                    // `.map` on a nullable Dictionary to Kotlin's Map.map (iterating entries as
                    // Tuple2, not Optional.map's single-value transform), a genuine ambiguity
                    // between Optional.map and Dictionary's own Sequence-style map. Spelled out
                    // with `if let` to avoid it entirely.
                    let outerKeys: String
                    if let friendDict {
                        outerKeys = keysDescription(friendDict)
                    } else {
                        outerKeys = "?"
                    }
                    lastSkippedEntryKeys = "outer=\(outerKeys) inner=\(keysDescription(friendData))"
                }
            }
            logger.warning("Friend Activity: skipped, no user field")
            return nil
        }
        guard let userInfo = userInfoValue as? [String: Any] else {
            // user is present but not an object: mirrors Dart's `userInfo['uri']` throwing on a
            // non-Map value, caught by the outer per-entry try/catch as an exception, not a
            // "no user" skip.
            if updateDiagnostics { lastSkipException += 1 }
            return nil
        }

        let ts = int64Value(from: friendData["timestamp"]) ?? now

        let userUri = (userInfo["uri"] as? String) ?? ""
        let userId: String
        if userUri.hasPrefix("spotify:user:") {
            userId = String(userUri.dropFirst("spotify:user:".count))
        } else {
            userId = userUri
        }

        let user = User(
            id: userId,
            displayName: (userInfo["name"] as? String) ?? "Unknown User",
            email: "",
            imageUrl: userInfo["imageUrl"] as? String,
            followers: 0,
            country: ""
        )

        let timestamp = Date(timeIntervalSince1970: Double(ts) / 1000.0)
        let trackInfo = friendData["track"] as? [String: Any]
        let playlistInfo = friendData["playlist"] as? [String: Any]
        let episodeInfo = friendData["episode"] as? [String: Any]

        if let playlistInfo {
            return Activity(
                user: user,
                playlist: makePlaylist(from: playlistInfo),
                timestamp: timestamp,
                isCurrentlyPlaying: false,
                type: ActivityType.playlist
            )
        }

        if let trackInfo {
            let elapsedMs = now - ts
            let isPlaying = elapsedMs >= 0 && elapsedMs < currentlyPlayingThresholdMs
            return Activity(
                user: user,
                track: makeTrack(from: trackInfo),
                timestamp: timestamp,
                isCurrentlyPlaying: isPlaying,
                type: ActivityType.track
            )
        }

        if let episodeInfo {
            let elapsedMs = now - ts
            let isPlaying = elapsedMs >= 0 && elapsedMs < currentlyPlayingThresholdMs
            return Activity(
                user: user,
                track: makeEpisodeTrack(from: episodeInfo),
                timestamp: timestamp,
                isCurrentlyPlaying: isPlaying,
                type: ActivityType.track
            )
        }

        // Friends browsing without actively playing have only a context key (playlist/album/show
        // URI). Treat as a playlist activity so they appear in the feed rather than being
        // silently dropped.
        let contextInfo = friendData["context"] as? [String: Any]
        let contextUri = (contextInfo?["uri"] as? String) ?? ""
        guard !contextUri.isEmpty else {
            if updateDiagnostics {
                lastSkipNoActivity += 1
                if lastSkippedEntryKeys.isEmpty {
                    lastSkippedEntryKeys = "noActivity keys=\(keysDescription(friendData))"
                }
            }
            return nil
        }

        let playlist = Playlist(
            id: lastUriSegment(contextUri),
            name: (contextInfo?["name"] as? String) ?? "Spotify",
            description: nil,
            imageUrl: contextInfo?["imageUrl"] as? String,
            trackCount: 0,
            uri: contextUri,
            ownerId: "",
            ownerName: "",
            isPublic: true
        )
        return Activity(
            user: user, playlist: playlist, timestamp: timestamp, isCurrentlyPlaying: false,
            type: ActivityType.playlist
        )
    }

    private static func makePlaylist(from playlistInfo: [String: Any]) -> Playlist {
        let playlistUri = (playlistInfo["uri"] as? String) ?? ""
        let owner = playlistInfo["owner"] as? [String: Any]
        return Playlist(
            id: lastUriSegment(playlistUri),
            name: (playlistInfo["name"] as? String) ?? "Unknown Playlist",
            description: playlistInfo["description"] as? String,
            imageUrl: playlistInfo["imageUrl"] as? String,
            trackCount: intValue(from: playlistInfo["trackCount"]) ?? 0,
            uri: playlistUri,
            ownerId: (owner?["id"] as? String) ?? "",
            ownerName: (owner?["name"] as? String) ?? "Unknown",
            isPublic: (playlistInfo["public"] as? Bool) == true
        )
    }

    private static func makeTrack(from trackInfo: [String: Any]) -> Track {
        let albumInfo = (trackInfo["album"] as? [String: Any]) ?? [:]
        let artistInfo = (trackInfo["artist"] as? [String: Any]) ?? [:]
        let artistUri = artistInfo["uri"] as? String
        let trackUri = (trackInfo["uri"] as? String) ?? ""
        return Track(
            id: trackUri,
            name: (trackInfo["name"] as? String) ?? "Unknown Track",
            artists: [(artistInfo["name"] as? String) ?? "Unknown Artist"],
            artistUris: artistUri != nil ? [artistUri!] : [],
            album: (albumInfo["name"] as? String) ?? "Unknown Album",
            albumUri: albumInfo["uri"] as? String,
            imageUrl: (trackInfo["imageUrl"] as? String) ?? (albumInfo["imageUrl"] as? String),
            durationMs: 0,
            uri: trackUri
        )
    }

    private static func makeEpisodeTrack(from episodeInfo: [String: Any]) -> Track {
        let showInfo = (episodeInfo["show"] as? [String: Any]) ?? [:]
        let showName = (showInfo["name"] as? String) ?? "Unknown Podcast"
        let episodeUri = (episodeInfo["uri"] as? String) ?? ""
        return Track(
            id: episodeUri,
            name: (episodeInfo["name"] as? String) ?? "Unknown Episode",
            artists: [showName],
            album: showName,
            albumUri: showInfo["uri"] as? String,
            imageUrl: (episodeInfo["imageUrl"] as? String) ?? (showInfo["imageUrl"] as? String),
            durationMs: 0,
            uri: episodeUri
        )
    }

    // MARK: - Small parsing helpers

    // The last colon-separated segment of a Spotify URI, e.g. "spotify:playlist:abc" -> "abc".
    // `omittingEmptySubsequences: false` matches Dart's `String.split`, which always keeps empty
    // components (including for an empty input string, where Dart's `''.split(':')` is `['']`).
    private static func lastUriSegment(_ uri: String) -> String {
        let parts = uri.split(separator: ":", omittingEmptySubsequences: false)
        guard let last = parts.last else { return "" }
        return String(last)
    }

    private static func keysDescription(_ dict: [String: Any]) -> String {
        "[" + dict.keys.joined(separator: ", ") + "]"
    }

    // JSON numeric values from `JSONSerialization` can arrive boxed as either a 32-bit or 64-bit
    // integer depending on magnitude and platform, so both are tried explicitly, same fix as
    // `Track.intValue`/`Playlist.intValue`.
    private static func intValue(from element: Any?) -> Int? {
        if let i = element as? Int { return i }
        if let i32 = element as? Int32 { return Int(i32) }
        return nil
    }

    // Same as `intValue` but widened to Int64 for millisecond-epoch timestamps, which routinely
    // exceed Int32's range. Only accepts a genuine integer-boxed value, never a Double, matching
    // Dart's strict `rawTimestamp is int` check (a JSON number written with a decimal point
    // decodes to Dart `double` and is rejected the same way here).
    private static func int64Value(from element: Any?) -> Int64? {
        if let i64 = element as? Int64 { return i64 }
        if let i = element as? Int { return Int64(i) }
        if let i32 = element as? Int32 { return Int64(i32) }
        return nil
    }
}
