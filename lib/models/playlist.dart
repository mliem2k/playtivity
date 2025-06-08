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
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      imageUrl: json['images'] != null && json['images'].isNotEmpty
          ? json['images'][0]['url']
          : null,
      trackCount: json['tracks']?['total'] ?? 0,
      uri: json['uri'] ?? '',
      ownerId: json['owner']?['id'] ?? '',
      ownerName: json['owner']?['display_name'] ?? '',
      isPublic: json['public'] ?? false,
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