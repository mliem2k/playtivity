import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../models/activity.dart';
import '../widgets/activity_card.dart';
import '../widgets/activity_skeleton.dart';
import '../widgets/last_updated_indicator.dart';
import '../widgets/optimized_list_view.dart';
import '../widgets/blurred_app_bar.dart';
import '../services/debounced_refresh_service.dart';
import '../utils/auth_utils.dart';
import '../services/app_logger.dart';
import '../constants/app_constants.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> 
    with DebouncedRefreshMixin {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Delay initial data load to ensure providers are fully initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    DebouncedRefreshService.cancel(DebounceKeys.homeRefresh);
    super.dispose();
  }

  void _startAutoRefresh() {
    // Auto-refresh every 30 seconds with debouncing
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        DebouncedRefreshService.throttle(
          DebounceKeys.homeRefresh,
          const Duration(seconds: 5), // Prevent spam refreshes
          _refreshData,
        );
      }
    });
  }

  Future<void> _loadData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    
    // Ensure authentication is initialized before loading data
    if (!authProvider.isInitialized) {
      AppLogger.warning('Authentication not yet initialized, skipping data load');
      return;
    }
    
    if (authProvider.isAuthenticated) {
      // Use fast initial load with skeleton
      await spotifyProvider.fastInitialLoad();
      
      // Update widget with current user data
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      AppLogger.warning('No authentication available - cannot load friend activities');
    }
  }

  Future<void> _refreshData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    
    // Ensure authentication is initialized before refreshing data
    if (!authProvider.isInitialized) {
      AppLogger.warning('Authentication not yet initialized, skipping data refresh');
      return;
    }
    
    if (authProvider.isAuthenticated) {
      // Silent refresh - don't show loading spinner
      await spotifyProvider.silentRefresh();
      
      // Update widget with current user data
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      AppLogger.warning('No authentication available - cannot refresh friend activities');
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const BlurredAppBar(title: 'Friends\' Activities'),
      body: SafeArea(
        child: Consumer2<AuthProvider, SpotifyProvider>(
          builder: (context, authProvider, spotifyProvider, child) {
            if (!authProvider.isAuthenticated) {
              return _buildAuthenticationRequired();
            }
            
            return Column(
              children: [
                // Last updated indicator
                LastUpdatedIndicator(
                  lastUpdated: spotifyProvider.lastUpdated,
                  isRefreshing: spotifyProvider.isLoading,
                ),
                
                // Main content
                Expanded(
                  child: _buildMainContent(
                    spotifyProvider.isLoading,
                    spotifyProvider.friendsActivities,
                    spotifyProvider.error,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
  Widget _buildAuthenticationRequired() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          const Text(
            'Authentication Required',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppConstants.smallPadding),
          const Text(
            'Please log in to view friends\' activities',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isLoading, List<Activity> activities, String? error) {
    // Show skeleton loading for initial load
    if (isLoading && activities.isEmpty) {
      return _buildSkeletonLoader();
    }

    if (isLoading && activities.isNotEmpty) {
      // Show activities with loading indicator
      return _buildActivitiesList(activities, showLoadingIndicator: true);
    }

    if (error != null) {
      return _buildErrorState(error);
    }

    if (activities.isEmpty) {
      return _buildEmptyState();
    }

    return _buildActivitiesList(activities);
  }

  Widget _buildSkeletonLoader() {
    return OptimizedListView<int>(
      items: List.generate(6, (index) => index),
      itemHeight: 200, // Approximate height of ActivitySkeleton
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      itemBuilder: (context, _, index) => const ActivitySkeleton(),
    );
  }

  Widget _buildErrorState(String error) {
    final isAuthError = error.contains('Authentication expired');
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isAuthError ? Icons.lock_outline : Icons.error_outline,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          Text(
            isAuthError ? 'Authentication Required' : 'Error loading activities',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppConstants.smallPadding),
          Text(
            error,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          if (isAuthError) ...[
            ElevatedButton(
              onPressed: () => _handleReAuthentication(),
              child: const Text('Login Again'),
            ),
            const SizedBox(height: AppConstants.smallPadding),
            TextButton(
              onPressed: () => _handleRetry(),
              child: const Text('Retry'),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: _refreshData,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.music_note_outlined,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          Text(
            'No recent activities',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppConstants.smallPadding),
          const Text(
            'Your friends haven\'t been listening to music recently',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          ElevatedButton(
            onPressed: _refreshData,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesList(List<Activity> activities, {bool showLoadingIndicator = false}) {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: CustomScrollView(
        slivers: [
          if (showLoadingIndicator)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(),
            ),
          SliverPadding(
            padding: const EdgeInsets.all(AppConstants.defaultPadding),
            sliver: OptimizedSliverList<Activity>(
              items: activities,
              itemExtent: 200, // Approximate height of ActivityCard
              itemBuilder: (context, activity, index) => RepaintBoundary(
                child: ActivityCard(activity: activity),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReAuthentication() async {
    final success = await AuthUtils.handleReAuthentication(context);
    if (success && mounted) {
      debouncedRefresh(DebounceKeys.homeRefresh, const Duration(milliseconds: 500), _loadData);
    }
  }

  void _handleRetry() {
    final spotifyProvider = context.read<SpotifyProvider>();
    spotifyProvider.clearError();
    debouncedRefresh(DebounceKeys.homeRefresh, const Duration(milliseconds: 300), _refreshData);
  }
} 