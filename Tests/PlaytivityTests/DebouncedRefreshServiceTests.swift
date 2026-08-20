import Foundation
import XCTest
@testable import Playtivity

/// Thread-safe counter/flag for asserting on state mutated from inside a `@Sendable` callback
/// invoked on a background `Task` (`DebouncedRefreshService.debounce`/`throttle` require
/// `@Sendable` callbacks, so a plain captured `var` doesn't compile under Swift 6 strict
/// concurrency). `NSLock`-backed, the same proven-transpilable synchronization idiom already used
/// throughout this codebase (`TOTPGenerator`, `HeadlessReAuthSpikeCoordinator`).
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}

final class DebouncedRefreshServiceTests: XCTestCase {
    override func tearDown() {
        DebouncedRefreshService.cancelAll()
        super.tearDown()
    }

    // Real, short wait margin comfortably longer than any delay/interval used below, so a
    // pending debounce/throttle Task has definitely either fired or been cancelled by the time
    // assertions run. `debounce`/`throttle` return Void (matching the Dart original's
    // fire-and-forget signature), so there is no Task handle to await directly.
    private func waitPastDelay() async {
        try? await Task.sleep(for: Duration.milliseconds(150))
    }

    func testDebounceExecutesCallbackAfterDelay() async {
        let calls = Counter()
        DebouncedRefreshService.debounce("single-call", delay: Duration.milliseconds(20)) {
            calls.increment()
        }
        await waitPastDelay()
        XCTAssertEqual(calls.value, 1)
    }

    func testDebounceCollapsesRapidCallsToOne() async {
        let calls = Counter()
        for _ in 0..<3 {
            DebouncedRefreshService.debounce("collapse-key", delay: Duration.milliseconds(30)) {
                calls.increment()
            }
        }
        await waitPastDelay()
        XCTAssertEqual(calls.value, 1)
    }

    func testCancelStopsAPendingDebounceCall() async {
        let calls = Counter()
        DebouncedRefreshService.debounce("cancel-key", delay: Duration.milliseconds(30)) {
            calls.increment()
        }
        DebouncedRefreshService.cancel("cancel-key")
        await waitPastDelay()
        XCTAssertEqual(calls.value, 0)
    }

    func testDebounceExecuteImmediatelyFiresSynchronouslyOnFirstCall() {
        let calls = Counter()
        DebouncedRefreshService.debounce("immediate-key", delay: Duration.milliseconds(50), executeImmediately: true) {
            calls.increment()
        }
        XCTAssertEqual(calls.value, 1)
    }

    func testDebounceExecuteImmediatelyDoesNotFireAgainWithinDelayWindow() async {
        let calls = Counter()
        DebouncedRefreshService.debounce("immediate-key-2", delay: Duration.milliseconds(30), executeImmediately: true) {
            calls.increment()
        }
        XCTAssertEqual(calls.value, 1) // first call fires synchronously

        DebouncedRefreshService.debounce("immediate-key-2", delay: Duration.milliseconds(30), executeImmediately: true) {
            calls.increment()
        }
        // second call is within the delay window, so it must debounce rather than fire immediately
        XCTAssertEqual(calls.value, 1)
        await waitPastDelay()
        XCTAssertEqual(calls.value, 2)
    }

    func testThrottleExecutesFirstCallImmediately() {
        let calls = Counter()
        DebouncedRefreshService.throttle("throttle-first", interval: Duration.milliseconds(50)) {
            calls.increment()
        }
        XCTAssertEqual(calls.value, 1)
    }

    func testThrottleWithinIntervalSchedulesExactlyOneDelayedCall() async {
        let calls = Counter()
        DebouncedRefreshService.throttle("throttle-collapse", interval: Duration.milliseconds(40)) {
            calls.increment()
        }
        XCTAssertEqual(calls.value, 1) // first call executes immediately

        for _ in 0..<3 {
            DebouncedRefreshService.throttle("throttle-collapse", interval: Duration.milliseconds(40)) {
                calls.increment()
            }
        }
        await waitPastDelay()
        // exactly one more call, not three: repeated calls within the same interval don't stack timers
        XCTAssertEqual(calls.value, 2)
    }

    func testCancelAllStopsEveryPendingOperation() async {
        let callsA = Counter()
        let callsB = Counter()
        DebouncedRefreshService.debounce("cancel-all-a", delay: Duration.milliseconds(30)) {
            callsA.increment()
        }
        DebouncedRefreshService.debounce("cancel-all-b", delay: Duration.milliseconds(30)) {
            callsB.increment()
        }
        DebouncedRefreshService.cancelAll()
        await waitPastDelay()
        XCTAssertEqual(callsA.value, 0)
        XCTAssertEqual(callsB.value, 0)
    }

    func testDebounceKeysActivitiesRefreshValue() {
        XCTAssertEqual(DebounceKeys.activitiesRefresh, "activities_refresh")
    }
}
