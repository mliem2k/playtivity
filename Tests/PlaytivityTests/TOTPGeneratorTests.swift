import XCTest
@testable import Playtivity

final class TOTPGeneratorTests: XCTestCase {
    override func tearDown() {
        TOTPGenerator.clearRuntimeSecrets()
        super.tearDown()
    }

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

    // MARK: - applySecrets mutability (Task 1: runtime secret refresh)

    func testApplySecretsChangesActiveVersionToHighestAppliedKey() {
        let cipher15: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20].map { UInt8($0) }
        TOTPGenerator.applySecrets(["15": cipher15])
        XCTAssertEqual(TOTPGenerator.activeVersion, "15")
    }

    func testApplySecretsChangesGenerateCodeOutputForTheAppliedVersion() {
        let before = TOTPGenerator.generateCode(timestampMillis: 1_700_000_000_000)

        let cipher14: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20].map { UInt8($0) }
        TOTPGenerator.applySecrets(["14": cipher14])
        let after = TOTPGenerator.generateCode(timestampMillis: 1_700_000_000_000)

        XCTAssertNotEqual(before, after)
    }

    func testClearRuntimeSecretsRevertsActiveVersionToHardcodedFallback() {
        let cipher15: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20].map { UInt8($0) }
        TOTPGenerator.applySecrets(["15": cipher15])
        XCTAssertEqual(TOTPGenerator.activeVersion, "15")

        TOTPGenerator.clearRuntimeSecrets()
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }

    func testGenerateParamsTotpVerReflectsAppliedActiveVersion() {
        let cipher15: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20].map { UInt8($0) }
        TOTPGenerator.applySecrets(["15": cipher15])

        let params = TOTPGenerator.generateParams(timestampMillis: 1_700_000_000_000)
        XCTAssertEqual(params["totpVer"], "15")
    }

    func testApplySecretsBeforeCallLeavesHardcodedBehaviorByteIdentical() {
        // Pre-existing vectors must still hold with no applySecrets call in this test at all,
        // guarding against any regression where mutability accidentally changes default behavior.
        XCTAssertEqual(TOTPGenerator.generateCode(timestampMillis: 1_752_300_000_000), "345437")
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }
}
