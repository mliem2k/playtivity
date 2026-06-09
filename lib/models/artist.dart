class Artist {
  final String id;
  final String name;
  final String? imageUrl;
  final int followers;
  final int monthlyListeners;
  final String uri;

  Artist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.followers,
    required this.monthlyListeners,
    required this.uri,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      imageUrl: json['image_url'] as String?,
      followers: json['followers'] as int? ?? -1,
      monthlyListeners: json['monthly_listeners'] as int? ?? -1,
      uri: json['uri'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
      'followers': followers,
      'monthly_listeners': monthlyListeners,
      'uri': uri,
    };
  }
} 