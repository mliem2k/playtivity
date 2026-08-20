import XCTest
@testable import Playtivity

final class ApiRetryServiceTests: XCTestCase {
    override func tearDown() {
        ApiRetryService.sleepOverride = nil
        super.tearDown()
    }

    private struct TestError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    func testSucceedsImmediatelyOnFirstTry() async throws {
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            return "ok"
        }, initialDelay: Duration.zero)
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls, 1)
    }

    func testRetriesAfterFailureAndSucceedsOnThirdAttempt() async throws {
        ApiRetryService.sleepOverride = { _ in }
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            if calls < 3 { throw TestError(message: "transient") }
            return "recovered"
        }, maxRetries: 3, initialDelay: Duration.zero)
        XCTAssertEqual(result, "recovered")
        XCTAssertEqual(calls, 3)
    }

    func testRethrowsAfterExhaustingMaxRetries() async throws {
        ApiRetryService.sleepOverride = { _ in }
        var calls = 0
        do {
            let _: String = try await ApiRetryService.retryApiCall({
                calls += 1
                throw TestError(message: "persistent")
            }, maxRetries: 2, initialDelay: Duration.zero)
            XCTFail("expected retryApiCall to throw")
        } catch let error as TestError {
            XCTAssertEqual(error.message, "persistent")
        }
        // 1 initial + 2 retries = 3 total
        XCTAssertEqual(calls, 3)
    }

    func testMaxRetriesZeroMeansExactlyOneAttemptWithNoRetry() async throws {
        var calls = 0
        do {
            let _: String = try await ApiRetryService.retryApiCall({
                calls += 1
                throw TestError(message: "fail")
            }, maxRetries: 0, initialDelay: Duration.zero)
            XCTFail("expected retryApiCall to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(calls, 1)
    }

    func testNegativeMaxRetriesThrowsInsteadOfTrapping() async throws {
        var calls = 0
        do {
            let _: String = try await ApiRetryService.retryApiCall({
                calls += 1
                return "unreachable"
            }, maxRetries: -1, initialDelay: Duration.zero)
            XCTFail("expected retryApiCall to throw")
        } catch {
            // expected: a typed throw, not a range-construction crash
        }
        XCTAssertEqual(calls, 0)
    }

    func testSucceedsOnLastAllowedRetry() async throws {
        ApiRetryService.sleepOverride = { _ in }
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            if calls <= 3 { throw TestError(message: "fail \(calls)") }
            return "final"
        }, maxRetries: 3, initialDelay: Duration.zero)
        XCTAssertEqual(result, "final")
        XCTAssertEqual(calls, 4) // 1 initial + 3 retries
    }

    func testDoesNotRetryOn401() async throws {
        var calls = 0
        do {
            let _: String = try await ApiRetryService.retryApiCall({
                calls += 1
                throw TestError(message: "HTTP 401 Unauthorized")
            }, initialDelay: Duration.zero)
            XCTFail("expected retryApiCall to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(calls, 1)
    }

    func testDoesNotRetryOn403() async throws {
        var calls = 0
        do {
            let _: String = try await ApiRetryService.retryApiCall({
                calls += 1
                throw TestError(message: "HTTP 403 Forbidden")
            }, initialDelay: Duration.zero)
            XCTFail("expected retryApiCall to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(calls, 1)
    }

    func testDoesNotRetryOnUnauthorizedMessage() async throws {
        var calls = 0
        do {
            let _: String = try await ApiRetryService.retryApiCall({
                calls += 1
                throw TestError(message: "request unauthorized")
            }, initialDelay: Duration.zero)
            XCTFail("expected retryApiCall to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(calls, 1)
    }

    func testDoesNotRetryOnAuthenticationErrorMessage() async throws {
        var calls = 0
        do {
            let _: String = try await ApiRetryService.retryApiCall({
                calls += 1
                throw TestError(message: "authentication error, token expired")
            }, initialDelay: Duration.zero)
            XCTFail("expected retryApiCall to throw")
        } catch {
            // expected
        }
        XCTAssertEqual(calls, 1)
    }

    func test429TriggersRetryWithLongerBackoff() async throws {
        var capturedDelays: [Duration] = []
        ApiRetryService.sleepOverride = { delay in capturedDelays.append(delay) }
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            if calls == 1 { throw TestError(message: "HTTP 429 rate limit exceeded") }
            return "after-rate-limit"
        }, maxRetries: 2, initialDelay: Duration.milliseconds(50))
        XCTAssertEqual(result, "after-rate-limit")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(capturedDelays, [Duration.seconds(5)])
    }

    func test429BackoffDoublesAcrossRepeatedAttempts() async throws {
        var capturedDelays: [Duration] = []
        ApiRetryService.sleepOverride = { delay in capturedDelays.append(delay) }
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            if calls <= 2 { throw TestError(message: "status 429") }
            return "ok"
        }, maxRetries: 2, initialDelay: Duration.milliseconds(50))
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls, 3)
        // Rate-limit backoff doubles from a 5 second base, independent of initialDelay: 5s, 10s.
        XCTAssertEqual(capturedDelays, [Duration.seconds(5), Duration.seconds(10)])
    }

    func testRateLimitStringInErrorMessageTriggersRateLimitBackoff() async throws {
        var capturedDelays: [Duration] = []
        ApiRetryService.sleepOverride = { delay in capturedDelays.append(delay) }
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            if calls == 1 { throw TestError(message: "rate limit exceeded") }
            return "ok"
        }, maxRetries: 1, initialDelay: Duration.milliseconds(50))
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(capturedDelays, [Duration.seconds(5)])
    }

    func testNonRateLimitErrorUsesInitialDelayBasedExponentialBackoff() async throws {
        var capturedDelays: [Duration] = []
        ApiRetryService.sleepOverride = { delay in capturedDelays.append(delay) }
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            if calls <= 2 { throw TestError(message: "timeout") }
            return "ok"
        }, maxRetries: 2, initialDelay: Duration.milliseconds(100))
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(capturedDelays, [Duration.milliseconds(100), Duration.milliseconds(200)])
    }

    func testOmittingInitialDelayUsesTheDefault50MillisecondBackoff() async throws {
        // Exercises ApiRetryService.retryApiCall's default `initialDelay` parameter value
        // directly (every other test in this file passes initialDelay explicitly), confirming
        // the default is both reachable and produces the documented 50ms base backoff.
        var capturedDelays: [Duration] = []
        ApiRetryService.sleepOverride = { delay in capturedDelays.append(delay) }
        var calls = 0
        let result: String = try await ApiRetryService.retryApiCall({
            calls += 1
            if calls == 1 { throw TestError(message: "timeout") }
            return "ok"
        }, maxRetries: 1)
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(capturedDelays, [Duration.milliseconds(50)])
    }

    func testOperationNameAppearsInLogButDoesNotAffectRetryBehavior() async throws {
        var calls = 0
        let result: Int = try await ApiRetryService.retryApiCall({
            calls += 1
            return 42
        }, initialDelay: Duration.zero, operation: "Custom Operation Name")
        XCTAssertEqual(result, 42)
        XCTAssertEqual(calls, 1)
    }

    func testWorksWithGenericTypeParameters() async throws {
        let intResult: Int = try await ApiRetryService.retryApiCall({ 7 }, initialDelay: Duration.zero)
        XCTAssertEqual(intResult, 7)

        let mapResult: [String: String] = try await ApiRetryService.retryApiCall({
            ["key": "value"]
        }, initialDelay: Duration.zero)
        XCTAssertEqual(mapResult, ["key": "value"])
    }
}
