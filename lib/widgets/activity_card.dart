import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/activity.dart';
import '../models/playlist.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import '../utils/friend_profile_launcher.dart';
import 'avatar_widget.dart';
import 'common/album_art_widget.dart';
import 'equalizer_icon.dart';

class ActivityCard extends StatelessWidget {
  final Activity activity;

  const ActivityCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        HapticFeedback.lightImpact();
        await SpotifyLauncher.launchSpotifyUriAndPlay(activity.contentUri);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(activity: activity),
            const SizedBox(width: 12),
            Expanded(child: _InfoColumn(activity: activity)),
            const SizedBox(width: 12),
            _AlbumArt(activity: activity),
          ],
        ),
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  final Activity activity;
  const _AlbumArt({required this.activity});

  @override
  Widget build(BuildContext context) {
    final art = AlbumArtWidget(imageUrl: activity.contentImageUrl, size: 48);
    if (!activity.isCurrentlyPlaying) return art;
    return Stack(
      children: [
        art,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.primaryActive, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final Activity activity;
  const _Avatar({required this.activity});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        HapticFeedback.lightImpact();
        await FriendProfileLauncher.openFriendProfile(
          activity.user.id,
          friendName: activity.user.displayName,
        );
      },
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
        ..._contentRows(tt),
      ],
    );
  }

  List<Widget> _contentRows(TextTheme tt) {
    final String title;
    final String subtitle;

    if (activity.track != null) {
      title = activity.track!.name;
      subtitle = '${activity.track!.artistsString} · ${activity.track!.album}';
    } else if (activity.playlist != null) {
      title = activity.contentName;
      subtitle = _playlistSubtitle(activity.playlist!);
    } else {
      return const [];
    }

    return [
      const SizedBox(height: 4),
      Text(title, style: tt.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(subtitle, style: tt.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
    ];
  }

  static String _playlistSubtitle(Playlist playlist) {
    final owner = playlist.ownerName.isNotEmpty ? playlist.ownerName : null;
    final count = playlist.trackCount > 0 ? '${playlist.trackCount} tracks' : null;
    if (owner != null && count != null) return '$owner · $count';
    if (owner != null) return owner;
    if (count != null) return 'Playlist · $count';
    return 'Playlist';
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
        Text(timeago.format(timestamp), style: tt.labelSmall),
      ],
    );
  }
}
