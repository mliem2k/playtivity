import Foundation

private struct BuddyActivityServiceError: Error, CustomStringConvertible {
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

    // Injectable seam for tests: `URLProtocol` does not transpile on Skip Lite (confirmed in
    // Phase 2), so a closure per real network boundary is the standard technique here, mirroring
    // `SpotifyTokenService`'s override closures. `nonisolated(unsafe)` because Swift 6 rejects a
    // plain mutable static var as unsynchronized global state; production code only reads this,
    // only tests write it, matching the established, reviewed precedent.
    nonisolated(unsafe) static var buddyListFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?

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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
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
