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
    // album is a nested Map in the live Spotify API format, but a flat String
    // in our own persisted format (Track.toJson()). Handle both so that
    // Activity.fromJson round-trips correctly through SharedPreferences.
    final albumRaw = json['album'];
    final String albumName;
    final String? albumUri;
    final String? imageUrl;

    if (albumRaw is Map) {
      final albumMap = Map<String, dynamic>.from(albumRaw as Map);
      albumName = albumMap['name'] as String? ?? '';
      albumUri = albumMap['uri'] as String?;
      imageUrl = json['image_url'] as String?
          ?? albumMap['imageUrl'] as String?
          ?? JsonHelpers.getSpotifyImageUrl(albumMap);
    } else {
      // Flat persisted format: album is the album name string.
      albumName = albumRaw is String ? albumRaw : '';
      albumUri = json['album_uri'] as String?;
      imageUrl = json['image_url'] as String?;
    }

    // artists is List<Map> in the Spotify API format, List<String> in persisted format.
    // URIs are embedded in the Map entries (API) or in a separate 'artist_uris' list (persisted).
    final rawArtists = json['artists'] as List? ?? [];
    final artistNames = <String>[];
    final urisFromList = <String>[];
    for (final a in rawArtists) {
      if (a is String) {
        if (a.isNotEmpty) artistNames.add(a);
      } else if (a is Map) {
        final name = (a as Map)['name'] as String? ?? '';
        final uri = (a as Map)['uri'] as String? ?? '';
        if (name.isNotEmpty) artistNames.add(name);
        if (uri.isNotEmpty) urisFromList.add(uri);
      }
    }
    final rawUris = json['artist_uris'] as List?;
    final artistUris = urisFromList.isNotEmpty
        ? urisFromList
        : (rawUris?.whereType<String>().toList() ?? <String>[]);

    return Track(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      artists: artistNames,
      artistUris: artistUris,
      album: albumName,
      albumUri: albumUri,
      imageUrl: imageUrl,
      durationMs: json['duration_ms'] as int? ?? 0,
      previewUrl: json['preview_url'] as String?,
      uri: json['uri'] as String? ?? '',
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