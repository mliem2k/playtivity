import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../utils/theme.dart';
import '../utils/spotify_launcher.dart';

class ArtistTile extends StatelessWidget {
  final Artist artist;
  final int? rank;

  const ArtistTile({super.key, required this.artist, this.rank});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async => SpotifyLauncher.launchSpotifyUri(artist.uri),
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textSubdued),
                  textAlign: TextAlign.center,
                ),
              ),
            if (rank != null) const SizedBox(width: 12),
            // Artist photo
            CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.surfaceElevated,
              backgroundImage: artist.imageUrl != null
                  ? CachedNetworkImageProvider(artist.imageUrl!)
                  : null,
              child: artist.imageUrl == null
                  ? const Icon(
                      Icons.person,
                      color: AppTheme.textSubdued,
                      size: 24,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Name + listeners
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (artist.monthlyListeners >= 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${_formatCount(artist.monthlyListeners)} monthly listeners',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
