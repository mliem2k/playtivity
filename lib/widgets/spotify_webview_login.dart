import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import '../services/spotify_service.dart';
import '../services/spotify_buddy_service.dart';

class SpotifyWebViewLogin extends StatefulWidget {
  final Function(String, Map<String, String>) onAuthComplete; // Bearer access token and headers
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
  bool _spDcDetected = false;
  String _currentUrl = '';
  bool _showOverlay = true;

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
                : Stack(
                    children: [
                      // WebView (always present, loading in background when overlay is shown)
                      InAppWebView(
                        initialSettings: InAppWebViewSettings(
                          userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/537.36",
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
                        ),
                        initialUrlRequest: URLRequest(
                          url: WebUri('https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F__noul__%2F'),
                          headers: {
                            'sec-ch-ua': '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
                            'sec-ch-ua-mobile': '?0',
                            'sec-ch-ua-platform': '"Windows"',
                            'sec-fetch-dest': 'document',
                            'sec-fetch-mode': 'navigate',
                            'sec-fetch-site': 'none',
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
                          print('🌐 Page loaded: $urlString');
                            // Update current URL and overlay logic
                          setState(() {
                            _currentUrl = urlString;
                            // Hide overlay only for Spotify URLs that are NOT login or challenge pages
                            // Show overlay for: non-Spotify sites OR Spotify login/challenge pages
                            bool isSpotifyUrl = urlString.contains('spotify.com');
                            bool isLoginOrChallenge = urlString.contains('/login') || urlString.contains('challenge.spotify.com');
                            _showOverlay = !isSpotifyUrl || isLoginOrChallenge;
                          });
                          
                          // Set up network interception to capture Bearer token
                          if (urlString.contains('open.spotify.com')) {
                            await _setupNetworkInterception(controller, url);
                          }
                        },
                        onReceivedError: (controller, request, error) {
                          setState(() {
                            _error = 'Failed to load page: ${error.description}';
                            _isLoading = false;
                          });
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
                                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 32),
                                // Spotify branding with theme-aware colors
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.15),
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
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _setupNetworkInterception(InAppWebViewController controller, WebUri url) async {
    try {
      print('🌐 Setting up network interception for Bearer token capture...');
      
      // Get all cookies for building complete header context
      final cookies = await CookieManager.instance().getCookies(url: url);
      final cookieString = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
      
      print('🍪 Found ${cookies.length} cookies');
      print('🍪 Initial cookie string: ${cookieString.isNotEmpty ? cookieString.substring(0, 100) + '...' : 'EMPTY'}');
      print('🍪 Cookie names: ${cookies.map((c) => c.name).join(', ')}');
      
      // Check if sp_dc cookie is present
      bool hasSpDc = cookies.any((cookie) => cookie.name == 'sp_dc');
      print('🍪 sp_dc cookie present in initial request: $hasSpDc');
      
      // Log sp_dc detection
      if (hasSpDc) {
        print('🔄 sp_dc detected');
      }
      
      // Build headers that will be saved and reused
      _extractedHeaders = {
        'Cookie': cookieString,
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br, zstd',
        'DNT': '1',
        'Connection': 'keep-alive',
        'sec-ch-ua': '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'Upgrade-Insecure-Requests': '1',
      };
      
      print('🔧 Initial _extractedHeaders Cookie: ${_extractedHeaders['Cookie']?.isNotEmpty == true ? _extractedHeaders['Cookie']!.substring(0, 100) + '...' : 'EMPTY'}');
      
      // Set up network request interception
      await _interceptTokenRequests(controller);
      
    } catch (e) {
      print('❌ Failed to setup network interception: $e');
      setState(() {
        _error = 'Failed to setup authentication monitoring: $e';
      });
    }
  }

  Future<void> _interceptTokenRequests(InAppWebViewController controller) async {
    try {
      print('🕸️ Setting up network request interception...');
      
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
      print('✅ Network interception script injected');
      
      // Set up periodic checking for captured tokens
      _startTokenPolling(controller);
      
    } catch (e) {
      print('❌ Error setting up network interception: $e');
    }
  }

  void _startTokenPolling(InAppWebViewController controller) {
    print('⏰ Starting token polling...');
    
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        print('🔍 Polling for captured token...');
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
        
        print('🔍 Polling result: ${result != null ? 'DATA FOUND' : 'null'}');
        
        if (result != null) {
          final Map<String, dynamic> tokenInfo = Map<String, dynamic>.from(result);
          final bearerToken = tokenInfo['token'] as String?;
          final capturedCookie = tokenInfo['cookie'] as String?;
          
          print('🔍 Parsed result:');
          print('   - bearerToken: ${bearerToken != null ? 'EXISTS (${bearerToken.length} chars)' : 'null'}');
          print('   - capturedCookie: ${capturedCookie != null ? 'EXISTS (${capturedCookie.length} chars)' : 'null'}');
          
          // Handle cookie updates (even without token)
          if (capturedCookie != null && capturedCookie.isNotEmpty) {
            bool hadSpDcBefore = (_extractedHeaders['Cookie'] ?? '').contains('sp_dc=');
            bool hasSpDcNow = capturedCookie.contains('sp_dc=');
            
            if (!hadSpDcBefore && hasSpDcNow) {
              print('🍪 Found new sp_dc cookie! Updating headers...');
              _extractedHeaders['Cookie'] = capturedCookie;
              print('✅ Updated headers with sp_dc cookie');
              print('🍪 New cookie header: ${capturedCookie.substring(0, 100)}...');
              
              print('🔄 sp_dc detected in cookie update');
            } else if (hasSpDcNow) {
              // Update with latest cookie info
              _extractedHeaders['Cookie'] = capturedCookie;
            }
          }
          
          if (bearerToken != null && bearerToken.isNotEmpty) {
            print('🎯 Token polling found complete result!');
            timer.cancel();
            
            print('🎉 Successfully captured Bearer token: ${bearerToken.substring(0, 20)}...');
            print('📋 Token length: ${bearerToken.length} characters');
            print('🍪 Final captured cookie: ${capturedCookie?.substring(0, 50) ?? 'none'}...');
            print('📊 Token data: ${tokenInfo['data']}');
            
            print('🔄 Bearer token found');
            
            // Complete authentication with the Bearer token and headers
            if (mounted) {
              print('🔄 Calling onAuthComplete with Bearer token and updated headers...');
              print('📋 Final headers: ${_extractedHeaders.keys.join(', ')}');
              print('📋 Cookie header length: ${_extractedHeaders['Cookie']?.length ?? 0}');
              
              // Add debug logging for the callback
              try {
                widget.onAuthComplete(bearerToken, _extractedHeaders);
                print('✅ onAuthComplete callback executed successfully');
              } catch (e) {
                print('❌ Error in onAuthComplete callback: $e');
              }
              
              // Add a small delay to ensure the callback is processed
              await Future.delayed(const Duration(milliseconds: 100));
              
              // Close the WebView after authentication
              if (mounted && Navigator.canPop(context)) {
                Navigator.of(context).pop(true);
              }
            }
          } else {
            print('🍪 Cookie update received (no token yet)');
          }
        } else {
          // Only log every 5 seconds to reduce spam
          if (DateTime.now().millisecondsSinceEpoch % 5000 < 1000) {
            print('🔍 No token data found yet...');
          }
        }
      } catch (e) {
        print('❌ Error checking for captured token: $e');
      }
    });
    
    // Set a timeout to stop polling after 30 seconds
    Timer(const Duration(seconds: 30), () {
      print('⏰ Token polling timeout - stopping...');
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
          print('🍪 Found sp_dc cookie: ${spDcCookie.value.substring(0, 20)}...');
          
          print('🔄 sp_dc detected in cookie check');
          
          // Update the cookie string in headers with the complete set including sp_dc
          final allCookies = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
          _extractedHeaders['Cookie'] = allCookies;
          
          print('✅ Updated headers with sp_dc cookie');
          print('🍪 New cookie header: ${allCookies.substring(0, 100)}...');
        }
      }
    } catch (e) {
      print('❌ Error checking for sp_dc cookie: $e');
    }
  }
} 