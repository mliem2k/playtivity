import Foundation
import XCTest
@testable import Playtivity

// Skip does not support type declarations nested inside a function body (see
// LoginScreenLogicTests.swift's identical note), so this stub error lives at file scope.
private struct SpikeSleepStubError: Error {}

final class HeadlessReAuthSpikeLogicTests: XCTestCase {
    override func tearDown() {
        HeadlessReAuthSpikeCoordinator.resetForTesting()
        super.tearDown()
    }

    // MARK: - classifyNavigation (ref_auth_provider.dart:422-432)

    func testClassifyNavigationSessionGoneForTheLoginUrlEvenThoughItEmbedsOpenSpotifyCom() {
        // The exact URL LoginScreen itself navigates to: contains "open.spotify.com" in its own
        // continue= query param, so the login/auth check must run BEFORE the containment check.
        let url = URL(string: "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!
        XCTAssertEqual(HeadlessReAuthSpikeLogic.classifyNavigation(url: url), HeadlessReAuthSpikeLogic.NavigationOutcome.sessionGone)
    }

    func testClassifyNavigationSessionGoneWhenUrlContainsLoginSegment() {
        let url = URL(string: "https://open.spotify.com/login")!
        XCTAssertEqual(HeadlessReAuthSpikeLogic.classifyNavigation(url: url), HeadlessReAuthSpikeLogic.NavigationOutcome.sessionGone)
    }

    func testClassifyNavigationSessionGoneWhenUrlContainsAuthSegment() {
        let url = URL(string: "https://open.spotify.com/auth/callback")!
        XCTAssertEqual(HeadlessReAuthSpikeLogic.classifyNavigation(url: url), HeadlessReAuthSpikeLogic.NavigationOutcome.sessionGone)
    }

    func testClassifyNavigationCheckCookiesNowWhenUrlIsOpenSpotifyRoot() {
        let url = URL(string: "https://open.spotify.com/")!
        XCTAssertEqual(HeadlessReAuthSpikeLogic.classifyNavigation(url: url), HeadlessReAuthSpikeLogic.NavigationOutcome.checkCookiesNow)
    }

    func testClassifyNavigationCheckCookiesNowWhenUrlIsOpenSpotifyPathWithNoBlockedSegment() {
        let url = URL(string: "https://open.spotify.com/collection/tracks")!
        XCTAssertEqual(HeadlessReAuthSpikeLogic.classifyNavigation(url: url), HeadlessReAuthSpikeLogic.NavigationOutcome.checkCookiesNow)
    }

    func testClassifyNavigationIgnoreWhenUrlIsUnrelatedDomain() {
        let url = URL(string: "https://cdn.example.com/asset.js")!
        XCTAssertEqual(HeadlessReAuthSpikeLogic.classifyNavigation(url: url), HeadlessReAuthSpikeLogic.NavigationOutcome.ignore)
    }

    // MARK: - checkWithSettleRetry (ref_auth_provider.dart:433-438)

    func testCheckWithSettleRetryReturnsImmediatelyWhenFoundOnFirstCheck() async {
        var sleepCount = 0
        var checkCount = 0
        let result = await HeadlessReAuthSpikeLogic.checkWithSettleRetry(
            checkNow: {
                checkCount += 1
                return "abc"
            },
            sleep: { _ in sleepCount += 1 }
        )
        XCTAssertEqual(result, "abc")
        XCTAssertEqual(checkCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    func testCheckWithSettleRetrySleepsOnceWithSettleDelayThenReturnsSecondCheckResult() async {
        var checkCount = 0
        var sleptDurations: [Duration] = []
        let result = await HeadlessReAuthSpikeLogic.checkWithSettleRetry(
            checkNow: {
                checkCount += 1
                return checkCount == 1 ? nil : "xyz"
            },
            sleep: { duration in sleptDurations.append(duration) }
        )
        XCTAssertEqual(result, "xyz")
        XCTAssertEqual(checkCount, 2)
        XCTAssertEqual(sleptDurations, [HeadlessReAuthSpikeLogic.settleDelay])
    }

    func testCheckWithSettleRetryReturnsNilWhenBothChecksFail() async {
        var checkCount = 0
        let result = await HeadlessReAuthSpikeLogic.checkWithSettleRetry(
            checkNow: {
                checkCount += 1
                return nil
            },
            sleep: { _ in }
        )
        XCTAssertNil(result)
        XCTAssertEqual(checkCount, 2)
    }

    func testCheckWithSettleRetryReturnsNilAndSkipsSecondCheckWhenSleepThrows() async {
        var checkCount = 0
        let result = await HeadlessReAuthSpikeLogic.checkWithSettleRetry(
            checkNow: {
                checkCount += 1
                return nil
            },
            sleep: { _ in throw SpikeSleepStubError() }
        )
        XCTAssertNil(result)
        XCTAssertEqual(checkCount, 1)
    }

    // MARK: - resolvedSpDc (ref_auth_provider.dart:451-458)

    func testResolvedSpDcNilWhenNewIsNil() {
        XCTAssertNil(HeadlessReAuthSpikeLogic.resolvedSpDc(newSpDc: nil, existingSpDc: "old"))
    }

    func testResolvedSpDcNilWhenNewIsEmpty() {
        XCTAssertNil(HeadlessReAuthSpikeLogic.resolvedSpDc(newSpDc: "", existingSpDc: nil))
    }

    func testResolvedSpDcNilWhenNewEqualsExisting() {
        XCTAssertNil(HeadlessReAuthSpikeLogic.resolvedSpDc(newSpDc: "same", existingSpDc: "same"))
    }

    func testResolvedSpDcReturnsNewWhenExistingIsNil() {
        XCTAssertEqual(HeadlessReAuthSpikeLogic.resolvedSpDc(newSpDc: "fresh", existingSpDc: nil), "fresh")
    }

    func testResolvedSpDcReturnsNewWhenDifferentFromExisting() {
        XCTAssertEqual(HeadlessReAuthSpikeLogic.resolvedSpDc(newSpDc: "fresh", existingSpDc: "old"), "fresh")
    }

    // MARK: - awaitResolution (ref_auth_provider.dart:446, 20s overall budget)

    func testAwaitResolutionReturnsImmediatelyWhenAlreadyResolved() async {
        var pollCount = 0
        var sleepCount = 0
        let result = await HeadlessReAuthSpikeLogic.awaitResolution(
            poll: {
                pollCount += 1
                return HeadlessReAuthSpikeLogic.Outcome.resolved("found")
            },
            sleep: { _ in sleepCount += 1 }
        )
        XCTAssertEqual(result, "found")
        XCTAssertEqual(pollCount, 1)
        XCTAssertEqual(sleepCount, 0)
    }

    func testAwaitResolutionPollsUntilResolved() async {
        var pollCount = 0
        var sleptDurations: [Duration] = []
        let result = await HeadlessReAuthSpikeLogic.awaitResolution(
            poll: {
                pollCount += 1
                return pollCount < 3
                    ? HeadlessReAuthSpikeLogic.Outcome.pending
                    : HeadlessReAuthSpikeLogic.Outcome.resolved("found-later")
            },
            sleep: { duration in sleptDurations.append(duration) }
        )
        XCTAssertEqual(result, "found-later")
        XCTAssertEqual(pollCount, 3)
        XCTAssertEqual(sleptDurations, [
            HeadlessReAuthSpikeLogic.overallTimeoutPollInterval,
            HeadlessReAuthSpikeLogic.overallTimeoutPollInterval,
        ])
    }

    func testAwaitResolutionTimesOutAfterMaxPolls() async {
        var pollCount = 0
        var sleepCount = 0
        let result = await HeadlessReAuthSpikeLogic.awaitResolution(
            maxPolls: 3,
            interval: Duration.milliseconds(10),
            poll: {
                pollCount += 1
                return HeadlessReAuthSpikeLogic.Outcome.pending
            },
            sleep: { _ in sleepCount += 1 }
        )
        XCTAssertNil(result)
        XCTAssertEqual(pollCount, 3)
        XCTAssertEqual(sleepCount, 3)
    }

    func testAwaitResolutionReturnsNilImmediatelyWhenSleepThrows() async {
        var pollCount = 0
        let result = await HeadlessReAuthSpikeLogic.awaitResolution(
            maxPolls: 5,
            interval: Duration.milliseconds(10),
            poll: {
                pollCount += 1
                return HeadlessReAuthSpikeLogic.Outcome.pending
            },
            sleep: { _ in throw SpikeSleepStubError() }
        )
        XCTAssertNil(result)
        XCTAssertEqual(pollCount, 1)
    }

    // MARK: - HeadlessReAuthSpikeCoordinator

    func testCoordinatorStartGivesFreshPendingOutcome() {
        let id = HeadlessReAuthSpikeCoordinator.start()
        XCTAssertEqual(HeadlessReAuthSpikeCoordinator.outcome(id: id), HeadlessReAuthSpikeLogic.Outcome.pending)
        XCTAssertEqual(HeadlessReAuthSpikeCoordinator.currentRequestID, id)
    }

    func testCoordinatorResolveSetsOutcome() {
        let id = HeadlessReAuthSpikeCoordinator.start()
        HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: "abc")
        XCTAssertEqual(HeadlessReAuthSpikeCoordinator.outcome(id: id), HeadlessReAuthSpikeLogic.Outcome.resolved("abc"))
    }

    func testCoordinatorResolveIsIdempotentFirstWriteWins() {
        let id = HeadlessReAuthSpikeCoordinator.start()
        HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: "first")
        HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: "second")
        XCTAssertEqual(HeadlessReAuthSpikeCoordinator.outcome(id: id), HeadlessReAuthSpikeLogic.Outcome.resolved("first"))
    }

    func testCoordinatorResolveIgnoresStaleIdAfterANewRequestHasStarted() {
        let staleID = HeadlessReAuthSpikeCoordinator.start()
        HeadlessReAuthSpikeCoordinator.finish(id: staleID)
        let currentID = HeadlessReAuthSpikeCoordinator.start()

        // A late navigation callback for the old (already finished) request must not resolve or
        // resurrect state for it, and must not disturb the new current request.
        HeadlessReAuthSpikeCoordinator.resolve(id: staleID, spDc: "stale-value")

        XCTAssertEqual(HeadlessReAuthSpikeCoordinator.outcome(id: currentID), HeadlessReAuthSpikeLogic.Outcome.pending)
        XCTAssertEqual(HeadlessReAuthSpikeCoordinator.currentRequestID, currentID)
    }

    func testCoordinatorFinishClearsCurrentRequestID() {
        let id = HeadlessReAuthSpikeCoordinator.start()
        HeadlessReAuthSpikeCoordinator.finish(id: id)
        XCTAssertNil(HeadlessReAuthSpikeCoordinator.currentRequestID)
    }

    func testCoordinatorResetForTestingClearsAllState() {
        let id = HeadlessReAuthSpikeCoordinator.start()
        HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: "x")
        HeadlessReAuthSpikeCoordinator.resetForTesting()
        XCTAssertNil(HeadlessReAuthSpikeCoordinator.currentRequestID)
    }

    // MARK: - HeadlessReAuthSpike.attempt (integration of the above, no host mounted)
    //
    // `attempt()` uses the real 20 second/80 poll production budget (it has no injectable
    // clock, matching the brief's exact `static func attempt(existingSpDc: String?) async ->
    // String?` signature), so these tests race a resolver `Task` against `attempt()`'s own poll
    // loop instead of waiting out the full budget: `HeadlessReAuthSpikeCoordinator
    // .currentRequestID` becomes non-nil the instant `attempt()` calls `.start()`, so a
    // background task can grab that id and resolve it within a few milliseconds, well inside
    // `attempt()`'s first 250ms poll interval. This proves the actual `start -> poll -> resolve
    // -> resolvedSpDc` wiring end to end, not just each piece in isolation, without a 20 second
    // wall-clock tax on every `swift test` run. Deliberately built from `Task { }` +
    // `Task.sleep(for:)` only (no `async let`/continuations), the same concurrency idioms already
    // proven to transpile elsewhere in this codebase (LoginScreen's cookieRetryTask).

    func testAttemptResolvesQuicklyOnceCoordinatorReportsAFreshSpDc() async {
        Task {
            while HeadlessReAuthSpikeCoordinator.currentRequestID == nil {
                try? await Task.sleep(for: Duration.milliseconds(5))
            }
            if let id = HeadlessReAuthSpikeCoordinator.currentRequestID {
                HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: "fresh-value")
            }
        }
        let value = await HeadlessReAuthSpike.attempt(existingSpDc: "old-value")
        XCTAssertEqual(value, "fresh-value")
    }

    func testAttemptResolvesToNilWhenCoordinatorReportsTheSameSpDcAsExisting() async {
        Task {
            while HeadlessReAuthSpikeCoordinator.currentRequestID == nil {
                try? await Task.sleep(for: Duration.milliseconds(5))
            }
            if let id = HeadlessReAuthSpikeCoordinator.currentRequestID {
                HeadlessReAuthSpikeCoordinator.resolve(id: id, spDc: "unchanged")
            }
        }
        let value = await HeadlessReAuthSpike.attempt(existingSpDc: "unchanged")
        XCTAssertNil(value)
    }
}
