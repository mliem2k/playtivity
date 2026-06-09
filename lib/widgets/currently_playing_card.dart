import 'package:flutter/material.dart';
import '../models/track.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import 'cached_image_widget.dart';
import 'equalizer_icon.dart';

class CurrentlyPlayingCard extends StatelessWidget {
  final Track track;

  const CurrentlyPlayingCard({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async => SpotifyLauncher.launchSpotifyUri('spotify:'),
      child: Container(
        color: AppTheme.surfaceRaised,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: track.imageUrl != null && track.imageUrl!.isNotEmpty
                  ? CachedImageWidget(
                      imageUrl: track.imageUrl!,
                      width: 40,
                      height: 40,
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      color: AppTheme.surfaceElevated,
                      child: const Icon(
                        Icons.music_note,
                        color: AppTheme.textSubdued,
                        size: 18,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            // Track + artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
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
            const SizedBox(width: 12),
            const EqualizerIcon(size: 18),
          ],
        ),
      ),
    );
  }
} 