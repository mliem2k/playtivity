import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../utils/spotify_launcher.dart';
import 'activity_card_components.dart';

class ActivityCard extends StatelessWidget {
  final Activity activity;

  const ActivityCard({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Stack(
        children: [
          // Main card content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Info Section
                UserInfoSection(
                  user: activity.user,
                  isCurrentlyPlaying: activity.isCurrentlyPlaying,
                  timestamp: activity.timestamp,
                  contentUri: activity.contentUri,
                ),
                
                const SizedBox(height: 16),
                
                // Track Info Section
                if (activity.track != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 48), // Space for play button
                    child: TrackInfoSection(track: activity.track!),
                  ),
              ],
            ),
          ),
          
          // Play button - positioned absolutely
          Positioned(
            right: 16,
            top: 88, // Align with track info
            child: _PlayButton(contentUri: activity.contentUri),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final String contentUri;

  const _PlayButton({required this.contentUri});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await SpotifyLauncher.launchSpotifyUriAndPlay(contentUri);
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).primaryColor.withAlpha(26), // 0.1 * 255 ≈ 26
          ),
          child: Icon(
            Icons.play_arrow,
            color: Theme.of(context).primaryColor,
            size: 24,
          ),
        ),
      ),
    );
  }
}