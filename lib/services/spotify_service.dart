import 'dart:convert';
import 'dart:async';
import '../models/user.dart';
import '../models/track.dart';
import 'spotify_buddy_service.dart';
import 'http_interceptor.dart';
import 'app_logger.dart';
import 'api_retry_service.dart';
import '../constants/api_constants.dart';

class SpotifyService {
  String getAuthorizationUrl() {
    // Use Spotify's accounts page - the app will detect when user reaches the status page
    // and extract the sp_dc cookie automatically
    return ApiConstants.spotifyAuthUrl;
  }

  Future<User> getCurrentUser(String accessToken) async {
    return ApiRetryService.retryApiCall(
      () async {
        final url = ApiConstants.spotifyApiBaseUrl + ApiConstants.currentUserEndpoint;
        final headers = {
          'Authorization': 'Bearer $accessToken',
        };

        final response = await HttpInterceptor.get(
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
    return ApiRetryService.retryApiCall(
      () async {
        final url = ApiConstants.spotifyApiBaseUrl + ApiConstants.currentlyPlayingEndpoint;
        
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

        try {
        final response = await HttpInterceptor.get(
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
          AppLogger.spotify('Failed to get currently playing: ${response.statusCode} - ${response.body}');
          return null;
        }
        
        } catch (e) {
          AppLogger.spotify('Error getting currently playing', e);
          return null;
        }
      },
      operation: 'Get Currently Playing',
    );
  }


}