import 'package:flutter/material.dart';
import '../models/track.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import 'cached_image_widget.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final int? rank;

  const TrackTile({super.key, required this.track, this.rank});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (rank != null)
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: AppTheme.textSubdued,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (rank != null) const SizedBox(width: 12),
          // Album art
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: track.imageUrl != null && track.imageUrl!.isNotEmpty
                ? CachedImageWidget(
                    imageUrl: track.imageUrl!,
                    width: 48,
                    height: 48,
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: AppTheme.surfaceElevated,
                    child: const Icon(
                      Icons.music_note,
                      color: AppTheme.textSubdued,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  track.artistsString,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Duration + play
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                track.duration,
                style: const TextStyle(
                  color: AppTheme.textSubdued,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () async =>
                    SpotifyLauncher.launchSpotifyUriAndPlay(track.uri),
                child: const Icon(
                  Icons.play_circle_filled,
                  size: 24,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
} 