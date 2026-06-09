import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
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
  String _processingStep = '';
  InAppWebViewController? _webViewController;

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
              ],
            ),
            if (_processingAuth)
              Consumer<AuthProvider>(
                builder: (context, auth, _) => _AuthProcessingOverlay(
                  step: _processingStep,
                  events: auth.authEvents,
                  lastError: auth.lastAuthError,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _attemptTokenCapture(WebUri url) async {
    if (mounted) setState(() { _processingAuth = true; _processingStep = 'Verifying session...'; });
    try {
      final cookies = await CookieManager.instance().getCookies(url: url);
      final spDcCookie = cookies.firstWhere(
        (c) => c.name == 'sp_dc' && c.value.isNotEmpty,
        orElse: () => Cookie(name: '', value: ''),
      );
      if (spDcCookie.name.isEmpty) {
        if (mounted) setState(() => _processingAuth = false);
        return;
      }

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

      // Try to fetch user profile from within the browser context — avoids the
      // server-side rate limit that blocks api.spotify.com/v1/me from Dart code.
      if (_webViewController != null) {
        try {
          AppLogger.auth('Injecting JS to fetch /v1/me...');
          final result = await _webViewController!.callAsyncJavaScript(
            functionBody: '''
              try {
                const resp = await fetch('https://api.spotify.com/v1/me', {
                  headers: { 'Authorization': 'Bearer $token', 'Accept': 'application/json' }
                });
                if (!resp.ok) return null;
                const d = await resp.json();
                return {
                  id: d.id,
                  displayName: d.display_name,
                  imageUrl: (d.images && d.images.length > 0) ? d.images[0].url : null,
                  country: d.country || null,
                  followers: d.followers ? d.followers.total : 0
                };
              } catch(e) { return null; }
            ''',
          );
          final userMap = result?.value;
          if (userMap is Map && (userMap['id'] as String?)?.isNotEmpty == true) {
            headers['x-prefetched-user'] = jsonEncode(Map<String, dynamic>.from(userMap));
            AppLogger.auth('JS /v1/me OK: ${userMap["displayName"]}');
          }
        } catch (e) {
          AppLogger.auth('JS /v1/me failed: $e');
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

class _AuthProcessingOverlay extends StatefulWidget {
  final String step;
  final List<String> events;
  final String? lastError;
  const _AuthProcessingOverlay({required this.step, required this.events, this.lastError});

  @override
  State<_AuthProcessingOverlay> createState() => _AuthProcessingOverlayState();
}

class _AuthProcessingOverlayState extends State<_AuthProcessingOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final errorColor = Colors.red.shade400;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 10);

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
                  widget.step,
                  style: TextStyle(fontSize: 13, color: dimColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                // Debug panel
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: widget.lastError != null
                            ? errorColor.withValues(alpha: 0.5)
                            : dimColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.bug_report, size: 11, color: dimColor),
                            const SizedBox(width: 3),
                            Text(
                              'Debug  ${_expanded ? "▲" : "▼"}',
                              style: mono.copyWith(color: dimColor, fontWeight: FontWeight.bold),
                            ),
                            if (widget.lastError != null) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.error_outline, size: 11, color: errorColor),
                              const SizedBox(width: 2),
                              Text('error', style: mono.copyWith(color: errorColor)),
                            ],
                          ],
                        ),
                        if (widget.lastError != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.lastError!,
                            style: mono.copyWith(color: errorColor),
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded ? null : TextOverflow.ellipsis,
                          ),
                        ],
                        if (widget.events.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          ...( _expanded
                              ? widget.events.reversed.take(12)
                              : [widget.events.last]
                          ).map(
                            (e) => Text(e, style: mono.copyWith(color: dimColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
