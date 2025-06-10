import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user.dart';
import '../models/track.dart';
import '../models/artist.dart';
import 'spotify_buddy_service.dart';

class SpotifyService {
  static const String baseUrl = 'https://api.spotify.com/v1';
  static const String authUrl = 'https://accounts.spotify.com';
  static const String webAuthUrl = 'https://open.spotify.com'; // For WebView login to get sp_dc cookie


  /// Generates a curl command for debugging API requests
  // String _generateCurlCommand(String method, String url, Map<String, String> headers, {String? body}) {
  //   final buffer = StringBuffer();
  //   buffer.write('curl -X $method');
  //   
  //   // Add headers
  //   headers.forEach((key, value) {
  //     buffer.write(' -H "$key: $value"');
  //   });
  //   
  //   // Add body if present
  //   if (body != null && body.isNotEmpty) {
  //     buffer.write(' -d \'$body\'');
  //   }
  //   
  //   // Add URL
  //   buffer.write(' "$url"');
  //   
  //   return buffer.toString();
  // }

  String getAuthorizationUrl() {
    // Use Spotify's accounts page - the app will detect when user reaches the status page
    // and extract the sp_dc cookie automatically
    return 'https://accounts.spotify.com/';
  }

  Future<User> getCurrentUser(String accessToken) async {
    return _retryApiCall(
      () async {
        final url = '$baseUrl/me';
        final headers = {
          'Authorization': 'Bearer $accessToken',
        };

        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        );

        if (response.statusCode == 200) {
          return User.fromJson(json.decode(response.body));
        } else {
          throw Exception('Failed to get current user: ${response.statusCode} - ${response.body}');
        }
      },
      operation: 'Get Current User',
    );
  }

  Future<Track?> getCurrentlyPlaying(String accessToken) async {
    return _retryApiCall(
      () async {
        final url = '$baseUrl/me/player/currently-playing';
        
        // Get stored cookie from SpotifyBuddyService
        final cookieString = SpotifyBuddyService.instance.getCookieString();
        
        final headers = {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json, text/plain, */*',
          'Accept-Encoding': 'gzip',
          'Connection': 'Keep-Alive',
          'Host': 'api.spotify.com',
          'User-Agent': 'okhttp/4.9.2',
        };
        
        // Add cookie if available
        if (cookieString != null && cookieString.isNotEmpty) {
          headers['Cookie'] = cookieString;
        }

        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['item'] != null) {
            return Track.fromJson(data['item']);
          }
          return null;
        } else if (response.statusCode == 204) {
          // No content - nothing is currently playing
          return null;
        } else {
          print('Failed to get currently playing: ${response.statusCode} - ${response.body}');
          // throw Exception('Failed to get currently playing: ${response.statusCode} - ${response.body}');
        }
      },
      operation: 'Get Currently Playing',
    );
  }


  /// Retry logic for API calls with exponential backoff
  static Future<T> _retryApiCall<T>(
    Future<T> Function() apiCall, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 50),
    String operation = 'API call',
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    
    while (attempt < maxRetries) {
      try {
        print('🔄 Attempting $operation (attempt ${attempt + 1}/$maxRetries)');
        return await apiCall().timeout(
          const Duration(seconds: 15), // 15 second timeout per request
          onTimeout: () {
            throw TimeoutException('Request timed out after 15 seconds', const Duration(seconds: 15));
          },
        );
      } catch (e) {
        attempt++;
        
        if (attempt >= maxRetries) {
          print('❌ $operation failed after $maxRetries attempts: $e');
          rethrow;
        }
        
        print('⚠️ $operation failed (attempt $attempt/$maxRetries): $e');
        print('🔄 Retrying in ${delay.inMilliseconds}ms...');
        
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * 1.5).round()); // Exponential backoff
      }
    }
    
    throw Exception('Failed to complete $operation after $maxRetries attempts');
  }
}