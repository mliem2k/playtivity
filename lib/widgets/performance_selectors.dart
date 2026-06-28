import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../models/activity.dart';

class ActivitiesScreenDataSelector extends StatelessWidget {
  final Widget Function(
    BuildContext context, 
    bool isAuthenticated,
    bool isLoading,
    List<Activity> activities,
    String? error,
  ) builder;
  
  const ActivitiesScreenDataSelector({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector2<AuthProvider, SpotifyProvider, _ActivitiesScreenData>(
      selector: (context, authProvider, spotifyProvider) => _ActivitiesScreenData(
        isAuthenticated: authProvider.isAuthenticated,
        isLoading: authProvider.isLoading || spotifyProvider.isLoading || spotifyProvider.isSkeletonLoading,
        activities: spotifyProvider.friendsActivities,
        error: spotifyProvider.error,
      ),
      shouldRebuild: (previous, next) {
        if (previous.isAuthenticated != next.isAuthenticated ||
            previous.isLoading != next.isLoading ||
            previous.error != next.error) {
          return true;
        }
        if (previous.activities.length != next.activities.length) {
          return true;
        }
        for (int i = 0; i < previous.activities.length; i++) {
          if (previous.activities[i].isCurrentlyPlaying !=
                  next.activities[i].isCurrentlyPlaying ||
              previous.activities[i].timestamp != next.activities[i].timestamp ||
              previous.activities[i].contentUri != next.activities[i].contentUri) {
            return true;
          }
        }
        return false;
      },
      builder: (context, data, child) => builder(
        context,
        data.isAuthenticated,
        data.isLoading,
        data.activities,
        data.error,
      ),
    );
  }
}

class _ActivitiesScreenData {
  final bool isAuthenticated;
  final bool isLoading;
  final List<Activity> activities;
  final String? error;
  
  const _ActivitiesScreenData({
    required this.isAuthenticated,
    required this.isLoading,
    required this.activities,
    required this.error,
  });
}
