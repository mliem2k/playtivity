import 'track.dart';
import 'playlist.dart';
import 'user.dart';

enum ActivityType { track, playlist }

class Activity {
  final User user;
  final Track? track;
  final Playlist? playlist;
  final DateTime timestamp;
  final bool isCurrentlyPlaying;
  final ActivityType type;

  Activity({
    required this.user,
    this.track,
    this.playlist,
    required this.timestamp,
    required this.isCurrentlyPlaying,
    required this.type,
  }) : assert((track != null && playlist == null && type == ActivityType.track) ||
             (playlist != null && track == null && type == ActivityType.playlist));

  factory Activity.fromJson(Map<String, dynamic> json) {
    final type = json['type'] == 'playlist' ? ActivityType.playlist : ActivityType.track;
    final timestamp = DateTime.parse(json['timestamp']);

    // Recompute from current time rather than trusting the stored flag — persisted
    // activities can be hours/days old, so a stale true would show "Listening now"
    // indefinitely after a friend stopped playing.
    final bool isCurrentlyPlaying;
    if (type == ActivityType.playlist) {
      isCurrentlyPlaying = false;
    } else {
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - timestamp.millisecondsSinceEpoch;
      isCurrentlyPlaying = elapsedMs >= 0 && elapsedMs < (5 * 60 * 1000);
    }

    return Activity(
      user: User.fromJson(json['user']),
      track: type == ActivityType.track ? Track.fromJson(json['track']) : null,
      playlist: type == ActivityType.playlist ? Playlist.fromJson(json['playlist']) : null,
      timestamp: timestamp,
      isCurrentlyPlaying: isCurrentlyPlaying,
      type: type,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'track': track?.toJson(),
      'playlist': playlist?.toJson(),
      'timestamp': timestamp.toIso8601String(),
      'is_currently_playing': isCurrentlyPlaying,
      'type': type == ActivityType.playlist ? 'playlist' : 'track',
    };
  }

  // Helper getters
  String get contentName => track?.name ?? playlist?.name ?? 'Unknown';
  String get contentUri => track?.uri ?? playlist?.uri ?? '';
  String? get contentImageUrl => track?.imageUrl ?? playlist?.imageUrl;
  String get contentSubtitle => track?.artistsString ?? 'Playlist • ${playlist?.trackCount ?? 0} tracks';
  String get contentDetails => track?.album ?? 'by ${playlist?.ownerName ?? 'Unknown'}';
} 