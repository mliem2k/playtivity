import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user.dart';
import '../models/track.dart';
import '../models/artist.dart';

class SpotifyService {
  // Get credentials from environment variables
  static String get clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  static String get clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';
  static String get redirectUri => dotenv.env['SPOTIFY_REDIRECT_URI'] ?? '';
  static const String baseUrl = 'https://api.spotify.com/v1';
  static const String authUrl = 'https://accounts.spotify.com';
  static const String webAuthUrl = 'https://open.spotify.com'; // For WebView login to get sp_dc cookie

  /// Check if OAuth credentials are available
  static bool get isOAuthAvailable => clientId.isNotEmpty && clientSecret.isNotEmpty && redirectUri.isNotEmpty;

  /// Validates that all required environment variables are loaded
  /// Returns true if OAuth is available, false if only cookie-based auth should be used
  static bool validateEnvironmentVariables() {
    if (clientId.isEmpty || clientSecret.isEmpty || redirectUri.isEmpty) {
      print('⚠️  OAuth credentials not found in .env file');
      print('   Falling back to cookie-based authentication only');
      print('   Missing: ${clientId.isEmpty ? 'SPOTIFY_CLIENT_ID ' : ''}${clientSecret.isEmpty ? 'SPOTIFY_CLIENT_SECRET ' : ''}${redirectUri.isEmpty ? 'SPOTIFY_REDIRECT_URI' : ''}');
      return false;
    }
    print('✅ Environment variables loaded successfully');
    print('   Client ID: ${clientId.substring(0, 8)}...');
    print('   Redirect URI: $redirectUri');
    return true;
  }
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

  Future<Map<String, dynamic>> exchangeCodeForToken(String code) async {
    final url = '$authUrl/api/token';
    final headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',    };
    // final body = 'grant_type=authorization_code&code=$code&redirect_uri=$redirectUri';

    // Log curl format
    // final curlCommand = _generateCurlCommand('POST', url, headers, body: body);
    // print('🔧 Token Exchange CURL Command:');
    // print(curlCommand);

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to exchange code for token: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final url = '$authUrl/api/token';
    final headers = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Authorization': 'Basic ${base64Encode(utf8.encode('$clientId:$clientSecret'))}',    };
    // final body = 'grant_type=refresh_token&refresh_token=$refreshToken';

    // Log curl format
    // final curlCommand = _generateCurlCommand('POST', url, headers, body: body);
    // print('🔧 Refresh Token CURL Command:');
    // print(curlCommand);

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to refresh token: ${response.body}');
    }
  }

  Future<User> getCurrentUser(String accessToken) async {
    final url = '$baseUrl/me';
    final headers = {
      'Authorization': 'Bearer $accessToken',    };

    // Log curl format
    // final curlCommand = _generateCurlCommand('GET', url, headers);
    // print('🔧 Get Current User CURL Command:');
    // print(curlCommand);

    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return User.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to get current user: ${response.body}');
    }
  }

  Future<Track?> getCurrentlyPlaying(String accessToken) async {
    final url = '$baseUrl/me/player/currently-playing';
    final headers = {
      'Authorization': 'Bearer $accessToken',    };

    // Log curl format
    // final curlCommand = _generateCurlCommand('GET', url, headers);
    // print('🔧 Get Currently Playing CURL Command:');
    // print(curlCommand);

    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['item'] != null) {
        return Track.fromJson(data['item']);
      }
    } else if (response.statusCode == 204) {
      // No content - nothing is currently playing
      return null;
    }
    
    return null;
  }

  Future<List<Track>> getTopTracks(String accessToken, {String timeRange = 'medium_term', int limit = 20}) async {
    final url = '$baseUrl/me/top/tracks?time_range=$timeRange&limit=$limit';
    final headers = {
      'Authorization': 'Bearer $accessToken',    };

    // Log curl format
    // final curlCommand = _generateCurlCommand('GET', url, headers);
    // print('🔧 Get Top Tracks CURL Command:');
    // print(curlCommand);

    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['items'] as List;
      return items.map((item) => Track.fromJson(item)).toList();
    } else {
      throw Exception('Failed to get top tracks: ${response.body}');
    }
  }

  Future<List<Artist>> getTopArtists(String accessToken, {String timeRange = 'medium_term', int limit = 20}) async {
    final url = '$baseUrl/me/top/artists?time_range=$timeRange&limit=$limit';
    final headers = {
      'Authorization': 'Bearer $accessToken',    };

    // Log curl format
    // final curlCommand = _generateCurlCommand('GET', url, headers);
    // print('🔧 Get Top Artists CURL Command:');
    // print(curlCommand);

    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final items = data['items'] as List;
      return items.map((item) => Artist.fromJson(item)).toList();
    } else {
      throw Exception('Failed to get top artists: ${response.body}');
    }
  }
} 