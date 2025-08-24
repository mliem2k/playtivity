import '../utils/json_helpers.dart';

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
    final artists = JsonHelpers.getSpotifyArtists(json);
    
    return Track(
      id: JsonHelpers.getString(json, 'id'),
      name: JsonHelpers.getString(json, 'name'),
      artists: artists.names,
      artistUris: artists.uris,
      album: JsonHelpers.getNestedString(json, ['album', 'name']),
      albumUri: json['album']?['uri'] as String?,
      imageUrl: json['album'] != null ? JsonHelpers.getSpotifyImageUrl(json['album']) : null,
      durationMs: JsonHelpers.getInt(json, 'duration_ms'),
      previewUrl: json['preview_url'] as String?,
      uri: JsonHelpers.getString(json, 'uri'),
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