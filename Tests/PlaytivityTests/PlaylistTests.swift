import Foundation
import XCTest
@testable import Playtivity

final class PlaylistTests: XCTestCase {
    private func jsonDict(_ text: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
    }

    // MARK: - Persisted flat shape (this app's own toJson output)

    func testDecodesPersistedFlatShape() {
        let json = jsonDict("""
        {
            "id": "p1",
            "name": "My Playlist",
            "description": "A great mix",
            "image_url": "https://img/p1.jpg",
            "track_count": 42,
            "uri": "spotify:playlist:p1",
            "owner_id": "user1",
            "owner_name": "User One",
            "is_public": true
        }
        """)
        let playlist = Playlist.fromJson(json)
        XCTAssertEqual(playlist.id, "p1")
        XCTAssertEqual(playlist.name, "My Playlist")
        XCTAssertEqual(playlist.description, "A great mix")
        XCTAssertEqual(playlist.imageUrl, "https://img/p1.jpg")
        XCTAssertEqual(playlist.trackCount, 42)
        XCTAssertEqual(playlist.uri, "spotify:playlist:p1")
        XCTAssertEqual(playlist.ownerId, "user1")
        XCTAssertEqual(playlist.ownerName, "User One")
        XCTAssertTrue(playlist.isPublic)
    }

    // MARK: - API shape (nested Spotify Web API JSON)

    func testDecodesApiShapeWithNestedImagesTracksOwnerAndPublic() {
        let json = jsonDict("""
        {
            "id": "p1",
            "name": "My Playlist",
            "images": [{"url": "https://img/p1.jpg"}],
            "tracks": {"total": 42},
            "uri": "spotify:playlist:p1",
            "owner": {"id": "user1", "display_name": "User One"},
            "public": true
        }
        """)
        let playlist = Playlist.fromJson(json)
        XCTAssertEqual(playlist.imageUrl, "https://img/p1.jpg")
        XCTAssertEqual(playlist.trackCount, 42)
        XCTAssertEqual(playlist.ownerId, "user1")
        XCTAssertEqual(playlist.ownerName, "User One")
        XCTAssertTrue(playlist.isPublic)
    }

    func testApiShapeEmptyImagesArrayGivesNilImageUrlRatherThanCrashing() {
        let json = jsonDict("""
        {"id": "p1", "name": "N", "images": [], "uri": "u"}
        """)
        let playlist = Playlist.fromJson(json)
        XCTAssertNil(playlist.imageUrl)
    }

    func testApiShapeMissingTracksTotalDefaultsToZero() {
        let json = jsonDict("""
        {"id": "p1", "name": "N", "tracks": {}, "uri": "u"}
        """)
        let playlist = Playlist.fromJson(json)
        XCTAssertEqual(playlist.trackCount, 0)
    }

    // MARK: - Defensive defaults

    func testMissingFieldsDefaultGracefully() {
        let playlist = Playlist.fromJson([:])
        XCTAssertEqual(playlist.id, "")
        XCTAssertEqual(playlist.name, "")
        XCTAssertNil(playlist.description)
        XCTAssertNil(playlist.imageUrl)
        XCTAssertEqual(playlist.trackCount, 0)
        XCTAssertEqual(playlist.uri, "")
        XCTAssertEqual(playlist.ownerId, "")
        XCTAssertEqual(playlist.ownerName, "")
        XCTAssertFalse(playlist.isPublic)
    }

    // MARK: - Round trip

    func testRoundTripFromJsonToJsonPreservesFlatShape() {
        let original = Playlist(
            id: "p1", name: "My Playlist", description: "desc", imageUrl: "https://img/p1.jpg",
            trackCount: 10, uri: "spotify:playlist:p1", ownerId: "user1", ownerName: "User One", isPublic: false
        )
        let decoded = Playlist.fromJson(original.toJson())
        XCTAssertEqual(decoded, original)
    }

    func testCodableConformanceRoundTripsTheFlatShape() throws {
        let original = Playlist(
            id: "p1", name: "My Playlist", description: "desc", imageUrl: "https://img/p1.jpg",
            trackCount: 10, uri: "spotify:playlist:p1", ownerId: "user1", ownerName: "User One", isPublic: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Playlist.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
