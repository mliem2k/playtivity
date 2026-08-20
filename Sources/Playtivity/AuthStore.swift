import Foundation
import Observation

enum AuthState: Equatable {
    case uninitialized
    case loading
    case authenticated
    case unauthenticated
}

private struct AuthStoreError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Pure-Swift port of lib/providers/auth_provider.dart, minus the two pieces that need a live
/// WebView (the login screen itself, and the headless re-auth spike): those are injected as
/// closures for later tasks to wire in, matching this codebase's established seam pattern for
/// anything HTTP or WebView adjacent (see `SpotifyTokenService`/`SpotifySecretsService`).
///
/// Deliberate deviation from the Dart original: the Dart constructor self-starts
/// `_initializeAuth()` via `Future.microtask`, relying on Dart's single-threaded event loop
/// guaranteeing the microtask cannot run until the constructor's caller yields control, so tests
/// can set override closures on the instance immediately after construction, before the
/// microtask fires. Swift's `Task { }` has no such ordering guarantee against a plain synchronous
/// caller, the child task can begin executing on another thread while the caller continues, which
/// would race a test's post-construction `store.tokenFetchOverride = ...` assignment against
/// `initialize()` already reading it. So construction here does no async work; callers (tests, and
/// eventually the app's root view) call `initialize()` explicitly once overrides are set.
@Observable
final class AuthStore {
    private static let bearerTokenKey = "spotify_bearer_token"
    private static let headersKey = "spotify_headers"
    private static let userKey = "spotify_user"
    private static let spDcKey = "spotify_sp_dc"

    private let userDefaults: UserDefaults

    private(set) var authState: AuthState = .uninitialized
    private(set) var bearerToken: String?
    private(set) var headers: [String: String]?
    private var _currentUser: User?
    private(set) var authEvents: [String] = []
    private(set) var lastAuthError: String?

    /// The restored/authenticated user, if any. Backed by `_currentUser` so internal code can
    /// read/write it without tripping the DEBUG guard below, which is only meant to catch an
    /// external caller reading this before `initialize()` has ever run.
    var currentUser: User? {
        assertStoreIsInitialized()
        return _currentUser
    }

    var isAuthenticated: Bool {
        assertStoreIsInitialized()
        return authState == .authenticated
    }

    var isLoading: Bool { authState == .loading }

    // Deliberately NOT guarded by assertStoreIsInitialized(): authState's own `.uninitialized`
    // case already discloses "initialize() has not run yet" unambiguously on its own, and
    // isInitialized (== this check) is the sanctioned way calling code decides whether it needs
    // to call initialize() in the first place. Guarding it would make that legitimate pre-check
    // trip the assert it exists to avoid needing.
    var isInitialized: Bool { authState != .uninitialized }

    // DEBUG-only guard: currentUser and isAuthenticated both read as an "empty"/false value both
    // when the store has never been initialized AND when it genuinely has no user or is logged
    // out, so a forgotten `initialize()` call silently looks identical to a normal logged-out
    // state, with no signal anything is wrong. Trap loudly in development instead. authState
    // itself does not need this: `.uninitialized` already is the loud, unambiguous signal, and
    // asserting on every read of it would break the legitimate "check isInitialized, then decide
    // whether to call initialize()" pattern.
    private func assertStoreIsInitialized() {
        #if DEBUG
        if authState == .uninitialized {
            assertionFailure("""
                AuthStore.currentUser or .isAuthenticated was read before initialize() was ever \
                called. Without that call, authState stays .uninitialized forever and these read \
                exactly like a genuine logged-out user, with no signal why. Call \
                `await store.initialize()` before reading either.
                """)
        }
        #endif
    }

    private var spDc: String?
    private var isRecovering = false

    /// Injectable token fetcher, override in tests to avoid real network calls.
    var tokenFetchOverride: ((String) async -> String?)?

    /// Injectable user-profile fetcher, override in tests. No production default is wired here:
    /// the Dart original falls back to a `SpotifyBuddyService` that has not been ported in this
    /// phase (out of scope per the task brief), so in production the only profile source is the
    /// WebView-prefetched `x-prefetched-user` header handled directly in `loginComplete`.
    var userProfileFetchOverride: ((String) async -> User?)?

    /// Injectable sp_dc cookie-store reader for `tryRecoverFromExpiredToken`'s fast paths. Reading
    /// from the real WebView cookie store needs a live engine reference, which is Task 5's
    /// concern; defaults to nil, meaning "no cookie store access available yet", which correctly
    /// falls through past both fast paths to the headless path below.
    var readCookieStoreSpDc: (() async -> String?)?

    /// Injectable slow-path re-auth (loads a headless WebView so Spotify can issue a fresh sp_dc).
    /// This is Task 5's concern; defaults to nil, meaning "not available", which correctly makes
    /// recovery return false, the safe fallback the design doc specifies.
    var headlessReAuthOverride: (() async -> Bool)?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Event log

    private func addEvent(_ msg: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let ts = formatter.string(from: Date())
        authEvents.append("[\(ts)] \(msg)")
        if authEvents.count > 30 {
            authEvents.removeFirst()
        }
        logger.info("\(msg)")
    }

    // MARK: - Startup

    /// Port of `_initializeAuth` (ref_auth_provider.dart:68-161). Call once, after any test
    /// override closures have been set, before reading `authState`/`currentUser`.
    ///
    /// REQUIRED: without this call, `authState` remains `.uninitialized` forever and any stored
    /// credentials are never restored. `currentUser`/`isAuthenticated` will read exactly like a
    /// genuine logged-out user in that case (see `assertStoreIsInitialized`, which traps on that
    /// specific read in DEBUG builds so a forgotten call fails loudly during development instead
    /// of silently shipping a permanently-logged-out cold start).
    func initialize() async {
        authState = .loading

        addEvent("Starting auth initialization...")
        loadStoredData()

        let savedBearerToken = userDefaults.string(forKey: Self.bearerTokenKey)
        let savedHeadersJson = userDefaults.string(forKey: Self.headersKey)
        let savedUserJson = userDefaults.string(forKey: Self.userKey)

        spDc = userDefaults.string(forKey: Self.spDcKey)

        if let savedBearerToken, let savedHeadersJson {
            do {
                bearerToken = savedBearerToken
                headers = try decodeHeaders(savedHeadersJson)
                addEvent("Restored saved token + headers")

                if let savedUserJson {
                    var user = try decodeUser(savedUserJson)

                    // One-time migration: scrub placeholder values written by older app versions
                    // that hardcoded 'user@spotify.com' and 'US' as fallbacks.
                    if user.email == "user@spotify.com" {
                        user = User(
                            id: user.id,
                            displayName: user.displayName,
                            email: "",
                            imageUrl: user.imageUrl,
                            followers: user.followers,
                            country: user.country == "US" ? "" : user.country
                        )
                        if let encoded = try? encodeUser(user) {
                            userDefaults.set(encoded, forKey: Self.userKey)
                        }
                        addEvent("Scrubbed stale placeholder email/country from stored profile")
                    }

                    _currentUser = user
                    addEvent("Restored: \(user.displayName)")

                    // Proactively refresh the bearer token if sp_dc is available. Spotify tokens
                    // expire in about 1h; a cold start hours after the last session would use an
                    // expired token and cause all API calls to fail with 401. Refreshing here
                    // costs one network round trip on startup but prevents the cascading failures
                    // that would otherwise require the error-recovery flow to trigger and re-fetch
                    // everything.
                    if spDc != nil {
                        addEvent("Proactively refreshing token with sp_dc...")
                        let ok = await trySilentRefresh()
                        if !ok {
                            addEvent("Proactive refresh failed, proceeding with stored token")
                        }
                    }
                } else {
                    // Token present but no user, try silent refresh to obtain profile.
                    addEvent("Token without user, trying silent refresh...")
                    let didRefresh = await trySilentRefresh()
                    if !didRefresh {
                        clearStoredData()
                    }
                }
            } catch {
                addEvent("Restore error, trying silent refresh")
                lastAuthError = "Restore: \(error)"
                let didRefresh = await trySilentRefresh()
                if !didRefresh {
                    clearStoredData()
                }
            }
        } else if spDc != nil {
            addEvent("No stored token, silent refresh with sp_dc...")
            _ = await trySilentRefresh()
        } else {
            addEvent("No credentials found")
        }

        addEvent("Init complete, token:\(bearerToken != nil) user:\(_currentUser?.displayName ?? "none")")

        authState = (bearerToken != nil && _currentUser != nil) ? .authenticated : .unauthenticated
        addEvent("State -> \(authState)")
    }

    private func loadStoredData() {
        // One-time cleanup of stale keys from an even older app version.
        userDefaults.removeObject(forKey: "spotify_sp_dc_cookie")
        userDefaults.removeObject(forKey: "spotify_access_token")
        userDefaults.removeObject(forKey: "spotify_refresh_token")
        userDefaults.removeObject(forKey: "spotify_token_expiry")
    }

    // MARK: - Login

    /// Port of `loginComplete` (ref_auth_provider.dart:170-278).
    func loginComplete(bearerToken: String, headers: [String: String]) async throws {
        authState = .loading
        lastAuthError = nil

        addEvent("loginComplete: token len=\(bearerToken.count) headers=\(headers.keys.joined(separator: ","))")

        do {
            guard bearerToken.count >= 50 else {
                throw AuthStoreError(message: "Invalid bearer token (len=\(bearerToken.count))")
            }

            let cookieHeader = headers["Cookie"] ?? ""
            let extractedSpDc = SpotifyTokenService.extractSpDc(cookieHeader)
            if let extractedSpDc, !extractedSpDc.isEmpty {
                spDc = extractedSpDc
                addEvent("sp_dc extracted (len=\(extractedSpDc.count))")
            } else {
                addEvent("WARNING: sp_dc not found in headers")
            }

            self.bearerToken = bearerToken
            self.headers = headers

            var userProfile: User?

            // WebView pre-fetched profile via JS injection (avoids server-side rate limit).
            if let prefetchedJson = headers["x-prefetched-user"] {
                if let parsed = parsePrefetchedUser(prefetchedJson) {
                    userProfile = parsed
                    addEvent("Profile from WebView JS: \(parsed.displayName)")
                } else {
                    addEvent("Failed to parse prefetched user")
                }
            }

            // Server-side fallback, only used when WebView JS injection failed or was absent.
            if userProfile == nil {
                addEvent("Profile fetch (server-side fallback)...")
                if let fetched = await userProfileFetchOverride?(bearerToken) {
                    userProfile = fetched
                    addEvent("Profile loaded: \(fetched.displayName)")
                }
            }

            guard let profile = userProfile else {
                throw AuthStoreError(message: "Could not load profile. Please try logging in again.")
            }

            // Enrich with email/country if WebView JS didn't capture them.
            let finalProfile = await enrichedProfile(profile, spDc: spDc)

            _currentUser = finalProfile
            saveStoredData()

            authState = .authenticated
            addEvent("loginComplete SUCCESS: \(finalProfile.displayName)")
        } catch {
            lastAuthError = "loginComplete: \(error)"
            addEvent("loginComplete FAILED: \(error)")
            logger.error("Error in loginComplete: \(error)")

            self.bearerToken = nil
            self.headers = nil
            self._currentUser = nil
            clearStoredData()

            authState = .unauthenticated
            throw error
        }
    }

    // JSON numeric values from `JSONSerialization` can arrive boxed as either a 32-bit or 64-bit
    // integer depending on magnitude and platform (org.json's JSONTokener on Android picks
    // Integer vs Long per value), so both are tried explicitly, same fix as
    // `SpotifySecretsService.intValue`.
    private func intValue(from element: Any?) -> Int? {
        if let i = element as? Int { return i }
        if let i32 = element as? Int32 { return Int(i32) }
        return nil
    }

    // Returns `profile` enriched with email/country from account-settings when either is missing,
    // or `profile` unchanged when enrichment isn't needed or fails. Deliberately returns the final
    // value rather than mutating a captured local `var` from inside a nested optional-binding
    // closure: Skip's Kotlin transpilation cannot smart-cast a local `var` that is reassigned
    // inside such a closure ("Smart cast to 'User' is impossible, because ... is a local variable
    // that is mutated in a capturing closure"), which broke every later property access on it.
    // Stored properties (like `_currentUser` in trySilentRefresh below) don't have this problem:
    // Skip already force-unwraps every access to those instead of relying on a smart cast.
    private func enrichedProfile(_ profile: User, spDc: String?) async -> User {
        guard profile.email.isEmpty || profile.country.isEmpty, let spDc else { return profile }
        guard let acct = await SpotifyTokenService.fetchAccountProfile(spDc: spDc) else { return profile }
        let result = User(
            id: profile.id,
            displayName: profile.displayName,
            email: acct.email.isEmpty ? profile.email : acct.email,
            imageUrl: profile.imageUrl,
            followers: profile.followers,
            country: acct.country.isEmpty ? profile.country : acct.country
        )
        addEvent("Email/country enriched: \(result.email)")
        return result
    }

    private func parsePrefetchedUser(_ json: String) -> User? {
        guard let data = json.data(using: String.Encoding.utf8) else { return nil }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let id = obj["id"] as? String, !id.isEmpty else { return nil }
        let displayName = obj["displayName"] as? String ?? id
        let email = obj["email"] as? String ?? ""
        let imageUrl = obj["imageUrl"] as? String
        let followers = intValue(from: obj["followers"]) ?? 0
        let country = obj["country"] as? String ?? ""
        return User(id: id, displayName: displayName, email: email, imageUrl: imageUrl, followers: followers, country: country)
    }

    // MARK: - Persistence

    private func saveStoredData() {
        if let bearerToken {
            userDefaults.set(bearerToken, forKey: Self.bearerTokenKey)
        }
        if let headers, let encoded = try? encodeHeaders(headers) {
            userDefaults.set(encoded, forKey: Self.headersKey)
        }
        if let _currentUser, let encoded = try? encodeUser(_currentUser) {
            userDefaults.set(encoded, forKey: Self.userKey)
        }
        if let spDc {
            userDefaults.set(spDc, forKey: Self.spDcKey)
        }
        addEvent("Auth data saved")
    }

    private func clearStoredData() {
        userDefaults.removeObject(forKey: Self.bearerTokenKey)
        userDefaults.removeObject(forKey: Self.headersKey)
        userDefaults.removeObject(forKey: Self.userKey)
        // sp_dc intentionally NOT removed, survives token expiry for silent refresh.
        bearerToken = nil
        headers = nil
        _currentUser = nil
        addEvent("Auth data cleared")
    }

    private func decodeHeaders(_ json: String) throws -> [String: String] {
        guard let data = json.data(using: String.Encoding.utf8) else {
            throw AuthStoreError(message: "invalid headers encoding")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthStoreError(message: "invalid headers JSON")
        }
        var result = [String: String]()
        for (key, value) in obj {
            guard let str = value as? String else {
                throw AuthStoreError(message: "non-string header value")
            }
            result[key] = str
        }
        return result
    }

    private func encodeHeaders(_ headers: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: headers)
        guard let str = String(data: data, encoding: String.Encoding.utf8) else {
            throw AuthStoreError(message: "failed to encode headers")
        }
        return str
    }

    private func decodeUser(_ json: String) throws -> User {
        guard let data = json.data(using: String.Encoding.utf8) else {
            throw AuthStoreError(message: "invalid user encoding")
        }
        return try JSONDecoder().decode(User.self, from: data)
    }

    private func encodeUser(_ user: User) throws -> String {
        let data = try JSONEncoder().encode(user)
        guard let str = String(data: data, encoding: String.Encoding.utf8) else {
            throw AuthStoreError(message: "failed to encode user")
        }
        return str
    }

    // MARK: - Logout

    /// Port of `logout` (ref_auth_provider.dart:299-308). Clears everything including sp_dc,
    /// unlike `clearStoredData` which deliberately keeps it.
    func logout() async {
        addEvent("Logout requested")
        clearStoredData()
        userDefaults.removeObject(forKey: Self.spDcKey)
        spDc = nil
        // Buddy/activity cache clearing (`_buddyService.clearActivityCache()` in the Dart
        // original) is out of scope: that service has not been ported in this auth-flow phase.
        authState = .unauthenticated
        addEvent("Logged out")
    }

    // MARK: - Refresh

    /// Port of `refreshIfNeeded` (ref_auth_provider.dart:475-483).
    func refreshIfNeeded() async -> Bool {
        guard authState == .authenticated else { return false }
        let ok = await trySilentRefresh()
        if !ok {
            authState = .unauthenticated
        }
        return ok
    }

    /// Port of `_trySilentRefresh` (ref_auth_provider.dart:487-548).
    private func trySilentRefresh() async -> Bool {
        let effectiveSpDc = spDc ?? userDefaults.string(forKey: Self.spDcKey)
        guard let effectiveSpDc, !effectiveSpDc.isEmpty else {
            addEvent("Silent refresh skipped: no sp_dc")
            return false
        }

        addEvent("Silent refresh starting...")
        let newToken: String?
        if let override = tokenFetchOverride {
            newToken = await override(effectiveSpDc)
        } else {
            newToken = await SpotifyTokenService.fetchBearerToken(spDc: effectiveSpDc)
        }
        guard let newToken, !newToken.isEmpty else {
            addEvent("Silent refresh: no token returned")
            return false
        }

        spDc = effectiveSpDc
        bearerToken = newToken
        headers = SpotifyTokenService.headersFromSpDc(effectiveSpDc)

        // Only fetch profile when we don't already have one. Existing profile was obtained via
        // WebView JS injection and is correct; spclient/profile/me returns a different account
        // (social profile, not account settings).
        if _currentUser == nil {
            _currentUser = await userProfileFetchOverride?(newToken)

            if _currentUser == nil {
                addEvent("Silent refresh: no profile, aborting")
                bearerToken = nil
                headers = nil
                return false
            }
        }

        // Enrich with email/country when missing, spclient doesn't return these.
        // account-settings/v1/profile works with just sp_dc, no OAuth scopes needed.
        if _currentUser!.email.isEmpty || _currentUser!.country.isEmpty {
            _currentUser = await enrichedProfile(_currentUser!, spDc: effectiveSpDc)
        }

        saveStoredData()
        addEvent("Silent refresh OK: \(_currentUser!.displayName)")
        return true
    }

    // MARK: - 401 recovery (fast paths only, see readCookieStoreSpDc/headlessReAuthOverride docs)

    /// Port of the fast paths of `tryRecoverFromExpiredToken` (ref_auth_provider.dart:322-381).
    /// The slow path (headless WebView re-auth) is delegated to `headlessReAuthOverride`.
    func tryRecoverFromExpiredToken() async -> Bool {
        if isRecovering {
            addEvent("Recovery already in progress, skipping duplicate call")
            return false
        }
        isRecovering = true
        defer { isRecovering = false }

        addEvent("Token recovery: starting...")

        let cookieSpDc = await readCookieStoreSpDc?()

        if let cookieSpDc, !cookieSpDc.isEmpty, cookieSpDc != spDc {
            // Fresh sp_dc found in cookie jar, save it and try a silent refresh.
            addEvent("Token recovery: fresh sp_dc found in cookie store (fast path)")
            spDc = cookieSpDc
            userDefaults.set(cookieSpDc, forKey: Self.spDcKey)
            let ok = await trySilentRefresh()
            if ok {
                authState = .authenticated
                addEvent("Token recovery: OK via cookie-store fast path")
                return true
            }
        } else if let cookieSpDc, !cookieSpDc.isEmpty, cookieSpDc == spDc {
            // Same sp_dc in store, bearer may have just expired, try refresh directly.
            addEvent("Token recovery: sp_dc unchanged, refreshing bearer token")
            let ok = await trySilentRefresh()
            if ok {
                authState = .authenticated
                addEvent("Token recovery: OK via bearer refresh")
                return true
            }
        }

        addEvent("Token recovery: fast path failed, starting headless WebView...")
        let ok = await headlessReAuthOverride?() ?? false
        if ok {
            authState = .authenticated
            addEvent("Token recovery: OK via headless WebView")
            return true
        }

        addEvent("Token recovery: all paths failed, need login")
        return false
    }
}
