import Foundation
import XCTest
@testable import Playtivity

final class ActivityTests: XCTestCase {
    private func jsonDict(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
    }

    private func sampleUser() -> User {
        User(id: "u1", displayName: "Friend", email: "f@example.com", imageUrl: nil, followers: 3, country: "US")
    }

    private func sampleTrack() -> Track {
        Track(id: "t1", name: "Song", artists: ["Artist"], album: "Album", durationMs: 1000, uri: "spotify:track:t1")
    }

    private func samplePlaylist() -> Playlist {
        Playlist(id: "p1", name: "Playlist", trackCount: 5, uri: "spotify:playlist:p1", ownerId: "o1", ownerName: "Owner", isPublic: true)
    }

    private func iso8601String(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    // MARK: - Round trip (fromJson/toJson)

    func testRoundTripFromJsonToJsonTrackActivityPreservesFields() throws {
        let original = Activity(
            user: sampleUser(), track: sampleTrack(), timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isCurrentlyPlaying: true, type: ActivityType.track
        )
        let decoded = try Activity.fromJson(original.toJson())
        XCTAssertEqual(decoded.user, original.user)
        XCTAssertEqual(decoded.track, original.track)
        XCTAssertNil(decoded.playlist)
        XCTAssertEqual(decoded.type, ActivityType.track)
        // isCurrentlyPlaying is recomputed on decode, not preserved: this timestamp is from 2023,
        // so it must decode to false regardless of what was encoded.
        XCTAssertFalse(decoded.isCurrentlyPlaying)
    }

    func testRoundTripFromJsonToJsonPlaylistActivityPreservesFields() throws {
        let original = Activity(
            user: sampleUser(), playlist: samplePlaylist(), timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isCurrentlyPlaying: false, type: ActivityType.playlist
        )
        let decoded = try Activity.fromJson(original.toJson())
        XCTAssertEqual(decoded.user, original.user)
        XCTAssertNil(decoded.track)
        XCTAssertEqual(decoded.playlist, original.playlist)
        XCTAssertEqual(decoded.type, ActivityType.playlist)
        XCTAssertFalse(decoded.isCurrentlyPlaying)
    }

    func testCodableConformanceRoundTripsTrackActivity() throws {
        let original = Activity(
            user: sampleUser(), track: sampleTrack(), timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isCurrentlyPlaying: false, type: ActivityType.track
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Activity.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // A round trip alone cannot catch a missing CodingKeys enum: encode and decode would agree
    // with each other on the wrong (camelCase) key just as happily as the right one. This test
    // inspects the raw encoded JSON directly so a regression back to compiler-default camelCase
    // keys fails loudly, matching the snake_case key toJson() actually writes.
    func testCodableConformanceEncodesSnakeCaseIsCurrentlyPlayingKey() throws {
        let original = Activity(
            user: sampleUser(), track: sampleTrack(), timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isCurrentlyPlaying: false, type: ActivityType.track
        )
        let data = try JSONEncoder().encode(original)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["is_currently_playing"])
        XCTAssertNil(obj?["isCurrentlyPlaying"])
    }

    // MARK: - isCurrentlyPlaying recompute on decode (never trust the persisted flag)

    func testDecodeRecomputesIsCurrentlyPlayingFalseForStaleOldTimestampEvenWhenPersistedTrue() throws {
        // Hand-written JSON: is_currently_playing is persisted as true, but the timestamp is hours
        // old. Decoding must NOT trust the persisted flag.
        let json = jsonDict("""
        {
            "user": {"id": "u1", "display_name": "Friend", "email": "f@example.com", "followers": 0, "country": "US"},
            "track": {"id": "t1", "name": "Song", "artists": [], "album": "Al", "duration_ms": 0, "uri": "u"},
            "playlist": null,
            "timestamp": "2020-01-01T00:00:00.000Z",
            "is_currently_playing": true,
            "type": "track"
        }
        """)
        let activity = try Activity.fromJson(json)
        XCTAssertFalse(activity.isCurrentlyPlaying)
    }

    func testDecodeRecomputesIsCurrentlyPlayingTrueForRecentTimestampEvenWhenPersistedFalse() throws {
        let recentTimestamp = iso8601String(Date())
        let json = jsonDict("""
        {
            "user": {"id": "u1", "display_name": "Friend", "email": "f@example.com", "followers": 0, "country": "US"},
            "track": {"id": "t1", "name": "Song", "artists": [], "album": "Al", "duration_ms": 0, "uri": "u"},
            "playlist": null,
            "timestamp": "\(recentTimestamp)",
            "is_currently_playing": false,
            "type": "track"
        }
        """)
        let activity = try Activity.fromJson(json)
        XCTAssertTrue(activity.isCurrentlyPlaying)
    }

    func testPlaylistActivityIsCurrentlyPlayingIsAlwaysFalseEvenWithRecentTimestampAndPersistedTrue() throws {
        let recentTimestamp = iso8601String(Date())
        let json = jsonDict("""
        {
            "user": {"id": "u1", "display_name": "Friend", "email": "f@example.com", "followers": 0, "country": "US"},
            "track": null,
            "playlist": {"id": "p1", "name": "P", "track_count": 1, "uri": "u", "owner_id": "o", "owner_name": "O", "is_public": false},
            "timestamp": "\(recentTimestamp)",
            "is_currently_playing": true,
            "type": "playlist"
        }
        """)
        let activity = try Activity.fromJson(json)
        XCTAssertFalse(activity.isCurrentlyPlaying)
    }

    func testUnrecognizedTypeDefaultsToTrack() throws {
        let json = jsonDict("""
        {
            "user": {"id": "u1", "display_name": "Friend", "email": "f@example.com", "followers": 0, "country": "US"},
            "track": {"id": "t1", "name": "Song", "artists": [], "album": "Al", "duration_ms": 0, "uri": "u"},
            "timestamp": "2020-01-01T00:00:00.000Z",
            "is_currently_playing": false,
            "type": "something_else"
        }
        """)
        let activity = try Activity.fromJson(json)
        XCTAssertEqual(activity.type, ActivityType.track)
    }

    // MARK: - fromJson error cases

    func testFromJsonThrowsWhenUserMissing() {
        let json = jsonDict("""
        {"timestamp": "2020-01-01T00:00:00.000Z", "type": "track", "track": {"id": "t1", "name": "S", "artists": [], "album": "A", "duration_ms": 0, "uri": "u"}}
        """)
        do {
            _ = try Activity.fromJson(json)
            XCTFail("expected fromJson to throw when 'user' is missing")
        } catch {
            // expected
        }
    }

    func testFromJsonThrowsWhenTimestampMissing() {
        let json = jsonDict("""
        {"user": {"id": "u1", "display_name": "F", "email": "e", "followers": 0, "country": "US"}, "type": "track", "track": {"id": "t1", "name": "S", "artists": [], "album": "A", "duration_ms": 0, "uri": "u"}}
        """)
        do {
            _ = try Activity.fromJson(json)
            XCTFail("expected fromJson to throw when 'timestamp' is missing")
        } catch {
            // expected
        }
    }

    func testFromJsonThrowsWhenTrackMissingForTrackType() {
        let json = jsonDict("""
        {"user": {"id": "u1", "display_name": "F", "email": "e", "followers": 0, "country": "US"}, "timestamp": "2020-01-01T00:00:00.000Z", "type": "track"}
        """)
        do {
            _ = try Activity.fromJson(json)
            XCTFail("expected fromJson to throw when 'track' is missing for type track")
        } catch {
            // expected
        }
    }

    // MARK: - computeIsCurrentlyPlaying (pure helper, direct coverage)

    func testComputeIsCurrentlyPlayingTrueForOneMinuteAgo() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let timestamp = now.addingTimeInterval(-60)
        XCTAssertTrue(Activity.computeIsCurrentlyPlaying(type: ActivityType.track, timestamp: timestamp, now: now))
    }

    func testComputeIsCurrentlyPlayingFalseForTenMinutesAgo() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let timestamp = now.addingTimeInterval(-10 * 60)
        XCTAssertFalse(Activity.computeIsCurrentlyPlaying(type: ActivityType.track, timestamp: timestamp, now: now))
    }

    func testComputeIsCurrentlyPlayingFalseForFutureTimestamp() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let timestamp = now.addingTimeInterval(60)
        XCTAssertFalse(Activity.computeIsCurrentlyPlaying(type: ActivityType.track, timestamp: timestamp, now: now))
    }

    func testComputeIsCurrentlyPlayingAlwaysFalseForPlaylistType() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(Activity.computeIsCurrentlyPlaying(type: ActivityType.playlist, timestamp: now, now: now))
    }

    // MARK: - Invariant (exactly one of track/playlist matches type)

    func testIsValidPairingTrueForTrackTypeWithTrackOnly() {
        XCTAssertTrue(Activity.isValidPairing(track: sampleTrack(), playlist: nil, type: ActivityType.track))
    }

    func testIsValidPairingTrueForPlaylistTypeWithPlaylistOnly() {
        XCTAssertTrue(Activity.isValidPairing(track: nil, playlist: samplePlaylist(), type: ActivityType.playlist))
    }

    func testIsValidPairingFalseWhenBothNil() {
        XCTAssertFalse(Activity.isValidPairing(track: nil, playlist: nil, type: ActivityType.track))
    }

    func testIsValidPairingFalseWhenBothPresent() {
        XCTAssertFalse(Activity.isValidPairing(track: sampleTrack(), playlist: samplePlaylist(), type: ActivityType.track))
    }

    func testIsValidPairingFalseWhenTypeMismatchesPresentValue() {
        XCTAssertFalse(Activity.isValidPairing(track: sampleTrack(), playlist: nil, type: ActivityType.playlist))
    }

    // MARK: - Computed content properties

    func testContentPropertiesForTrackActivity() {
        let activity = Activity(user: sampleUser(), track: sampleTrack(), timestamp: Date(), isCurrentlyPlaying: false, type: ActivityType.track)
        XCTAssertEqual(activity.contentName, "Song")
        XCTAssertEqual(activity.contentUri, "spotify:track:t1")
        XCTAssertEqual(activity.contentSubtitle, "Artist")
        XCTAssertEqual(activity.contentDetails, "Album")
    }

    func testContentPropertiesForPlaylistActivity() {
        let activity = Activity(user: sampleUser(), playlist: samplePlaylist(), timestamp: Date(), isCurrentlyPlaying: false, type: ActivityType.playlist)
        XCTAssertEqual(activity.contentName, "Playlist")
        XCTAssertEqual(activity.contentUri, "spotify:playlist:p1")
        XCTAssertEqual(activity.contentSubtitle, "Playlist • 5 tracks")
        XCTAssertEqual(activity.contentDetails, "by Owner")
    }
}
