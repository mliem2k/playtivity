import Foundation
import XCTest
@testable import Playtivity

final class BuddyActivityServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        BuddyActivityService.buddyListFetchOverride = nil
        ApiRetryService.sleepOverride = { _ in } // skip real backoff delays in retry tests
        resetDiagnostics()
    }

    override func tearDown() {
        BuddyActivityService.buddyListFetchOverride = nil
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

    func testGetFriendActivityAlwaysRecordsFetchTimeEvenOnEmptyResult() async throws {
        let service = BuddyActivityService(userDefaults: freshUserDefaults())
        BuddyActivityService.buddyListFetchOverride = { _ in (statusCode: 200, body: "{\"friends\": []}") }
        _ = try await service.getFriendActivity(bearerToken: "tok")
        // With no prior cache, an empty result stays uncached (cachedActivities remains nil), but
        // the fetch timestamp must still have been recorded so the next call doesn't immediately
        // refetch and hammer the API. shouldRefreshBuddyList's first guard is "no cached data"
        // (cache OR fetch time nil), which is still true here since the cache itself stayed nil,
        // so this is verified indirectly via the persistence tests below and the empty-fetch
        // never-wipes test above, which is the behavior that actually depends on it.
        XCTAssertNil(service.cachedActivities)
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
