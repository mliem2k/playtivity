import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/app_logger.dart';

/// Safely truncates a string to a max length, avoiding RangeError
String _truncate(String? text, int maxLength) {
  if (text == null || text.isEmpty) return '';
  return text.length > maxLength ? '${text.substring(0, maxLength)}...' : text;
}

class SpotifyWebViewLogin extends StatefulWidget {
  final Future<void> Function(String, Map<String, String>) onAuthComplete; // Bearer access token and headers
  final VoidCallback? onCancel;

  const SpotifyWebViewLogin({
    super.key,
    required this.onAuthComplete,
    this.onCancel,
  });

  @override
  State<SpotifyWebViewLogin> createState() => _SpotifyWebViewLoginState();
}

class _SpotifyWebViewLoginState extends State<SpotifyWebViewLogin> {
  bool _isLoading = true;
  String? _error;
  Map<String, String> _extractedHeaders = {};
  bool _showOverlay = false;
  Timer? _overlayTimer;
  Timer? _pollingTimer;
  Timer? _directTokenFetchTimer;
  bool _isPollingActive = false;
  bool _networkInterceptionSetup = false;
  bool _directTokenFetchAttempted = false;

  @override
  void initState() {
    super.initState();
    
    // Failsafe: Hide overlay after 10 seconds to prevent permanently blocking login
    _overlayTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _showOverlay) {
        AppLogger.debug('Overlay timeout - hiding overlay to prevent blocking login');
        setState(() {
          _showOverlay = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _pollingTimer?.cancel();
    _directTokenFetchTimer?.cancel();
    _isPollingActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to Spotify'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onCancel ?? () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),      body: SafeArea(
        child: Column(
          children: [
            // Info banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.security,
                    color: Theme.of(context).primaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: const Text(
                      'Login with your Spotify account to access friend activities',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          
          // Error display
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.withValues(alpha: 26), // 0.1 * 255 ≈ 26
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          
          // WebView
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load Spotify login',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _error = null;
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      // WebView (always present, loading in background when overlay is shown)
                      InAppWebView(
                        initialSettings: InAppWebViewSettings(
                          // Desktop Chrome user agent for full Spotify desktop experience
                          userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36",
                          javaScriptEnabled: true,
                          domStorageEnabled: true,
                          thirdPartyCookiesEnabled: true,
                          supportZoom: false,
                          builtInZoomControls: false,
                          displayZoomControls: false,
                          useWideViewPort: true,
                          loadWithOverviewMode: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          mediaPlaybackRequiresUserGesture: false,
                          allowsInlineMediaPlayback: true,
                          iframeAllowFullscreen: true,
                          allowsBackForwardNavigationGestures: true,
                          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                          allowFileAccessFromFileURLs: true,
                          allowUniversalAccessFromFileURLs: true,
                        ),
                        initialUrlRequest: URLRequest(
                          url: WebUri('https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F__noul__%2F'),
                          headers: {
                            'sec-ch-ua': '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
                            'sec-ch-ua-mobile': '?0',
                            'sec-ch-ua-platform': '"Windows"',
                            'sec-fetch-dest': 'document',
                            'sec-fetch-mode': 'no-cors',
                            'sec-fetch-site': 'same-origin',
                            'sec-fetch-user': '?1',
                            'upgrade-insecure-requests': '1',
                            'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
                            'accept-encoding': 'gzip, deflate, br, zstd',
                            'accept-language': 'en-US,en;q=0.9',
                            'cache-control': 'max-age=0',
                            'dnt': '1',
                            'priority': 'u=0, i',
                          },
                        ),
                        onPermissionRequest: (controller, permissionRequest) async {
                          return PermissionResponse(
                            resources: permissionRequest.resources,
                            action: PermissionResponseAction.GRANT,
                          );
                        },
                        onLoadStart: (controller, url) async {
                          setState(() {
                            _isLoading = true;
                            _error = null;
                          });

                          // Set up network interception EARLY - before the page loads
                          // This ensures we catch Bearer tokens in API requests made during page load
                          if (url != null) {
                            String urlString = url.toString();
                            Uri uri = Uri.parse(urlString);
                            bool isSpotifyDomain = uri.host.endsWith('spotify.com');

                            if (isSpotifyDomain && !_networkInterceptionSetup) {
                              AppLogger.auth('Early setup of network interception for: $urlString');
                              await _setupNetworkInterception(controller, url);
                              _networkInterceptionSetup = true;
                            }
                          }
                        },
                        onLoadStop: (controller, url) async {
                          setState(() {
                            _isLoading = false;
                          });

                          if (url == null) return;

                          String urlString = url.toString();
                          AppLogger.auth('📄 Page loaded: $urlString');

                          // More precise overlay logic - only show when we're clearly logged in
                          Uri uri = Uri.parse(urlString);
                          bool isSpotifyDomain = uri.host.endsWith('spotify.com');

                          // Hide overlay for all login-related pages
                          bool isLoginFlow = urlString.contains('accounts.spotify.com') ||
                                           urlString.contains('/login') ||
                                           urlString.contains('/auth') ||
                                           urlString.contains('challenge.spotify.com') ||
                                           urlString.contains('/signup') ||
                                           urlString.contains('/authorize') ||
                                           urlString.contains('facebook.com') ||
                                           urlString.contains('google.com') ||
                                           !isSpotifyDomain;

                          // Check if we have sp_dc cookie (indicates user is logged in)
                          bool hasSpDcCookie = false;
                          if (!isLoginFlow && urlString.contains('open.spotify.com')) {
                            try {
                              final cookies = await CookieManager.instance().getCookies(url: url);
                              hasSpDcCookie = cookies.any((cookie) => cookie.name == 'sp_dc' && cookie.value.isNotEmpty);
                              AppLogger.auth('🍪 sp_dc cookie check on main page: $hasSpDcCookie');
                              AppLogger.debug('🔍 Cookie names found: ${cookies.map((c) => c.name).join(', ')}');
                            } catch (e) {
                              AppLogger.debug('Error checking for sp_dc cookie: $e');
                            }
                          }

                          // Show overlay ONLY when we're on main app AND have sp_dc cookie (confirmed logged in)
                          bool isMainSpotifyApp = urlString.contains('open.spotify.com') &&
                                                !urlString.contains('/login') &&
                                                !urlString.contains('/auth') &&
                                                !urlString.contains('/challenge') &&
                                                !urlString.contains('/error');

                          // ENHANCED LOGGING: Log all condition values
                          AppLogger.auth('🔍 onLoadStop condition check:');
                          AppLogger.auth('   - URL: $urlString');
                          AppLogger.auth('   - isSpotifyDomain: $isSpotifyDomain');
                          AppLogger.auth('   - isMainSpotifyApp: $isMainSpotifyApp');
                          AppLogger.auth('   - isLoginFlow: $isLoginFlow');
                          AppLogger.auth('   - hasSpDcCookie: $hasSpDcCookie');
                          AppLogger.auth('   - _isPollingActive: $_isPollingActive');
                          AppLogger.auth('   - _directTokenFetchTimer: ${_directTokenFetchTimer != null ? "EXISTS" : "NULL"}');

                          // Don't show overlay if we don't have authentication cookies
                          bool newShowOverlay = isMainSpotifyApp && !isLoginFlow && hasSpDcCookie;

                          setState(() {
                            AppLogger.debug('Overlay logic: host=${uri.host}, isMainApp=$isMainSpotifyApp, isLoginFlow=$isLoginFlow, hasSpDc=$hasSpDcCookie, showOverlay=$newShowOverlay');
                            _showOverlay = newShowOverlay;

                            // Reset timer when we detect we're in login flow
                            if (isLoginFlow && _overlayTimer != null) {
                              _overlayTimer?.cancel();
                              _overlayTimer = null;
                            }
                          });

                          // When on main Spotify page WITH sp_dc cookie, try direct token fetch as fallback
                          // This is more reliable than JavaScript interception
                          if (isMainSpotifyApp && hasSpDcCookie && _directTokenFetchTimer == null) {
                            AppLogger.auth('✅ On main Spotify page with sp_dc, scheduling direct token fetch...');
                            _directTokenFetchTimer = Timer(const Duration(seconds: 1), () {
                              if (mounted && _isPollingActive) {
                                AppLogger.auth('⏰ Timer triggered - Attempting direct token fetch as fallback...');
                                _tryDirectTokenFetch(controller);
                              } else {
                                AppLogger.auth('⏰ Timer fired but conditions not met - mounted=$mounted, _isPollingActive=$_isPollingActive');
                              }
                            });
                          } else if (isMainSpotifyApp && !hasSpDcCookie) {
                            AppLogger.auth('⚠️ On main Spotify page but NO sp_dc cookie - user needs to complete login first');
                          } else if (!isMainSpotifyApp) {
                            AppLogger.auth('ℹ️ Not on main Spotify app - skipping token fetch trigger');
                          }

                          // If on main page without sp_dc, log a hint to user
                          if (isMainSpotifyApp && !hasSpDcCookie && !isLoginFlow) {
                            AppLogger.auth('On main Spotify page but not logged in - user needs to complete login first');
                          }

                          // DISABLED: Auto-redirect was interfering with login flow
                          // Users need to complete login manually without being redirected

                          /* OLD CODE - Disabled due to redirect issues during login
                          try {
                            final pageInfo = await controller.evaluateJavascript(source: '''
                              (function() {
                                const bodyText = document.body.innerText || document.body.textContent || '';
                                const url = window.location.href;

                                console.log('🌐 Current URL:', url);
                                console.log('📄 Page text (first 300 chars):', bodyText.substring(0, 300));

                                // Look for device selection indicators in multiple languages
                                const deviceSelectionIndicators = [
                                  '登入身分',           // Chinese - "Login identity"
                                  '帳戶概覽',          // Chinese - "Account overview"
                                  '網頁播放器',        // Chinese - "Web player"
                                  '網頁播放',          // Chinese - "Web play"
                                  '播放器',            // Chinese - "Player"
                                  'web player',
                                  'web播放器',
                                  'choose a device',
                                  'select a device',
                                  'pick a device',
                                  'where do you want to listen',
                                  'どこで聴きますか',   // Japanese
                                  '어디에서 들으시겠어요', // Korean
                                  'account overview',
                                  'login to spotify',
                                  'login with your spotify account',
                                ];

                                const hasIndicator = deviceSelectionIndicators.some(indicator =>
                                  bodyText.toLowerCase().includes(indicator.toLowerCase())
                                );

                                // Check URL patterns
                                const isStatusPage = url.includes('/status') || url.includes('/en/login?continue=');
                                const isAccountsPage = url.includes('accounts.spotify.com');

                                console.log('📍 Has device/login indicator text:', hasIndicator);
                                console.log('📍 Is status/continue page:', isStatusPage);
                                console.log('📍 Is accounts page:', isAccountsPage);

                                return {
                                  hasIndicator: hasIndicator,
                                  isStatusPage: isStatusPage,
                                  isAccountsPage: isAccountsPage,
                                  url: url,
                                  shouldBypass: (hasIndicator || isStatusPage) && isAccountsPage
                                };
                              })();
                            ''');

                            if (pageInfo != null && pageInfo is Map) {
                              final shouldBypass = pageInfo['shouldBypass'] == true;
                              final detectedUrl = pageInfo['url'];

                              AppLogger.auth('Page detection: URL=$detectedUrl, shouldBypass=$shouldBypass');

                              if (shouldBypass) {
                                AppLogger.auth('✅ Detected device selection page, navigating to main app...');

                                // Show overlay to hide the device selection page
                                setState(() {
                                  _showOverlay = true;
                                });

                                await Future.delayed(const Duration(milliseconds: 500));
                                await controller.loadUrl(urlRequest: URLRequest(
                                  url: WebUri('https://open.spotify.com'),
                                ));
                              }
                            }
                          } catch (e) {
                            AppLogger.error('Error detecting device selection page', e);
                          }
                          */

                          // Additional check: inspect page content to ensure we're not blocking login forms
                          if (!newShowOverlay) {
                            await _checkForLoginFormPresence(controller);
                          }
                        },                        onReceivedError: (controller, request, error) {
                          setState(() {
                            _error = 'Failed to load page: ${error.description}';
                            _isLoading = false;
                          });
                        },                        onConsoleMessage: (controller, consoleMessage) {
                          // Filter out CSP and Google Analytics related console messages to reduce noise
                          final message = consoleMessage.message.toLowerCase();
                          if (message.contains('content security policy') ||
                              message.contains('googletagmanager') ||
                              message.contains('refused to execute inline script') ||
                              message.contains('google-analytics') ||
                              message.contains('gtm.js') ||
                              message.contains('violates the following content security policy') ||
                              message.contains('unsafe-inline') ||
                              message.contains('unsafe-eval') ||
                              message.contains('sha256-') ||
                              message.contains('nonce-') ||
                              message.contains('pixel.js') ||
                              message.contains('analytics.twitter.com') ||
                              message.contains('connect.facebook.net') ||
                              message.contains('www.googleadservices.com') ||
                              message.contains('analytics.tiktok.com') ||
                              message.contains('redditstatic.com') ||
                              message.contains('contentsquare.net') ||
                              message.contains('microsoft.com') ||
                              message.contains('scorecardresearch.com') ||
                              message.contains('cookielaw.org') ||
                              message.contains('onetrust.com') ||
                              message.contains('hotjar.com') ||
                              message.contains('ravenjs.com') ||
                              message.contains('gstatic.com') ||
                              message.contains('recaptcha') ||
                              message.contains('spotifycdn.com') ||
                              message.contains('fastly-insights.com') ||
                              message.contains('orb') ||
                              message.contains('opaque response') ||
                              message.contains('net::err_blocked') ||
                              message.contains('blocked by response') ||
                              message.contains('blocked by client') ||
                              message.contains('polling check')) {
                            // Silently ignore CSP violations and analytics/tracking errors
                            return;
                          }
                          
                          // Only log other console messages for debugging
                          AppLogger.debug('WebView Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
                        },
                      ),
                      
                      // Loading overlay from the beginning until login page is reached
                      if (_showOverlay)
                        Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Logging you in...',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Please wait while we complete your authentication',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 179), // 0.7 * 255 ≈ 179
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 32),
                                // Spotify branding with theme-aware colors
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 38), // 0.15 * 255 ≈ 38
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.music_note,
                                        color: Colors.green,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Connecting to Spotify',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),                    ],
                  ),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _setupNetworkInterception(InAppWebViewController controller, WebUri url) async {
    try {
      AppLogger.auth('Setting up network interception for Bearer token capture...');
      
      // Get all cookies for building complete header context
      final cookies = await CookieManager.instance().getCookies(url: url);
      final cookieString = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
      
      AppLogger.debug('Found ${cookies.length} cookies');
      AppLogger.debug('Initial cookie string: ${cookieString.isNotEmpty ? _truncate(cookieString, 100) : 'EMPTY'}');
      AppLogger.debug('Cookie names: ${cookies.map((c) => c.name).join(', ')}');
      
      // Check if sp_dc cookie is present
      bool hasSpDc = cookies.any((cookie) => cookie.name == 'sp_dc');
      AppLogger.debug('sp_dc cookie present in initial request: $hasSpDc');
      
      // Log sp_dc detection
      if (hasSpDc) {
        AppLogger.auth('sp_dc detected');
      }
      
      // Build headers that will be saved and reused
      _extractedHeaders = {
        'Cookie': cookieString,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'DNT': '1',
        'Connection': 'keep-alive',
        'sec-ch-ua': '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'no-cors',
        'sec-fetch-site': 'same-site',
        'Upgrade-Insecure-Requests': '1',
      };
      
      AppLogger.debug('Initial _extractedHeaders Cookie: ${_extractedHeaders['Cookie']?.isNotEmpty == true ? _truncate(_extractedHeaders['Cookie'], 100) : 'EMPTY'}');
      
      // Set up network request interception
      await _interceptTokenRequests(controller);
      
    } catch (e) {
      AppLogger.error('Failed to setup network interception', e);
      setState(() {
        _error = 'Failed to setup authentication monitoring: $e';
      });
    }
  }

  /// Directly fetches access token from Spotify's API using native HTTP client
  /// This bypasses WebView JavaScript limitations and CORS issues
  Future<void> _tryDirectTokenFetch(InAppWebViewController controller) async {
    try {
      AppLogger.auth('🔧 _tryDirectTokenFetch called');
      AppLogger.auth('   - Trigger: ${_directTokenFetchAttempted ? "Polling loop (alternative)" : "onLoadStop (primary)"}');
      AppLogger.auth('   - _isPollingActive: $_isPollingActive');
      AppLogger.auth('   - mounted: $mounted');

      // Get current URL for cookie extraction
      final currentUrl = await controller.getUrl();
      if (currentUrl == null) {
        AppLogger.auth('❌ No current URL for cookie extraction');
        return;
      }
      AppLogger.auth('   - Current URL: $currentUrl');

      // Get all cookies from CookieManager
      final cookies = await CookieManager.instance().getCookies(url: currentUrl);
      AppLogger.auth('📊 Found ${cookies.length} cookies for direct token fetch');
      AppLogger.debug('   - Cookie names: ${cookies.map((c) => c.name).join(', ')}');

      // Find the sp_dc cookie
      final spDcCookie = cookies.firstWhere(
        (cookie) => cookie.name == 'sp_dc',
        orElse: () => Cookie(name: '', value: ''),
      );

      if (spDcCookie.name.isEmpty || spDcCookie.value.isEmpty) {
        AppLogger.auth('❌ No sp_dc cookie found for direct token fetch');
        AppLogger.auth('   - Cannot proceed without sp_dc cookie');
        return;
      }

      AppLogger.auth('✅ sp_dc cookie found: ${_truncate(spDcCookie.value, 20)}');

      // Try WebView-based fetch first (more reliable as it uses the browser's context)
      AppLogger.auth('🌐 Attempting WebView-based token fetch...');
      String? accessToken = await _fetchAccessTokenViaWebView(controller);

      // Fallback to native HTTP request if WebView fetch fails
      if (accessToken == null || accessToken.isEmpty) {
        AppLogger.auth('⚠️ WebView fetch failed or returned empty, trying native HTTP request as fallback...');
        accessToken = await _fetchAccessTokenNative(spDcCookie.value);
      } else {
        AppLogger.auth('✅ WebView fetch succeeded!');
      }

      if (accessToken != null && accessToken.isNotEmpty) {
        AppLogger.auth('🎉 Successfully got access token: ${_truncate(accessToken, 20)}');
        AppLogger.auth('   - Token length: ${accessToken.length} characters');

        // Update extracted headers with current cookies
        final cookieString = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
        _extractedHeaders['Cookie'] = cookieString;

        // Cancel timers since we got the token
        _isPollingActive = false;
        _pollingTimer?.cancel();
        _directTokenFetchTimer?.cancel();
        AppLogger.auth('⏹️ Timers cancelled after successful token fetch');

        // Complete auth with the fetched token
        if (mounted) {
          await widget.onAuthComplete(accessToken, _extractedHeaders);

          await Future.delayed(const Duration(milliseconds: 500));

          if (mounted && Navigator.canPop(context)) {
            AppLogger.auth('Closing WebView after successful direct token fetch');
            Navigator.of(context).pop();
          }
        }
      } else {
        AppLogger.auth('❌ Direct token fetch did not return a valid token');
        AppLogger.auth('   - accessToken was null or empty');
      }
    } catch (e) {
      AppLogger.error('💥 Error in direct token fetch', e);
      AppLogger.auth('   - Exception: ${e.toString()}');
    }
  }

  /// Fetches access token using WebView's JavaScript context via fetch()
  /// This approach has the proper cookies and browser fingerprinting since it runs within the authenticated WebView
  Future<String?> _fetchAccessTokenViaWebView(InAppWebViewController controller) async {
    try {
      AppLogger.auth('Fetching access token via WebView JavaScript...');

      // Execute JavaScript fetch within the WebView's context
      final result = await controller.evaluateJavascript(source: '''
        (async function() {
          try {
            console.log('[Spotify Token Fetch] Starting fetch request...');
            // Try new endpoint first (2025 change), fallback to old endpoint
            const tokenUrl = 'https://open.spotify.com/api/token';
            const response = await fetch(tokenUrl, {
              method: 'GET',
              credentials: 'include', // Include cookies automatically
              headers: {
                'Accept': 'application/json',
                'App-Platform': 'WebPlayer'
              }
            });

            console.log('[Spotify Token Fetch] Response status:', response.status);
            console.log('[Spotify Token Fetch] Response ok:', response.ok);

            if (!response.ok) {
              console.error('[Spotify Token Fetch] HTTP Error:', response.status, response.statusText);
              return JSON.stringify({ error: 'HTTP ' + response.status, status: response.status });
            }

            const data = await response.json();
            console.log('[Spotify Token Fetch] Response data keys:', Object.keys(data));
            console.log('[Spotify Token Fetch] Has accessToken:', 'accessToken' in data);
            console.log('[Spotify Token Fetch] Has AnonymousToken:', 'AnonymousToken' in data);
            console.log('[Spotify Token Fetch] accessToken value:', data.accessToken);
            console.log('[Spotify Token Fetch] Full response:', JSON.stringify(data));

            // Check for different token field names
            const token = data.accessToken || data.AnonymousToken || data.token;

            if (!token) {
              console.error('[Spotify Token Fetch] No token found in response');
              return JSON.stringify({
                error: 'No token in response',
                keys: Object.keys(data),
                hasAccessToken: 'accessToken' in data,
                hasAnonymousToken: 'AnonymousToken' in data
              });
            }

            return JSON.stringify({ success: true, token: token, allKeys: Object.keys(data) });
          } catch (error) {
            console.error('[Spotify Token Fetch] Exception:', error.toString());
            console.error('[Spotify Token Fetch] Stack:', error.stack);
            return JSON.stringify({ error: error.toString(), errorType: error.name });
          }
        })()
      ''');

      // Log the raw result from JavaScript
      AppLogger.auth('Raw JavaScript result: $result');

      if (result == null || result is! String) {
        AppLogger.auth('WebView fetch returned null or invalid result');
        return null;
      }

      // Parse the JSON response from JavaScript
      AppLogger.auth('Parsing JSON result...');
      final jsonData = convert.jsonDecode(result);
      AppLogger.auth('Parsed JSON data: $jsonData');

      if (jsonData is Map) {
        if (jsonData['error'] != null) {
          AppLogger.auth('WebView fetch returned error: ${jsonData['error']}');
          if (jsonData['keys'] != null) {
            AppLogger.auth('Response keys available: ${jsonData['keys']}');
          }
          if (jsonData['hasAccessToken'] != null) {
            AppLogger.auth('Has accessToken field: ${jsonData['hasAccessToken']}');
          }
          if (jsonData['hasAnonymousToken'] != null) {
            AppLogger.auth('Has AnonymousToken field: ${jsonData['hasAnonymousToken']}');
          }
          return null;
        }

        AppLogger.auth('Response successful, all keys: ${jsonData['allKeys']}');
        final token = jsonData['token'] as String?;
        AppLogger.auth('Extracted token: $token');

        if (token != null && token.isNotEmpty) {
          AppLogger.auth('✅ Successfully got token via WebView fetch: ${_truncate(token, 20)}');
          return token;
        }
      }

      AppLogger.auth('WebView fetch did not return valid token data');
      AppLogger.auth('Final jsonData type: ${jsonData.runtimeType}');
      return null;
    } catch (e) {
      AppLogger.error('Error fetching token via WebView', e);
      return null;
    }
  }

  /// Makes a native HTTP request to Spotify's token endpoint to get an access token
  /// This bypasses WebView JavaScript context and CORS limitations
  Future<String?> _fetchAccessTokenNative(String spDcCookie) async {
    io.HttpClient client = io.HttpClient();
    try {
      AppLogger.auth('Making native HTTP request to Spotify token endpoint...');

      // Set up request with proper headers
      // Note: Spotify changed endpoint from get_access_token to api/token in 2025
      final request = await client.getUrl(Uri.parse(
        'https://open.spotify.com/api/token'
      ));

      // Set required headers
      request.headers.set('Cookie', 'sp_dc=$spDcCookie');
      request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36');
      request.headers.set('Accept', 'application/json');
      request.headers.set('App-Platform', 'WebPlayer');
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Referer', 'https://open.spotify.com/');
      request.headers.set('Origin', 'https://open.spotify.com');

      // Get response
      final response = await request.close();

      // Read response body
      final responseBody = await response.transform(convert.utf8.decoder).join();

      AppLogger.auth('Token endpoint response status: ${response.statusCode}');
      AppLogger.auth('Token endpoint response body: ${_truncate(responseBody, 300)}');

      if (response.statusCode == io.HttpStatus.ok) {
        try {
          final jsonData = convert.jsonDecode(responseBody);
          if (jsonData is Map && jsonData['accessToken'] != null) {
            return jsonData['accessToken'] as String;
          } else {
            AppLogger.auth('Response did not contain accessToken: ${_truncate(responseBody, 200)}');
          }
        } catch (e) {
          AppLogger.error('Error parsing token JSON response', e);
        }
      } else {
        AppLogger.auth('Token endpoint returned status ${response.statusCode}: ${response.reasonPhrase}');
      }
    } catch (e) {
      AppLogger.error('Native HTTP request to token endpoint failed', e);
    } finally {
      client.close();
    }
    return null;
  }

  Future<void> _interceptTokenRequests(InAppWebViewController controller) async {
    try {
      AppLogger.auth('Setting up network request interception...');
      
             final interceptScript = '''
         (function() {
           console.log('🕸️ Setting up Authorization header interception for all requests...');
           
           // Intercept fetch requests
           const originalFetch = window.fetch;
           window.fetch = function(...args) {
             const url = args[0];
             const options = args[1] || {};
             const headers = options.headers || {};
             
             // Check for Authorization header in any request
             let authHeader = null;
             let cookieHeader = null;
             
             if (headers) {
               // Handle different header formats
               if (typeof headers.get === 'function') {
                 authHeader = headers.get('Authorization') || headers.get('authorization');
                 cookieHeader = headers.get('Cookie') || headers.get('cookie');
               } else if (typeof headers === 'object') {
                 authHeader = headers['Authorization'] || headers['authorization'] || 
                             headers['AUTHORIZATION'] || headers['Auth'];
                 cookieHeader = headers['Cookie'] || headers['cookie'] || headers['COOKIE'];
               }
             }
             
             if (authHeader && authHeader.startsWith('Bearer ') && !window.capturedBearerToken) {
               const token = authHeader.substring(7);
               if (token.length > 100) { // Valid Spotify tokens are quite long
                 console.log('✅ Found Bearer token in fetch request:', token.substring(0, 20) + '...');
                 console.log('🎯 Request URL:', url);
                 
                 // Also capture the cookie from the same request
                 const requestCookie = cookieHeader || document.cookie;
                 console.log('🍪 Found Cookie in same request:', requestCookie ? requestCookie.substring(0, 50) + '...' : 'none');
                 console.log('🍪 Document.cookie fallback:', document.cookie ? document.cookie.substring(0, 50) + '...' : 'none');
                 
                 // Store the token and cookie globally so Flutter can access it
                 window.capturedBearerToken = token;
                 window.capturedCookie = requestCookie || document.cookie || '';
                 
                 // Additional logging for debugging
                 console.log('🔧 Final stored cookie:', window.capturedCookie ? window.capturedCookie.substring(0, 50) + '...' : 'EMPTY');
                 window.capturedTokenData = { 
                   accessToken: token, 
                   cookie: window.capturedCookie,
                   source: 'fetch_header' 
                 };
                 
                 // Trigger a custom event that Flutter can listen for
                 window.dispatchEvent(new CustomEvent('spotifyTokenCaptured', {
                   detail: { 
                     token: token, 
                     cookie: window.capturedCookie,
                     source: 'fetch_header' 
                   }
                 }));
               }
             }
             
             return originalFetch.apply(this, args);
           };
           
           // Intercept XMLHttpRequest
           const originalXHROpen = XMLHttpRequest.prototype.open;
           const originalXHRSend = XMLHttpRequest.prototype.send;
           const originalXHRSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
           
           // Track headers being set on XHR requests
           XMLHttpRequest.prototype._headers = {};
           
           XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
             // Store header for later use
             this._headers[name.toLowerCase()] = value;
             
             // Capture Authorization headers from XHR requests
             if (name.toLowerCase() === 'authorization' && value.startsWith('Bearer ') && !window.capturedBearerToken) {
               const token = value.substring(7);
               if (token.length > 100) {
                 console.log('✅ Found Bearer token in XHR header:', token.substring(0, 20) + '...');
                 console.log('🎯 Request URL:', this._interceptedUrl || 'unknown');
                 
                 // Get cookie from the same request or document
                 const requestCookie = this._headers['cookie'] || document.cookie;
                 console.log('🍪 Found Cookie in same XHR request:', requestCookie ? requestCookie.substring(0, 50) + '...' : 'none');
                 console.log('🍪 Document.cookie fallback:', document.cookie ? document.cookie.substring(0, 50) + '...' : 'none');
                 
                 window.capturedBearerToken = token;
                 window.capturedCookie = requestCookie || '';
                 
                 // Additional logging for debugging
                 console.log('🔧 Final stored cookie:', window.capturedCookie ? window.capturedCookie.substring(0, 50) + '...' : 'EMPTY');
                 window.capturedTokenData = { 
                   accessToken: token, 
                   cookie: requestCookie,
                   source: 'xhr_header' 
                 };
                 
                 window.dispatchEvent(new CustomEvent('spotifyTokenCaptured', {
                   detail: { 
                     token: token, 
                     cookie: requestCookie,
                     source: 'xhr_header' 
                   }
                 }));
               }
             }
             
             return originalXHRSetRequestHeader.call(this, name, value);
           };
           
           XMLHttpRequest.prototype.open = function(method, url, ...args) {
             this._interceptedUrl = url;
             this._headers = {}; // Reset headers for new request
             return originalXHROpen.call(this, method, url, ...args);
           };
           
           // Also check for tokens in cookies periodically and monitor sp_dc
           let cookieCheckInterval = setInterval(function() {
             const currentCookies = document.cookie;
             
             // Always update the captured cookie if sp_dc is found (even without token)
             if (currentCookies.includes('sp_dc=') && (!window.capturedCookie || !window.capturedCookie.includes('sp_dc='))) {
               console.log('🍪 Found sp_dc cookie, updating captured cookie');
               window.capturedCookie = currentCookies;
               
               // Trigger an event to notify Flutter about cookie update
               window.dispatchEvent(new CustomEvent('spotifyCookieUpdated', {
                 detail: { 
                   cookie: currentCookies,
                   source: 'sp_dc_found' 
                 }
               }));
             }
             
             if (window.capturedBearerToken) {
               clearInterval(cookieCheckInterval);
               return;
            }
             
             // Look for tokens in cookies (sometimes Spotify stores them there)
             const cookies = document.cookie.split(';');
             for (let cookie of cookies) {
               const [name, value] = cookie.trim().split('=');
               if (value && value.length > 100 && 
                   (name.includes('token') || name.includes('auth') || name.includes('bearer'))) {
                 console.log('✅ Found potential token in cookie:', name, value.substring(0, 20) + '...');
                 
                 window.capturedBearerToken = value;
                 window.capturedCookie = document.cookie;
                 window.capturedTokenData = { 
                   accessToken: value, 
                   cookie: document.cookie,
                   source: 'cookie_' + name 
                 };
                 
                 window.dispatchEvent(new CustomEvent('spotifyTokenCaptured', {
                   detail: { 
                     token: value, 
                     cookie: document.cookie,
                     source: 'cookie_' + name 
                   }
                 }));
                 break;
               }
             }
           }, 1000);
           
           // Stop cookie checking after 30 seconds
           setTimeout(() => {
             clearInterval(cookieCheckInterval);
           }, 30000);
           
           // Intercept WebSocket connections (often contain tokens in URL)
           const originalWebSocket = window.WebSocket;
           window.WebSocket = function(url, protocols) {
             console.log('🔌 WebSocket connection detected:', url);
             
             // Check if URL contains access_token parameter
             if (url.includes('access_token=') && !window.capturedBearerToken) {
               try {
                 const urlObj = new URL(url);
                 const accessToken = urlObj.searchParams.get('access_token');
                 
                 if (accessToken && accessToken.length > 100) {
                   console.log('✅ Found Bearer token in WebSocket URL:', accessToken.substring(0, 20) + '...');
                   console.log('🎯 WebSocket URL:', url.substring(0, 100) + '...');
                   
                   // Get current cookies from document
                   const currentCookie = document.cookie;
                   console.log('🍪 Current document cookies:', currentCookie ? currentCookie.substring(0, 50) + '...' : 'none');
                   
                   window.capturedBearerToken = accessToken;
                   window.capturedCookie = currentCookie || '';
                   
                   // Additional logging for debugging
                   console.log('🔧 Final stored cookie from WebSocket:', window.capturedCookie ? window.capturedCookie.substring(0, 50) + '...' : 'EMPTY');
                   window.capturedTokenData = { 
                     accessToken: accessToken, 
                     cookie: currentCookie,
                     source: 'websocket_url' 
                   };
                   
                   window.dispatchEvent(new CustomEvent('spotifyTokenCaptured', {
                     detail: { 
                       token: accessToken, 
                       cookie: currentCookie,
                       source: 'websocket_url' 
                     }
                   }));
                 }
               } catch (e) {
                 console.log('❌ Error parsing WebSocket URL:', e);
               }
             }
             
             return new originalWebSocket(url, protocols);
           };
           
           // Copy static properties to maintain compatibility
           Object.setPrototypeOf(window.WebSocket, originalWebSocket);
           Object.defineProperty(window.WebSocket, 'prototype', {
             value: originalWebSocket.prototype,
             writable: false
           });
           
           console.log('✅ Authorization header and WebSocket interception setup complete');
           return true;
         })();
      ''';
      
      await controller.evaluateJavascript(source: interceptScript);
      AppLogger.auth('Network interception script injected');
      
      // Set up periodic checking for captured tokens
      _startTokenPolling(controller);
      
    } catch (e) {
      AppLogger.error('Error setting up network interception', e);
    }
  }

  void _startTokenPolling(InAppWebViewController controller) {
    _isPollingActive = true;
    AppLogger.auth('Starting token polling...');

    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted || !_isPollingActive) {
        timer.cancel();
        return;
      }

      // Check if current URL is still on Spotify domain
      try {
        final currentUrl = await controller.getUrl();
        if (currentUrl != null) {
          Uri uri = Uri.parse(currentUrl.toString());
          bool isSpotifyDomain = uri.host.endsWith('spotify.com');

          if (!isSpotifyDomain) {
            return; // Skip this polling cycle
          }
        }
      } catch (e) {
        // WebView disposed - stop polling
        if (e.toString().contains('MissingPluginException')) {
          _isPollingActive = false;
          timer.cancel();
          return;
        }
      }

      try {
        final result = await controller.evaluateJavascript(source: '''
          (function() {
            console.log('🔍 Polling check - capturedBearerToken:', window.capturedBearerToken ? 'EXISTS' : 'null');
            console.log('🔍 Polling check - capturedCookie:', window.capturedCookie ? window.capturedCookie.substring(0, 50) + '...' : 'null');
            
            // Check if we have an updated cookie with sp_dc even without token
            if (window.capturedCookie && window.capturedCookie.includes('sp_dc=')) {
              console.log('🍪 Found sp_dc in captured cookie, updating Flutter headers');
            }
            
            if (window.capturedBearerToken) {
              const token = window.capturedBearerToken;
              const cookie = window.capturedCookie;
              const data = window.capturedTokenData;
              
              console.log('✅ Returning captured data to Flutter');
              console.log('   - token length:', token ? token.length : 0);
              console.log('   - cookie length:', cookie ? cookie.length : 0);
              
              // Clear the captured token to prevent duplicate processing
              delete window.capturedBearerToken;
              delete window.capturedCookie;
              delete window.capturedTokenData;
              
              return { token: token, cookie: cookie, data: data };
            }
            
            // Return cookie updates even without token for sp_dc monitoring
            if (window.capturedCookie && window.capturedCookie.includes('sp_dc=')) {
              const cookie = window.capturedCookie;
              console.log('🍪 Returning cookie update with sp_dc to Flutter');
              
              // Don't clear the cookie, keep it for when we get the token
              return { token: null, cookie: cookie, data: { source: 'sp_dc_update' } };
            }
            
            return null;
          })();
        ''');
        
        // Also check for sp_dc cookie updates even if no token yet
        await _checkForSpDcCookie(controller);
        
        AppLogger.debug('Polling result: ${result != null ? 'DATA FOUND' : 'null'}');
        
        if (result != null) {
          final Map<String, dynamic> tokenInfo = Map<String, dynamic>.from(result);
          final bearerToken = tokenInfo['token'] as String?;
          final capturedCookie = tokenInfo['cookie'] as String?;
          
          AppLogger.debug('Parsed result:');
          AppLogger.debug('   - bearerToken: ${bearerToken != null ? 'EXISTS (${bearerToken.length} chars)' : 'null'}');
          AppLogger.debug('   - capturedCookie: ${capturedCookie != null ? 'EXISTS (${capturedCookie.length} chars)' : 'null'}');
          
          // Handle cookie updates (even without token)
          if (capturedCookie != null && capturedCookie.isNotEmpty) {
            bool hadSpDcBefore = (_extractedHeaders['Cookie'] ?? '').contains('sp_dc=');
            bool hasSpDcNow = capturedCookie.contains('sp_dc=');
            
            if (!hadSpDcBefore && hasSpDcNow) {
              AppLogger.auth('Found new sp_dc cookie! Updating headers...');
              _extractedHeaders['Cookie'] = capturedCookie;
              AppLogger.auth('Updated headers with sp_dc cookie');
              AppLogger.debug('New cookie header: ${_truncate(capturedCookie, 100)}');
              
              AppLogger.auth('sp_dc detected in cookie update');
            } else if (hasSpDcNow) {
              // Update with latest cookie info
              _extractedHeaders['Cookie'] = capturedCookie;
            }
          }
          
          if (bearerToken != null && bearerToken.isNotEmpty) {
            AppLogger.auth('Token polling found complete result!');

            AppLogger.auth('Successfully captured Bearer token: ${_truncate(bearerToken, 20)}');
            AppLogger.debug('Token length: ${bearerToken.length} characters');
            AppLogger.debug('Final captured cookie: ${_truncate(capturedCookie, 50)}');
            AppLogger.debug('Token data: ${tokenInfo['data']}');
            
            AppLogger.auth('Bearer token found');
            
            // Navigate to user profile page to capture client-token
            AppLogger.auth('Navigating to user profile page to capture client-token...');
            await controller.loadUrl(urlRequest: URLRequest(
              url: WebUri('https://open.spotify.com/user/21fvdxlt6ejvha6jnrgdwamja'),
              headers: {
                'Authorization': 'Bearer $bearerToken',
                'Cookie': _extractedHeaders['Cookie'] ?? '',
              },
            ));

            // Add additional client-token interception
            await controller.evaluateJavascript(source: '''
              (function() {
                console.log('🔍 Setting up client-token interception...');
                
                // Function to check headers for client-token
                function checkForClientToken(headers) {
                  if (!headers) return null;
                  
                  // Handle different header formats
                  let clientToken = null;
                  if (typeof headers.get === 'function') {
                    clientToken = headers.get('client-token');
                  } else if (typeof headers === 'object') {
                    clientToken = headers['client-token'] || headers['Client-Token'];
                  }
                  
                  if (clientToken && !window.capturedClientToken) {
                    console.log('✅ Found client-token:', clientToken.substring(0, 20) + '...');
                    window.capturedClientToken = clientToken;
                    window.dispatchEvent(new CustomEvent('spotifyClientTokenCaptured', {
                      detail: { clientToken: clientToken }
                    }));
                  }
                  return clientToken;
                }
                
                // Intercept fetch requests for client-token
                const originalFetch = window.fetch;
                window.fetch = function(...args) {
                  const options = args[1] || {};
                  checkForClientToken(options.headers);
                  return originalFetch.apply(this, args);
                };
                
                // Intercept XHR for client-token
                const originalXHRSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
                XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
                  if (name.toLowerCase() === 'client-token') {
                    checkForClientToken({ 'client-token': value });
                  }
                  return originalXHRSetRequestHeader.call(this, name, value);
                };
                
                console.log('✅ Client-token interception setup complete');
              })();
            ''');

            // Start polling for client-token
            bool clientTokenFound = false;
            int attempts = 0;
            while (!clientTokenFound && attempts < 30) {
              final clientTokenResult = await controller.evaluateJavascript(source: '''
                window.capturedClientToken || null;
              ''');
              
              if (clientTokenResult != null) {
                AppLogger.auth('Client token captured: ${_truncate(clientTokenResult.toString(), 20)}');
                _extractedHeaders['client-token'] = clientTokenResult.toString();
                clientTokenFound = true;
              } else {
                attempts++;
                await Future.delayed(const Duration(milliseconds: 500));
              }
            }

            // Complete authentication with both tokens
            if (mounted) {
              AppLogger.auth('Calling onAuthComplete with Bearer token and updated headers (including client-token)...');
              AppLogger.debug('Final headers: ${_extractedHeaders.keys.join(', ')}');
              
              try {
                await widget.onAuthComplete(bearerToken, _extractedHeaders);
                AppLogger.auth('onAuthComplete callback executed successfully');
                
                await Future.delayed(const Duration(milliseconds: 500));
                
                if (mounted && Navigator.canPop(context)) {
                  AppLogger.auth('Closing WebView after successful authentication');
                  Navigator.of(context).pop();
                }
              } catch (e) {
                AppLogger.error('Error in onAuthComplete callback', e);
                if (mounted) {
                  String errorMessage = e.toString();
                  if (errorMessage.contains('Authentication verification failed after completion')) {
                    errorMessage = 'Authentication took too long to complete. Please try again or check your internet connection.';
                  }
                  setState(() {
                    _error = 'Authentication failed: $errorMessage';
                  });
                }
              }
            }

            timer.cancel();
          } else {
            AppLogger.debug('Cookie update received (no token yet)');
          }
        } else {
          // Only log every 5 seconds to reduce spam
          if (DateTime.now().millisecondsSinceEpoch % 5000 < 1000) {
            AppLogger.debug('No token data found yet...');
          }
        }
      } catch (e) {
        // WebView disposed - stop polling silently
        if (e.toString().contains('MissingPluginException')) {
          _isPollingActive = false;
          timer.cancel();
          return;
        }
        // Only log other errors occasionally to reduce spam
        if (DateTime.now().millisecondsSinceEpoch % 10000 < 1000) {
          AppLogger.error('Error checking for captured token', e);
        }
      }
    });

    // Set a timeout to stop polling after 120 seconds (increased from 60)
    Timer(const Duration(seconds: 120), () {
      _isPollingActive = false;
      _pollingTimer?.cancel();
      AppLogger.auth('Token polling timeout after 120 seconds - stopping...');
    });
  }

  Future<void> _checkForSpDcCookie(InAppWebViewController controller) async {
    try {
      // Check if we already have sp_dc in our headers
      final currentCookie = _extractedHeaders['Cookie'] ?? '';
      if (currentCookie.contains('sp_dc=')) {
        return; // Already have sp_dc, no need to check again
      }

      // Get current cookies from the browser
      final currentUrl = await controller.getUrl();
      if (currentUrl != null) {
        final cookies = await CookieManager.instance().getCookies(url: currentUrl);
        final spDcCookie = cookies.firstWhere(
          (cookie) => cookie.name == 'sp_dc',
          orElse: () => Cookie(name: '', value: ''),
        );

        if (spDcCookie.name.isNotEmpty && spDcCookie.value.isNotEmpty) {
          AppLogger.auth('Found sp_dc cookie: ${_truncate(spDcCookie.value, 20)}');

          AppLogger.auth('sp_dc detected in cookie check');

          // Update the cookie string in headers with the complete set including sp_dc
          final allCookies = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
          _extractedHeaders['Cookie'] = allCookies;

          AppLogger.auth('Updated headers with sp_dc cookie');
          AppLogger.debug('New cookie header: ${_truncate(allCookies, 100)}');

          // ALTERNATIVE TOKEN FETCH TRIGGER: Try to fetch token when sp_dc is found in polling
          // This provides an additional path to token acquisition beyond onLoadStop
          if (!_directTokenFetchAttempted && _isPollingActive) {
            _directTokenFetchAttempted = true;
            AppLogger.auth('🎯 Alternative trigger: sp_dc found in polling, attempting direct token fetch...');
            AppLogger.auth('   - _directTokenFetchAttempted flag set to prevent duplicates');

            // Delay slightly to ensure cookies are fully set
            await Future.delayed(const Duration(milliseconds: 500));

            if (mounted && _isPollingActive) {
              AppLogger.auth('⚡ Executing alternative direct token fetch from polling loop...');
              await _tryDirectTokenFetch(controller);
            } else {
              AppLogger.auth('⚠️ Alternative fetch skipped - mounted=$mounted, _isPollingActive=$_isPollingActive');
            }
          } else if (_directTokenFetchAttempted) {
            AppLogger.debug('ℹ️ sp_dc found but direct token fetch already attempted, skipping');
          }
        }
      }
    } catch (e) {
      AppLogger.error('Error checking for sp_dc cookie', e);
    }
  }

  Future<void> _checkForLoginFormPresence(InAppWebViewController controller) async {
    try {
      // Check if the page actually contains login form elements
      final hasLoginForm = await controller.evaluateJavascript(source: '''
        (function() {
          // Look for common login form indicators
          const loginSelectors = [
            'input[type="email"]',
            'input[type="password"]',
            'input[name="username"]',
            'input[name="password"]',
            'input[id*="login"]',
            'input[id*="email"]',
            'input[id*="password"]',
            'form[action*="login"]',
            'button[type="submit"]',
            '[data-testid*="login"]',
            '.login-form',
            '#login-form'
          ];

          for (const selector of loginSelectors) {
            if (document.querySelector(selector)) {
              console.log('Found login form element:', selector);
              return true;
            }
          }

          // Check for specific Spotify login text
          const bodyText = document.body.textContent || '';
          const hasLoginText = bodyText.includes('Log in to Spotify') ||
                              bodyText.includes('Sign up') ||
                              bodyText.includes('Continue with') ||
                              bodyText.includes('Email or username');

          if (hasLoginText) {
            console.log('Found login-related text content');
            return true;
          }

          return false;
        })();
      ''');

      if (hasLoginForm == true) {
        AppLogger.debug('Login form detected on page - ensuring overlay is hidden');
        if (mounted) {
          setState(() {
            _showOverlay = false;
          });
        }
      }
    } catch (e) {
      AppLogger.error('Error checking for login form presence', e);
    }
  }
}