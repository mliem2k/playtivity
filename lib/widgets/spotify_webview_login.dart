import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/app_logger.dart';
import '../services/spotify_token_service.dart';

class SpotifyWebViewLogin extends StatefulWidget {
  final Future<void> Function(String bearerToken, Map<String, String> headers) onAuthComplete;
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
  bool _completed = false;
  bool _processingAuth = false;
  bool _capturing = false;
  String _processingStep = '';
  InAppWebViewController? _webViewController;
  Timer? _cookieRetryTimer;
  int _cookieRetryCount = 0;
  static const int _maxCookieRetries = 8;
  WebUri? _pendingCaptureUrl;

  @override
  void dispose() {
    _cookieRetryTimer?.cancel();
    super.dispose();
  }

  void _scheduleCookieRetry(WebUri url) {
    _cookieRetryTimer?.cancel();
    _pendingCaptureUrl = url;
    _cookieRetryCount = 0;
    _cookieRetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_completed || !mounted) {
        _cookieRetryTimer?.cancel();
        return;
      }
      _cookieRetryCount++;
      AppLogger.auth('sp_dc retry $_cookieRetryCount/$_maxCookieRetries...');
      _attemptTokenCapture(_pendingCaptureUrl!);
      if (_cookieRetryCount >= _maxCookieRetries) {
        _cookieRetryTimer?.cancel();
        if (mounted && !_completed) {
          setState(() {
            _processingAuth = false;
            _error = 'Login timed out. Please try again.';
          });
        }
      }
    });
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
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _InfoBanner(
                  primaryColor: Theme.of(context).primaryColor,
                  surfaceColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                if (_error != null)
                  _ErrorBanner(
                    error: _error!,
                    onRetry: () => setState(() => _error = null),
                  ),
                Expanded(
                  child: Visibility(
                    visible: !_processingAuth,
                    maintainState: true,
                    maintainSize: true,
                    maintainAnimation: true,
                    child: InAppWebView(
                    initialSettings: InAppWebViewSettings(
                      userAgent: SpotifyTokenService.userAgent,
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      supportZoom: false,
                    ),
                    initialUrlRequest: URLRequest(
                      url: WebUri(
                        'https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F',
                      ),
                    ),
                    onWebViewCreated: (c) => _webViewController = c,
                    onLoadStart: (_, _) => setState(() {
                      _isLoading = true;
                      _error = null;
                    }),
                    onLoadStop: (controller, url) async {
                      setState(() => _isLoading = false);
                      if (_completed || url == null) {
                        return;
                      }
                      final urlStr = url.toString();
                      if (!urlStr.contains('open.spotify.com')) {
                        return;
                      }
                      if (urlStr.contains('/login') ||
                          urlStr.contains('/auth') ||
                          urlStr.contains('/challenge') ||
                          urlStr.contains('/error')) {
                        return;
                      }
                      await _attemptTokenCapture(url);
                    },
                    onReceivedError: (_, _, error) => setState(() {
                      _error = 'Failed to load page: ${error.description}';
                      _isLoading = false;
                    }),
                  ),
                  ),
                ),
              ],
            ),
            if (_processingAuth)
              _AuthProcessingOverlay(
                step: _processingStep,
                onCancel: () {
                  _cookieRetryTimer?.cancel();
                  _capturing = false;
                  if (mounted) setState(() { _processingAuth = false; _completed = false; });
                  if (widget.onCancel != null) {
                    widget.onCancel!();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _attemptTokenCapture(WebUri url) async {
    if (_capturing) return;
    _capturing = true;
    if (mounted) setState(() { _processingAuth = true; _processingStep = 'Verifying session...'; });
    try {
      final cookies = await CookieManager.instance().getCookies(url: url);
      final spDcCookie = cookies.firstWhere(
        (c) => c.name == 'sp_dc' && c.value.isNotEmpty,
        orElse: () => Cookie(name: '', value: ''),
      );
      if (spDcCookie.name.isEmpty) {
        // sp_dc not yet in cookie store — Spotify SPA may not have committed it yet.
        // Schedule retries so we don't silently give up after the first onLoadStop.
        _capturing = false;
        if (mounted) setState(() => _processingAuth = false);
        if (_cookieRetryTimer == null || !_cookieRetryTimer!.isActive) {
          _scheduleCookieRetry(url);
        }
        return;
      }
      _cookieRetryTimer?.cancel();

      if (mounted) setState(() => _processingStep = 'Fetching access token...');
      AppLogger.auth('sp_dc found — fetching Bearer token...');
      final token = await SpotifyTokenService.fetchBearerToken(spDcCookie.value);
      if (token == null || token.isEmpty) {
        if (mounted) {
          setState(() {
            _processingAuth = false;
            _error = 'Failed to get access token. Please try again.';
          });
        }
        return;
      }

      _completed = true;
      final headers = SpotifyTokenService.headersFromSpDc(spDcCookie.value);

      // Extract user identity via WebView JS — avoids the server-side rate limit
      // on api.spotify.com/v1/me. Primary: read localStorage key prefix to get
      // the Spotify user ID instantly, then call spclient/profile/{id}.
      // Fallback: /v1/me from browser context.
      if (_webViewController != null) {
        try {
          AppLogger.auth('Injecting JS to get user identity...');
          final result = await _webViewController!.callAsyncJavaScript(
            functionBody: r'''

              async function getUser(token) {
                // Spotify namespaces all per-user localStorage keys as "{userId}:settingName".
                // Reading the first non-"anonymous" prefix gives us the real Spotify ID
                // instantly — no API call, no rate limits, no DOM polling needed.
                let userId = null;
                for (let i = 0; i < localStorage.length; i++) {
                  const key = localStorage.key(i) || '';
                  const m = key.match(/^([a-z0-9]{20,}):/);
                  if (m && m[1] !== 'anonymous') { userId = m[1]; break; }
                }

                if (userId) {
                  // Call spclient (name/image/followers) and account-settings (email/country) in parallel.
                  // account-settings uses browser cookies automatically — no Authorization header,
                  // no rate limiting, and not affected by the Feb 2026 /v1/me scope removal.
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

                // Fallback: account-settings gives us userId via profile.username
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
              return getUser('SPOTIFY_TOKEN');
            '''.replaceAll('SPOTIFY_TOKEN', token),
          ).timeout(const Duration(seconds: 15), onTimeout: () => null);
          final userMap = result?.value;
          if (userMap is Map && (userMap['id'] as String?)?.isNotEmpty == true) {
            headers['x-prefetched-user'] = jsonEncode(Map<String, dynamic>.from(userMap));
            AppLogger.auth('JS identity OK: ${userMap["displayName"]} (${userMap["id"]})');
          } else {
            AppLogger.auth('JS identity returned null — will fall through to server-side fetch');
          }
        } catch (e) {
          AppLogger.auth('JS identity injection failed: $e');
        }
      }

      if (!mounted) return;
      if (mounted) setState(() => _processingStep = 'Loading your profile...');
      try {
        await widget.onAuthComplete(token, headers);
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        _completed = false;
        if (mounted) {
          setState(() {
            _processingAuth = false;
            _error = 'Authentication failed: $e';
          });
        }
      }
    } catch (e) {
      AppLogger.error('Error during token capture', e);
      if (mounted) {
        setState(() {
          _processingAuth = false;
          _error = 'Authentication error: $e';
        });
      }
    } finally {
      _capturing = false;
    }
  }
}

class _InfoBanner extends StatelessWidget {
  final Color primaryColor;
  final Color surfaceColor;
  const _InfoBanner({required this.primaryColor, required this.surfaceColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: surfaceColor,
      child: Row(
        children: [
          Icon(Icons.security, color: primaryColor, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Login with your Spotify account to access friend activities',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.red.withValues(alpha: 26),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _AuthProcessingOverlay extends StatelessWidget {
  final String step;
  final VoidCallback? onCancel;
  const _AuthProcessingOverlay({required this.step, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: primary),
                const SizedBox(height: 16),
                Text(
                  'Signing in to Spotify',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
                ),
                const SizedBox(height: 6),
                Text(
                  step,
                  style: TextStyle(fontSize: 13, color: dimColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onCancel,
                  child: Text('Cancel', style: TextStyle(color: dimColor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
