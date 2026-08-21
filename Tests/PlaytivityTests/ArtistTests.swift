import XCTest
@testable import Playtivity

final class ArtistTests: XCTestCase {
    func testFromJsonParsesAllFields() {
        let json: [String: Any] = [
            "id": "artist1", "name": "Test Artist",
            "image_url": "https://example.com/art.jpg",
            "followers": 1000, "monthly_listeners": 5000,
            "uri": "spotify:artist:artist1",
        ]
        let artist = Artist.fromJson(json)
        XCTAssertEqual(artist.id, "artist1")
        XCTAssertEqual(artist.name, "Test Artist")
        XCTAssertEqual(artist.imageUrl, "https://example.com/art.jpg")
        XCTAssertEqual(artist.followers, 1000)
        XCTAssertEqual(artist.monthlyListeners, 5000)
        XCTAssertEqual(artist.uri, "spotify:artist:artist1")
    }

    func testFromJsonDefaultsFollowersAndMonthlyListenersToNegativeOneNotZero() {
        // The critical sentinel: -1 means "not yet fetched", distinct from a
        // confirmed 0. A `?? 0` default here would silently break
        // ArtistTile's `>= 0` gate on the monthly-listeners display line.
        let json: [String: Any] = ["id": "a", "name": "N", "uri": "spotify:artist:a"]
        let artist = Artist.fromJson(json)
        XCTAssertEqual(artist.followers, -1)
        XCTAssertEqual(artist.monthlyListeners, -1)
    }

    func testFromJsonHandlesNilImageUrl() {
        let json: [String: Any] = ["id": "a", "name": "N", "uri": "spotify:artist:a"]
        let artist = Artist.fromJson(json)
        XCTAssertNil(artist.imageUrl)
    }

    func testToJsonRoundTripsSnakeCaseKeys() {
        let artist = Artist(
            id: "a1", name: "Name", imageUrl: "https://x.test/i.jpg",
            followers: 42, monthlyListeners: 7, uri: "spotify:artist:a1"
        )
        let json = artist.toJson()
        XCTAssertEqual(json["id"] as? String, "a1")
        XCTAssertEqual(json["name"] as? String, "Name")
        XCTAssertEqual(json["image_url"] as? String, "https://x.test/i.jpg")
        XCTAssertEqual(json["followers"] as? Int, 42)
        XCTAssertEqual(json["monthly_listeners"] as? Int, 7)
        XCTAssertEqual(json["uri"] as? String, "spotify:artist:a1")

        let roundTripped = Artist.fromJson(json)
        XCTAssertEqual(roundTripped, artist)
    }

    func testFromJsonHandlesFollowersAsDifferentNumericBoxingViaIntValueHelper() {
        // Matches Track/BuddyActivityService's own established intValue(from:)
        // idiom: JSONSerialization can box an integer as Int or Int32
        // depending on platform/transpile path; the parser must try both.
        let json: [String: Any] = [
            "id": "a", "name": "N", "uri": "spotify:artist:a",
            "followers": Int32(99), "monthly_listeners": Int32(3),
        ]
        let artist = Artist.fromJson(json)
        XCTAssertEqual(artist.followers, 99)
        XCTAssertEqual(artist.monthlyListeners, 3)
    }
}
