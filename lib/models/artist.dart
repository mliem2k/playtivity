class Artist {
  final String id;
  final String name;
  final String? imageUrl;
  final List<String> genres;
  final int popularity;
  final int followers;
  final String uri;

  Artist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.genres,
    required this.popularity,
    required this.followers,
    required this.uri,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      imageUrl: json['images'] != null && json['images'].isNotEmpty
          ? json['images'][0]['url']
          : null,
      genres: (json['genres'] as List?)?.map((genre) => genre as String).toList() ?? [],
      popularity: json['popularity'] ?? 0,
      followers: json['followers']?['total'] ?? 0,
      uri: json['uri'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
      'genres': genres,
      'popularity': popularity,
      'followers': followers,
      'uri': uri,
    };
  }
} 