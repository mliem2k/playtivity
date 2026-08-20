import Foundation

/// String keys for `DebouncedRefreshService`, ported from the Dart original's `DebounceKeys`.
/// Only the one key this phase's activities feed refresh loop needs is ported; the original's
/// other keys (`profileRefresh`, `manualRefresh`, `searchQuery`, `apiCall`, `cacheRefresh`,
/// `activityEnhancement`, `friendsActivities`, `currentlyPlaying`) belong to screens/services this
/// phase doesn't build and are deliberately not ported.
enum DebounceKeys {
    static let activitiesRefresh = "activities_refresh"
}

/// Swift `Task`-based port of `lib/services/debounced_refresh_service.dart`'s static
/// `debounce`/`throttle`/`cancel`/`cancelAll` API (`dart:async` `Timer`-based in the original),
/// matching the `Task`+`Task.sleep` timer-like pattern this codebase already established in
/// `LoginScreen`/`ApiRetryService`, since Skip's Kotlin transpile target has no `Timer` equivalent
/// exposed the same way. The Dart file's `DebouncedRefreshMixin` (widget-lifecycle cleanup on
/// `dispose()`) is deliberately not ported: SwiftUI's `.task`/`.onDisappear` modifiers already
/// provide structured cancellation, so no equivalent plumbing is needed.
///
/// `nonisolated(unsafe)` mutable statics guarded by a real `NSLock`, the same proven-transpilable
/// idiom already used by `HeadlessReAuthSpikeCoordinator`/`TOTPGenerator`'s shared mutable state.
enum DebouncedRefreshService {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var tasks: [String: Task<Void, Never>] = [:]
    nonisolated(unsafe) private static var lastExecution: [String: Date] = [:]

    /// Debounces a callback: if called again for the same `key` before `delay` elapses, the
    /// pending call is cancelled and replaced, so only the last call in a rapid burst executes.
    /// With `executeImmediately: true`, a call is run synchronously right away if enough time has
    /// passed since the last execution for `key`, matching the Dart original's `executeImmediately`
    /// fast path. Returns `Void`, matching the Dart original's signature: the pending call is a
    /// fire-and-forget background operation, not something callers are expected to await.
    static func debounce(
        _ key: String,
        delay: Duration,
        executeImmediately: Bool = false,
        callback: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            tasks[key]?.cancel()
            tasks[key] = nil
        }

        if executeImmediately {
            let now = Date()
            let shouldFireNow: Bool = lock.withLock {
                let last = lastExecution[key]
                guard last == nil || now.timeIntervalSince(last!) >= delay.timeInterval else {
                    return false
                }
                lastExecution[key] = now
                return true
            }
            if shouldFireNow {
                callback()
                return
            }
        }

        let task = Task<Void, Never> {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            lock.withLock { lastExecution[key] = Date() }
            callback()
            lock.withLock { tasks[key] = nil }
        }
        lock.withLock { tasks[key] = task }
    }

    /// Throttles a callback to execute at most once per `interval`: the first call (or a call
    /// after `interval` has already elapsed) executes immediately; a call within the window
    /// schedules exactly one delayed execution at the end of the window, and further calls within
    /// the same window don't stack additional timers. Returns `Void`, matching the Dart original's
    /// signature.
    static func throttle(
        _ key: String,
        interval: Duration,
        callback: @escaping @Sendable () -> Void
    ) {
        let now = Date()
        let decision: ThrottleDecision = lock.withLock {
            let last = lastExecution[key]
            if last == nil || now.timeIntervalSince(last!) >= interval.timeInterval {
                lastExecution[key] = now
                return ThrottleDecision.executeNow
            }
            if tasks[key] != nil {
                return ThrottleDecision.alreadyScheduled
            }
            return ThrottleDecision.scheduleAfter(remainingDuration(interval: interval, since: last!, now: now))
        }

        switch decision {
        case ThrottleDecision.executeNow:
            callback()
        case ThrottleDecision.alreadyScheduled:
            break
        case ThrottleDecision.scheduleAfter(let remaining):
            let task = Task<Void, Never> {
                try? await Task.sleep(for: remaining)
                guard !Task.isCancelled else { return }
                lock.withLock { lastExecution[key] = Date() }
                callback()
                lock.withLock { tasks[key] = nil }
            }
            lock.withLock { tasks[key] = task }
        }
    }

    /// Cancels a specific pending debounced/throttled operation for `key`, if any.
    static func cancel(_ key: String) {
        lock.withLock {
            tasks[key]?.cancel()
            tasks[key] = nil
            lastExecution[key] = nil
        }
    }

    /// Cancels every pending operation across all keys.
    static func cancelAll() {
        lock.withLock {
            for task in tasks.values { task.cancel() }
            tasks.removeAll()
            lastExecution.removeAll()
        }
    }

    private enum ThrottleDecision {
        case executeNow
        case alreadyScheduled
        case scheduleAfter(Duration)
    }

    // Integer-millisecond arithmetic rather than reconstructing a Duration from a Double via
    // Duration.seconds(_: Double): only the Int64-based Duration.milliseconds(_:) factory is a
    // proven-transpilable form in this codebase (see LoginScreenLogic/ApiRetryService), so the
    // remaining wait is computed in whole milliseconds instead.
    private static func remainingDuration(interval: Duration, since last: Date, now: Date) -> Duration {
        let intervalMs = Int64((interval.timeInterval * 1000).rounded())
        let elapsedMs = Int64((now.timeIntervalSince(last) * 1000).rounded())
        let remainingMs = max(0, intervalMs - elapsedMs)
        return Duration.milliseconds(remainingMs)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
