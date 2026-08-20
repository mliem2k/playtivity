import Foundation

/// Pure-Swift port of lib/services/spotify_token_service.dart. Fetches Spotify Bearer tokens from
/// an sp_dc cookie without a WebView, used for silent token refresh on subsequent app sessions.
enum SpotifyTokenService {
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

    // Injectable seams for tests: `URLProtocol` does not transpile on Skip Lite (confirmed in
    // Task 1 against the vendored skip-foundation source: no request-interception API exists,
    // and URLSession is `final`), so a closure per real network boundary is the standard
    // technique here, mirroring SpotifySecretsService.remoteFetchOverride. All default to nil,
    // meaning "make the real request via URLSession.shared". `nonisolated(unsafe)` because Swift
    // 6 rejects a plain mutable static var as unsynchronized global state; these are read/written
    // only from tests, never from production code, matching Task 1's ApiRetryService.sleepOverride
    // precedent (no lock needed there).
    nonisolated(unsafe) static var serverTimeFetchOverride: (() async throws -> String?)?
    nonisolated(unsafe) static var bearerTokenFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?
    nonisolated(unsafe) static var accountProfileFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?
    nonisolated(unsafe) static var spclientProfileFetchOverride: ((URLRequest) async throws -> (statusCode: Int, body: String))?

    /// Fetches Spotify's server time via the HTTP Date header for TOTP sync. Falls back to the
    /// local clock on any failure (missing header, request error, unparseable date).
    static func fetchServerTime() async -> Int64 {
        do {
            if let dateStr = try await fetchServerTimeDateHeader(), let parsed = parseHttpDate(dateStr) {
                return parsed
            }
        } catch {
            logger.error("Failed to fetch Spotify server time: \(error)")
        }
        return Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func fetchServerTimeDateHeader() async throws -> String? {
        if let override = serverTimeFetchOverride {
            return try await override()
        }
        let request = URLRequest(url: URL(string: "https://open.spotify.com/")!, timeoutInterval: 10)
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date")
    }

    // RFC 1123 HTTP-date, e.g. "Wed, 21 Oct 2015 07:28:00 GMT".
    private static func parseHttpDate(_ dateStr: String) -> Int64? {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        guard let date = formatter.date(from: dateStr) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    /// Builds the /api/token URL with the given TOTP query parameters.
    static func buildTokenUrl(_ totpParams: [String: String]) -> URL {
        var components = URLComponents(string: "https://open.spotify.com/api/token")!
        components.queryItems = [
            URLQueryItem(name: "reason", value: "transport"),
            URLQueryItem(name: "productType", value: "web-player"),
            URLQueryItem(name: "totp", value: totpParams["totp"] ?? ""),
            URLQueryItem(name: "totpServer", value: totpParams["totpServer"] ?? ""),
            URLQueryItem(name: "totpVer", value: totpParams["totpVer"] ?? ""),
        ]
        return components.url!
    }

    /// Parses a /api/token HTTP response and returns the accessToken string, or nil if the
    /// status is not 200-OK, the body is malformed, or Spotify returned only an anonymous token
    /// (sp_dc expired/invalid).
    static func parseTokenResponse(statusCode: Int, body: String) -> String? {
        guard statusCode == 200 else { return nil }
        guard !body.isEmpty else { return nil }
        guard let data = body.data(using: String.Encoding.utf8) else { return nil }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let isAnonymous = json["isAnonymous"] as? Bool, isAnonymous {
            return nil
        }
        guard let token = json["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// Fetches a Bearer access token using a stored sp_dc cookie value. Returns nil if the
    /// request fails or sp_dc has expired.
    static func fetchBearerToken(spDc: String) async -> String? {
        logger.info("Fetching Bearer token from sp_dc...")
        let serverTime = await fetchServerTime()
        let totpParams = TOTPGenerator.generateParams(timestampMillis: serverTime)
        let tokenUrl = buildTokenUrl(totpParams)

        var request = URLRequest(url: tokenUrl, timeoutInterval: 10)
        request.setValue("sp_dc=\(spDc)", forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://open.spotify.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")

        do {
            let (statusCode, body) = try await performBearerTokenRequest(request)
            logger.info("Token endpoint status: \(statusCode)")
            if let token = parseTokenResponse(statusCode: statusCode, body: body) {
                logger.info("Silent token refresh succeeded")
                return token
            }
            logger.warning("Silent token refresh failed: HTTP \(statusCode)")
        } catch {
            logger.error("Silent token refresh error: \(error)")
        }
        return nil
    }

    private static func performBearerTokenRequest(_ request: URLRequest) async throws -> (statusCode: Int, body: String) {
        if let override = bearerTokenFetchOverride {
            return try await override(request)
        }
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: responseData, encoding: String.Encoding.utf8) ?? ""
        return (statusCode, body)
    }

    /// Decodes the JWT payload and returns the Spotify user ID from the `sub` claim. Returns nil
    /// if the token is malformed or the claim is missing.
    static func extractUserIdFromJwt(_ token: String) -> String? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }

        // Base64url -> base64: replace URL-safe chars and pad to a multiple of 4.
        var payload = parts[1]
        payload = payload.replacingOccurrences(of: "-", with: "+")
        payload = payload.replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }

        guard let data = Data(base64Encoded: payload) else { return nil }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let sub = json["sub"] as? String, !sub.isEmpty else { return nil }

        // sub is either "spotify:user:<id>" or just the id.
        let prefix = "spotify:user:"
        if sub.hasPrefix(prefix) {
            return String(sub.dropFirst(prefix.count))
        }
        return sub
    }

    /// Extracts the sp_dc value from a Cookie header string.
    static func extractSpDc(_ cookieHeader: String) -> String? {
        for part in cookieHeader.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: CharacterSet.whitespaces)
            if trimmed.hasPrefix("sp_dc=") {
                return String(trimmed.dropFirst("sp_dc=".count))
            }
        }
        return nil
    }

    /// Fetches email and country from Spotify's account-settings endpoint. Unlike /v1/me, this
    /// endpoint is not rate-limited and works with just the sp_dc cookie, no bearer token or
    /// OAuth scopes needed.
    static func fetchAccountProfile(spDc: String) async -> (email: String, country: String)? {
        var request = URLRequest(
            url: URL(string: "https://www.spotify.com/api/account-settings/v1/profile")!,
            timeoutInterval: 10
        )
        request.setValue("sp_dc=\(spDc)", forHTTPHeaderField: "Cookie")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://www.spotify.com/account/overview/", forHTTPHeaderField: "Referer")

        do {
            let (statusCode, body) = try await performAccountProfileRequest(request)
            guard statusCode == 200 else { return nil }
            guard let data = body.data(using: String.Encoding.utf8) else { return nil }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            guard let profile = json["profile"] as? [String: Any] else { return nil }
            let email = profile["email"] as? String ?? ""
            let country = profile["country"] as? String ?? ""
            return (email: email, country: country)
        } catch {
            logger.error("fetchAccountProfile failed: \(error)")
            return nil
        }
    }

    private static func performAccountProfileRequest(_ request: URLRequest) async throws -> (statusCode: Int, body: String) {
        if let override = accountProfileFetchOverride {
            return try await override(request)
        }
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: responseData, encoding: String.Encoding.utf8) ?? ""
        return (statusCode, body)
    }

    /// Fetches display name, avatar, and follower count via Spotify's user-profile-view endpoint,
    /// using the user id decoded from the bearer token itself (`extractUserIdFromJwt`). Mirrors
    /// `LoginScreen.identityJS`'s primary path exactly (same endpoint, same headers): that JS
    /// prefetch is the fast path used during a fresh WebView login, and this function is the
    /// production default `AuthStore` falls back to whenever the prefetch failed, timed out, or
    /// wasn't available at all (e.g. a startup silent refresh, which has no WebView to inject
    /// into). Returns nil if the token isn't decodable, the request fails, or the response isn't
    /// 200/parseable JSON. Email and country are not available from this endpoint, so they're
    /// left empty here; `AuthStore.enrichedProfile`'s separate account-settings fetch fills those
    /// in afterwards whenever either is still missing.
    static func fetchProfileViaSpclient(bearerToken: String) async -> User? {
        guard let userId = extractUserIdFromJwt(bearerToken) else {
            logger.warning("fetchProfileViaSpclient: could not decode user id from bearer token")
            return nil
        }

        var request = URLRequest(
            url: URL(string: "https://guc-spclient.spotify.com/user-profile-view/v3/profile/\(userId)")!,
            timeoutInterval: 10
        )
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")

        do {
            let (statusCode, body) = try await performSpclientProfileRequest(request)
            guard statusCode == 200 else {
                logger.warning("fetchProfileViaSpclient: HTTP \(statusCode)")
                return nil
            }
            guard let data = body.data(using: String.Encoding.utf8) else { return nil }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            let displayName = json["name"] as? String ?? userId
            let imageUrl = json["image_url"] as? String
            let followers = spclientIntValue(from: json["followers_count"]) ?? 0
            return User(id: userId, displayName: displayName, email: "", imageUrl: imageUrl, followers: followers, country: "")
        } catch {
            logger.error("fetchProfileViaSpclient failed: \(error)")
            return nil
        }
    }

    private static func performSpclientProfileRequest(_ request: URLRequest) async throws -> (statusCode: Int, body: String) {
        if let override = spclientProfileFetchOverride {
            return try await override(request)
        }
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: responseData, encoding: String.Encoding.utf8) ?? ""
        return (statusCode, body)
    }

    // JSON numeric values can arrive boxed as either a 32-bit or 64-bit integer depending on
    // magnitude and platform (org.json's JSONTokener on Android picks Integer vs Long per value),
    // so both are tried explicitly, same fix as SpotifySecretsService.intValue.
    private static func spclientIntValue(from element: Any?) -> Int? {
        if let i = element as? Int { return i }
        if let i32 = element as? Int32 { return Int(i32) }
        return nil
    }

    /// Builds a minimal headers map from an sp_dc value for downstream API calls.
    static func headersFromSpDc(_ spDc: String) -> [String: String] {
        [
            "Cookie": "sp_dc=\(spDc)",
            "User-Agent": userAgent,
            "Accept": "application/json",
            "App-Platform": "WebPlayer",
            "Referer": "https://open.spotify.com/",
            "Origin": "https://open.spotify.com",
        ]
    }
}
