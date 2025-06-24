import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/activity.dart';
import '../models/track.dart';
import '../utils/spotify_launcher.dart';
import '../utils/friend_profile_launcher.dart';

class ActivityCard extends StatelessWidget {
  final Activity activity;

  const ActivityCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          // Main card content - no longer clickable
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // User Info Row
              Row(
                children: [
                  // User Avatar - clickable
                  InkWell(
                    onTap: () async {
                      // Launch the user profile when avatar is tapped
                      await FriendProfileLauncher.openFriendProfile(
                        activity.user.id,
                        friendName: activity.user.displayName,
                      );
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).primaryColor,
                      backgroundImage: activity.user.imageUrl != null
                          ? CachedNetworkImageProvider(activity.user.imageUrl!)
                          : null,
                      child: activity.user.imageUrl == null
                          ? Text(
                              activity.user.displayName.isNotEmpty
                                  ? activity.user.displayName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // User Name and Status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () async {
                            // Launch the user profile when name is tapped
                            await FriendProfileLauncher.openFriendProfile(
                              activity.user.id,
                              friendName: activity.user.displayName,
                            );
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                            child: Text(
                              activity.user.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            // Launch the content (track or playlist) when status is tapped
                            await SpotifyLauncher.launchSpotifyUri(activity.contentUri);
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                            child: Row(
                              children: [
                                Icon(
                                  activity.isCurrentlyPlaying 
                                      ? Icons.play_circle_filled 
                                      : Icons.history,
                                  size: 16,
                                  color: activity.isCurrentlyPlaying 
                                      ? Theme.of(context).primaryColor 
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getActivityStatusText(activity, context),
                                  style: TextStyle(
                                    color: activity.isCurrentlyPlaying || _isRecentActivity(activity)
                                        ? Theme.of(context).primaryColor 
                                        : Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Content Info Row (Track or Playlist) - with padding for play button
              Padding(
                padding: const EdgeInsets.only(right: 48), // Space for play button
                child: Row(
                  children: [
                    // Content Image (Album Art or Playlist Cover) - clickable
                    InkWell(
                      onTap: () async {
                        if (activity.type == ActivityType.track && activity.track != null) {
                          // For tracks, try to go to the album page
                          await _launchAlbum(activity.track!);
                        } else {
                          // For playlists, go to the playlist page
                          await SpotifyLauncher.launchSpotifyUri(activity.contentUri);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[300],
                        ),
                        child: activity.contentImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: activity.contentImageUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: Colors.grey[300],
                                    child: Icon(
                                      activity.type == ActivityType.playlist 
                                          ? Icons.queue_music 
                                          : Icons.music_note,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[300],
                                    child: Icon(
                                      activity.type == ActivityType.playlist 
                                          ? Icons.queue_music 
                                          : Icons.music_note,
                                    ),
                                  ),
                                ),
                              )
                            : Icon(
                                activity.type == ActivityType.playlist 
                                    ? Icons.queue_music 
                                    : Icons.music_note,
                                color: Colors.grey,
                              ),
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // Content Details - clickable
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          // Launch the content (track or playlist) when content details are tapped
                          await _launchAlbum(activity.track!);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activity.contentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                activity.contentSubtitle,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                activity.contentDetails,
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
                    ),
                  ],
                ),
              ),
              ],
            ),
          ),
          
          // Play button - positioned absolutely, only clickable element
          Positioned(
            right: 16,
            top: 88, // 16 (padding) + 56 (user info section) + 16 (spacing) = 88px from top to align with album image center
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  // Only the play button launches and plays the content
                  await SpotifyLauncher.launchSpotifyUriAndPlay(activity.contentUri);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getActivityStatusText(Activity activity, BuildContext context) {
    if (activity.isCurrentlyPlaying || _isRecentActivity(activity)) {
      if (activity.type == ActivityType.playlist) {
        return 'Listening to playlist now';
      } else {
        return 'Listening now';
      }
    } else {
      if (activity.type == ActivityType.playlist) {
        return 'Played playlist ${timeago.format(activity.timestamp)}';
      } else {
        return 'Played ${timeago.format(activity.timestamp)}';
      }
    }
  }

  bool _isRecentActivity(Activity activity) {
    final now = DateTime.now();
    final timestamp = activity.timestamp.toLocal();
    final difference = now.difference(timestamp);
    return difference.inMinutes < 1;
  }

  Future<void> _launchAlbum(Track track) async {
    try {
      // Use the album URI directly from the track data
      if (track.albumUri != null && track.albumUri!.isNotEmpty) {
        await SpotifyLauncher.launchSpotifyUri(track.albumUri!);
        print('✅ Launched album: ${track.albumUri}');
      } else {
        print('⚠️ No album URI available, not launching anything');
      }
    } catch (e) {
      print('❌ Error launching album: $e');
    }
  }


} 