class Track {
  final String id;
  final String name;
  final List<String> artists;
  final String album;
  final String? imageUrl;
  final int durationMs;
  final String? previewUrl;
  final String uri;

  Track({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    this.imageUrl,
    required this.durationMs,
    this.previewUrl,
    required this.uri,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      artists: (json['artists'] as List?)?.map((artist) => artist['name'] as String).toList() ?? [],
      album: json['album']?['name'] ?? '',
      imageUrl: json['album']?['images'] != null && json['album']['images'].isNotEmpty
          ? json['album']['images'][0]['url']
          : null,
      durationMs: json['duration_ms'] ?? 0,
      previewUrl: json['preview_url'],
      uri: json['uri'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artists': artists,
      'album': album,
      'image_url': imageUrl,
      'duration_ms': durationMs,
      'preview_url': previewUrl,
      'uri': uri,
    };
  }

  String get artistsString => artists.join(', ');

  String get duration {
    final minutes = (durationMs / 60000).floor();
    final seconds = ((durationMs % 60000) / 1000).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
} 