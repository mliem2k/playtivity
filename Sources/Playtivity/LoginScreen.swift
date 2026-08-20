import Foundation
import SwiftUI

// SkipWeb's own `WebView`/`WebEngine`/`WebViewScriptMessage` types are gated `#if SKIP ||
// os(iOS)` inside the library itself (confirmed in the resolved skip-web 0.11.3 source,
// WebView.swift:124 and WebEngine.swift:87): they exist for the real targets, Android via the
// Skip transpile and real iOS, but not for a native macOS host build. This file mirrors that
// same gate so `swift build`/`swift test` on macOS (the machine this was developed and tested
// on) compiles cleanly; the WebView-using code is still fully compiled and exercised by the Skip
// transpile step of `swift test`, which is the real signal for the Android target this app
// ships on.
#if SKIP || os(iOS)
import SkipWeb

/// Pure-Swift/SkipUI port of lib/widgets/spotify_webview_login.dart. Presents Spotify's login
/// page in a WebView, captures the resulting `sp_dc` session cookie, exchanges it for a Bearer
/// token, opportunistically pre-fetches the user's identity via JS injection, then hands
/// everything to `AuthStore.loginComplete`.
///
/// Live login (real cookie capture, real JS identity injection) has not been verified against a
/// real Spotify account as part of this task; see the task report for the required manual pass.
struct LoginScreen: View {
    let authStore: AuthStore
    var onComplete: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var navigator = WebViewNavigator()
    @State private var webViewState = WebViewState()
    @State private var scriptDelegate = IdentityScriptMessageDelegate()

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var completed = false
    @State private var processingAuth = false
    @State private var processingStep = ""
    @State private var capturing = false
    @State private var cookieRetryTask: Task<Void, Never>?

    private static let loginURL = URL(
        string: "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F"
    )!
    private static let identityHandlerName = "playtivityIdentity"

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    LoginInfoBanner()
                    if let errorMessage {
                        LoginErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    }
                    WebView(
                        configuration: WebEngineConfiguration(
                            javaScriptEnabled: true,
                            customUserAgent: SpotifyTokenService.userAgent,
                            scriptMessageHandlerNames: [Self.identityHandlerName],
                            scriptMessageDelegate: scriptDelegate
                        ),
                        navigator: navigator,
                        url: Self.loginURL,
                        state: $webViewState,
                        onNavigationCommitted: {
                            isLoading = true
                            errorMessage = nil
                        },
                        onNavigationFinished: {
                            isLoading = false
                            Task { await attemptTokenCaptureIfEligible() }
                        },
                        onNavigationFailed: {
                            isLoading = false
                            errorMessage = "Failed to load page."
                        }
                    )
                    // Keeps the WebView mounted (and its cookie/JS state alive) while hidden,
                    // matching Dart's Visibility(maintainState/maintainSize/maintainAnimation).
                    // Double literals, not Int (0/1): Skip's Kotlin transpile emits an Int
                    // literal for a bare `0`/`1` here even though `opacity` takes a Double,
                    // failing Kotlin compilation with an argument type mismatch.
                    .opacity(processingAuth ? 0.0 : 1.0)
                }
                if processingAuth {
                    LoginProcessingOverlay(step: processingStep, onCancel: cancelLogin)
                }
            }
            .navigationTitle("Login to Spotify")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        performCancel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isLoading {
                        ProgressView()
                    }
                }
            }
        }
        .onDisappear {
            cookieRetryTask?.cancel()
        }
    }

    // MARK: - Capture

    /// Port of `onLoadStop`'s gating (ref_spotify_webview_login.dart:124-139).
    private func attemptTokenCaptureIfEligible() async {
        guard !completed, let url = webViewState.url else { return }
        guard LoginScreenLogic.isEligibleForCapture(url: url) else { return }
        _ = await attemptTokenCapture(url: url)
    }

    /// Port of `_attemptTokenCapture` (ref_spotify_webview_login.dart:170-319). Returns `true`
    /// once the `sp_dc` cookie itself has been found (regardless of whether the rest of the
    /// exchange succeeds), which is the signal the cookie-retry loop uses to stop retrying.
    @discardableResult
    private func attemptTokenCapture(url: URL) async -> Bool {
        guard !capturing else { return false }
        capturing = true
        defer { capturing = false }

        processingAuth = true
        processingStep = "Verifying session..."

        let cookies = await navigator.cookies(for: url)
        guard let spDcCookie = cookies.first(where: { $0.name == "sp_dc" && !$0.value.isEmpty }) else {
            // sp_dc not yet in the cookie store: the Spotify SPA may not have committed it yet.
            // Schedule retries so we don't silently give up after the first navigation event.
            processingAuth = false
            scheduleCookieRetryIfNeeded(for: url)
            return false
        }

        cookieRetryTask?.cancel()
        cookieRetryTask = nil

        processingStep = "Fetching access token..."
        logger.info("sp_dc found, fetching Bearer token...")
        guard let token = await SpotifyTokenService.fetchBearerToken(spDc: spDcCookie.value), !token.isEmpty else {
            processingAuth = false
            errorMessage = "Failed to get access token. Please try again."
            return true
        }

        completed = true
        var headers = SpotifyTokenService.headersFromSpDc(spDcCookie.value)

        // Extract user identity via WebView JS injection, avoids the server-side rate limit on
        // api.spotify.com/v1/me. AuthStore.loginComplete already validates and falls through to
        // its own server-side fetcher whenever this comes back nil or without a usable id, so no
        // duplicate validation is needed here.
        logger.info("Injecting JS to get user identity...")
        if let identityJSON = await fetchPrefetchedIdentity(token: token) {
            headers["x-prefetched-user"] = identityJSON
            logger.info("JS identity injection completed")
        } else {
            logger.info("JS identity injection timed out, will fall through to server-side fetch")
        }

        processingStep = "Loading your profile..."
        do {
            try await authStore.loginComplete(bearerToken: token, headers: headers)
            processingAuth = false
            performComplete()
        } catch {
            completed = false
            processingAuth = false
            errorMessage = "Authentication failed: \(error)"
        }
        return true
    }

    /// Port of `_scheduleCookieRetry` (ref_spotify_webview_login.dart:41-63): only starts a new
    /// loop if one is not already running, matching the Dart timer's own re-entrancy guard.
    private func scheduleCookieRetryIfNeeded(for url: URL) {
        guard cookieRetryTask == nil else { return }
        cookieRetryTask = Task {
            let result = await LoginScreenLogic.runCookieRetryLoop(
                sleep: { try await Task.sleep(for: $0) },
                isCancelled: { Task.isCancelled },
                check: { attempt in
                    logger.info("sp_dc retry \(attempt)/\(LoginScreenLogic.maxCookieRetries)...")
                    return await attemptTokenCapture(url: url)
                }
            )
            if result == .exhausted, !completed {
                processingAuth = false
                errorMessage = "Login timed out. Please try again."
            }
            cookieRetryTask = nil
        }
    }

    private func cancelLogin() {
        cookieRetryTask?.cancel()
        cookieRetryTask = nil
        capturing = false
        processingAuth = false
        completed = false
        performCancel()
    }

    /// Port of the Dart original's unconditional `Navigator.of(context).pop(true)` after a
    /// successful `onAuthComplete` (ref_spotify_webview_login.dart:296-298): falls back to
    /// `dismiss()` when no `onComplete` is supplied, so the screen (and its "Loading your
    /// profile..." overlay) cannot get stuck on screen after a successful login just because the
    /// caller didn't supply `onComplete`. Mirrors `performCancel` below exactly.
    private func performComplete() {
        if let onComplete {
            onComplete()
        } else {
            dismiss()
        }
    }

    /// Port of the Dart original's `widget.onCancel ?? () => Navigator.of(context).pop()`
    /// fallback (ref_spotify_webview_login.dart:72, 157-161).
    private func performCancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    // MARK: - Identity JS injection

    /// Runs the identity-fetch JS and waits (poll-based, not `evaluateJavaScript`'s return
    /// value, per the confirmed Android unreliability) for the resulting `postMessage`, up to
    /// `LoginScreenLogic.identityMaxPolls` * `LoginScreenLogic.identityPollInterval` (15s).
    private func fetchPrefetchedIdentity(token: String) async -> String? {
        scriptDelegate.reset()
        let js = Self.identityJS(token: token, handlerName: Self.identityHandlerName)
        _ = try? await navigator.evaluateJavaScript(js)
        return await waitForIdentityMessage()
    }

    private func waitForIdentityMessage() async -> String? {
        for _ in 0..<LoginScreenLogic.identityMaxPolls {
            if let json = scriptDelegate.lastMessageJSON { return json }
            try? await Task.sleep(for: LoginScreenLogic.identityPollInterval)
        }
        return scriptDelegate.lastMessageJSON
    }

    /// Ported from ref_spotify_webview_login.dart:216-277 (localStorage-prefix primary path,
    /// account-settings fallback path). One deliberate change from the Dart source: the result
    /// is delivered via `postMessage` to `handlerName` instead of being returned from the
    /// top-level script, since `evaluateJavaScript`'s return value is not reliable on Android.
    private static func identityJS(token: String, handlerName: String) -> String {
        // Written as if let rather than Optional.flatMap: Skip's Kotlin transpile of
        // `.flatMap` on a `try?`-chained optional resolved to the wrong stdlib overload
        // (`String.flatMap`, a regex-style extension) and failed to compile.
        var tokenJSON = "null"
        if let tokenData = try? JSONEncoder().encode(token),
           let encoded = String(data: tokenData, encoding: String.Encoding.utf8) {
            tokenJSON = encoded
        }
        return """
        (function() {
          async function getUser(token) {
            // Spotify namespaces all per-user localStorage keys as "{userId}:settingName".
            // Reading the first non-"anonymous" prefix gives us the real Spotify ID instantly,
            // no API call, no rate limits, no DOM polling needed.
            let userId = null;
            for (let i = 0; i < localStorage.length; i++) {
              const key = localStorage.key(i) || '';
              const m = key.match(/^([a-z0-9]{20,}):/);
              if (m && m[1] !== 'anonymous') { userId = m[1]; break; }
            }

            if (userId) {
              const [spResult, accountResult] = await Promise.allSettled([
                fetch(
                  'https://guc-spclient.spotify.com/user-profile-view/v3/profile/' + userId,
                  { headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'App-Platform': 'WebPlayer' } }
                ).then(r => r.ok ? r.json() : null).catch(() => null),
                fetch('https://www.spotify.com/api/account-settings/v1/profile', {
                  headers: { 'Accept': 'application/json' }
                }).then(r => r.ok ? r.json() : null).catch(() => null),
              ]);
              const sp = spResult.status === 'fulfilled' ? spResult.value : null;
              const account = accountResult.status === 'fulfilled' ? accountResult.value : null;
              const ap = account && account.profile;
              return {
                id: userId,
                displayName: (sp && sp.name) || userId,
                imageUrl: (sp && sp.image_url) || null,
                email: (ap && ap.email) || null,
                country: (ap && ap.country) || null,
                followers: (sp && sp.followers_count) || 0,
              };
            }

            // Fallback: account-settings gives us userId via profile.username.
            try {
              const r = await fetch('https://www.spotify.com/api/account-settings/v1/profile', {
                headers: { 'Accept': 'application/json' }
              });
              if (r.ok) {
                const data = await r.json();
                const p = data && data.profile;
                if (p && p.username) {
                  let spFallback = null;
                  try {
                    const sr = await fetch('https://guc-spclient.spotify.com/user-profile-view/v3/profile/' + p.username, {
                      headers: { 'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'App-Platform': 'WebPlayer' }
                    });
                    if (sr.ok) spFallback = await sr.json();
                  } catch (_) {}
                  return { id: p.username, displayName: (spFallback && spFallback.name) || p.username, imageUrl: (spFallback && spFallback.image_url) || null, email: p.email || null, country: p.country || null, followers: (spFallback && spFallback.followers_count) || 0 };
                }
              }
            } catch (_) {}
            return null;
          }
          getUser(\(tokenJSON)).then(function(result) {
            window.webkit.messageHandlers.\(handlerName).postMessage(result || {});
          }).catch(function(e) {
            window.webkit.messageHandlers.\(handlerName).postMessage({});
          });
        })();
        """
    }
}

/// Bridges the identity-fetch JS's `postMessage` callback back into Swift. Poll-based on the
/// `LoginScreen` side rather than continuation-based: this class only records the latest
/// message, avoiding `withCheckedContinuation`, whose Skip Lite transpilation was not
/// independently verified for this task.
@MainActor
final class IdentityScriptMessageDelegate: WebViewScriptMessageDelegate {
    private(set) var lastMessageJSON: String?

    func reset() {
        lastMessageJSON = nil
    }

    func webEngine(_ webEngine: WebEngine, didReceiveScriptMessage message: WebViewScriptMessage) {
        lastMessageJSON = message.bodyJSON
    }
}

// MARK: - UI chrome (ref_spotify_webview_login.dart:322-423)

private struct LoginInfoBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.green)
            Text("Login with your Spotify account to access friend activities")
                .font(.caption)
            Spacer()
        }
        .padding(12)
        .background(Color(white: 0.12))
    }
}

private struct LoginErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(Color.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.red)
            Spacer()
            Button("Retry", action: onRetry)
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
    }
}

private struct LoginProcessingOverlay: View {
    let step: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Color.green)
                Text("Signing in to Spotify")
                    .font(.headline)
                    .foregroundStyle(Color.green)
                Text(step)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondary)
                Button("Cancel", action: onCancel)
                    .foregroundStyle(Color.secondary)
            }
            .padding(24)
            .background(Color(white: 0.08))
            .cornerRadius(16)
            .padding(.horizontal, 32)
        }
        .ignoresSafeArea()
    }
}

#endif // SKIP || os(iOS)
