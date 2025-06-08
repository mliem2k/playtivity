import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/spotify_service.dart';

class SpotifyWebViewLogin extends StatefulWidget {
  final Function(String, String?) onAuthComplete; // OAuth code and sp_dc cookie
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
  String? _extractedSpDcCookie;
  bool _isInOAuthFlow = false;

  // Helper method to check if OAuth is available
  bool get _isOAuthAvailable {
    try {
      return SpotifyService.clientId.isNotEmpty && 
             SpotifyService.clientSecret.isNotEmpty && 
             SpotifyService.redirectUri.isNotEmpty;
    } catch (e) {
      print('❌ Error checking OAuth availability: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isInOAuthFlow ? 'Authorizing App' : 'Login to Spotify'),
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
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Row(
              children: [
                Icon(
                  Icons.security,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isInOAuthFlow 
                        ? 'Authorizing app access to your Spotify profile...'
                        : 'Login with your Spotify account to access friend activities',
                    style: const TextStyle(fontSize: 12),
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
              color: Colors.red.withOpacity(0.1),
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
                : InAppWebView(
                    initialSettings: InAppWebViewSettings(
                      userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/105.0.0.0 Safari/537.36",
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                    ),
                    initialUrlRequest: URLRequest(
                      url: WebUri(SpotifyService().getAuthorizationUrl()),
                    ),
                    onPermissionRequest: (controller, permissionRequest) async {
                      return PermissionResponse(
                        resources: permissionRequest.resources,
                        action: PermissionResponseAction.GRANT,
                      );
                    },
                    onLoadStart: (controller, url) {
                      setState(() {
                        _isLoading = true;
                        _error = null;
                      });
                    },
                    onLoadStop: (controller, url) async {
                      setState(() {
                        _isLoading = false;
                      });
                      
                      if (url == null) return;
                      
                      String urlString = url.toString();
                      if (urlString.endsWith("/")) {
                        urlString = urlString.substring(0, urlString.length - 1);
                      }

                      if (!_isInOAuthFlow) {
                        // Step 1: Check if we've reached the Spotify status page (indicates successful login)
                        final statusPageRegex = RegExp(r"https:\/\/accounts\.spotify\.com\/.+\/status");
                        
                        if (statusPageRegex.hasMatch(urlString)) {
                          print('🎯 Detected Spotify status page: $urlString');
                          // Don't show logging in screen, keep webview visible
                          await _extractSpDcCookieAndStartOAuth(controller, url);
                        }
                      } else {
                        // Step 2: Handle OAuth redirect (but don't show it)
                        if (urlString.startsWith('https://mliem.com') || urlString.startsWith('https://www.mliem.com')) {
                          _handleOAuthRedirect(urlString);
                        }
                      }
                    },
                    onReceivedError: (controller, request, error) {
                      setState(() {
                        _error = 'Failed to load page: ${error.description}';
                        _isLoading = false;
                      });
                    },
                  ),
          ),
        ],
      ),
    );
  }



  Future<void> _extractSpDcCookieAndStartOAuth(InAppWebViewController controller, WebUri url) async {
    try {
      print('🍪 Extracting sp_dc cookie from: $url');
      
      // Get cookies from the current page
      final cookies = await CookieManager.instance().getCookies(url: url);
      
      // Find the sp_dc cookie
      final spDcCookie = cookies.firstWhere(
        (cookie) => cookie.name == "sp_dc",
        orElse: () => throw Exception("sp_dc cookie not found"),
      );
      
      final cookieValue = spDcCookie.value;
      print('✅ Successfully extracted sp_dc cookie: ${cookieValue.substring(0, 20)}...');
      
      // Store the sp_dc cookie
      _extractedSpDcCookie = cookieValue;
      
      // Check if OAuth is available
      if (_isOAuthAvailable) {
        // Start OAuth flow if credentials are available
      await _startOAuthFlow(controller);
      } else {
        // Skip OAuth and complete authentication with just the cookie
        print('⚠️ OAuth credentials not available, completing authentication with cookie only');
        if (mounted) {
          widget.onAuthComplete('', cookieValue); // Empty OAuth code, just cookie
        }
      }
      
    } catch (e) {
      print('❌ Failed to extract sp_dc cookie: $e');
      setState(() {
        _error = 'Failed to extract authentication cookie: $e';
      });
    }
  }

  Future<void> _startOAuthFlow(InAppWebViewController controller) async {
    try {
      // Double-check that OAuth is available before proceeding
      if (!_isOAuthAvailable) {
        print('⚠️ OAuth credentials not available in _startOAuthFlow, skipping');
        if (mounted) {
          widget.onAuthComplete('', _extractedSpDcCookie);
        }
        return;
      }

      setState(() {
        _isInOAuthFlow = true;
      });

      print('🔄 Starting OAuth flow...');
      
      // Build OAuth authorization URL
      final scopes = [
        'user-read-private',
        'user-read-email',
        'user-read-currently-playing',
        'user-read-playback-state',
        'user-top-read',
      ].join(' ');

      final oauthUrl = 'https://accounts.spotify.com/authorize?'
          'client_id=${SpotifyService.clientId}&'
          'response_type=code&'
          'redirect_uri=${Uri.encodeComponent(SpotifyService.redirectUri)}&'
          'scope=${Uri.encodeComponent(scopes)}&'
          'show_dialog=false'; // Don't show dialog since user is already logged in

      print('🌐 Redirecting to OAuth: $oauthUrl');
      
      // Navigate to OAuth authorization
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(oauthUrl)));
      
    } catch (e) {
      print('❌ OAuth flow failed: $e');
      setState(() {
        _error = 'OAuth authorization failed: $e';
        _isInOAuthFlow = false;
      });
    }
  }

  void _handleOAuthRedirect(String url) {
    print('🔗 Handling OAuth redirect: $url');
    
    try {
      final uri = Uri.parse(url);
      print('📋 Parsed URI: ${uri.toString()}');
      print('🔍 Query parameters: ${uri.queryParameters}');
      
      // Check for authorization code
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        print('✅ Successfully extracted OAuth authorization code: ${code.substring(0, 20)}...');
        print('📏 Code length: ${code.length} characters');
        
        // Complete the authentication with both OAuth code and sp_dc cookie
        if (mounted) {
        widget.onAuthComplete(code, _extractedSpDcCookie);
        }
        return;
      }
      
      // Check for error
      final error = uri.queryParameters['error'];
      final errorDescription = uri.queryParameters['error_description'];
      
      if (error != null) {
        final fullError = errorDescription != null 
            ? '$error: $errorDescription' 
            : error;
        print('❌ OAuth error: $fullError');
        setState(() {
          _error = 'OAuth authorization failed: $fullError';
          _isInOAuthFlow = false;
        });
        return;
      }
      
      // If we reach here, no code or error was found
      print('⚠️ No authorization code or error found in URL: $url');
      setState(() {
        _error = 'No authorization code received from Spotify';
        _isInOAuthFlow = false;
      });
      
    } catch (e) {
      print('❌ Error parsing OAuth redirect URL: $e');
      setState(() {
        _error = 'Failed to parse OAuth response: $e';
        _isInOAuthFlow = false;
      });
    }
  }
} 