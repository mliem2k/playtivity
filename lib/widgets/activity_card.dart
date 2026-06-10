import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../utils/friend_profile_launcher.dart';
import 'avatar_widget.dart';
import 'common/album_art_widget.dart';
import 'equalizer_icon.dart';
import 'package:timeago/timeago.dart' as timeago;

class ActivityCard extends StatelessWidget {
  final Activity activity;

  const ActivityCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async =>
          SpotifyLauncher.launchSpotifyUriAndPlay(activity.contentUri),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(activity: activity),
            const SizedBox(width: 16),
            Expanded(child: _InfoColumn(activity: activity)),
            const SizedBox(width: 12),
            AlbumArtWidget(imageUrl: activity.track?.imageUrl, size: 48),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Activity activity;
  const _Avatar({required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async => FriendProfileLauncher.openFriendProfile(
        activity.user.id,
        friendName: activity.user.displayName,
      ),
      customBorder: const CircleBorder(),
      child: AvatarWidget(
        imageUrl: activity.user.imageUrl,
        displayName: activity.user.displayName,
        radius: 22,
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final Activity activity;
  const _InfoColumn({required this.activity});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          activity.user.displayName,
          style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        _StatusLine(
          isCurrentlyPlaying: activity.isCurrentlyPlaying,
          timestamp: activity.timestamp,
        ),
        if (activity.track != null) ...[
          const SizedBox(height: 4),
          Text(
            activity.track!.name,
            style: tt.bodyLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${activity.track!.artistsString} · ${activity.track!.album}',
            style: tt.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final bool isCurrentlyPlaying;
  final DateTime timestamp;
  const _StatusLine({required this.isCurrentlyPlaying, required this.timestamp});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (isCurrentlyPlaying) {
      return Row(
        children: [
          const EqualizerIcon(size: 12),
          const SizedBox(width: 4),
          Text(
            'Listening now',
            style: tt.labelSmall?.copyWith(color: AppTheme.primaryActive),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.history, size: 12, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          timeago.format(timestamp),
          style: tt.labelSmall,
        ),
      ],
    );
  }
}
