import 'package:flutter/material.dart';
import '../models/track.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import 'common/album_art_widget.dart';
import 'equalizer_icon.dart';

class CurrentlyPlayingCard extends StatelessWidget {
  final Track track;

  const CurrentlyPlayingCard({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: () async => SpotifyLauncher.launchSpotifyUri('spotify:'),
      child: Container(
        color: AppTheme.surfaceRaised,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            AlbumArtWidget(imageUrl: track.imageUrl, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artistsString,
                    style: tt.bodyMedium,
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
