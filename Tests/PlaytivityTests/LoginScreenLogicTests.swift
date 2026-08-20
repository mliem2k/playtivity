import Foundation
import XCTest
@testable import Playtivity

// Skip does not support type declarations nested inside a function body (confirmed by a real
// transpile failure while writing this test file), so this stub error lives at file scope
// instead of inline in testRetryLoopStopsWhenSleepThrows below.
private struct SleepCancelledStubError: Error {}

final class LoginScreenLogicTests: XCTestCase {
    // MARK: - isEligibleForCapture (ref_spotify_webview_login.dart:129-138)

    func testEligibleWhenUrlIsOnOpenSpotifyComWithNoBlockedSegment() {
        let url = URL(string: "https://open.spotify.com/")!
        XCTAssertTrue(LoginScreenLogic.isEligibleForCapture(url: url))
    }

    func testEligibleWhenUrlIsOpenSpotifyComPathThatIsNotBlocked() {
        let url = URL(string: "https://open.spotify.com/collection/tracks")!
        XCTAssertTrue(LoginScreenLogic.isEligibleForCapture(url: url))
    }

    func testNotEligibleWhenUrlIsNotOnOpenSpotifyCom() {
        let url = URL(string: "https://accounts.spotify.com/en/login")!
        XCTAssertFalse(LoginScreenLogic.isEligibleForCapture(url: url))
    }

    func testNotEligibleWhenUrlContainsLoginSegment() {
        let url = URL(string: "https://open.spotify.com/login")!
        XCTAssertFalse(LoginScreenLogic.isEligibleForCapture(url: url))
    }

    func testNotEligibleWhenUrlContainsAuthSegment() {
        let url = URL(string: "https://open.spotify.com/auth/callback")!
        XCTAssertFalse(LoginScreenLogic.isEligibleForCapture(url: url))
    }

    func testNotEligibleWhenUrlContainsChallengeSegment() {
        let url = URL(string: "https://open.spotify.com/challenge/abc")!
        XCTAssertFalse(LoginScreenLogic.isEligibleForCapture(url: url))
    }

    func testNotEligibleWhenUrlContainsErrorSegment() {
        let url = URL(string: "https://open.spotify.com/error")!
        XCTAssertFalse(LoginScreenLogic.isEligibleForCapture(url: url))
    }

    // MARK: - runCookieRetryLoop (ref_spotify_webview_login.dart:41-63)

    func testRetryLoopFindsOnFirstAttempt() async {
        var sleepCount = 0
        var checkedAttempts: [Int] = []
        let result = await LoginScreenLogic.runCookieRetryLoop(
            sleep: { _ in sleepCount += 1 },
            check: { attempt in
                checkedAttempts.append(attempt)
                return true
            }
        )
        XCTAssertEqual(result, LoginScreenLogic.RetryLoopResult.found(attempt: 1))
        XCTAssertEqual(sleepCount, 1)
        XCTAssertEqual(checkedAttempts, [1])
    }

    func testRetryLoopFindsOnLastAttempt() async {
        var checkedAttempts: [Int] = []
        let result = await LoginScreenLogic.runCookieRetryLoop(
            sleep: { _ in },
            check: { attempt in
                checkedAttempts.append(attempt)
                return attempt == LoginScreenLogic.maxCookieRetries
            }
        )
        XCTAssertEqual(result, LoginScreenLogic.RetryLoopResult.found(attempt: LoginScreenLogic.maxCookieRetries))
        XCTAssertEqual(checkedAttempts, Array(1...LoginScreenLogic.maxCookieRetries))
    }

    func testRetryLoopExhaustsAfterMaxRetriesWithoutFinding() async {
        var checkCount = 0
        let result = await LoginScreenLogic.runCookieRetryLoop(
            sleep: { _ in },
            check: { _ in
                checkCount += 1
                return false
            }
        )
        XCTAssertEqual(result, LoginScreenLogic.RetryLoopResult.exhausted)
        XCTAssertEqual(checkCount, LoginScreenLogic.maxCookieRetries)
    }

    func testRetryLoopSleepsOnceBeforeEachAttemptWithConfiguredInterval() async {
        var sleptDurations: [Duration] = []
        _ = await LoginScreenLogic.runCookieRetryLoop(
            sleep: { duration in sleptDurations.append(duration) },
            check: { attempt in attempt == 3 }
        )
        XCTAssertEqual(sleptDurations, [
            LoginScreenLogic.cookieRetryInterval,
            LoginScreenLogic.cookieRetryInterval,
            LoginScreenLogic.cookieRetryInterval,
        ])
    }

    func testRetryLoopRespectsCustomMaxRetriesAndInterval() async {
        var checkCount = 0
        let customInterval = Duration.milliseconds(50)
        let result = await LoginScreenLogic.runCookieRetryLoop(
            maxRetries: 3,
            interval: customInterval,
            sleep: { duration in XCTAssertEqual(duration, customInterval) },
            check: { _ in
                checkCount += 1
                return false
            }
        )
        XCTAssertEqual(result, LoginScreenLogic.RetryLoopResult.exhausted)
        XCTAssertEqual(checkCount, 3)
    }

    func testRetryLoopStopsImmediatelyWhenAlreadyCancelled() async {
        var checkCount = 0
        let result = await LoginScreenLogic.runCookieRetryLoop(
            sleep: { _ in },
            isCancelled: { true },
            check: { _ in
                checkCount += 1
                return false
            }
        )
        XCTAssertEqual(result, LoginScreenLogic.RetryLoopResult.cancelled)
        XCTAssertEqual(checkCount, 0)
    }

    func testRetryLoopStopsMidLoopOnceCancellationFlagFlips() async {
        var checkCount = 0
        var cancelled = false
        let result = await LoginScreenLogic.runCookieRetryLoop(
            sleep: { _ in },
            isCancelled: { cancelled },
            check: { attempt in
                checkCount += 1
                if attempt == 2 { cancelled = true }
                return false
            }
        )
        XCTAssertEqual(result, LoginScreenLogic.RetryLoopResult.cancelled)
        XCTAssertEqual(checkCount, 2)
    }

    func testRetryLoopStopsWhenSleepThrows() async {
        var checkCount = 0
        let result = await LoginScreenLogic.runCookieRetryLoop(
            sleep: { _ in throw SleepCancelledStubError() },
            check: { _ in
                checkCount += 1
                return false
            }
        )
        XCTAssertEqual(result, LoginScreenLogic.RetryLoopResult.cancelled)
        XCTAssertEqual(checkCount, 0)
    }
}
