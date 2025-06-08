import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../utils/spotify_launcher.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final int? rank;

  const TrackTile({
    super.key,
    required this.track,
    this.rank,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: [
          // Main tile content - no longer clickable
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Leading content (rank + album art)
                Row(
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
                    
                    // Album Art
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.grey[300],
                      ),
                      child: track.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: track.imageUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.music_note, size: 24),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.music_note, size: 24),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.music_note,
                              color: Colors.grey,
                              size: 24,
                            ),
                    ),
                  ],
                ),
                
                const SizedBox(width: 16),
                
                // Track info - with padding for play button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 60), // Space for duration + play button
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artistsString,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          track.album,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Trailing content (duration + play button) - positioned absolutely, only clickable element
          Positioned(
            right: 16,
            top: 16,
            bottom: 16,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  track.duration,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      // Only the play button launches and plays the track
                      await SpotifyLauncher.launchSpotifyUriAndPlay(track.uri);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Icon(
                      Icons.play_circle_filled,
                      size: 24,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 