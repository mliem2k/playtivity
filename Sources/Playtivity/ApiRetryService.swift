/// Pure-Swift port of lib/services/api_retry_service.dart. Retries a fallible async call with
/// exponential backoff, never retrying an authentication failure (401/403/"unauthorized"/
/// "authentication error", since a stale token fails identically on every retry) and using a
/// longer, rate-limit-specific backoff schedule (5s, 10s, 20s doubling) for 429 responses.
enum ApiRetryService {
    /// Injectable seam for tests: replaces the real delay between retries. Defaults to a real
    /// `Task.sleep`, so production behavior is unchanged; tests substitute a no-op (or a
    /// delay-recording closure) to avoid waiting out multi-second rate-limit backoffs for real.
    /// `nonisolated(unsafe)` for the same reason as TOTPGenerator's runtime secrets store: Swift
    /// 6 rejects a plain mutable static var as unsynchronized global state.
    nonisolated(unsafe) static var sleepOverride: ((Duration) async throws -> Void)?

    static func retryApiCall<T>(
        _ apiCall: () async throws -> T,
        maxRetries: Int = 3,
        initialDelay: Duration = Duration.milliseconds(50),
        operation: String = "API call"
    ) async throws -> T {
        // A negative maxRetries has no valid attempt range (Dart's `for (attempt=0;
        // attempt<=maxRetries; ...)` simply never runs its body in that case, landing on the
        // same "should not reach this point" outcome below); guard explicitly rather than
        // letting the range construction below trap.
        guard maxRetries >= 0 else {
            throw UnreachableRetryError()
        }
        for attempt in 0...maxRetries {
            do {
                let result = try await apiCall()
                if attempt > 0 {
                    logger.info("\(operation) succeeded after \(attempt + 1) attempts")
                }
                return result
            } catch {
                let errorStr = "\(error)".lowercased()

                // Never retry authentication errors: the token is expired and retrying the same
                // request with the same token will always fail the same way.
                if isAuthError(errorStr) {
                    logger.error("\(operation) failed with auth error, not retrying: \(error)")
                    throw error
                }

                if attempt == maxRetries {
                    logger.error("\(operation) failed after \(maxRetries + 1) attempts: \(error)")
                    throw error
                }

                let multiplier = 1 << attempt
                let delay: Duration
                if isRateLimitError(errorStr) {
                    // Longer backoff for rate limit errors: 5s, 10s, 20s.
                    delay = Duration.seconds(5) * multiplier
                    logger.warning("\(operation) attempt \(attempt + 1) failed with rate limit (429), backing off for \(delay)")
                } else {
                    delay = initialDelay * multiplier
                    logger.warning("\(operation) attempt \(attempt + 1) failed, retrying in \(delay): \(error)")
                }

                try await sleep(delay)
            }
        }

        throw UnreachableRetryError()
    }

    private static func sleep(_ duration: Duration) async throws {
        if let override = sleepOverride {
            try await override(duration)
        } else {
            try await Task.sleep(for: duration)
        }
    }

    private static func isAuthError(_ lowercasedMessage: String) -> Bool {
        lowercasedMessage.contains("401") ||
            lowercasedMessage.contains("403") ||
            lowercasedMessage.contains("authentication error") ||
            lowercasedMessage.contains("unauthorized")
    }

    private static func isRateLimitError(_ lowercasedMessage: String) -> Bool {
        lowercasedMessage.contains("429") || lowercasedMessage.contains("rate limit")
    }
}

private struct UnreachableRetryError: Error, CustomStringConvertible {
    var description: String { "Retry logic should not reach this point" }
}
