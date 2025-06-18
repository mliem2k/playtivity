import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../widgets/activity_card.dart';
import '../widgets/activity_skeleton.dart';
import '../widgets/last_updated_indicator.dart';
import '../utils/auth_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
    super.dispose();
  }

  void _startAutoRefresh() {
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _refreshData();
    });
  }

  Future<void> _loadData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    
    // Ensure authentication is initialized before loading data
    if (!authProvider.isInitialized) {
      print('⚠️ Authentication not yet initialized, skipping data load');
      return;
    }
    
    if (authProvider.isAuthenticated) {
      // Use fast initial load with skeleton
      await spotifyProvider.fastInitialLoad();
      
      // Update widget with current user data
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      print('⚠️ No authentication available - cannot load friend activities');
    }
  }

  Future<void> _refreshData() async {
    final authProvider = context.read<AuthProvider>();
    final spotifyProvider = context.read<SpotifyProvider>();
    
    // Ensure authentication is initialized before refreshing data
    if (!authProvider.isInitialized) {
      print('⚠️ Authentication not yet initialized, skipping data refresh');
      return;
    }
    
    if (authProvider.isAuthenticated) {
      // Silent refresh - don't show loading spinner
      await spotifyProvider.silentRefresh();
      
      // Update widget with current user data
      await spotifyProvider.updateWidget(currentUser: authProvider.currentUser);
    } else {
      print('⚠️ No authentication available - cannot refresh friend activities');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // Extend body behind app bar
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              title: const Text(
                'Friends\' Activities',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),      body: SafeArea(
        child: Consumer2<AuthProvider, SpotifyProvider>(
          builder: (context, authProvider, spotifyProvider, child) {
            return Column(
              children: [
                
                // Main content
                Expanded(
                  child: _buildMainContent(spotifyProvider),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
  Widget _buildMainContent(SpotifyProvider spotifyProvider) {
    // Show skeleton loading for initial load
    if (spotifyProvider.isSkeletonLoading) {
      return Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16,
              ),
              itemCount: 6, // Show 6 skeleton cards
              itemBuilder: (context, index) {
                return const ActivitySkeleton();
              },
            ),
          ),
        ],
      );
    }

    if (spotifyProvider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }          if (spotifyProvider.error != null) {
            final isAuthError = spotifyProvider.error!.contains('Authentication expired');
            
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isAuthError ? Icons.lock_outline : Icons.error_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isAuthError ? 'Authentication Required' : 'Error loading activities',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    spotifyProvider.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isAuthError) ...[
                    ElevatedButton(
                      onPressed: () async {
                        final success = await AuthUtils.handleReAuthentication(context);
                        if (success && mounted) {
                          // Clear error and refresh data
                          spotifyProvider.clearError();
                          _loadData();
                        }
                      },
                      child: const Text('Login Again'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        spotifyProvider.clearError();
                        _refreshData();
                      },
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

          final activities = spotifyProvider.friendsActivities;          if (activities.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.music_note_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No recent activities',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your friends haven\'t been listening to music recently',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshData,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            );
          }          return RefreshIndicator(
            onRefresh: _refreshData,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      LastUpdatedIndicator(
                        lastUpdated: spotifyProvider.lastUpdated,
                        isRefreshing: spotifyProvider.isRefreshing,
                      ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: 16,
                  ),
                  sliver: SliverList.builder(
                    itemCount: activities.length,
                    itemBuilder: (context, index) {
                      final activity = activities[index];
                      return ActivityCard(activity: activity);
                    },
                  ),
                ),
              ],
            ),
          );
  }
} 