import Foundation
import XCTest
@testable import Playtivity

final class AuthStoreTests: XCTestCase {
    private let validToken = "Bearer.token.abc1234567890123456789012345678901234567890"

    override func setUp() {
        super.setUp()
        // AuthStore's email/country enrichment step, and its own default (un-overridden) token
        // refresh path, both call SpotifyTokenService's static functions directly, not through an
        // AuthStore-level seam. Stub all three of SpotifyTokenService's network seams here so no
        // test can accidentally make a real network call, regardless of whether a given test's
        // own AuthStore-level overrides happen to be wired up before the call that would reach
        // them. This is defense-in-depth: every test below should still set its own
        // tokenFetchOverride before any call that can reach trySilentRefresh, this blanket stub
        // only catches the case where one forgets to.
        SpotifyTokenService.accountProfileFetchOverride = { _ in (statusCode: 404, body: "") }
        SpotifyTokenService.bearerTokenFetchOverride = { _ in (statusCode: 401, body: "") }
        SpotifyTokenService.serverTimeFetchOverride = { nil }
    }

    override func tearDown() {
        SpotifyTokenService.accountProfileFetchOverride = nil
        SpotifyTokenService.bearerTokenFetchOverride = nil
        SpotifyTokenService.serverTimeFetchOverride = nil
        super.tearDown()
    }

    private func makeUserDefaults(_ initialValues: [String: String] = [:]) -> UserDefaults {
        let ud = UserDefaults(suiteName: "AuthStoreTests.\(UUID().uuidString)")!
        for (key, value) in initialValues {
            ud.set(value, forKey: key)
        }
        return ud
    }

    private func fakeUser(
        id: String = "user_123",
        displayName: String = "Test User",
        email: String = "test@example.com",
        imageUrl: String? = nil,
        followers: Int = 10,
        country: String = "US"
    ) -> User {
        User(id: id, displayName: displayName, email: email, imageUrl: imageUrl, followers: followers, country: country)
    }

    private func userJson(_ user: User) -> String {
        // Mirrors User's snake_case persistence shape directly, without depending on
        // AuthStore's own encode path, so restore tests exercise decode independently of encode.
        var escapedImageUrl = "null"
        if let imageUrl = user.imageUrl {
            escapedImageUrl = "\"\(imageUrl)\""
        }
        return """
        {"id":"\(user.id)","display_name":"\(user.displayName)","email":"\(user.email)",\
        "image_url":\(escapedImageUrl),"followers":\(user.followers),"country":"\(user.country)"}
        """
    }

    // MARK: - Initial state

    func testAuthStateIsUninitializedBeforeInitializeIsCalled() {
        let store = AuthStore(userDefaults: makeUserDefaults())
        XCTAssertEqual(store.authState, AuthState.uninitialized)
        XCTAssertFalse(store.isInitialized)
    }

    func testColdStartWithNoStoredDataResolvesToUnauthenticated() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.unauthenticated)
        XCTAssertTrue(store.isInitialized)
        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.currentUser)
    }

    func testRestoreWithValidTokenAndUserResolvesToAuthenticatedWithNoNetworkCall() async {
        // No sp_dc stored, so the proactive-refresh branch is never entered: no network call
        // is possible here, which this test proves by never configuring tokenFetchOverride
        // (an unconfigured override would trap/crash a real network call, not silently no-op).
        let user = fakeUser()
        let ud = makeUserDefaults([
            "spotify_bearer_token": "storedToken",
            "spotify_headers": "{\"Cookie\":\"sp_dc=x\"}",
            "spotify_user": userJson(user),
        ])
        let store = AuthStore(userDefaults: ud)
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.authenticated)
        XCTAssertEqual(store.currentUser?.id, "user_123")
        XCTAssertEqual(store.bearerToken, "storedToken")
    }

    func testRestoreWithTokenButNoUserAttemptsSilentRefresh() async {
        let ud = makeUserDefaults([
            "spotify_bearer_token": "storedToken",
            "spotify_headers": "{\"Cookie\":\"sp_dc=x\"}",
            "spotify_sp_dc": "storedSpDc",
        ])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { spDc in
            XCTAssertEqual(spDc, "storedSpDc")
            return "refreshedToken12345678901234567890123456789012345"
        }
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.authenticated)
        XCTAssertEqual(store.bearerToken, "refreshedToken12345678901234567890123456789012345")
    }

    func testRestoreWithTokenButNoUserClearsStoredDataWhenSilentRefreshFails() async {
        let ud = makeUserDefaults([
            "spotify_bearer_token": "storedToken",
            "spotify_headers": "{\"Cookie\":\"sp_dc=x\"}",
            "spotify_sp_dc": "storedSpDc",
        ])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.unauthenticated)
        XCTAssertNil(ud.string(forKey: "spotify_bearer_token"))
    }

    func testRestoreFailureFromMalformedStoredHeadersAttemptsSilentRefreshAndClearsOnFailure() async {
        let ud = makeUserDefaults([
            "spotify_bearer_token": "storedToken",
            "spotify_headers": "not-valid-json{{{",
            "spotify_sp_dc": "storedSpDc",
        ])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.unauthenticated)
        XCTAssertNil(ud.string(forKey: "spotify_bearer_token"))
        XCTAssertNil(store.currentUser)
    }

    func testRestoreFailureThenSuccessfulSilentRefreshAuthenticates() async {
        let ud = makeUserDefaults([
            "spotify_bearer_token": "storedToken",
            "spotify_headers": "not-valid-json{{{",
            "spotify_sp_dc": "storedSpDc",
        ])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in "refreshedToken12345678901234567890123456789012345" }
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.authenticated)
        XCTAssertEqual(store.bearerToken, "refreshedToken12345678901234567890123456789012345")
    }

    func testSilentlyRefreshesAndAuthenticatesWhenStoredTokenAbsentButSpDcExists() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "storedSpDc"])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in "refreshedToken12345678901234567890123456789012345" }
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.authenticated)
        XCTAssertEqual(store.currentUser?.id, "user_123")
    }

    func testStaysUnauthenticatedWhenNoTokenAndNoSpDc() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()

        XCTAssertEqual(store.authState, AuthState.unauthenticated)
        XCTAssertNil(store.currentUser)
    }

    func testPersistsNewTokenAndUserAfterSuccessfulStartupSilentRefresh() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "storedSpDc"])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in "persistedToken12345678901234567890123456789" }
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        await store.initialize()

        XCTAssertEqual(ud.string(forKey: "spotify_bearer_token"), "persistedToken12345678901234567890123456789")
        XCTAssertNotNil(ud.string(forKey: "spotify_user"))
    }

    func testSpDcIsNotRemovedWhenStoredCredentialsAreRestoredEvenIfProactiveRefreshFails() async {
        // Token validity is checked lazily (on first API call), so stored credentials make the
        // store appear authenticated at startup. sp_dc must survive so refreshIfNeeded can get a
        // new token when the first 401 hits.
        let user = fakeUser()
        let ud = makeUserDefaults([
            "spotify_bearer_token": "expiredToken",
            "spotify_headers": "{\"Cookie\":\"sp_dc=myDc\"}",
            "spotify_user": userJson(user),
            "spotify_sp_dc": "myDc",
        ])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()

        XCTAssertEqual(ud.string(forKey: "spotify_sp_dc"), "myDc")
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.bearerToken, "expiredToken")
    }

    // MARK: - Placeholder email/country migration scrub

    func testScrubsPlaceholderEmailAndCountryStoredFromOlderAppVersion() async {
        let placeholderUser = User(
            id: "21fvdxlt6ejvha6jnrgdwamja",
            displayName: "Michael Liem",
            email: "user@spotify.com",
            imageUrl: nil,
            followers: 48,
            country: "US"
        )
        let ud = makeUserDefaults([
            "spotify_bearer_token": validToken,
            "spotify_headers": "{\"Cookie\":\"sp_dc=validSpDc\"}",
            "spotify_user": userJson(placeholderUser),
        ])
        let store = AuthStore(userDefaults: ud)
        await store.initialize()

        XCTAssertEqual(store.currentUser?.email, "")
        XCTAssertEqual(store.currentUser?.country, "")
        XCTAssertEqual(store.currentUser?.displayName, "Michael Liem")
    }

    func testLeavesRealUsCountryIntactWhenEmailIsAlsoReal() async {
        let realUser = User(
            id: "realuserid1234567890",
            displayName: "Real User",
            email: "real@gmail.com",
            imageUrl: nil,
            followers: 5,
            country: "US"
        )
        let ud = makeUserDefaults([
            "spotify_bearer_token": validToken,
            "spotify_headers": "{\"Cookie\":\"sp_dc=validSpDc\"}",
            "spotify_user": userJson(realUser),
        ])
        let store = AuthStore(userDefaults: ud)
        await store.initialize()

        XCTAssertEqual(store.currentUser?.email, "real@gmail.com")
        XCTAssertEqual(store.currentUser?.country, "US")
    }

    // MARK: - loginComplete: token validation

    func testLoginCompleteThrowsWhenBearerTokenIsTooShort() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        do {
            try await store.loginComplete(bearerToken: "short-token", headers: ["Cookie": "sp_dc=x"])
            XCTFail("expected loginComplete to throw")
        } catch {
            // expected
        }
        XCTAssertFalse(store.isAuthenticated)
    }

    // MARK: - loginComplete: sp_dc extraction

    func testLoginCompleteStoresSpDcWhenCookieHeaderContainsIt() async throws {
        let ud = makeUserDefaults()
        let store = AuthStore(userDefaults: ud)
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        try await store.loginComplete(
            bearerToken: validToken,
            headers: ["Cookie": "sp_t=trackVal; sp_dc=mySecretSpDc; sp_key=keyVal"]
        )

        XCTAssertEqual(ud.string(forKey: "spotify_sp_dc"), "mySecretSpDc")
    }

    func testLoginCompleteDoesNotCrashWhenCookieHeaderIsMissingSpDc() async throws {
        let ud = makeUserDefaults()
        let store = AuthStore(userDefaults: ud)
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        try await store.loginComplete(
            bearerToken: validToken,
            headers: ["Cookie": "sp_t=trackVal; sp_key=keyVal"]
        )

        XCTAssertNil(ud.string(forKey: "spotify_sp_dc"))
        XCTAssertTrue(store.isAuthenticated)
    }

    // MARK: - loginComplete: full flow

    func testLoginCompleteSetsAuthenticatedAfterValidTokenAndProfileFetch() async throws {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        try await store.loginComplete(bearerToken: validToken, headers: ["Cookie": "sp_dc=validSpDc; sp_t=trackVal"])

        XCTAssertTrue(store.isAuthenticated)
    }

    func testLoginCompleteSetsCurrentUserAfterSuccess() async throws {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        try await store.loginComplete(bearerToken: validToken, headers: ["Cookie": "sp_dc=validSpDc"])

        XCTAssertEqual(store.currentUser?.id, "user_123")
    }

    func testLoginCompletePersistsBearerTokenToUserDefaults() async throws {
        let ud = makeUserDefaults()
        let store = AuthStore(userDefaults: ud)
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        try await store.loginComplete(bearerToken: validToken, headers: ["Cookie": "sp_dc=validSpDc"])

        XCTAssertEqual(ud.string(forKey: "spotify_bearer_token"), validToken)
    }

    func testLoginCompleteThrowsAndStaysUnauthenticatedWhenProfileFetchAlwaysReturnsNil() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in nil }

        do {
            try await store.loginComplete(bearerToken: validToken, headers: ["Cookie": "sp_dc=validSpDc"])
            XCTFail("expected loginComplete to throw")
        } catch {
            // expected
        }

        XCTAssertFalse(store.isAuthenticated)
        XCTAssertNil(store.currentUser)
    }

    func testLoginCompleteStoresBearerTokenInGetterAfterSuccess() async throws {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        try await store.loginComplete(bearerToken: validToken, headers: ["Cookie": "sp_dc=x"])

        XCTAssertEqual(store.bearerToken, validToken)
    }

    func testLoginCompleteFallsBackToProfileFetcherWhenXPrefetchedUserHeaderIsAbsent() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in nil }

        do {
            try await store.loginComplete(bearerToken: validToken, headers: ["Cookie": "sp_dc=validSpDc"])
            XCTFail("expected loginComplete to throw")
        } catch {
            // expected
        }
        XCTAssertFalse(store.isAuthenticated)
    }

    // MARK: - loginComplete: x-prefetched-user header

    private func headersWithPrefetch(_ user: [String: Any?]) -> [String: String] {
        let data = try! JSONSerialization.data(withJSONObject: user.compactMapValues { $0 ?? NSNull() })
        let json = String(data: data, encoding: String.Encoding.utf8)!
        return ["Cookie": "sp_dc=validSpDc", "x-prefetched-user": json]
    }

    func testLoginCompleteUsesPrefetchedUserDirectlyWithoutCallingProfileFetcher() async throws {
        var profileFetcherCalled = false
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in
            profileFetcherCalled = true
            return self.fakeUser()
        }

        try await store.loginComplete(
            bearerToken: validToken,
            headers: headersWithPrefetch([
                "id": "spotify-user-abc123",
                "displayName": "Test Display Name",
                "imageUrl": nil,
                "country": "AU",
                "followers": 12,
            ])
        )

        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(store.currentUser?.displayName, "Test Display Name")
        XCTAssertFalse(profileFetcherCalled)
    }

    func testPrefetchedUserFieldsAreStoredCorrectlyOnTheUserModel() async throws {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()

        try await store.loginComplete(
            bearerToken: validToken,
            headers: headersWithPrefetch([
                "id": "spotify-user-abc123",
                "displayName": "Test Display Name",
                "imageUrl": "https://i.scdn.co/image/abc123",
                "country": "AU",
                "followers": 42,
            ])
        )

        let user = try XCTUnwrap(store.currentUser)
        XCTAssertEqual(user.id, "spotify-user-abc123")
        XCTAssertEqual(user.displayName, "Test Display Name")
        XCTAssertEqual(user.imageUrl, "https://i.scdn.co/image/abc123")
        XCTAssertEqual(user.country, "AU")
        XCTAssertEqual(user.followers, 42)
    }

    func testLoginCompleteFallsThroughToProfileFetcherWhenPrefetchedUserIdIsEmpty() async throws {
        var profileFetcherCalled = false
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in
            profileFetcherCalled = true
            return self.fakeUser()
        }

        try await store.loginComplete(
            bearerToken: validToken,
            headers: headersWithPrefetch(["id": "", "displayName": "Should be ignored"])
        )

        XCTAssertTrue(profileFetcherCalled)
        XCTAssertTrue(store.isAuthenticated)
    }

    func testLoginCompleteFallsThroughToProfileFetcherWhenPrefetchedUserIsMalformedJson() async throws {
        var profileFetcherCalled = false
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in
            profileFetcherCalled = true
            return self.fakeUser()
        }

        try await store.loginComplete(
            bearerToken: validToken,
            headers: ["Cookie": "sp_dc=validSpDc", "x-prefetched-user": "not-valid-json"]
        )

        XCTAssertTrue(profileFetcherCalled)
        XCTAssertTrue(store.isAuthenticated)
    }

    func testPrefetchedUserReturnsRealEmailAndCountry() async throws {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()

        try await store.loginComplete(
            bearerToken: validToken,
            headers: headersWithPrefetch([
                "id": "21fvdxlt6ejvha6jnrgdwamja",
                "displayName": "Michael Liem",
                "email": "michael_liem2000@yahoo.com",
                "country": "ID",
                "followers": 48,
            ])
        )

        XCTAssertEqual(store.currentUser?.email, "michael_liem2000@yahoo.com")
        XCTAssertEqual(store.currentUser?.country, "ID")
    }

    func testPrefetchedUserStoresEmptyStringForNullEmailAndCountry() async throws {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()

        try await store.loginComplete(
            bearerToken: validToken,
            headers: headersWithPrefetch([
                "id": "21fvdxlt6ejvha6jnrgdwamja",
                "displayName": "Michael Liem",
                "email": nil,
                "country": nil,
                "followers": 48,
            ])
        )

        XCTAssertEqual(store.currentUser?.email, "")
        XCTAssertEqual(store.currentUser?.country, "")
    }

    // MARK: - logout

    func testLogoutTransitionsToUnauthenticatedAfterBeingAuthenticated() async throws {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        try await store.loginComplete(bearerToken: validToken, headers: ["Cookie": "sp_dc=validSpDc"])
        XCTAssertTrue(store.isAuthenticated)

        await store.logout()

        XCTAssertEqual(store.authState, AuthState.unauthenticated)
        XCTAssertFalse(store.isAuthenticated)
    }

    func testLogoutClearsSpDcFromUserDefaults() async {
        let ud = makeUserDefaults([
            "spotify_sp_dc": "storedSpDc",
            "spotify_bearer_token": "oldToken",
        ])
        let store = AuthStore(userDefaults: ud)
        // No spotify_headers stored alongside the bearer token, so initialize() falls into the
        // "no stored token, silent refresh with sp_dc" branch. Set this before initialize() so
        // that attempt is deterministic and network-free, not just relying on the setUp() stub.
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()

        await store.logout()

        XCTAssertNil(ud.string(forKey: "spotify_sp_dc"))
        XCTAssertNil(ud.string(forKey: "spotify_bearer_token"))
    }

    func testLogoutIsIdempotent() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        XCTAssertEqual(store.authState, AuthState.unauthenticated)

        await store.logout()
        await store.logout()

        XCTAssertEqual(store.authState, AuthState.unauthenticated)
    }

    // MARK: - refreshIfNeeded

    func testRefreshIfNeededReturnsFalseWhenNotAuthenticated() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()

        let result = await store.refreshIfNeeded()

        XCTAssertFalse(result)
        XCTAssertEqual(store.authState, AuthState.unauthenticated)
    }

    func testRefreshIfNeededReturnsTrueAndStaysAuthenticatedOnSuccess() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "validSpDc"])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in "refreshedToken12345678901234567890123456789012345" }
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        await store.initialize()
        XCTAssertTrue(store.isAuthenticated)

        let result = await store.refreshIfNeeded()

        XCTAssertTrue(result)
        XCTAssertEqual(store.authState, AuthState.authenticated)
        XCTAssertEqual(store.bearerToken, "refreshedToken12345678901234567890123456789012345")
    }

    func testRefreshIfNeededReturnsFalseWhenNoSpDcStored() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        // Force an authenticated state directly via loginComplete without sp_dc surviving
        // (no Cookie header sp_dc means refreshIfNeeded has nothing stored to use).
        try? await store.loginComplete(bearerToken: validToken, headers: [:])

        let result = await store.refreshIfNeeded()

        XCTAssertFalse(result)
        XCTAssertEqual(store.authState, AuthState.unauthenticated)
    }

    func testRefreshIfNeededReturnsFalseAndTransitionsToUnauthenticatedWhenSilentRefreshFails() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "validSpDc"])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in "refreshedToken12345678901234567890123456789012345" }
        store.userProfileFetchOverride = { _ in self.fakeUser() }
        await store.initialize()
        XCTAssertTrue(store.isAuthenticated)

        store.tokenFetchOverride = { _ in nil }
        let result = await store.refreshIfNeeded()

        XCTAssertFalse(result)
        XCTAssertEqual(store.authState, AuthState.unauthenticated)
    }

    func testRefreshIfNeededReturnsFalseWhenUserProfileFetchFailsAfterTokenFetch() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "validSpDc"])
        let store = AuthStore(userDefaults: ud)
        store.tokenFetchOverride = { _ in "freshToken12345678901234567890123456789012345" }
        store.userProfileFetchOverride = { _ in nil }
        await store.initialize()

        let result = await store.refreshIfNeeded()

        XCTAssertFalse(result)
        XCTAssertEqual(store.authState, AuthState.unauthenticated)
    }

    // MARK: - tryRecoverFromExpiredToken: both fast paths fail through to false

    func testRecoveryReturnsFalseWhenNoCookieReadAndNoHeadlessOverrideConfigured() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()

        let result = await store.tryRecoverFromExpiredToken()

        XCTAssertFalse(result)
        XCTAssertFalse(store.isAuthenticated)
    }

    // MARK: - tryRecoverFromExpiredToken: fast path 1, fresh sp_dc in cookie store

    func testRecoveryFastPathSucceedsWithFreshSpDcFromCookieStore() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "oldSpDc"])
        let store = AuthStore(userDefaults: ud)
        // stored sp_dc with no bearer token/headers routes initialize() into its own silent
        // refresh attempt; keep that network-free with a plain nil before wiring the overrides
        // that are actually under test here, since the assertion below expects "freshSpDc"
        // specifically, which is not the value initialize() would see (it only knows "oldSpDc").
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()
        store.readCookieStoreSpDc = { "freshSpDc" }
        store.tokenFetchOverride = { spDc in
            XCTAssertEqual(spDc, "freshSpDc")
            return "newToken1234567890123456789012345678901234567890"
        }
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        let result = await store.tryRecoverFromExpiredToken()

        XCTAssertTrue(result)
        XCTAssertTrue(store.isAuthenticated)
        XCTAssertEqual(ud.string(forKey: "spotify_sp_dc"), "freshSpDc")
    }

    func testRecoveryFastPathFallsThroughToHeadlessWhenFreshSpDcRefreshFails() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "oldSpDc"])
        let store = AuthStore(userDefaults: ud)
        // Same nil-returning override covers both initialize()'s own silent refresh attempt and
        // the recovery call under test, so it can be set once, before initialize().
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()
        store.readCookieStoreSpDc = { "freshSpDc" }

        let result = await store.tryRecoverFromExpiredToken()

        XCTAssertFalse(result)
        XCTAssertFalse(store.isAuthenticated)
    }

    // MARK: - tryRecoverFromExpiredToken: fast path 2, sp_dc unchanged

    func testRecoveryFastPathSucceedsWhenCookieSpDcMatchesStoredAndBearerRefreshWorks() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "sameSpDc"])
        let store = AuthStore(userDefaults: ud)
        // Keep initialize()'s own silent refresh attempt network-free with a plain nil, then wire
        // the success overrides for the recovery call actually under test.
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()
        store.readCookieStoreSpDc = { "sameSpDc" }
        store.tokenFetchOverride = { _ in "newToken1234567890123456789012345678901234567890" }
        store.userProfileFetchOverride = { _ in self.fakeUser() }

        let result = await store.tryRecoverFromExpiredToken()

        XCTAssertTrue(result)
        XCTAssertTrue(store.isAuthenticated)
    }

    func testRecoveryFastPathFallsThroughToHeadlessWhenUnchangedSpDcRefreshFails() async {
        let ud = makeUserDefaults(["spotify_sp_dc": "sameSpDc"])
        let store = AuthStore(userDefaults: ud)
        // Same nil-returning override covers both initialize()'s own silent refresh attempt and
        // the recovery call under test, so it can be set once, before initialize().
        store.tokenFetchOverride = { _ in nil }
        await store.initialize()
        store.readCookieStoreSpDc = { "sameSpDc" }

        let result = await store.tryRecoverFromExpiredToken()

        XCTAssertFalse(result)
        XCTAssertFalse(store.isAuthenticated)
    }

    // MARK: - tryRecoverFromExpiredToken: slow path delegated to headlessReAuthOverride

    func testRecoveryUsesHeadlessOverrideWhenBothFastPathsUnavailable() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        var headlessCalled = false
        store.headlessReAuthOverride = {
            headlessCalled = true
            return true
        }

        let result = await store.tryRecoverFromExpiredToken()

        XCTAssertTrue(result)
        XCTAssertTrue(headlessCalled)
        XCTAssertTrue(store.isAuthenticated)
    }

    func testRecoveryReturnsFalseWhenHeadlessOverrideReturnsFalse() async {
        let store = AuthStore(userDefaults: makeUserDefaults())
        await store.initialize()
        store.headlessReAuthOverride = { false }

        let result = await store.tryRecoverFromExpiredToken()

        XCTAssertFalse(result)
        XCTAssertFalse(store.isAuthenticated)
    }
}
