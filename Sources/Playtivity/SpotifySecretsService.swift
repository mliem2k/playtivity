import Foundation

/// Pure-Swift port of lib/services/spotify_secrets_service.dart. Refreshes TOTPGenerator's
/// secret-cipher dictionary from a community-maintained mirror of Spotify's current in-use
/// secrets, since Spotify periodically rotates the values baked into the client (this app's own
/// commit history shows Spotify has forced this before: v14 to v59-v61). Cache-first (6 hour
/// TTL via UserDefaults, which SkipFoundation backs with SharedPreferences on Android), silent
/// on any failure: TOTPGenerator simply keeps using whatever it already has, the hardcoded
/// fallback, or a previously applied set of secrets.
enum SpotifySecretsService {
    private static let remoteUrl = URL(string: "https://github.com/xyloflake/spot-secrets-go/blob/main/secrets/secretDict.json?raw=true")!

    // Not `private`, so `@testable import` can seed/inspect cache state directly, mirroring the
    // Dart test suite's own approach of poking SharedPreferences via `setMockInitialValues`.
    static let cacheKey = "spotify_totp_secrets"
    static let cacheTimestampKey = "spotify_totp_secrets_ts"
    private static let cacheTtlMillis = 6 * 60 * 60 * 1000

    /// Injectable seam for tests: the `UserDefaults` suite used for the cache. Defaults to
    /// `.standard`, matching production. `nonisolated(unsafe)` for the same reason as
    /// TOTPGenerator's runtime secrets store: Swift 6 rejects a plain mutable static var as
    /// unsynchronized global state.
    nonisolated(unsafe) static var userDefaults: UserDefaults = .standard

    /// Injectable seam for tests: replaces the real remote HTTP GET with a canned response.
    /// SkipFoundation implements neither Foundation's real `URLProtocol` request interception
    /// (the only symbol by that name there is a private, unrelated typealias backing internal
    /// "asset:/" URL loading) nor a mockable `URLSession` (it is declared `final`), so this
    /// closure is the only cross-platform seam available for stubbing the network in tests.
    /// Defaults to nil, meaning "make the real request via URLSession.shared".
    nonisolated(unsafe) static var remoteFetchOverride: (() async throws -> (statusCode: Int, body: Data))?

    /// Loads secrets (cache-first, then remote), applies them to TOTPGenerator.
    /// Silent on failure: TOTPGenerator falls back to whatever it already has.
    static func loadAndApply() async -> [String: [Int]]? {
        guard let secrets = await loadSecrets() else { return nil }

        var cipherBytes = [String: [UInt8]]()
        for (version, ints) in secrets {
            cipherBytes[version] = ints.map { UInt8($0 & 0xff) }
        }
        TOTPGenerator.applySecrets(cipherBytes)
        logger.info("TOTP secrets loaded (version: \(TOTPGenerator.activeVersion))")
        return secrets
    }

    /// Validates that `raw` is a non-empty dict of digit-string keys to non-empty int-list
    /// values. Returns the typed map on success, nil on any validation failure.
    static func validateSecretsFormat(_ raw: [String: Any]) -> [String: [Int]]? {
        if raw.isEmpty { return nil }
        var result = [String: [Int]]()
        for (key, value) in raw {
            guard isDigitString(key) else { return nil }
            guard let list = value as? [Any], !list.isEmpty else { return nil }
            var ints = [Int]()
            ints.reserveCapacity(list.count)
            for element in list {
                guard let n = intValue(from: element) else { return nil }
                ints.append(n)
            }
            result[key] = ints
        }
        return result
    }

    // JSON numeric values can arrive boxed as either a 32-bit or 64-bit integer depending on
    // magnitude and platform (org.json's JSONTokener on Android picks Integer vs Long per
    // value, independent of how the JSON was produced), so both are tried explicitly rather
    // than relying on a single cast.
    private static func intValue(from element: Any) -> Int? {
        if let i = element as? Int { return i }
        if let i32 = element as? Int32 { return Int(i32) }
        return nil
    }

    // NOTE: widens to UInt32 before comparing, rather than comparing a bare UInt8 against Int
    // literals directly. This mirrors TOTPGenerator.hexDigitValue's established workaround: Skip
    // Lite's transpiler mishandles a UInt8 compared against a plain Int literal (produces a
    // Kotlin UByte-vs-UInt argument type mismatch at compile time).
    private static func isDigitString(_ s: String) -> Bool {
        if s.isEmpty { return false }
        for c in s {
            guard let ascii = c.asciiValue else { return false }
            let v = UInt32(ascii)
            if v < UInt32(48) || v > UInt32(57) { return false }
        }
        return true
    }

    private static func loadSecrets() async -> [String: [Int]]? {
        if let cached = loadFromCache() {
            return cached
        }

        do {
            let (statusCode, body) = try await fetchRemote()
            guard statusCode == 200 else {
                logger.warning("TOTP secrets fetch failed: HTTP status \(statusCode)")
                return nil
            }

            guard let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return nil
            }

            guard let validated = validateSecretsFormat(decoded) else {
                logger.warning("TOTP secrets failed format validation")
                return nil
            }

            saveToCache(validated)
            return validated
        } catch {
            logger.warning("TOTP secrets fetch error: \(error)")
            return nil
        }
    }

    private static func fetchRemote() async throws -> (statusCode: Int, body: Data) {
        if let override = remoteFetchOverride {
            return try await override()
        }
        var request = URLRequest(url: remoteUrl, timeoutInterval: 5)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (responseBody, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (statusCode, responseBody)
    }

    private static func loadFromCache() -> [String: [Int]]? {
        guard let ts = userDefaults.object(forKey: cacheTimestampKey) as? Int else { return nil }

        let nowMillis = Int(Date().timeIntervalSince1970 * 1000)
        let age = nowMillis - ts
        if age > cacheTtlMillis { return nil }

        guard let raw = userDefaults.string(forKey: cacheKey) else { return nil }
        guard let data = raw.data(using: String.Encoding.utf8) else { return nil }
        guard let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return validateSecretsFormat(decoded)
    }

    private static func saveToCache(_ secrets: [String: [Int]]) {
        guard let data = try? JSONSerialization.data(withJSONObject: secrets),
              let json = String(data: data, encoding: String.Encoding.utf8) else { return }
        userDefaults.set(json, forKey: cacheKey)
        userDefaults.set(Int(Date().timeIntervalSince1970 * 1000), forKey: cacheTimestampKey)
    }
}
