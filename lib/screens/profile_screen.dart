import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/spotify_provider.dart';
import '../widgets/track_tile.dart';
import '../widgets/artist_tile.dart';
import '../widgets/currently_playing_card.dart';
import '../widgets/refresh_indicator_bar.dart';
import '../utils/spotify_launcher.dart';
import 'settings_screen.dart';
import '../services/app_logger.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Delay initial data load to ensure providers are fully initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      // Show loading only if we have no cached data
      final showLoading = spotifyProvider.topTracks.isEmpty && spotifyProvider.topArtists.isEmpty;
      await spotifyProvider.refreshData(showLoading: showLoading);
    } else {
      AppLogger.warning('No authentication available - cannot load profile data');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      extendBodyBehindAppBar: true, // Extend body behind app bar
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: isDark ? 20 : 10, sigmaY: isDark ? 20 : 10),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor.withValues(alpha: 230),
                boxShadow: [], // Empty box shadow
              ),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: const Text(
                  'Profile',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),      body: SafeArea(
        child: Consumer2<AuthProvider, SpotifyProvider>(
          builder: (context, authProvider, spotifyProvider, child) {
            final user = authProvider.currentUser;
            
            return Column(
              children: [
                // Refresh indicator bar
                RefreshIndicatorBar(
                  isRefreshing: spotifyProvider.isRefreshing,
                  message: 'Updating profile data...',
                ),
                // User Profile Header
                Container(
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: 24,
                  ),
                child: Column(
                  children: [
                    // Profile Picture
                    GestureDetector(
                      onTap: () async {
                        if (user != null) {
                          final spotifyUri = 'spotify:user:${user.id}';
                          await SpotifyLauncher.launchSpotifyUri(spotifyUri);
                        }
                      },
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: Theme.of(context).primaryColor,
                        backgroundImage: user?.imageUrl != null
                            ? CachedNetworkImageProvider(user!.imageUrl!)
                            : null,
                        child: user?.imageUrl == null
                            ? Text(
                                user?.displayName.isNotEmpty == true
                                    ? user!.displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // User Name
                    Text(
                      user?.displayName ?? 'Unknown User',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // Followers
                    Text(
                      '${user?.followers ?? 0} followers',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Currently Playing
              if (spotifyProvider.currentlyPlaying != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CurrentlyPlayingCard(
                    track: spotifyProvider.currentlyPlaying!,
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // Tabs
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Top Songs'),
                  Tab(text: 'Top Artists'),
                ],
              ),
              
              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Top Songs Tab
                    _buildTopSongsTab(spotifyProvider),
                    
                    // Top Artists Tab
                    _buildTopArtistsTab(spotifyProvider),
                  ],
                ),
              ),            ],
          );
        },
        ),
      ),
    );
  }

  Widget _buildTopSongsTab(SpotifyProvider spotifyProvider) {
    if (spotifyProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (spotifyProvider.topTracks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No top tracks found'),
          ],
        ),
      );
    }    return ListView.builder(
      padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
      itemCount: spotifyProvider.topTracks.length,
      itemBuilder: (context, index) {
        final track = spotifyProvider.topTracks[index];
        return TrackTile(
          track: track,
          rank: index + 1,
        );
      },
    );
  }

  Widget _buildTopArtistsTab(SpotifyProvider spotifyProvider) {
    if (spotifyProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (spotifyProvider.topArtists.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No top artists found'),
          ],
        ),
      );
    }    return ListView.builder(
      padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 16),
      itemCount: spotifyProvider.topArtists.length,
      itemBuilder: (context, index) {
        final artist = spotifyProvider.topArtists[index];
        return ArtistTile(
          artist: artist,
          rank: index + 1,
        );
      },
    );
  }
} 