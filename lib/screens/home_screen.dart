import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../widgets/activity_card.dart';
import '../widgets/activity_skeleton.dart';
import '../widgets/refresh_indicator_bar.dart';
import '../widgets/last_updated_indicator.dart';
import '../services/spotify_service.dart';

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
    
    final token = await authProvider.getValidToken();
    final spDcCookie = authProvider.spDcCookie;
    
    if (spDcCookie != null) {
      // Use fast initial load with skeleton
      await spotifyProvider.fastInitialLoad(
        token ?? '', // Pass empty string if no OAuth token
        spDcCookie: spDcCookie
      );
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
    
    final token = await authProvider.getValidToken();
    final spDcCookie = authProvider.spDcCookie;
    
    if (spDcCookie != null) {
      // Silent refresh - don't show loading spinner
      // For cookie-only auth, only refresh friends' activities
      if (token != null) {
        // Full OAuth + cookie refresh
        await spotifyProvider.silentRefresh(token, spDcCookie: spDcCookie);
      } else {
        // Cookie-only refresh (just friends' activities)
        await spotifyProvider.loadFriendsActivities('', spDcCookie: spDcCookie, showLoading: false);
      }
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
      ),
      body: Consumer2<AuthProvider, SpotifyProvider>(
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
    );
  }

  Widget _buildMainContent(SpotifyProvider spotifyProvider) {
    // Show skeleton loading for initial load
    if (spotifyProvider.isSkeletonLoading) {
      return Column(
        children: [
          // Add proper spacing to account for the app bar
          SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight + 16),
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
      return Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

          if (spotifyProvider.error != null) {
            return Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading activities',
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
                        ElevatedButton(
                          onPressed: _refreshData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          final activities = spotifyProvider.friendsActivities;

          if (activities.isEmpty) {
            return Column(
              children: [
                SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
                Expanded(
                  child: Center(
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
                  ),
                ),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshData,
            edgeOffset: kToolbarHeight,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Add proper spacing to account for the app bar
                      SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight + 8),
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