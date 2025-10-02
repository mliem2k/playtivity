import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/track.dart';
import '../models/user.dart';
import '../utils/spotify_launcher.dart';
import '../utils/friend_profile_launcher.dart';
import 'avatar_widget.dart';
import 'cached_image_widget.dart';
import 'common/clickable_content.dart';

class UserInfoSection extends StatelessWidget {
  final User user;
  final bool isCurrentlyPlaying;
  final DateTime timestamp;
  final String contentUri;

  const UserInfoSection({
    super.key,
    required this.user,
    required this.isCurrentlyPlaying,
    required this.timestamp,
    required this.contentUri,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // User Avatar - clickable
        ClickableContent.standard(
          onTap: () async {
            await FriendProfileLauncher.openFriendProfile(
              user.id,
              friendName: user.displayName,
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: AvatarWidget(
            imageUrl: user.imageUrl,
            displayName: user.displayName,
            radius: 20,
          ),
        ),
        
        const SizedBox(width: 12),
        
        // User Name and Status
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClickableContent.compact(
                onTap: () async {
                  await FriendProfileLauncher.openFriendProfile(
                    user.id,
                    friendName: user.displayName,
                  );
                },
                child: Text(
                  user.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              ClickableContent.compact(
                onTap: () async {
                  await SpotifyLauncher.launchSpotifyUri(contentUri);
                },
                child: Row(
                  children: [
                    Icon(
                      isCurrentlyPlaying 
                          ? Icons.play_circle_filled 
                          : Icons.history,
                      size: 16,
                      color: isCurrentlyPlaying 
                          ? Theme.of(context).primaryColor 
                          : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getActivityStatusText(isCurrentlyPlaying, timestamp),
                      style: TextStyle(
                        color: isCurrentlyPlaying || _isRecentActivity(timestamp)
                            ? Theme.of(context).primaryColor 
                            : Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // Timestamp
        Text(
          timeago.format(timestamp),
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _getActivityStatusText(bool isCurrentlyPlaying, DateTime timestamp) {
    if (isCurrentlyPlaying) {
      return 'Currently playing';
    } else if (_isRecentActivity(timestamp)) {
      return 'Recently played';
    } else {
      return 'Played';
    }
  }

  bool _isRecentActivity(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    return difference.inMinutes < 5;
  }
}

class TrackInfoSection extends StatelessWidget {
  final Track track;

  const TrackInfoSection({
    super.key,
    required this.track,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Album Art
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedImageWidget(
            imageUrl: track.imageUrl,
            width: 60,
            height: 60,
            placeholder: Container(
              width: 60,
              height: 60,
              color: Colors.grey[300],
              child: const Icon(Icons.music_note, color: Colors.grey),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Track Details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Track Name - clickable
              ClickableContent.compact(
                onTap: () async {
                  await SpotifyLauncher.launchSpotifyUri(track.uri);
                },
                child: Text(
                  track.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              
              // Artists - clickable
              _buildArtistRow(context, track),
              const SizedBox(height: 4),
              
              // Album - clickable
              if (track.albumUri != null)
                ClickableContent.compact(
                  onTap: () async {
                    await SpotifyLauncher.launchSpotifyUri(track.albumUri!);
                  },
                  child: Text(
                    track.album,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                Text(
                  track.album,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArtistRow(BuildContext context, Track track) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(track.artists.length, (index) {
        final artist = track.artists[index];
        final hasUri = index < track.artistUris.length;
        
        if (hasUri) {
          return ClickableContent.compact(
            onTap: () async {
              await SpotifyLauncher.launchSpotifyUri(track.artistUris[index]);
            },
            child: Text(
              artist,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          );
        } else {
          return Text(
            artist,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          );
        }
      }),
    );
  }

}