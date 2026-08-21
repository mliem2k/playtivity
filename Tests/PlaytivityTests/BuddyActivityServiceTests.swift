import Foundation
import XCTest
@testable import Playtivity

/// Thread-safe recorder for `onArtistDetailsUpdate` callback invocations from inside a
/// `@Sendable` closure passed to `getTopArtistsWithDetails` (a plain captured `var` doesn't
/// compile under Swift 6 strict concurrency once the closure crosses the `Task { }` boundary
/// inside `BuddyActivityService`). Same `NSLock`-backed idiom as `DebouncedRefreshServiceTests`'s
/// `Counter` and `SpotifyStoreTests`'s own `Counter`.
private final class ArtistUpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations: [[Artist]] = []

    func record(_ artists: [Artist]) {
        lock.withLock { invocations.append(artists) }
    }

    var all: [[Artist]] {
        lock.withLock { invocations }
    }
}

final class BuddyActivityServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BuddyActivityService.buddyListFetchOverride = nil
        BuddyActivityService.topContentFetchOverride = nil
        BuddyActivityService.artistDetailsFetchOverride = nil
        ApiRetryService.sleepOverride = { _ in } // skip real backoff delays in retry tests
        resetDiagnostics()
    }

    override func tearDown() {
        BuddyActivityService.buddyListFetchOverride = nil
        BuddyActivityService.topContentFetchOverride = nil
        BuddyActivityService.artistDetailsFetchOverride = nil
        ApiRetryService.sleepOverride = nil
        resetDiagnostics()
        super.tearDown()
    }

    private func resetDiagnostics() {
        BuddyActivityService.lastDiagnostic = "No fetch yet"
        BuddyActivityService.lastRawSnippet = ""
        BuddyActivityService.lastApiBytes = 0
        BuddyActivityService.lastApiFriendCount = -1
        BuddyActivityService.lastParsedCount = -1
        BuddyActivityService.lastMergedCount = -1
        BuddyActivityService.lastSkipNull = 0
        BuddyActivityService.lastSkipNoUser = 0
        BuddyActivityService.lastSkipNoActivity = 0
        BuddyActivityService.lastSkipException = 0
        BuddyActivityService.lastSkippedEntryKeys = ""
    }

    private func freshUserDefaults() -> UserDefaults {
        UserDefaults(suiteName: "BuddyActivityServiceTests.\(UUID().uuidString)")!
    }

    /// Writes directly to the `artist_details_cache` `UserDefaults` key in the exact shape
    /// `saveArtistDetailsCache`/`loadArtistDetailsCache` use, so a test can seed a cache entry
    /// with a specific age (a `fetchedAt` outside some TTL) that a live network round-trip could
    /// only produce by actually waiting out that TTL in real time.
    private func seedArtistDetailsCache(_ userDefaults: UserDefaults, entries: [String: [String: Any]]) {
        let data = try! JSONSerialization.data(withJSONObject: entries)
        userDefaults.set(String(data: data, encoding: .utf8)!, forKey: "artist_details_cache")
    }

    private func date(msEpoch ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    private func nowMsEpoch() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: - parseFriendsJson: track activity

    func testParseTrackActivityMapsAllFields() {
        let nowMs: Int64 = 1_780_948_030_000 // 30s after the track timestamp below
        let body = """
        {
          "friends": [
            {
              "timestamp": 1780948000000,
              "user": {"uri": "spotify:user:abc123", "name": "Alice", "imageUrl": "https://example.com/alice.jpg"},
              "track": {
                "uri": "spotify:track:xyz789",
                "name": "Test Song",
                "album": {"name": "Test Album", "uri": "spotify:album:alb123"},
                "artist": {"name": "Test Artist"},
                "imageUrl": "https://example.com/track.jpg",
                "duration_ms": 210000
              }
            }
          ]
        }
        """
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: nowMs)
        XCTAssertEqual(activities.count, 1)
        let a = activities[0]
        XCTAssertEqual(a.user.id, "abc123", "strips spotify:user: prefix")
        XCTAssertEqual(a.user.displayName, "Alice")
        XCTAssertEqual(a.user.imageUrl, "https://example.com/alice.jpg")
        XCTAssertEqual(a.type, ActivityType.track)
        XCTAssertEqual(a.timestamp, date(msEpoch: 1_780_948_000_000))
        XCTAssertEqual(a.track?.name, "Test Song")
        XCTAssertEqual(a.track?.artists, ["Test Artist"])
        XCTAssertEqual(a.track?.album, "Test Album")
        XCTAssertEqual(a.track?.albumUri, "spotify:album:alb123")
        XCTAssertEqual(a.track?.imageUrl, "https://example.com/track.jpg")
        XCTAssertEqual(a.track?.durationMs, 0, "buddylist API duration_ms is never used, always 0")
        XCTAssertEqual(a.track?.uri, "spotify:track:xyz789")
        XCTAssertTrue(a.isCurrentlyPlaying, "30s elapsed is within the 5-minute threshold")
    }

    func testTrackIsCurrentlyPlayingFalseAfterFiveMinutes() {
        let body = trackBody(timestamp: 1_780_948_000_000, uri: "spotify:track:t")
        let exactlyFiveMinutesLater: Int64 = 1_780_948_000_000 + (5 * 60 * 1000)
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: exactlyFiveMinutesLater)
        XCTAssertFalse(activities[0].isCurrentlyPlaying, "exactly 5 minutes elapsed must not count as playing")
    }

    func testTrackIsCurrentlyPlayingTrueAtZeroElapsed() {
        let body = trackBody(timestamp: 1_780_948_000_000, uri: "spotify:track:t")
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: 1_780_948_000_000)
        XCTAssertTrue(activities[0].isCurrentlyPlaying)
    }

    func testTrackIsCurrentlyPlayingFalseAtSixMinutes() {
        let body = trackBody(timestamp: 1_780_948_000_000, uri: "spotify:track:t")
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: 1_780_948_000_000 + 6 * 60 * 1000)
        XCTAssertFalse(activities[0].isCurrentlyPlaying)
    }

    func testMissingDurationMsDefaultsToZero() {
        let body = trackBody(timestamp: 1_780_948_000_000, uri: "spotify:track:t")
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities[0].track?.durationMs, 0)
    }

    func testUserIdWithoutSpotifyUserPrefixPreservedAsIs() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":{"uri":"rawid","name":"Raw","imageUrl":null},\
        "track":{"uri":"spotify:track:t","name":"T","album":{"name":"A"},"artist":{"name":"Ar"},"duration_ms":0}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities[0].user.id, "rawid")
    }

    func testTrackFallsBackToAlbumImageUrlWhenTrackImageUrlIsNull() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":{"uri":"spotify:user:x","name":"X","imageUrl":null},\
        "track":{"uri":"spotify:track:t","name":"T","album":{"name":"A","imageUrl":"https://example.com/album.jpg"},\
        "artist":{"name":"Ar"},"duration_ms":0}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities[0].track?.imageUrl, "https://example.com/album.jpg")
    }

    private func trackBody(timestamp: Int64, uri: String) -> String {
        """
        {"friends":[{"timestamp":\(timestamp),"user":{"uri":"spotify:user:x","name":"X","imageUrl":null},\
        "track":{"uri":"\(uri)","name":"T","album":{"name":"A"},"artist":{"name":"Ar"},"imageUrl":null}}]}
        """
    }

    // MARK: - parseFriendsJson: playlist activity

    func testParsePlaylistActivityMapsAllFields() {
        let body = """
        {
          "friends": [
            {
              "timestamp": 1780947000000,
              "user": {"uri": "spotify:user:def456", "name": "Bob", "imageUrl": null},
              "playlist": {
                "uri": "spotify:playlist:plist123",
                "name": "Chill Mix",
                "description": "Great vibes",
                "imageUrl": "https://example.com/playlist.jpg",
                "trackCount": 20,
                "owner": {"id": "owner1", "name": "Owner Name"},
                "public": true
              }
            }
          ]
        }
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        let a = activities[0]
        XCTAssertEqual(a.type, ActivityType.playlist)
        XCTAssertEqual(a.playlist?.name, "Chill Mix")
        XCTAssertEqual(a.playlist?.description, "Great vibes")
        XCTAssertEqual(a.playlist?.imageUrl, "https://example.com/playlist.jpg")
        XCTAssertEqual(a.playlist?.trackCount, 20)
        XCTAssertEqual(a.playlist?.uri, "spotify:playlist:plist123")
        XCTAssertEqual(a.playlist?.id, "plist123", "id is the last URI segment")
        XCTAssertEqual(a.playlist?.ownerId, "owner1")
        XCTAssertEqual(a.playlist?.ownerName, "Owner Name")
        XCTAssertEqual(a.playlist?.isPublic, true)
        XCTAssertFalse(a.isCurrentlyPlaying, "playlists are never currently playing")
        XCTAssertNil(a.user.imageUrl, "null imageUrl is preserved as null, not defaulted")
    }

    // MARK: - parseFriendsJson: episode/podcast activity

    func testParseEpisodeActivityMapsShowFieldsIntoTrack() {
        let nowMs: Int64 = 1_780_948_030_000
        let body = """
        {
          "friends": [
            {
              "timestamp": 1780948000000,
              "user": {"uri": "spotify:user:carol789", "name": "Carol", "imageUrl": "https://example.com/carol.jpg"},
              "episode": {
                "uri": "spotify:episode:ep001",
                "name": "The Morning Rundown",
                "imageUrl": "https://example.com/episode.jpg",
                "show": {
                  "uri": "spotify:show:show001",
                  "name": "Daily News",
                  "imageUrl": "https://example.com/show.jpg"
                }
              }
            }
          ]
        }
        """
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: nowMs)
        XCTAssertEqual(activities.count, 1)
        let a = activities[0]
        XCTAssertEqual(a.type, ActivityType.track, "episodes are ActivityType.track, not a distinct type")
        XCTAssertEqual(a.track?.name, "The Morning Rundown")
        XCTAssertEqual(a.track?.artists, ["Daily News"], "show name doubles as the artists entry")
        XCTAssertEqual(a.track?.album, "Daily News", "show name doubles as the album name")
        XCTAssertEqual(a.track?.albumUri, "spotify:show:show001")
        XCTAssertEqual(a.track?.imageUrl, "https://example.com/episode.jpg")
        XCTAssertEqual(a.track?.uri, "spotify:episode:ep001")
        XCTAssertEqual(a.user.displayName, "Carol")
        XCTAssertEqual(a.user.id, "carol789")
        XCTAssertTrue(a.isCurrentlyPlaying)
    }

    func testMixedTrackAndEpisodeFriendsBothAppear() {
        let body = """
        {
          "friends": [
            {"timestamp": 1780948000000, "user": {"uri": "spotify:user:alice", "name": "Alice", "imageUrl": null},
             "track": {"uri": "spotify:track:t1", "name": "Song", "album": {"name": "Album", "uri": "spotify:album:a1"}, "artist": {"name": "Artist"}, "imageUrl": null}},
            {"timestamp": 1780948001000, "user": {"uri": "spotify:user:carol", "name": "Carol", "imageUrl": null},
             "episode": {"uri": "spotify:episode:e1", "name": "Podcast Ep", "imageUrl": null, "show": {"uri": "spotify:show:s1", "name": "Show"}}}
          ]
        }
        """
        XCTAssertEqual(BuddyActivityService.parseFriendsJson(body).count, 2)
    }

    // MARK: - parseFriendsJson: sort and edge cases

    func testSortsActivitiesByTimestampDescending() {
        let body = """
        {
          "friends": [
            {"timestamp": 1780947000000, "user": {"uri": "spotify:user:bob", "name": "Bob", "imageUrl": null},
             "track": {"uri": "spotify:track:b", "name": "B", "album": {"name": "B"}, "artist": {"name": "B"}, "imageUrl": null}},
            {"timestamp": 1780948000000, "user": {"uri": "spotify:user:alice", "name": "Alice", "imageUrl": null},
             "track": {"uri": "spotify:track:a", "name": "A", "album": {"name": "A"}, "artist": {"name": "A"}, "imageUrl": null}}
          ]
        }
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities[0].user.id, "alice")
        XCTAssertEqual(activities[1].user.id, "bob")
    }

    func testEmptyFriendsArrayReturnsEmpty() {
        XCTAssertTrue(BuddyActivityService.parseFriendsJson("{\"friends\": []}").isEmpty)
    }

    func testAbsentFriendsKeyReturnsEmptyAndSetsDiagnostic() {
        XCTAssertTrue(BuddyActivityService.parseFriendsJson("{\"data\": []}").isEmpty)
        XCTAssertEqual(BuddyActivityService.lastApiFriendCount, 0)
        XCTAssertEqual(BuddyActivityService.lastParsedCount, 0)
    }

    func testMalformedJsonReturnsEmpty() {
        XCTAssertTrue(BuddyActivityService.parseFriendsJson("{bad json}").isEmpty)
    }

    func testEmptyStringInputReturnsEmpty() {
        XCTAssertTrue(BuddyActivityService.parseFriendsJson("").isEmpty)
    }

    func testFriendsKeyPresentButWrongTypeReturnsEmpty() {
        // Mirrors Dart's `data['friends'] as List?` throwing a CastError, caught by the outer
        // try/catch, when "friends" is present but not an array.
        XCTAssertTrue(BuddyActivityService.parseFriendsJson("{\"friends\": \"not a list\"}").isEmpty)
    }

    func testFriendWithoutTrackOrPlaylistOrContextIsSkipped() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":{"uri":"spotify:user:ghost","name":"Ghost","imageUrl":null}}]}
        """
        XCTAssertTrue(BuddyActivityService.parseFriendsJson(body).isEmpty)
    }

    // MARK: - parseFriendsJson: context-only (browsing) activity

    func testContextOnlyFriendBecomesPlaylistActivity() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":{"uri":"spotify:user:browser1","name":"Browser","imageUrl":null},\
        "context":{"uri":"spotify:playlist:abc123","name":"Chill Vibes","imageUrl":"https://example.com/playlist.jpg"}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities.count, 1)
        let a = activities[0]
        XCTAssertEqual(a.type, ActivityType.playlist)
        XCTAssertEqual(a.playlist?.name, "Chill Vibes")
        XCTAssertEqual(a.playlist?.uri, "spotify:playlist:abc123")
        XCTAssertEqual(a.playlist?.id, "abc123")
        XCTAssertEqual(a.playlist?.imageUrl, "https://example.com/playlist.jpg")
        XCTAssertEqual(a.user.displayName, "Browser")
        XCTAssertFalse(a.isCurrentlyPlaying)
    }

    func testMixedTrackFriendAndContextFriendBothAppearInTimestampOrder() {
        let body = """
        {"friends":[
          {"timestamp":1780948000000,"user":{"uri":"spotify:user:u1","name":"Player","imageUrl":null},
           "track":{"uri":"spotify:track:t1","name":"Song","imageUrl":null,"album":{"name":"Album"},"artist":{"name":"Artist"}}},
          {"timestamp":1780947000000,"user":{"uri":"spotify:user:u2","name":"Browser","imageUrl":null},
           "context":{"uri":"spotify:playlist:p1","name":"My Playlist","imageUrl":null}}
        ]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].user.displayName, "Player")
        XCTAssertEqual(activities[1].user.displayName, "Browser")
    }

    func testFriendWithEmptyContextUriIsSkipped() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":{"uri":"spotify:user:u1","name":"Ghost","imageUrl":null},\
        "context":{"uri":"","name":"nothing"}}]}
        """
        XCTAssertTrue(BuddyActivityService.parseFriendsJson(body).isEmpty)
    }

    // MARK: - parseFriendsJson: envelope-wrapped format {"friend": {...}}

    func testEnvelopeWrappedTrackActivityIsParsed() {
        let nowMs: Int64 = 1_780_948_030_000
        let body = """
        {"friends":[{"friend":{
          "timestamp":1780948000000,
          "user":{"uri":"spotify:user:abc123","name":"Alice","imageUrl":"https://example.com/alice.jpg"},
          "track":{"uri":"spotify:track:xyz789","name":"Test Song",
                    "album":{"name":"Test Album","uri":"spotify:album:alb123"},
                    "artist":{"name":"Test Artist"},"imageUrl":"https://example.com/track.jpg"}
        }}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: nowMs)
        XCTAssertEqual(activities.count, 1)
        let a = activities[0]
        XCTAssertEqual(a.user.id, "abc123")
        XCTAssertEqual(a.user.displayName, "Alice")
        XCTAssertEqual(a.track?.name, "Test Song")
        XCTAssertEqual(a.track?.artists, ["Test Artist"])
        XCTAssertEqual(a.track?.album, "Test Album")
        XCTAssertEqual(a.track?.imageUrl, "https://example.com/track.jpg")
        XCTAssertEqual(a.type, ActivityType.track)
        XCTAssertTrue(a.isCurrentlyPlaying)
    }

    func testEnvelopeWrappedPlaylistActivityIsParsed() {
        let body = """
        {"friends":[{"friend":{
          "timestamp":1780947000000,
          "user":{"uri":"spotify:user:def456","name":"Bob","imageUrl":null},
          "playlist":{"uri":"spotify:playlist:plist123","name":"Chill Mix","imageUrl":"https://example.com/playlist.jpg",
                      "trackCount":20,"owner":{"id":"owner1","name":"Owner Name"},"public":true}
        }}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].type, ActivityType.playlist)
        XCTAssertEqual(activities[0].playlist?.name, "Chill Mix")
        XCTAssertEqual(activities[0].user.displayName, "Bob")
    }

    func testEnvelopeWrappedContextOnlyActivityIsParsed() {
        let body = """
        {"friends":[{"friend":{
          "timestamp":1780948000000,
          "user":{"uri":"spotify:user:browser1","name":"Browser","imageUrl":null},
          "context":{"uri":"spotify:playlist:ctx123","name":"My Mix","imageUrl":null}
        }}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].type, ActivityType.playlist)
        XCTAssertEqual(activities[0].playlist?.name, "My Mix")
    }

    func testMixedEnvelopeAndFlatEntriesBothParsedInTimestampOrder() {
        let nowMs: Int64 = 1_780_948_030_000
        let body = """
        {"friends":[
          {"friend":{"timestamp":1780948000000,"user":{"uri":"spotify:user:u1","name":"EnvelopeUser","imageUrl":null},
            "track":{"uri":"spotify:track:t1","name":"Envelope Song","imageUrl":null,"album":{"name":"Album"},"artist":{"name":"Artist"}}}},
          {"timestamp":1780947000000,"user":{"uri":"spotify:user:u2","name":"FlatUser","imageUrl":null},
            "track":{"uri":"spotify:track:t2","name":"Flat Song","imageUrl":null,"album":{"name":"Album2"},"artist":{"name":"Artist2"}}}
        ]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: nowMs)
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].user.displayName, "EnvelopeUser")
        XCTAssertEqual(activities[1].user.displayName, "FlatUser")
    }

    func testEmptyFriendEnvelopeFallsBackToTopLevelData() {
        // Some API responses include "friend":{} as a marker while real data sits at the top
        // level; the empty envelope must not shadow it.
        let nowMs: Int64 = 1_780_948_030_000
        let body = """
        {"friends":[{
          "timestamp":1780948000000,"user":{"uri":"spotify:user:u1","name":"TopLevel","imageUrl":null},
          "track":{"uri":"spotify:track:t1","name":"Top Song","imageUrl":null,"album":{"name":"Album"},"artist":{"name":"Artist"}},
          "friend":{}
        }]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: nowMs)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].user.displayName, "TopLevel")
        XCTAssertEqual(activities[0].track?.name, "Top Song")
    }

    func testMultipleFriendsEnvelopeAndTopLevelWithEmptyFriendBothParsedInOrder() {
        let nowMs: Int64 = 1_780_948_030_000
        let body = """
        {"friends":[
          {"friend":{"timestamp":1780948000000,"user":{"uri":"spotify:user:u1","name":"Enveloped","imageUrl":null},
            "track":{"uri":"spotify:track:t1","name":"Song A","imageUrl":null,"album":{"name":"A"},"artist":{"name":"Ar"}}}},
          {"timestamp":1780947000000,"user":{"uri":"spotify:user:u2","name":"TopLevel","imageUrl":null},
            "track":{"uri":"spotify:track:t2","name":"Song B","imageUrl":null,"album":{"name":"B"},"artist":{"name":"Ar"}},"friend":{}}
        ]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body, nowMs: nowMs)
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities[0].user.displayName, "Enveloped")
        XCTAssertEqual(activities[1].user.displayName, "TopLevel")
    }

    // MARK: - parseFriendsJson: null-entry / missing-user / no-activity skip counting + diagnostics

    func testNullEntryInFriendsArrayIsSkippedAndCounted() {
        let body = """
        {"friends":[null,{"timestamp":1780948000000,"user":{"uri":"spotify:user:x","name":"X","imageUrl":null},
          "track":{"uri":"spotify:track:t","name":"T","album":{"name":"A"},"artist":{"name":"Ar"},"imageUrl":null}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(BuddyActivityService.lastSkipNull, 1)
        XCTAssertEqual(BuddyActivityService.lastApiFriendCount, 2)
        XCTAssertEqual(BuddyActivityService.lastParsedCount, 1)
    }

    func testMissingUserFieldIsSkippedAndCounted() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"track":{"uri":"spotify:track:t","name":"T"}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertTrue(activities.isEmpty)
        XCTAssertEqual(BuddyActivityService.lastSkipNoUser, 1)
        XCTAssertFalse(BuddyActivityService.lastSkippedEntryKeys.isEmpty)
    }

    func testNullUserFieldIsSkippedAsNoUser() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":null,"track":{"uri":"spotify:track:t","name":"T"}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertTrue(activities.isEmpty)
        XCTAssertEqual(BuddyActivityService.lastSkipNoUser, 1)
    }

    func testUserFieldPresentButWrongShapeCountsAsException() {
        // "user" is present (non-null) but is a String, not an object: Dart's `userInfo['uri']`
        // would throw here, caught by the per-entry try/catch as an exception, not "no user".
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":"not an object","track":{"uri":"spotify:track:t","name":"T"}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertTrue(activities.isEmpty)
        XCTAssertEqual(BuddyActivityService.lastSkipException, 1)
        XCTAssertEqual(BuddyActivityService.lastSkipNoUser, 0)
    }

    func testNoActivityFieldsIsSkippedAndCounted() {
        let body = """
        {"friends":[{"timestamp":1780948000000,"user":{"uri":"spotify:user:u1","name":"Ghost","imageUrl":null}}]}
        """
        let activities = BuddyActivityService.parseFriendsJson(body)
        XCTAssertTrue(activities.isEmpty)
        XCTAssertEqual(BuddyActivityService.lastSkipNoActivity, 1)
    }

    func testUpdateDiagnosticsFalseLeavesCountersUnchanged() {
        BuddyActivityService.lastApiFriendCount = 42
        let body = "{\"friends\": []}"
        _ = BuddyActivityService.parseFriendsJson(body, updateDiagnostics: false)
        XCTAssertEqual(BuddyActivityService.lastApiFriendCount, 42, "updateDiagnostics: false must not touch the counters")
    }

    // MARK: - mergeWithExisting

    func testMergeWithExistingReturnsFreshUnchangedWhenNoExistingCache() {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let fresh = [makeActivity(userId: "u1", ts: 1000)]
        XCTAssertEqual(service.mergeWithExisting(fresh).map { $0.user.id }, ["u1"])
    }

    func testMergeWithExistingNeverEvictsByAgeAndFreshOverwritesSameUser() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        // Seed the in-memory cache via a real (mocked) fetch: friend "old" listened 10 days ago,
        // friend "recent" listened just now.
        let seedBody = friendsBody([
            ("old", now - 10 * 24 * 60 * 60 * 1000, "Old Song"),
            ("recent", now, "Recent Song"),
        ])
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: seedBody) }
        _ = try await service.getFriendActivity(bearerToken: "tok")

        // Fresh data only mentions "recent" (with an updated track) and a brand-new "newcomer".
        // "old" must still survive the merge (never evicted by age here).
        let fresh = [
            makeActivity(userId: "recent", ts: now, trackName: "Updated Song"),
            makeActivity(userId: "newcomer", ts: now),
        ]
        let merged = service.mergeWithExisting(fresh)
        let byId = Dictionary(uniqueKeysWithValues: merged.map { ($0.user.id, $0) })
        XCTAssertEqual(byId.count, 3, "old friend must be carried over, not evicted by age")
        XCTAssertNotNil(byId["old"])
        XCTAssertEqual(byId["recent"]?.track?.name, "Updated Song", "fresh overwrites the same user's stale entry")
        XCTAssertNotNil(byId["newcomer"])
    }

    func testMergeWithExistingSortsByTimestampDescending() async throws {
        // mergeWithExisting only sorts on the actual merge path (an existing non-empty cache);
        // with no existing cache it returns `fresh` verbatim (Dart: `if (existing == null ||
        // existing.isEmpty) return fresh;`), so seed a cache first via a real (mocked) fetch.
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.buddyListFetchOverride = { _ in
            (statusCode: 200, body: self.friendsBody([("seed", 500, "Seed")]))
        }
        _ = try await service.getFriendActivity(bearerToken: "tok")

        let fresh = [
            self.makeActivity(userId: "a", ts: 1000),
            self.makeActivity(userId: "b", ts: 3000),
            self.makeActivity(userId: "c", ts: 2000),
        ]
        let merged = service.mergeWithExisting(fresh)
        XCTAssertEqual(merged.map { $0.user.id }, ["b", "c", "a", "seed"])
    }

    // MARK: - recomputeStatus

    func testRecomputeStatusFlipsPlaylistCurrentlyPlayingToFalse() {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let playlist = Playlist(id: "p", name: "P", trackCount: 1, uri: "spotify:playlist:p", ownerId: "o", ownerName: "O", isPublic: true)
        let activity = Activity(
            user: sampleUser(), playlist: playlist, timestamp: Date(),
            isCurrentlyPlaying: true, type: ActivityType.playlist
        )
        XCTAssertFalse(service.recomputeStatus(activity).isCurrentlyPlaying)
    }

    func testRecomputeStatusLeavesPlaylistAlreadyNotPlayingUnchanged() {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let playlist = Playlist(id: "p", name: "P", trackCount: 1, uri: "spotify:playlist:p", ownerId: "o", ownerName: "O", isPublic: true)
        let activity = Activity(
            user: sampleUser(), playlist: playlist, timestamp: Date(),
            isCurrentlyPlaying: false, type: ActivityType.playlist
        )
        XCTAssertFalse(service.recomputeStatus(activity).isCurrentlyPlaying)
    }

    func testRecomputeStatusFlipsTrackToFalseAfterThreshold() {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let sixMinutesAgo = Date().addingTimeInterval(-6 * 60)
        let track = Track(id: "t", name: "T", artists: ["A"], album: "Al", durationMs: 0, uri: "spotify:track:t")
        let activity = Activity(
            user: sampleUser(), track: track, timestamp: sixMinutesAgo,
            isCurrentlyPlaying: true, type: ActivityType.track
        )
        XCTAssertFalse(service.recomputeStatus(activity).isCurrentlyPlaying)
    }

    func testRecomputeStatusKeepsTrackTrueWithinThreshold() {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let track = Track(id: "t", name: "T", artists: ["A"], album: "Al", durationMs: 0, uri: "spotify:track:t")
        let activity = Activity(
            user: sampleUser(), track: track, timestamp: Date(),
            isCurrentlyPlaying: false, type: ActivityType.track
        )
        XCTAssertTrue(service.recomputeStatus(activity).isCurrentlyPlaying, "just-started track recomputes to true")
    }

    // MARK: - shouldRefreshBuddyList

    func testShouldRefreshIsTrueWithNoCachedData() {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        XCTAssertTrue(service.shouldRefreshBuddyList())
    }

    func testShouldRefreshIsFalseImmediatelyAfterAFreshFetch() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertFalse(service.shouldRefreshBuddyList())
    }

    func testShouldRefreshIsTrueWhenACurrentlyPlayingEntryCrossedTheThreshold() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        // Started 4:59.5 ago: isCurrentlyPlaying = true at parse time (elapsed < 5 min), but by
        // the time shouldRefreshBuddyList re-checks against a fresh Date(), elapsed has already
        // crossed the 5-minute mark.
        let startedAgoMs = Int64((5 * 60 - 0.5) * 1000)
        let ts = nowMsEpoch() - startedAgoMs
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", ts, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        // Sleep past the remaining 0.5s so the real clock has crossed the threshold.
        try await Task.sleep(for: Duration.seconds(1))
        XCTAssertTrue(service.shouldRefreshBuddyList())
    }

    func testShouldRefreshIsTrueWhenCacheAgeExceedsActiveDuration() async throws {
        // No injectable clock for shouldRefreshBuddyList (matching the Dart original, which also
        // uses DateTime.now() directly here), so this specifically needs real elapsed time past
        // the 30-second active-cache duration.
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        // A currently-playing entry keeps the cache duration at the shorter 30s (active) window
        // rather than the 5-minute (quiet) one, minimizing this test's real runtime.
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertFalse(service.shouldRefreshBuddyList(), "cache is fresh immediately after the fetch")
        try await Task.sleep(for: Duration.seconds(31))
        XCTAssertTrue(service.shouldRefreshBuddyList())
    }

    // MARK: - getFriendActivity

    func testGetFriendActivitySendsTheExactSevenHeadersAndNoTotpParams() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        var captured: URLRequest?
        BuddyActivityService.buddyListFetchOverride = { request in
            captured = request
            return (statusCode: 200, body: "{\"friends\": []}")
        }
        _ = try await service.getFriendActivity(bearerToken: "tok123")
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://guc-spclient.spotify.com/presence-view/v1/buddylist")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "App-Platform"), "WebPlayer")
        XCTAssertEqual(request.value(forHTTPHeaderField: "accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "accept-language"), "en")
        XCTAssertEqual(request.value(forHTTPHeaderField: "origin"), "https://open.spotify.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "referer"), "https://open.spotify.com/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), SpotifyTokenService.userAgent)
        XCTAssertNil(request.value(forHTTPHeaderField: "totp"))
    }

    func testGetFriendActivityCacheHitSkipsNetwork() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        var callCount = 0
        BuddyActivityService.buddyListFetchOverride = { _ in
            callCount += 1
            return (statusCode: 200, body: self.friendsBody([("u1", self.nowMsEpoch(), "Song")]))
        }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(callCount, 1)
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(callCount, 1, "second call within the cache window must not hit the network")
    }

    func testGetFriendActivityCacheMissFetchesFromNetwork() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        var callCount = 0
        BuddyActivityService.buddyListFetchOverride = { _ in
            callCount += 1
            return (statusCode: 200, body: self.friendsBody([("u1", self.nowMsEpoch(), "Song")]))
        }
        let result = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(result.count, 1)
    }

    func testGetFriendActivityThrowsDistinguishableAuthErrorOn401() async {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 401, body: "") }
        do {
            _ = try await service.getFriendActivity(bearerToken: "tok")
            XCTFail("expected getFriendActivity to throw")
        } catch {
            XCTAssertTrue("\(error)".lowercased().contains("authentication error"))
            XCTAssertTrue("\(error)".contains("401"))
        }
    }

    func testGetFriendActivityThrowsDistinguishableAuthErrorOn403AndDoesNotRetry() async {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        var callCount = 0
        BuddyActivityService.buddyListFetchOverride = { _ in
            callCount += 1
            return (statusCode: 403, body: "")
        }
        do {
            _ = try await service.getFriendActivity(bearerToken: "tok")
            XCTFail("expected getFriendActivity to throw")
        } catch {
            XCTAssertTrue("\(error)".lowercased().contains("authentication error"))
        }
        XCTAssertEqual(callCount, 1, "auth errors must not be retried")
    }

    func testGetFriendActivityNeverDropsToZeroCardsOnAnEmptyFetch() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(service.cachedActivities?.count, 1)

        service.forceRefresh()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: "{\"friends\": []}") }
        let result = try await service.getFriendActivity(bearerToken: "tok")

        XCTAssertEqual(result.count, 1, "an empty fetch must not wipe the already-known friend")
        XCTAssertEqual(service.cachedActivities?.count, 1)
    }

    func testGetFriendActivityNeverDropsToZeroCardsOnANonAuthFailure() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(service.cachedActivities?.count, 1)

        service.forceRefresh()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 500, body: "") }
        do {
            _ = try await service.getFriendActivity(bearerToken: "tok")
            XCTFail("expected getFriendActivity to throw after exhausting retries")
        } catch {
            // expected: a persistent non-auth failure propagates to the caller
        }
        XCTAssertEqual(service.cachedActivities?.count, 1, "a failed fetch must not wipe the already-known friend")
    }

    /// Finding 9 (whole-branch review, Important): the previous version of this test only asserted
    /// `cachedActivities` stayed nil, which is true regardless of whether `lastBuddyListFetch =
    /// Date()` runs, since `shouldRefreshBuddyList`'s very first guard already returns `true`
    /// whenever `cachedActivities` itself is nil (`guard let activities = ..., let lastFetch =
    /// ... else { return true }` requires BOTH), independent of the fetch-time write. That means
    /// the write's effect is only observable once a cache already exists: this test seeds one with
    /// a real (non-empty) fetch first, then exercises an empty-bodied response against it (fresh
    /// data is `[]`, but `mergeWithExisting` carries the existing friend over, so the cache stays
    /// populated either way, unrelated to the line under test), and proves the fetch-time write
    /// specifically by checking that a third call within the cache window does not hit the network
    /// again. Non-vacuity confirmed by temporarily commenting out `self.lastBuddyListFetch =
    /// Date()` in `BuddyActivityService.getFriendActivity` and observing this test fail (the third
    /// call re-hits the network because `lastBuddyListFetch` never became non-nil again after
    /// `forceRefresh()` cleared it), then restoring the line and observing it pass again.
    func testGetFriendActivityAlwaysRecordsFetchTimeEvenOnEmptyResult() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(service.cachedActivities?.count, 1)

        // Force the next check to want a refresh, then return an empty body against the existing
        // cache.
        service.forceRefresh()
        var secondCallCount = 0
        BuddyActivityService.buddyListFetchOverride = { _ in
            secondCallCount += 1
            return (statusCode: 200, body: "{\"friends\": []}")
        }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(secondCallCount, 1)

        // A third call within the cache window must not hit the network: this only holds if the
        // empty-bodied second fetch actually recorded a fresh lastBuddyListFetch, since
        // forceRefresh() above had already cleared it and the cache being populated alone is not
        // sufficient (shouldRefreshBuddyList requires both).
        var thirdCallCount = 0
        BuddyActivityService.buddyListFetchOverride = { _ in
            thirdCallCount += 1
            return (statusCode: 200, body: "{\"friends\": []}")
        }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(thirdCallCount, 0, "an empty-bodied fetch must still record the fetch time, or the next call within the cache window hammers the API again")
    }

    func testGetFriendActivityPersistsRawAndMergedOnSuccessfulNonEmptyFetch() async throws {
        let ud = freshUserDefaults()
        let service = BuddyActivityService(userDefaults: ud)
        let now = nowMsEpoch()
        let body = friendsBody([("u1", now, "Song")])
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: body) }
        _ = try await service.getFriendActivity(bearerToken: "tok")

        XCTAssertEqual(ud.string(forKey: "buddy_list_raw_json"), body)
        XCTAssertNotNil(ud.string(forKey: "buddy_list_merged_json"))
    }

    func testGetFriendActivityDoesNotPersistOnEmptyResultWithNoPriorCache() async throws {
        let ud = freshUserDefaults()
        let service = BuddyActivityService(userDefaults: ud)
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: "{\"friends\": []}") }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertNil(ud.string(forKey: "buddy_list_raw_json"))
        XCTAssertNil(ud.string(forKey: "buddy_list_merged_json"))
    }

    // MARK: - Persistence

    func testFreshInstanceLoadsPersistedMergedActivitiesOnPersistenceReady() async throws {
        let ud = freshUserDefaults()
        let writer = BuddyActivityService(userDefaults: ud)
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await writer.getFriendActivity(bearerToken: "tok")

        // A brand-new instance sharing the same UserDefaults must pick up the persisted data via
        // persistenceReady (awaited internally by getFriendActivity, mirroring the Dart original's
        // `await _persistenceReady;`), without any network call, since the loaded cache already
        // satisfies shouldRefreshBuddyList.
        BuddyActivityService.buddyListFetchOverride = { _ in
            XCTFail("must not hit the network when persisted data satisfies the cache")
            return (statusCode: 500, body: "")
        }
        let reader = BuddyActivityService(userDefaults: ud)
        let result = try await reader.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(reader.cachedActivities?.count, 1)
        XCTAssertEqual(reader.cachedActivities?.first?.user.id, "u1")
    }

    func testLoadPersistedBuddyListPrefersMergedOverRaw() async throws {
        let ud = freshUserDefaults()
        let now = nowMsEpoch()
        // Merged copy has 2 friends; raw snapshot only has 1. Merged must win.
        let mergedActivities = [
            makeActivity(userId: "a", ts: now),
            makeActivity(userId: "b", ts: now),
        ]
        let mergedJson = try JSONSerialization.data(withJSONObject: mergedActivities.map { $0.toJson() })
        ud.set(String(data: mergedJson, encoding: .utf8), forKey: "buddy_list_merged_json")
        ud.set(friendsBody([("c", now, "Song")]), forKey: "buddy_list_raw_json")

        let service = BuddyActivityService(userDefaults: ud)
        await service.loadPersistedBuddyList(force: true)
        XCTAssertEqual(service.cachedActivities?.count, 2)
    }

    func testLoadPersistedBuddyListFallsBackToRawWhenMergedAbsent() async throws {
        let ud = freshUserDefaults()
        let now = nowMsEpoch()
        ud.set(friendsBody([("c", now, "Song")]), forKey: "buddy_list_raw_json")

        let service = BuddyActivityService(userDefaults: ud)
        await service.loadPersistedBuddyList(force: true)
        XCTAssertEqual(service.cachedActivities?.count, 1)
        XCTAssertEqual(service.cachedActivities?.first?.user.id, "c")
    }

    func testLoadPersistedBuddyListDropsEntriesOlderThanNinetyDays() async throws {
        let ud = freshUserDefaults()
        let now = nowMsEpoch()
        let oldTimestamp = Date().addingTimeInterval(-91 * 24 * 60 * 60)
        let recentActivity = makeActivity(userId: "recent", ts: now)
        let oldActivity = Activity(
            user: sampleUser(id: "ancient"),
            track: Track(id: "t", name: "T", artists: ["A"], album: "Al", durationMs: 0, uri: "spotify:track:t"),
            timestamp: oldTimestamp, isCurrentlyPlaying: false, type: ActivityType.track
        )
        let mergedJson = try JSONSerialization.data(withJSONObject: [recentActivity, oldActivity].map { $0.toJson() })
        ud.set(String(data: mergedJson, encoding: .utf8), forKey: "buddy_list_merged_json")

        let service = BuddyActivityService(userDefaults: ud)
        await service.loadPersistedBuddyList(force: true)
        XCTAssertEqual(service.cachedActivities?.map { $0.user.id }, ["recent"])
    }

    func testLoadPersistedBuddyListSkipsCorruptedEntriesWithoutFailingTheWholeLoad() async throws {
        let ud = freshUserDefaults()
        let now = nowMsEpoch()
        let goodActivity = makeActivity(userId: "good", ts: now)
        let goodJson = goodActivity.toJson()
        let corruptedJson: [String: Any] = ["not": "a valid activity"]
        let arrayJson: [Any] = [corruptedJson, goodJson]
        let mergedData = try JSONSerialization.data(withJSONObject: arrayJson)
        ud.set(String(data: mergedData, encoding: .utf8), forKey: "buddy_list_merged_json")

        let service = BuddyActivityService(userDefaults: ud)
        await service.loadPersistedBuddyList(force: true)
        XCTAssertEqual(service.cachedActivities?.map { $0.user.id }, ["good"])
    }

    func testReloadPersistedCacheOverwritesAnAlreadyPopulatedInMemoryCache() async throws {
        let ud = freshUserDefaults()
        let service = BuddyActivityService(userDefaults: ud)
        let now = nowMsEpoch()

        // Populate the in-memory cache first (simulating what a running app already has).
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertEqual(service.cachedActivities?.count, 1)

        // Simulate a background widget update writing newer merged data directly to storage.
        let widgetActivities = [makeActivity(userId: "u1", ts: now), makeActivity(userId: "u2", ts: now)]
        let widgetJson = try JSONSerialization.data(withJSONObject: widgetActivities.map { $0.toJson() })
        ud.set(String(data: widgetJson, encoding: .utf8), forKey: "buddy_list_merged_json")

        await service.reloadPersistedCache()
        XCTAssertEqual(service.cachedActivities?.count, 2, "reloadPersistedCache must force-overwrite the in-memory cache")
    }

    // MARK: - clearBuddyListCache / forceRefresh / clearActivityCache

    func testClearBuddyListCacheResetsToNoCacheState() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertNotNil(service.cachedActivities)

        service.clearBuddyListCache()
        XCTAssertNil(service.cachedActivities)
        XCTAssertTrue(service.shouldRefreshBuddyList())
    }

    func testClearActivityCacheDelegatesToClearBuddyListCache() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")

        service.clearActivityCache()
        XCTAssertNil(service.cachedActivities)
    }

    func testForceRefreshKeepsActivitiesButForcesNextFetch() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        let now = nowMsEpoch()
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: self.friendsBody([("u1", now, "Song")])) }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        XCTAssertFalse(service.shouldRefreshBuddyList())

        service.forceRefresh()
        XCTAssertNotNil(service.cachedActivities, "forceRefresh must not clear existing activities")
        XCTAssertTrue(service.shouldRefreshBuddyList())
    }

    // MARK: - getTopTracks / getTopArtists / getTopArtistsWithDetails

    func testGetTopTracksParsesUserTopContentGraphQLResponse() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { request in
            // Assert the request shape is correct, not just that a response comes back.
            XCTAssertEqual(request.url?.absoluteString, "https://api-partner.spotify.com/pathfinder/v2/query")
            XCTAssertEqual(request.httpMethod, "POST")
            let bodyData = request.httpBody ?? Data()
            let body = try! JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
            XCTAssertEqual(body["operationName"] as? String, "userTopContent")
            let variables = body["variables"] as! [String: Any]
            let topTracksInput = variables["topTracksInput"] as! [String: Any]
            XCTAssertEqual(topTracksInput["timeRange"] as? String, "SHORT_TERM")
            // Both gates are non-nullable Boolean! variables on the persisted query; omitting
            // either produces a malformed request (Important finding 2).
            XCTAssertEqual(variables["includeTopTracks"] as? Bool, true)
            XCTAssertEqual(variables["includeTopArtists"] as? Bool, true)
            let extensions = body["extensions"] as! [String: Any]
            let persistedQuery = extensions["persistedQuery"] as! [String: Any]
            XCTAssertEqual(persistedQuery["sha256Hash"] as? String, "feb6d55177e2cbce2ac59214f9493f1ef2e4368eec01b3d4c3468fa1b97336e2")

            let responseJson: [String: Any] = [
                "data": ["me": ["profile": ["topTracks": ["items": [
                    ["uri": "spotify:track:t1", "name": "Song A"],
                ]]]]],
            ]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        let tracks = try await service.getTopTracks(bearerToken: "tok")
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].uri, "spotify:track:t1")
    }

    func testGetTopArtistsHardcodesShortTermRegardlessOfCallerIntent() async throws {
        // Pins the Global Constraints requirement: timeRange must always be
        // SHORT_TERM in the request body, even though the public method
        // signature accepts a timeRange parameter for interface parity. Passes an explicit
        // non-default timeRange so the assertion doesn't rely on an implicit default matching
        // SHORT_TERM by coincidence.
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        var capturedTimeRange: String?
        BuddyActivityService.topContentFetchOverride = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let variables = body["variables"] as! [String: Any]
            let topArtistsInput = variables["topArtistsInput"] as! [String: Any]
            capturedTimeRange = topArtistsInput["timeRange"] as? String
            // `[Any]()` rather than a bare `[]` literal: nested three-plus levels deep inside
            // dictionary literals assigned to `[String: Any]`, Kotlin cannot infer an empty array
            // literal's element type on transpile ("Cannot infer type for type parameter 'V'"),
            // even though the exact same shape resolves fine in Swift.
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [Any]()]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        _ = try await service.getTopArtists(bearerToken: "tok", timeRange: "long_term")
        XCTAssertEqual(capturedTimeRange, "SHORT_TERM")
    }

    func testGetTopArtistsAuthErrorThrowsOn401() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { _ in (401, "") }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        do {
            _ = try await service.getTopArtists(bearerToken: "tok")
            XCTFail("expected throw")
        } catch let error as BuddyActivityServiceError {
            XCTAssertTrue(error.message.contains("Authentication error"))
        }
    }

    func testGetTopArtistsBasicListHasNegativeOneStatsSentinel() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [
                ["uri": "spotify:artist:a1", "profile": ["name": "Artist One"]],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        let artists = try await service.getTopArtists(bearerToken: "tok")
        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(artists[0].followers, -1)
        XCTAssertEqual(artists[0].monthlyListeners, -1)
    }

    func testGetTopTracksParsesWrappedDataEnvelope() async throws {
        // The real Spotify GraphQL response wraps each item's fields one level down under a
        // `data` key (Dart line 779: `final trackData = item['data'];`). The other tests in this
        // file use a flat shape (matching the plan brief's own fixtures, still supported as a
        // fallback), but production's actual shape must also parse correctly (Critical finding 1).
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = [
                "data": ["me": ["profile": ["topTracks": ["items": [
                    ["data": ["uri": "spotify:track:t1", "name": "Song A"]],
                ]]]]],
            ]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        let tracks = try await service.getTopTracks(bearerToken: "tok")
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].uri, "spotify:track:t1")
        XCTAssertEqual(tracks[0].name, "Song A")
    }

    func testGetTopArtistsParsesWrappedDataEnvelope() async throws {
        // Same wrapped-envelope shape as the tracks equivalent above (Dart line 866:
        // `final artistData = item['data'];`), Critical finding 1.
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [
                ["data": ["uri": "spotify:artist:a1", "profile": ["name": "Artist One"]]],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer { BuddyActivityService.topContentFetchOverride = nil }

        let artists = try await service.getTopArtists(bearerToken: "tok")
        XCTAssertEqual(artists.count, 1)
        XCTAssertEqual(artists[0].uri, "spotify:artist:a1")
        XCTAssertEqual(artists[0].name, "Artist One")
        XCTAssertEqual(artists[0].followers, -1)
    }

    func testGetTopArtistsWithDetailsFetchesEnrichmentAndInvokesCallbackProgressively() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [
                ["uri": "spotify:artist:a1", "profile": ["name": "Artist One"]],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        var detailsRequestCount = 0
        BuddyActivityService.artistDetailsFetchOverride = { request in
            detailsRequestCount += 1
            // Thoroughly pin the request shape (method, persisted-query hash, and the JSON
            // encoded into the `variables`/`extensions` query-string params), mirroring how
            // thoroughly the topContent POST body is already pinned above (Minor finding 9).
            XCTAssertEqual(request.httpMethod, "GET")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(queryItems["operationName"], "queryArtistOverview")
            let variables = try! JSONSerialization.jsonObject(with: queryItems["variables"]!.data(using: .utf8)!) as! [String: Any]
            XCTAssertEqual(variables["uri"] as? String, "spotify:artist:a1")
            XCTAssertEqual(variables["locale"] as? String, "")
            XCTAssertEqual(variables["includePrerelease"] as? Bool, true)
            let extensions = try! JSONSerialization.jsonObject(with: queryItems["extensions"]!.data(using: .utf8)!) as! [String: Any]
            let persistedQuery = extensions["persistedQuery"] as! [String: Any]
            XCTAssertEqual(persistedQuery["sha256Hash"] as? String, "d66221ea13998b2f81883c5187d174c8646e4041d67f5b1e103bc262d447e3a0")

            let responseJson: [String: Any] = ["data": ["artist": ["stats": ["followers": 500, "monthlyListeners": 200]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer {
            BuddyActivityService.topContentFetchOverride = nil
            BuddyActivityService.artistDetailsFetchOverride = nil
        }

        let recorder = ArtistUpdateRecorder()
        let artists = try await service.getTopArtistsWithDetails(bearerToken: "tok") { updated in
            recorder.record(updated)
        }
        // Initial return still carries the -1 sentinel; details arrive asynchronously after.
        XCTAssertEqual(artists[0].followers, -1)
        // Deterministically wait for the fire-and-forget fan-out to finish (rather than sleeping a
        // fixed duration) before asserting the progressive callback actually fired with enriched
        // data. Non-vacuous: deleting the fan-out call entirely would leave the recorder empty and
        // this wait would return immediately (nil task), so the assertions below would still fail
        // as expected rather than hanging.
        await service.waitUntilArtistDetailsFanOutComplete()
        XCTAssertEqual(detailsRequestCount, 1)
        XCTAssertFalse(recorder.all.isEmpty)
        XCTAssertEqual(recorder.all.last?.first?.followers, 500)
        XCTAssertEqual(recorder.all.last?.first?.monthlyListeners, 200)
    }

    func testArtistDetailsCacheAvoidsRefetchingWithinSevenDays() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [
                ["uri": "spotify:artist:a1", "profile": ["name": "Artist One"]],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        var detailsRequestCount = 0
        BuddyActivityService.artistDetailsFetchOverride = { _ in
            detailsRequestCount += 1
            let responseJson: [String: Any] = ["data": ["artist": ["stats": ["followers": 500, "monthlyListeners": 200]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer {
            BuddyActivityService.topContentFetchOverride = nil
            BuddyActivityService.artistDetailsFetchOverride = nil
        }

        _ = try await service.getTopArtistsWithDetails(bearerToken: "tok")
        await service.waitUntilArtistDetailsFanOutComplete()
        XCTAssertEqual(detailsRequestCount, 1)

        // Second call for the same artist id, within the 7-day TTL: must serve
        // from cache, not re-fetch. This is the actual behavior under test,
        // not just "the method runs twice without crashing".
        _ = try await service.getTopArtistsWithDetails(bearerToken: "tok")
        await service.waitUntilArtistDetailsFanOutComplete()
        XCTAssertEqual(detailsRequestCount, 1, "second call within TTL must not re-fetch artist details")
    }

    func testArtistDetailsFailedCacheEntryWrittenOnPersistentFailureAndLeavesSentinelStats() async throws {
        // A network failure on the details endpoint must write a `failed: true` cache entry, and
        // an immediate second fan-out over the same artist id must not blow that up into a second
        // round of retries (it must not fetch 4 more times, i.e. 8 total).
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [
                ["uri": "spotify:artist:bad1", "profile": ["name": "Bad Artist"]],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        var detailsRequestCount = 0
        BuddyActivityService.artistDetailsFetchOverride = { _ in
            detailsRequestCount += 1
            return (500, "")
        }
        defer {
            BuddyActivityService.topContentFetchOverride = nil
            BuddyActivityService.artistDetailsFetchOverride = nil
        }

        let recorder = ArtistUpdateRecorder()
        _ = try await service.getTopArtistsWithDetails(bearerToken: "tok") { updated in recorder.record(updated) }
        await service.waitUntilArtistDetailsFanOutComplete()
        // A persistent non-auth failure (500) is retried by ApiRetryService.retryApiCall's default
        // maxRetries: 3, so the first call makes 4 attempts (1 initial + 3 retries) before the
        // fan-out gives up and caches the `failed` marker.
        XCTAssertEqual(detailsRequestCount, 4)
        // The "ensure at least one notification fires even if all fetches failed" fallback still
        // invokes the callback, with stats left unchanged at the sentinel, matching this test's name.
        XCTAssertFalse(recorder.all.isEmpty)
        XCTAssertEqual(recorder.all.last?.first?.followers, -1)
        XCTAssertEqual(recorder.all.last?.first?.monthlyListeners, -1)

        _ = try await service.getTopArtistsWithDetails(bearerToken: "tok")
        await service.waitUntilArtistDetailsFanOutComplete()
        XCTAssertEqual(detailsRequestCount, 4, "an immediate re-call must not re-trigger the retry storm")
    }

    func testArtistDetailsFailedCacheEntryRetriesAfterOwnTtlExpiresAndAppliesFetchedStats() async throws {
        // Non-vacuous proof that the `failed` branch is actually consulted, not just that
        // *something* skips the network call: seed a `failed` entry whose `fetchedAt` is OUTSIDE
        // the 1-hour failed-TTL but well INSIDE the 7-day success-TTL. If the `isFailed` check were
        // deleted (falling through to the generic success-TTL branch instead, which a bare
        // `fetchedAt` age check cannot tell apart from a real success entry), this artist would be
        // treated as a fresh cache hit and the network call would stay skipped, exactly the mutation
        // that made the previous version of this test pass either way.
        let ud = freshUserDefaults()
        let twoHoursAgoMs = Int64(Date().timeIntervalSince1970 * 1000) - (2 * 60 * 60 * 1000)
        seedArtistDetailsCache(ud, entries: [
            "bad1": ["failed": true, "fetchedAt": twoHoursAgoMs],
        ])
        let service = BuddyActivityService(userDefaults: ud)
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [
                ["uri": "spotify:artist:bad1", "profile": ["name": "Bad Artist"]],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        var detailsRequestCount = 0
        BuddyActivityService.artistDetailsFetchOverride = { _ in
            detailsRequestCount += 1
            let responseJson: [String: Any] = ["data": ["artist": ["stats": ["followers": 500, "monthlyListeners": 200]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        defer {
            BuddyActivityService.topContentFetchOverride = nil
            BuddyActivityService.artistDetailsFetchOverride = nil
        }

        let recorder = ArtistUpdateRecorder()
        _ = try await service.getTopArtistsWithDetails(bearerToken: "tok") { updated in recorder.record(updated) }
        await service.waitUntilArtistDetailsFanOutComplete()

        XCTAssertEqual(detailsRequestCount, 1, "an expired failed marker must be retried, not skipped forever")
        XCTAssertFalse(recorder.all.isEmpty)
        XCTAssertEqual(recorder.all.last?.first?.followers, 500)
        XCTAssertEqual(recorder.all.last?.first?.monthlyListeners, 200)
    }

    func testLoadArtistDetailsCacheRestoresFreshEntryFromUserDefaultsWithoutNetworkCall() async throws {
        // Minor finding 10: every other test uses a fresh UserDefaults, only ever exercising
        // loadArtistDetailsCache's empty-input branch. Seed a populated cache, construct a new
        // service instance on the SAME UserDefaults (simulating a relaunch), and confirm the
        // restored entry is served without a network call.
        let ud = freshUserDefaults()
        let recentMs = Int64(Date().timeIntervalSince1970 * 1000) - 1000 // 1 second ago, well within TTL
        seedArtistDetailsCache(ud, entries: [
            "a1": ["followers": 500, "monthlyListeners": 200, "fetchedAt": recentMs],
        ])
        let service = BuddyActivityService(userDefaults: ud)
        BuddyActivityService.topContentFetchOverride = { _ in
            let responseJson: [String: Any] = ["data": ["me": ["profile": ["topArtists": ["items": [
                ["uri": "spotify:artist:a1", "profile": ["name": "Artist One"]],
            ]]]]]]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            return (200, String(data: data, encoding: .utf8)!)
        }
        var detailsRequestCount = 0
        BuddyActivityService.artistDetailsFetchOverride = { _ in
            detailsRequestCount += 1
            return (500, "") // if this fires at all, the restore didn't work; fail loudly via count
        }
        defer {
            BuddyActivityService.topContentFetchOverride = nil
            BuddyActivityService.artistDetailsFetchOverride = nil
        }

        let recorder = ArtistUpdateRecorder()
        _ = try await service.getTopArtistsWithDetails(bearerToken: "tok") { updated in recorder.record(updated) }
        await service.waitUntilArtistDetailsFanOutComplete()

        XCTAssertEqual(detailsRequestCount, 0, "a fresh restored cache entry must be served without hitting the network")
        XCTAssertFalse(recorder.all.isEmpty)
        XCTAssertEqual(recorder.all.last?.first?.followers, 500)
        XCTAssertEqual(recorder.all.last?.first?.monthlyListeners, 200)
    }

    // MARK: - Test fixtures

    private func sampleUser(id: String = "u1") -> User {
        User(id: id, displayName: "Friend", email: "", imageUrl: nil, followers: 0, country: "")
    }

    private func makeActivity(userId: String, ts: Int64, trackName: String = "Song") -> Activity {
        Activity(
            user: sampleUser(id: userId),
            track: Track(id: "t-\(userId)", name: trackName, artists: ["Artist"], album: "Album", durationMs: 0, uri: "spotify:track:\(userId)"),
            timestamp: date(msEpoch: ts),
            isCurrentlyPlaying: false,
            type: ActivityType.track
        )
    }

    /// Builds a flat buddylist API response body with one track-activity friend per tuple.
    private func friendsBody(_ friends: [(id: String, ts: Int64, trackName: String)]) -> String {
        let entries = friends.map { friend in
            """
            {"timestamp":\(friend.ts),"user":{"uri":"spotify:user:\(friend.id)","name":"\(friend.id)","imageUrl":null},
             "track":{"uri":"spotify:track:\(friend.id)","name":"\(friend.trackName)","imageUrl":null,"album":{"name":"Album"},"artist":{"name":"Artist"}}}
            """
        }
        return "{\"friends\": [\(entries.joined(separator: ","))]}"
    }
}
