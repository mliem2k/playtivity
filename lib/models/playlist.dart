class Playlist {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final int trackCount;
  final String uri;
  final String ownerId;
  final String ownerName;
  final bool isPublic;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.trackCount,
    required this.uri,
    required this.ownerId,
    required this.ownerName,
    required this.isPublic,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    // Handle both persisted format (flat keys from toJson) and Spotify API format (nested).
    String? imageUrl;
    if (json.containsKey('image_url')) {
      imageUrl = json['image_url'] as String?;
    } else if (json['images'] is List && (json['images'] as List).isNotEmpty) {
      final first = (json['images'] as List)[0];
      imageUrl = first is Map ? first['url'] as String? : null;
    }

    final tracksRaw = json['tracks'];
    final trackCount = json.containsKey('track_count')
        ? json['track_count'] as int? ?? 0
        : (tracksRaw is Map ? tracksRaw['total'] as int? ?? 0 : 0);

    final ownerId = json.containsKey('owner_id')
        ? json['owner_id'] as String? ?? ''
        : json['owner']?['id'] as String? ?? '';

    final ownerName = json.containsKey('owner_name')
        ? json['owner_name'] as String? ?? ''
        : json['owner']?['display_name'] as String? ?? '';

    final isPublic = json.containsKey('is_public')
        ? json['is_public'] as bool? ?? false
        : json['public'] as bool? ?? false;

    return Playlist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      imageUrl: imageUrl,
      trackCount: trackCount,
      uri: json['uri'] as String? ?? '',
      ownerId: ownerId,
      ownerName: ownerName,
      isPublic: isPublic,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'image_url': imageUrl,
      'track_count': trackCount,
      'uri': uri,
      'owner_id': ownerId,
      'owner_name': ownerName,
      'is_public': isPublic,
    };
  }
} 