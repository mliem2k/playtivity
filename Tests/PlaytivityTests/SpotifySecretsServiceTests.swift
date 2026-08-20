import Foundation
import XCTest
@testable import Playtivity

final class SpotifySecretsServiceTests: XCTestCase {
    private struct FakeNetworkError: Error, CustomStringConvertible {
        var description: String { "simulated network failure" }
    }

    override func setUp() {
        super.setUp()
        // A uniquely named suite per test guarantees a pristine cache with no cross-test
        // leakage, without needing SkipFoundation's UserDefaults.removePersistentDomain, which
        // is unavailable there.
        SpotifySecretsService.userDefaults = UserDefaults(suiteName: "SpotifySecretsServiceTests.\(UUID().uuidString)")!
        SpotifySecretsService.remoteFetchOverride = nil
        TOTPGenerator.clearRuntimeSecrets()
    }

    override func tearDown() {
        SpotifySecretsService.remoteFetchOverride = nil
        TOTPGenerator.clearRuntimeSecrets()
        super.tearDown()
    }

    // MARK: - validateSecretsFormat

    func testValidateSecretsFormatAcceptsValidDictWithIntListValues() {
        let result = SpotifySecretsService.validateSecretsFormat([
            "14": [62, 54, 109, 83],
            "13": [59, 92, 64, 70],
        ])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["14"], [62, 54, 109, 83])
        XCTAssertEqual(result?["13"], [59, 92, 64, 70])
    }

    func testValidateSecretsFormatRejectsEmptyDict() {
        XCTAssertNil(SpotifySecretsService.validateSecretsFormat([:]))
    }

    func testValidateSecretsFormatRejectsNonDigitKey() {
        XCTAssertNil(SpotifySecretsService.validateSecretsFormat(["v14": [1, 2, 3]]))
    }

    func testValidateSecretsFormatRejectsKeyWithLettersMixedIn() {
        XCTAssertNil(SpotifySecretsService.validateSecretsFormat(["14a": [1, 2, 3]]))
    }

    func testValidateSecretsFormatRejectsValueThatIsNotAList() {
        XCTAssertNil(SpotifySecretsService.validateSecretsFormat(["14": "not-a-list"]))
    }

    func testValidateSecretsFormatRejectsValueThatIsAMapNotAList() {
        XCTAssertNil(SpotifySecretsService.validateSecretsFormat(["14": ["nested": 1]]))
    }

    func testValidateSecretsFormatRejectsListContainingNonInts() {
        let mixed: [Any] = [1, "two", 3]
        XCTAssertNil(SpotifySecretsService.validateSecretsFormat(["14": mixed]))
    }

    func testValidateSecretsFormatRejectsEmptyValueList() {
        let empty: [Any] = []
        XCTAssertNil(SpotifySecretsService.validateSecretsFormat(["14": empty]))
    }

    // MARK: - loadAndApply: cache hit, no network touched

    func testLoadAndApplyWithFreshCacheAppliesSecretsWithoutTouchingNetworkAgain() async {
        // Seed the cache through one real remote-fetch pass, then remove the override so a
        // second call must be served from cache: the override would fail the test if reached.
        SpotifySecretsService.remoteFetchOverride = {
            (200, self.jsonData(["61": [44, 55, 47, 42, 70, 40, 34, 114]]))
        }
        let seeded = await SpotifySecretsService.loadAndApply()
        XCTAssertNotNil(seeded)

        SpotifySecretsService.remoteFetchOverride = {
            XCTFail("should not reach the network with a fresh cache present")
            throw FakeNetworkError()
        }
        let result = await SpotifySecretsService.loadAndApply()

        XCTAssertEqual(result?["61"], [44, 55, 47, 42, 70, 40, 34, 114])
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }

    // MARK: - loadAndApply: cache TTL expiry

    func testLoadAndApplyWithStaleCacheFallsThroughToRemoteFetch() async {
        let staleTs = Int(Date().timeIntervalSince1970 * 1000) - (7 * 60 * 60 * 1000) // 7h ago
        SpotifySecretsService.userDefaults.set(staleTs, forKey: SpotifySecretsService.cacheTimestampKey)
        SpotifySecretsService.userDefaults.set("{\"14\": [1, 2, 3, 4]}", forKey: SpotifySecretsService.cacheKey)

        var fetchWasCalled = false
        SpotifySecretsService.remoteFetchOverride = {
            fetchWasCalled = true
            return (200, self.jsonData(["77": [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]]))
        }

        let result = await SpotifySecretsService.loadAndApply()

        XCTAssertTrue(fetchWasCalled)
        XCTAssertEqual(result?["77"], [9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
    }

    func testLoadAndApplyWithFreshCacheWithinTtlDoesNotFetch() async {
        let freshTs = Int(Date().timeIntervalSince1970 * 1000) - (1 * 60 * 60 * 1000) // 1h ago
        SpotifySecretsService.userDefaults.set(freshTs, forKey: SpotifySecretsService.cacheTimestampKey)
        SpotifySecretsService.userDefaults.set("{\"61\": [1, 2, 3, 4]}", forKey: SpotifySecretsService.cacheKey)

        SpotifySecretsService.remoteFetchOverride = {
            XCTFail("should not reach the network with a fresh cache present")
            throw FakeNetworkError()
        }

        let result = await SpotifySecretsService.loadAndApply()
        XCTAssertEqual(result?["61"], [1, 2, 3, 4])
    }

    func testLoadAndApplyWithMissingTimestampMeansNoUsableCache() async {
        SpotifySecretsService.userDefaults.set("{\"61\": [1, 2, 3, 4]}", forKey: SpotifySecretsService.cacheKey)
        // No timestamp key written at all.

        var fetchWasCalled = false
        SpotifySecretsService.remoteFetchOverride = {
            fetchWasCalled = true
            return (200, self.jsonData(["61": [1, 2, 3, 4]]))
        }

        _ = await SpotifySecretsService.loadAndApply()
        XCTAssertTrue(fetchWasCalled)
    }

    // MARK: - loadAndApply: remote-fetch-then-cache

    func testLoadAndApplyAppliesSecretsToTOTPGeneratorOnRemoteFetchSuccess() async {
        let cipher15 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
        SpotifySecretsService.remoteFetchOverride = {
            (200, self.jsonData(["15": cipher15]))
        }

        let result = await SpotifySecretsService.loadAndApply()

        XCTAssertNotNil(result)
        XCTAssertEqual(TOTPGenerator.activeVersion, "15")
    }

    func testLoadAndApplyCachesTheRemoteFetchResultForASubsequentCall() async {
        var fetchCallCount = 0
        SpotifySecretsService.remoteFetchOverride = {
            fetchCallCount += 1
            return (200, self.jsonData(["16": [1, 2, 3, 4]]))
        }
        _ = await SpotifySecretsService.loadAndApply()
        XCTAssertEqual(fetchCallCount, 1)

        SpotifySecretsService.remoteFetchOverride = {
            fetchCallCount += 1
            return (200, self.jsonData(["16": [1, 2, 3, 4]]))
        }
        _ = await SpotifySecretsService.loadAndApply()

        // The second call must be served entirely from the cache the first call wrote.
        XCTAssertEqual(fetchCallCount, 1)
    }

    // MARK: - loadAndApply: silent on failure, hardcoded fallback intact

    func testLoadAndApplyReturnsNilOnNonSuccessHttpStatus() async {
        SpotifySecretsService.remoteFetchOverride = {
            (500, Data())
        }

        let result = await SpotifySecretsService.loadAndApply()

        XCTAssertNil(result)
        let code = TOTPGenerator.generateCode(timestampMillis: 1_700_000_000_000)
        XCTAssertEqual(code.count, 6)
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }

    func testLoadAndApplyReturnsNilOnMalformedJson() async {
        SpotifySecretsService.remoteFetchOverride = {
            (200, "not json at all".data(using: String.Encoding.utf8)!)
        }

        let result = await SpotifySecretsService.loadAndApply()
        XCTAssertNil(result)
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }

    func testLoadAndApplyReturnsNilWhenFormatValidationFails() async {
        SpotifySecretsService.remoteFetchOverride = {
            (200, self.jsonDataRaw(["14": "not-a-list"]))
        }

        let result = await SpotifySecretsService.loadAndApply()
        XCTAssertNil(result)
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }

    func testLoadAndApplyReturnsNilOnNetworkError() async {
        SpotifySecretsService.remoteFetchOverride = {
            throw FakeNetworkError()
        }

        let result = await SpotifySecretsService.loadAndApply()

        XCTAssertNil(result)
        XCTAssertEqual(TOTPGenerator.activeVersion, "61")
    }

    // MARK: - Helpers

    private func jsonData(_ dict: [String: [Int]]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    private func jsonDataRaw(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }
}
