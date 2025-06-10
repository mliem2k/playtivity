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
      id: json['id'] ?? '',
      displayName: json['display_name'] ?? '',
      email: json['email'] ?? '',
      imageUrl: json['image_url'],
      followers: json['followers'] ?? 0,
      country: json['country'] ?? '',
    );
  }

  /// Creates User from Spotify API response
  factory User.fromSpotifyApi(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      displayName: json['display_name'] ?? '',
      email: json['email'] ?? '',
      imageUrl: json['images'] != null && json['images'].isNotEmpty 
          ? json['images'][0]['url'] 
          : null,
      followers: json['followers']?['total'] ?? 0,
      country: json['country'] ?? '',
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