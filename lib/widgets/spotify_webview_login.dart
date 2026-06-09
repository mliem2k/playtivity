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
        child: Column(
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
      ),
    );
  }

  Future<void> _attemptTokenCapture(WebUri url) async {
    try {
      final cookies = await CookieManager.instance().getCookies(url: url);
      final spDcCookie = cookies.firstWhere(
        (c) => c.name == 'sp_dc' && c.value.isNotEmpty,
        orElse: () => Cookie(name: '', value: ''),
      );
      if (spDcCookie.name.isEmpty) return;

      AppLogger.auth('sp_dc found — fetching Bearer token...');
      final token = await SpotifyTokenService.fetchBearerToken(spDcCookie.value);
      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _error = 'Failed to get access token. Please try again.');
        return;
      }

      _completed = true;
      final headers = SpotifyTokenService.headersFromSpDc(spDcCookie.value);
      if (!mounted) return;
      try {
        await widget.onAuthComplete(token, headers);
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        _completed = false;
        if (mounted) setState(() => _error = 'Authentication failed: $e');
      }
    } catch (e) {
      AppLogger.error('Error during token capture', e);
      if (mounted) setState(() => _error = 'Authentication error: $e');
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
