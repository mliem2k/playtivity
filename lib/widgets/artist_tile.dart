import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';
import '../utils/spotify_launcher.dart';

class ArtistTile extends StatelessWidget {
  final Artist artist;
  final int? rank;

  const ArtistTile({
    super.key,
    required this.artist,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rank number
            if (rank != null)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).primaryColor,
                ),
                child: Center(
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            
            if (rank != null) const SizedBox(width: 12),
            
            // Artist Image
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[300],
              backgroundImage: artist.imageUrl != null
                  ? CachedNetworkImageProvider(artist.imageUrl!)
                  : null,
              child: artist.imageUrl == null
                  ? const Icon(
                      Icons.person,
                      color: Colors.grey,
                      size: 24,
                    )
                  : null,
            ),
          ],
        ),
        title: Text(
          artist.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: artist.monthlyListeners >= 0
            ? Text(
                '${_formatCount(artist.monthlyListeners)} monthly listeners',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              )
            : null,

        onTap: () async {
          // Clicking the tile goes to the artist profile without playing
          await SpotifyLauncher.launchSpotifyUri(artist.uri);
        },
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
} 