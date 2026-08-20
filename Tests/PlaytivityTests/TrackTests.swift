import Foundation
import XCTest
@testable import Playtivity

final class TrackTests: XCTestCase {
    private func jsonDict(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
    }

    // MARK: - API shape (nested Spotify Web API JSON)

    func testDecodesApiShapeWithNestedAlbumAndArtistObjects() {
        let json = jsonDict("""
        {
            "id": "t1",
            "name": "Song One",
            "artists": [
                {"name": "Artist One", "uri": "spotify:artist:a1"},
                {"name": "Artist Two", "uri": "spotify:artist:a2"}
            ],
            "album": {
                "name": "Album Name",
                "uri": "spotify:album:al1",
                "images": [{"url": "https://img/1.jpg"}]
            },
            "duration_ms": 210000,
            "preview_url": "https://preview.example/1",
            "uri": "spotify:track:t1"
        }
        """)
        let track = Track.fromJson(json)
        XCTAssertEqual(track.id, "t1")
        XCTAssertEqual(track.name, "Song One")
        XCTAssertEqual(track.artists, ["Artist One", "Artist Two"])
        XCTAssertEqual(track.artistUris, ["spotify:artist:a1", "spotify:artist:a2"])
        XCTAssertEqual(track.album, "Album Name")
        XCTAssertEqual(track.albumUri, "spotify:album:al1")
        XCTAssertEqual(track.imageUrl, "https://img/1.jpg")
        XCTAssertEqual(track.durationMs, 210000)
        XCTAssertEqual(track.previewUrl, "https://preview.example/1")
        XCTAssertEqual(track.uri, "spotify:track:t1")
    }

    func testApiAlbumImageUrlFallsBackToImagesArrayWhenNoTopLevelOrAlbumImageUrlField() {
        let json = jsonDict("""
        {"id": "t1", "name": "Song", "artists": [], "album": {"name": "A", "images": [{"url": "https://img/2.jpg"}]},
         "duration_ms": 1000, "uri": "u"}
        """)
        let track = Track.fromJson(json)
        XCTAssertEqual(track.imageUrl, "https://img/2.jpg")
    }

    func testApiArtistUrisFallBackToTopLevelArtistUrisWhenArtistObjectsCarryNoUri() {
        let json = jsonDict("""
        {"id": "t1", "name": "Song", "artists": [{"name": "Artist One"}, {"name": "Artist Two"}],
         "artist_uris": ["spotify:artist:fallback"], "album": {"name": "A"}, "duration_ms": 1000, "uri": "u"}
        """)
        let track = Track.fromJson(json)
        XCTAssertEqual(track.artists, ["Artist One", "Artist Two"])
        XCTAssertEqual(track.artistUris, ["spotify:artist:fallback"])
    }

    // MARK: - Persisted flat shape (this app's own toJson output)

    func testDecodesPersistedFlatShape() {
        let json = jsonDict("""
        {
            "id": "t1",
            "name": "Song One",
            "artists": ["Artist One", "Artist Two"],
            "artist_uris": ["spotify:artist:a1", "spotify:artist:a2"],
            "album": "Album Name",
            "album_uri": "spotify:album:al1",
            "image_url": "https://img/1.jpg",
            "duration_ms": 210000,
            "preview_url": null,
            "uri": "spotify:track:t1"
        }
        """)
        let track = Track.fromJson(json)
        XCTAssertEqual(track.id, "t1")
        XCTAssertEqual(track.name, "Song One")
        XCTAssertEqual(track.artists, ["Artist One", "Artist Two"])
        XCTAssertEqual(track.artistUris, ["spotify:artist:a1", "spotify:artist:a2"])
        XCTAssertEqual(track.album, "Album Name")
        XCTAssertEqual(track.albumUri, "spotify:album:al1")
        XCTAssertEqual(track.imageUrl, "https://img/1.jpg")
        XCTAssertEqual(track.durationMs, 210000)
        XCTAssertNil(track.previewUrl)
        XCTAssertEqual(track.uri, "spotify:track:t1")
    }

    // MARK: - Defensive defaults

    func testMissingFieldsDefaultGracefully() {
        let track = Track.fromJson([:])
        XCTAssertEqual(track.id, "")
        XCTAssertEqual(track.name, "")
        XCTAssertEqual(track.artists, [String]())
        XCTAssertEqual(track.artistUris, [String]())
        XCTAssertEqual(track.album, "")
        XCTAssertNil(track.albumUri)
        XCTAssertNil(track.imageUrl)
        XCTAssertEqual(track.durationMs, 0)
        XCTAssertNil(track.previewUrl)
        XCTAssertEqual(track.uri, "")
    }

    // MARK: - Computed properties

    func testArtistsStringJoinsWithCommaSpace() {
        let track = Track(id: "1", name: "N", artists: ["A", "B", "C"], album: "Al", durationMs: 0, uri: "u")
        XCTAssertEqual(track.artistsString, "A, B, C")
    }

    func testDurationFormatsMinutesAndZeroPaddedSeconds() {
        let track = Track(id: "1", name: "N", artists: ["A"], album: "Al", durationMs: 65000, uri: "u")
        XCTAssertEqual(track.duration, "1:05")
    }

    func testDurationUnderOneMinute() {
        let track = Track(id: "1", name: "N", artists: ["A"], album: "Al", durationMs: 5000, uri: "u")
        XCTAssertEqual(track.duration, "0:05")
    }

    func testFirstArtistUriReturnsFirstWhenPresent() {
        let track = Track(id: "1", name: "N", artists: ["A"], artistUris: ["u1", "u2"], album: "Al", durationMs: 0, uri: "u")
        XCTAssertEqual(track.firstArtistUri, "u1")
    }

    func testFirstArtistUriReturnsNilWhenEmpty() {
        let track = Track(id: "1", name: "N", artists: ["A"], album: "Al", durationMs: 0, uri: "u")
        XCTAssertNil(track.firstArtistUri)
    }

    // MARK: - Round trip

    func testRoundTripFromJsonToJsonPreservesFlatShape() {
        let original = Track(
            id: "t1", name: "Song", artists: ["Artist One"], artistUris: ["spotify:artist:a1"],
            album: "Album", albumUri: "spotify:album:al1", imageUrl: "https://img/1.jpg",
            durationMs: 123456, previewUrl: "https://preview", uri: "spotify:track:t1"
        )
        let decoded = Track.fromJson(original.toJson())
        XCTAssertEqual(decoded, original)
    }

    func testCodableConformanceRoundTripsTheFlatShape() throws {
        let original = Track(
            id: "t1", name: "Song", artists: ["Artist One"], artistUris: ["spotify:artist:a1"],
            album: "Album", albumUri: "spotify:album:al1", imageUrl: "https://img/1.jpg",
            durationMs: 123456, previewUrl: "https://preview", uri: "spotify:track:t1"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
