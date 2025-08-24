import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../models/activity.dart';
import '../models/user.dart';

/// High-performance selector widgets that only rebuild when specific data changes
/// Eliminates unnecessary widget rebuilds caused by Consumer2<AuthProvider, SpotifyProvider>

class AuthStatusSelector extends StatelessWidget {
  final Widget Function(BuildContext context, bool isAuthenticated) builder;
  
  const AuthStatusSelector({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector<AuthProvider, bool>(
      selector: (context, authProvider) => authProvider.isAuthenticated,
      builder: (context, isAuthenticated, child) => builder(context, isAuthenticated),
    );
  }
}

class LoadingStateSelector extends StatelessWidget {
  final Widget Function(BuildContext context, bool isLoading) builder;
  final bool includeSpotifyLoading;
  
  const LoadingStateSelector({
    super.key,
    required this.builder,
    this.includeSpotifyLoading = true,
  });
  
  @override
  Widget build(BuildContext context) {
    if (includeSpotifyLoading) {
      return Selector2<AuthProvider, SpotifyProvider, bool>(
        selector: (context, authProvider, spotifyProvider) => 
            authProvider.isLoading || spotifyProvider.isLoading,
        builder: (context, isLoading, child) => builder(context, isLoading),
      );
    }
    
    return Selector<AuthProvider, bool>(
      selector: (context, authProvider) => authProvider.isLoading,
      builder: (context, isLoading, child) => builder(context, isLoading),
    );
  }
}

class CurrentUserSelector extends StatelessWidget {
  final Widget Function(BuildContext context, User? currentUser) builder;
  
  const CurrentUserSelector({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector<AuthProvider, User?>(
      selector: (context, authProvider) => authProvider.currentUser,
      builder: (context, currentUser, child) => builder(context, currentUser),
    );
  }
}

class FriendsActivitiesSelector extends StatelessWidget {
  final Widget Function(BuildContext context, List<Activity> activities) builder;
  
  const FriendsActivitiesSelector({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, List<Activity>>(
      selector: (context, spotifyProvider) => spotifyProvider.friendsActivities,
      shouldRebuild: (previous, next) {
        // Only rebuild if the list actually changed, not just object reference
        if (previous.length != next.length) return true;
        
        // Check if any activity IDs changed (more efficient than deep comparison)
        for (int i = 0; i < previous.length; i++) {
          if (previous[i].contentUri != next[i].contentUri ||
              previous[i].timestamp != next[i].timestamp) {
            return true;
          }
        }
        return false;
      },
      builder: (context, activities, child) => builder(context, activities),
    );
  }
}

class ErrorStateSelector extends StatelessWidget {
  final Widget Function(BuildContext context, String? error) builder;
  
  const ErrorStateSelector({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector2<AuthProvider, SpotifyProvider, String?>(
      selector: (context, authProvider, spotifyProvider) => 
          authProvider.errorMessage ?? spotifyProvider.errorMessage,
      builder: (context, error, child) => builder(context, error),
    );
  }
}

class LastUpdatedSelector extends StatelessWidget {
  final Widget Function(BuildContext context, DateTime? lastUpdated) builder;
  
  const LastUpdatedSelector({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector<SpotifyProvider, DateTime?>(
      selector: (context, spotifyProvider) => spotifyProvider.lastUpdated,
      builder: (context, lastUpdated, child) => builder(context, lastUpdated),
    );
  }
}

/// Composite selector for common combinations to reduce nesting
class HomeScreenDataSelector extends StatelessWidget {
  final Widget Function(
    BuildContext context, 
    bool isAuthenticated,
    bool isLoading,
    List<Activity> activities,
    String? error,
  ) builder;
  
  const HomeScreenDataSelector({
    super.key,
    required this.builder,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector4<AuthProvider, SpotifyProvider, bool, List<Activity>>(
      selector: (context, authProvider, spotifyProvider) => _HomeScreenData(
        isAuthenticated: authProvider.isAuthenticated,
        isLoading: authProvider.isLoading || spotifyProvider.isLoading,
        activities: spotifyProvider.friendsActivities,
        error: authProvider.errorMessage ?? spotifyProvider.errorMessage,
      ),
      shouldRebuild: (previous, next) {
        return previous.isAuthenticated != next.isAuthenticated ||
               previous.isLoading != next.isLoading ||
               previous.activities.length != next.activities.length ||
               previous.error != next.error;
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

class _HomeScreenData {
  final bool isAuthenticated;
  final bool isLoading;
  final List<Activity> activities;
  final String? error;
  
  const _HomeScreenData({
    required this.isAuthenticated,
    required this.isLoading,
    required this.activities,
    required this.error,
  });
}

/// Optimized provider initialization widget
class OptimizedProviderSelector<T extends ChangeNotifier, R> extends StatelessWidget {
  final R Function(BuildContext context, T provider) selector;
  final Widget Function(BuildContext context, R data, Widget? child) builder;
  final Widget? child;
  final bool Function(R previous, R next)? shouldRebuild;
  
  const OptimizedProviderSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.child,
    this.shouldRebuild,
  });
  
  @override
  Widget build(BuildContext context) {
    return Selector<T, R>(
      selector: selector,
      shouldRebuild: shouldRebuild,
      builder: builder,
      child: child,
    );
  }
}