import Foundation
import XCTest
@testable import Playtivity

final class SpotifyTokenServiceTests: XCTestCase {
    private struct FakeNetworkError: Error, CustomStringConvertible {
        var description: String { "simulated network failure" }
    }

    override func tearDown() {
        SpotifyTokenService.serverTimeFetchOverride = nil
        SpotifyTokenService.bearerTokenFetchOverride = nil
        SpotifyTokenService.accountProfileFetchOverride = nil
        super.tearDown()
    }

    // MARK: - extractSpDc

    func testExtractSpDcFromCookieStringWithMultipleCookies() {
        let cookie = "sp_t=abc123; sp_dc=mySpDcValue; sp_key=xyz"
        XCTAssertEqual(SpotifyTokenService.extractSpDc(cookie), "mySpDcValue")
    }

    func testExtractSpDcWhenItIsTheFirstCookie() {
        XCTAssertEqual(SpotifyTokenService.extractSpDc("sp_dc=firstValue; other=x"), "firstValue")
    }

    func testExtractSpDcWhenItIsTheOnlyCookie() {
        XCTAssertEqual(SpotifyTokenService.extractSpDc("sp_dc=solo"), "solo")
    }

    func testExtractSpDcReturnsNilWhenAbsent() {
        XCTAssertNil(SpotifyTokenService.extractSpDc("sp_t=abc; sp_key=xyz"))
    }

    func testExtractSpDcReturnsNilForEmptyCookieString() {
        XCTAssertNil(SpotifyTokenService.extractSpDc(""))
    }

    func testExtractSpDcHandlesValueContainingEqualsSign() {
        // Base64-like values may contain =
        XCTAssertEqual(SpotifyTokenService.extractSpDc("sp_dc=abc=def; other=x"), "abc=def")
    }

    func testExtractSpDcIsNotConfusedByCookieWhoseNameEndsWithSpDc() {
        // e.g. "not_sp_dc=value" should not match
        XCTAssertNil(SpotifyTokenService.extractSpDc("not_sp_dc=trap; other=x"))
    }

    func testExtractSpDcTrimsSurroundingWhitespaceFromCookieParts() {
        XCTAssertEqual(SpotifyTokenService.extractSpDc("  sp_dc=trimmed  ; other=y"), "trimmed")
    }

    // MARK: - headersFromSpDc

    func testHeadersFromSpDcReturnsMapWithCookieContainingOnlySpDc() {
        let headers = SpotifyTokenService.headersFromSpDc("mySpDc")
        XCTAssertEqual(headers["Cookie"], "sp_dc=mySpDc")
    }

    func testHeadersFromSpDcIncludesRequiredSpotifyHeaders() {
        let headers = SpotifyTokenService.headersFromSpDc("x")
        XCTAssertNotNil(headers["User-Agent"])
        XCTAssertEqual(headers["App-Platform"], "WebPlayer")
        XCTAssertEqual(headers["Origin"], "https://open.spotify.com")
    }

    // MARK: - parseTokenResponse

    func testParseTokenResponseReturnsAccessTokenFromValid200Response() {
        let body = "{\"accessToken\":\"Bearer.abc.123\",\"isAnonymous\":false}"
        XCTAssertEqual(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: body), "Bearer.abc.123")
    }

    func testParseTokenResponseReturnsNilFor401RegardlessOfBody() {
        let body = "{\"accessToken\":\"should-be-ignored\"}"
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 401, body: body))
    }

    func testParseTokenResponseReturnsNilFor400() {
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 400, body: "{}"))
    }

    func testParseTokenResponseReturnsNilFor403() {
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 403, body: "{\"error\":\"forbidden\"}"))
    }

    func testParseTokenResponseReturnsNilWhenBodyHasOnlyAnonymousToken() {
        // AnonymousToken means Spotify rejected the sp_dc; the correct response is nil so the
        // caller can fall back to re-authentication.
        let body = "{\"AnonymousToken\":\"anon-tok\",\"isAnonymous\":true}"
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: body))
    }

    func testParseTokenResponseReturnsNilWhenIsAnonymousTrueEvenWithAccessTokenPresent() {
        // Spotify includes accessToken in the response body even for anonymous sessions (no
        // valid sp_dc). Accepting an anonymous token causes every subsequent API call to fail
        // with 401 because the token lacks user-scoped permissions, so isAnonymous must be
        // checked and the token rejected regardless of accessToken's presence.
        let body = "{\"accessToken\":\"BQ-anonymous\",\"isAnonymous\":true,\"clientId\":\"d8a5ed958d274c2e8ee717e6a4b0971d\"}"
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: body))
    }

    func testParseTokenResponseReturnsNilWhenBodyHasNoAccessTokenField() {
        let body = "{\"someOtherField\":\"value\"}"
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: body))
    }

    func testParseTokenResponseReturnsNilForEmptyBody() {
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: ""))
    }

    func testParseTokenResponseReturnsNilForMalformedJson() {
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: "not-json{{{"))
    }

    func testParseTokenResponseReturnsNilWhenAccessTokenIsNullInJson() {
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: "{\"accessToken\":null}"))
    }

    func testParseTokenResponseReturnsNilWhenAccessTokenIsEmptyString() {
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 200, body: "{\"accessToken\":\"\"}"))
    }

    func testParseTokenResponseReturnsNilFor500ServerError() {
        XCTAssertNil(SpotifyTokenService.parseTokenResponse(statusCode: 500, body: "{\"error\":\"server error\"}"))
    }

    // MARK: - buildTokenUrl

    private let sampleParams = ["totp": "123456", "totpServer": "654321", "totpVer": "14"]

    func testBuildTokenUrlTargetsCorrectSpotifyEndpoint() {
        let url = SpotifyTokenService.buildTokenUrl(sampleParams)
        XCTAssertEqual(url.host, "open.spotify.com")
        XCTAssertEqual(url.path, "/api/token")
    }

    func testBuildTokenUrlIncludesReasonTransportQueryParameter() {
        let url = SpotifyTokenService.buildTokenUrl(sampleParams)
        XCTAssertEqual(queryValue(url, "reason"), "transport")
    }

    func testBuildTokenUrlIncludesProductTypeWebPlayerQueryParameter() {
        let url = SpotifyTokenService.buildTokenUrl(sampleParams)
        XCTAssertEqual(queryValue(url, "productType"), "web-player")
    }

    func testBuildTokenUrlIncludesTotpParameterFromProvidedParams() {
        let url = SpotifyTokenService.buildTokenUrl(sampleParams)
        XCTAssertEqual(queryValue(url, "totp"), "123456")
    }

    func testBuildTokenUrlIncludesTotpServerParameterFromProvidedParams() {
        let url = SpotifyTokenService.buildTokenUrl(sampleParams)
        XCTAssertEqual(queryValue(url, "totpServer"), "654321")
    }

    func testBuildTokenUrlIncludesTotpVerParameterFromProvidedParams() {
        let url = SpotifyTokenService.buildTokenUrl(sampleParams)
        XCTAssertEqual(queryValue(url, "totpVer"), "14")
    }

    func testBuildTokenUrlUsesHttpsScheme() {
        let url = SpotifyTokenService.buildTokenUrl(sampleParams)
        XCTAssertEqual(url.scheme, "https")
    }

    private func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value
    }

    // MARK: - extractUserIdFromJwt

    func testExtractUserIdFromJwtDecodesSpotifyUserPrefixedSub() {
        let jwt = makeJwt(sub: "spotify:user:abc123")
        XCTAssertEqual(SpotifyTokenService.extractUserIdFromJwt(jwt), "abc123")
    }

    func testExtractUserIdFromJwtDecodesBareSub() {
        let jwt = makeJwt(sub: "abc123")
        XCTAssertEqual(SpotifyTokenService.extractUserIdFromJwt(jwt), "abc123")
    }

    func testExtractUserIdFromJwtReturnsNilForTokenWithWrongPartCount() {
        XCTAssertNil(SpotifyTokenService.extractUserIdFromJwt("not.a.valid.jwt.token"))
        XCTAssertNil(SpotifyTokenService.extractUserIdFromJwt("onlyonepart"))
    }

    func testExtractUserIdFromJwtReturnsNilForMalformedBase64Payload() {
        XCTAssertNil(SpotifyTokenService.extractUserIdFromJwt("header.not-valid-base64!!!.signature"))
    }

    func testExtractUserIdFromJwtReturnsNilWhenSubClaimMissing() {
        let jwt = makeJwtFromPayload(["exp": 12345])
        XCTAssertNil(SpotifyTokenService.extractUserIdFromJwt(jwt))
    }

    func testExtractUserIdFromJwtReturnsNilWhenSubClaimEmpty() {
        let jwt = makeJwt(sub: "")
        XCTAssertNil(SpotifyTokenService.extractUserIdFromJwt(jwt))
    }

    private func base64UrlEncode(_ dict: [String: Any]) -> String {
        let jsonData = try! JSONSerialization.data(withJSONObject: dict)
        var encoded = jsonData.base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        encoded = encoded.replacingOccurrences(of: "=", with: "")
        return encoded
    }

    private func makeJwtFromPayload(_ payload: [String: Any]) -> String {
        let header = base64UrlEncode(["alg": "HS256", "typ": "JWT"])
        let encodedPayload = base64UrlEncode(payload)
        return "\(header).\(encodedPayload).signature"
    }

    private func makeJwt(sub: String) -> String {
        makeJwtFromPayload(["sub": sub])
    }

    // MARK: - fetchServerTime

    func testFetchServerTimeParsesDateHeaderIntoEpochMillis() async {
        SpotifyTokenService.serverTimeFetchOverride = { "Wed, 21 Oct 2015 07:28:00 GMT" }
        let millis = await SpotifyTokenService.fetchServerTime()
        XCTAssertEqual(millis, 1_445_412_480_000)
    }

    func testFetchServerTimeFallsBackToLocalClockWhenHeaderMissing() async {
        SpotifyTokenService.serverTimeFetchOverride = { nil }
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let millis = await SpotifyTokenService.fetchServerTime()
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertTrue(millis >= before && millis <= after)
    }

    func testFetchServerTimeFallsBackToLocalClockOnThrownError() async {
        SpotifyTokenService.serverTimeFetchOverride = { throw FakeNetworkError() }
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let millis = await SpotifyTokenService.fetchServerTime()
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertTrue(millis >= before && millis <= after)
    }

    // MARK: - fetchBearerToken (headers + parsing, network stubbed via injectable closure)

    func testFetchBearerTokenSendsExpectedHeadersAndReturnsToken() async {
        SpotifyTokenService.serverTimeFetchOverride = { "Wed, 21 Oct 2015 07:28:00 GMT" }
        var capturedRequest: URLRequest?
        SpotifyTokenService.bearerTokenFetchOverride = { request in
            capturedRequest = request
            return (statusCode: 200, body: "{\"accessToken\":\"tok123\",\"isAnonymous\":false}")
        }

        let token = await SpotifyTokenService.fetchBearerToken(spDc: "mySpDc")

        XCTAssertEqual(token, "tok123")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Cookie"), "sp_dc=mySpDc")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "User-Agent"), SpotifyTokenService.userAgent)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "App-Platform"), "WebPlayer")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Referer"), "https://open.spotify.com/")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Origin"), "https://open.spotify.com")
    }

    func testFetchBearerTokenReturnsNilWhenEndpointRejectsSpDc() async {
        SpotifyTokenService.serverTimeFetchOverride = { "Wed, 21 Oct 2015 07:28:00 GMT" }
        SpotifyTokenService.bearerTokenFetchOverride = { _ in
            (statusCode: 200, body: "{\"isAnonymous\":true}")
        }

        let token = await SpotifyTokenService.fetchBearerToken(spDc: "expiredSpDc")
        XCTAssertNil(token)
    }

    func testFetchBearerTokenReturnsNilOnNetworkError() async {
        SpotifyTokenService.serverTimeFetchOverride = { "Wed, 21 Oct 2015 07:28:00 GMT" }
        SpotifyTokenService.bearerTokenFetchOverride = { _ in
            throw FakeNetworkError()
        }

        let token = await SpotifyTokenService.fetchBearerToken(spDc: "mySpDc")
        XCTAssertNil(token)
    }

    // MARK: - fetchAccountProfile (headers + parsing, network stubbed via injectable closure)

    func testFetchAccountProfileSendsExpectedHeadersAndReturnsProfile() async {
        var capturedRequest: URLRequest?
        SpotifyTokenService.accountProfileFetchOverride = { request in
            capturedRequest = request
            return (statusCode: 200, body: "{\"profile\":{\"email\":\"user@example.com\",\"country\":\"US\"}}")
        }

        let profile = await SpotifyTokenService.fetchAccountProfile(spDc: "mySpDc")

        XCTAssertEqual(profile?.email, "user@example.com")
        XCTAssertEqual(profile?.country, "US")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Cookie"), "sp_dc=mySpDc")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "User-Agent"), SpotifyTokenService.userAgent)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Referer"), "https://www.spotify.com/account/overview/")
    }

    func testFetchAccountProfileReturnsNilOnNon200Status() async {
        SpotifyTokenService.accountProfileFetchOverride = { _ in
            (statusCode: 401, body: "")
        }

        let profile = await SpotifyTokenService.fetchAccountProfile(spDc: "mySpDc")
        XCTAssertNil(profile)
    }

    func testFetchAccountProfileReturnsNilWhenProfileFieldMissing() async {
        SpotifyTokenService.accountProfileFetchOverride = { _ in
            (statusCode: 200, body: "{\"someOtherField\":true}")
        }

        let profile = await SpotifyTokenService.fetchAccountProfile(spDc: "mySpDc")
        XCTAssertNil(profile)
    }

    func testFetchAccountProfileReturnsNilOnNetworkError() async {
        SpotifyTokenService.accountProfileFetchOverride = { _ in
            throw FakeNetworkError()
        }

        let profile = await SpotifyTokenService.fetchAccountProfile(spDc: "mySpDc")
        XCTAssertNil(profile)
    }
}
