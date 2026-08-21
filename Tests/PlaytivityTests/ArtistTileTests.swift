import XCTest
@testable import Playtivity

final class ArtistTileTests: XCTestCase {
    func testFormatCountLeavesSmallCountsPlain() {
        XCTAssertEqual(ArtistTile.formatCount(500), "500")
        XCTAssertEqual(ArtistTile.formatCount(999), "999")
    }

    func testFormatCountAbbreviatesThousands() {
        XCTAssertEqual(ArtistTile.formatCount(1_000), "1.0K")
        XCTAssertEqual(ArtistTile.formatCount(999_500), "999.5K")
    }

    func testFormatCountAbbreviatesMillions() {
        XCTAssertEqual(ArtistTile.formatCount(1_000_000), "1.0M")
        XCTAssertEqual(ArtistTile.formatCount(1_500_000), "1.5M")
        XCTAssertEqual(ArtistTile.formatCount(1_234_567), "1.2M")
    }
}
