import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../utils/friend_profile_launcher.dart';
import 'avatar_widget.dart';
import 'cached_image_widget.dart';
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
            _AlbumArt(activity: activity),
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
    return GestureDetector(
      onTap: () async => FriendProfileLauncher.openFriendProfile(
        activity.user.id,
        friendName: activity.user.displayName,
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          activity.user.displayName,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
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
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${activity.track!.artistsString} · ${activity.track!.album}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
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
    if (isCurrentlyPlaying) {
      return const Row(
        children: [
          EqualizerIcon(size: 12),
          SizedBox(width: 4),
          Text(
            'Listening now',
            style: TextStyle(
              color: AppTheme.primaryActive,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
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
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final Activity activity;
  const _AlbumArt({required this.activity});

  @override
  Widget build(BuildContext context) {
    final imageUrl = activity.track?.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CachedImageWidget(imageUrl: imageUrl, width: 48, height: 48),
      );
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.music_note, color: AppTheme.textSubdued, size: 20),
    );
  }
}
