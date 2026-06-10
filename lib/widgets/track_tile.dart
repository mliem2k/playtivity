import 'package:flutter/material.dart';
import '../models/track.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';
import 'common/album_art_widget.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final int? rank;

  const TrackTile({super.key, required this.track, this.rank});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: () async => SpotifyLauncher.launchSpotifyUriAndPlay(track.uri),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (rank != null)
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: tt.bodyLarge?.copyWith(color: AppTheme.textSubdued),
                  textAlign: TextAlign.center,
                ),
              ),
            if (rank != null) const SizedBox(width: 12),
            AlbumArtWidget(imageUrl: track.imageUrl, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    style: tt.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
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
            Text(
              track.duration,
              style: tt.labelSmall?.copyWith(
                color: AppTheme.textSubdued,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
