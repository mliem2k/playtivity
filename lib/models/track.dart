class Track {
  final String id;
  final String name;
  final List<String> artists;
  final List<String> artistUris;
  final String album;
  final String? albumUri;
  final String? imageUrl;
  final int durationMs;
  final String? previewUrl;
  final String uri;

  Track({
    required this.id,
    required this.name,
    required this.artists,
    this.artistUris = const [],
    required this.album,
    this.albumUri,
    this.imageUrl,
    required this.durationMs,
    this.previewUrl,
    required this.uri,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    List<String> artistNames = [];
    List<String> artistUris = [];
    
    if (json['artists'] is List) {
      final artistsList = json['artists'] as List;
      artistNames = artistsList.map((artist) => artist['name'] as String).toList();
      artistUris = artistsList.map((artist) => artist['uri'] as String? ?? '').where((uri) => uri.isNotEmpty).toList();
    } else if (json['artist'] != null) {
      final artist = json['artist'];
      artistNames = [artist['name'] as String? ?? 'Unknown Artist'];
      final artistUri = artist['uri'] as String?;
      if (artistUri != null && artistUri.isNotEmpty) {
        artistUris = [artistUri];
      }
    }
    
    return Track(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      artists: artistNames,
      artistUris: artistUris,
      album: json['album']?['name'] ?? '',
      albumUri: json['album']?['uri'],
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
      'artist_uris': artistUris,
      'album': album,
      'album_uri': albumUri,
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

  String? get firstArtistUri => artistUris.isNotEmpty ? artistUris.first : null;
} 