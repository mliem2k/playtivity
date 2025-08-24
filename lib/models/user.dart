import '../utils/json_helpers.dart';

class User {
  final String id;
  final String displayName;
  final String email;
  final String? imageUrl;
  final int followers;
  final String country;

  User({
    required this.id,
    required this.displayName,
    required this.email,
    this.imageUrl,
    required this.followers,
    required this.country,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: JsonHelpers.getString(json, 'id'),
      displayName: JsonHelpers.getString(json, 'display_name'),
      email: JsonHelpers.getString(json, 'email'),
      imageUrl: json['image_url'] as String?,
      followers: JsonHelpers.getInt(json, 'followers'),
      country: JsonHelpers.getString(json, 'country'),
    );
  }

  /// Creates User from Spotify API response
  factory User.fromSpotifyApi(Map<String, dynamic> json) {
    return User(
      id: JsonHelpers.getString(json, 'id'),
      displayName: JsonHelpers.getString(json, 'display_name'),
      email: JsonHelpers.getString(json, 'email'),
      imageUrl: JsonHelpers.getSpotifyImageUrl(json),
      followers: JsonHelpers.getNestedInt(json, ['followers', 'total']),
      country: JsonHelpers.getString(json, 'country'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'email': email,
      'image_url': imageUrl,
      'followers': followers,
      'country': country,
    };
  }
} 