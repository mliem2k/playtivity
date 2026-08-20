import XCTest
@testable import Playtivity

final class TOTPGeneratorTests: XCTestCase {
    func testActiveVersionIsHighestKey() {
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }

    func testGenerateCodeMatchesKnownVectors() {
        // Vectors generated from the real, unmodified Dart implementation
        // (lib/services/spotify_totp_helper.dart), cross-checked against an
        // independent Python re-implementation using hashlib/hmac.
        let vectors: [(Int64, String)] = [
            (0, "204513"),
            (1_000_000_000_000, "371947"),
            (1_750_000_000_000, "848996"),
            (1_752_300_000_000, "345437"),
        ]
        for (timestamp, expected) in vectors {
            XCTAssertEqual(
                TOTPGenerator.generateCode(timestampMillis: timestamp),
                expected,
                "mismatch for timestampMillis=\(timestamp)"
            )
        }
    }

    func testGenerateParamsIncludesMatchingTotpAndTotpServer() {
        let params = TOTPGenerator.generateParams(timestampMillis: 1_752_300_000_000)
        XCTAssertEqual(params["totp"], "345437")
        XCTAssertEqual(params["totpServer"], "345437")
        XCTAssertEqual(params["totpVer"], "61")
    }
}
