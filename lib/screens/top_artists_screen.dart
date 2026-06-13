import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/spotify_provider.dart';
import '../models/artist.dart';
import '../utils/theme.dart';
import '../widgets/artist_tile.dart';
import '../widgets/common/state_display_widget.dart';
import '../widgets/common/profile_skeleton.dart';

class TopArtistsScreen extends StatefulWidget {
  final ScrollController? scrollController;
  const TopArtistsScreen({super.key, this.scrollController});

  @override
  State<TopArtistsScreen> createState() => _TopArtistsScreenState();
}

class _TopArtistsScreenState extends State<TopArtistsScreen> {
  late final ScrollController _scrollController;
  bool _ownScrollController = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _ownScrollController = widget.scrollController == null;
  }

  @override
  void dispose() {
    if (_ownScrollController) _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    final spotifyProvider = context.read<SpotifyProvider>();
    await spotifyProvider.refreshProfileData(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppTheme.primary,
        child: Selector<SpotifyProvider,
            ({List<Artist> topArtists, bool isLoading})>(
          selector: (_, sp) => (
            topArtists: sp.topArtists,
            isLoading: sp.isLoading,
          ),
          shouldRebuild: (prev, next) =>
              !identical(prev.topArtists, next.topArtists) ||
              prev.isLoading != next.isLoading,
          builder: (ctx, data, _) => CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      'Top Artists',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
              _buildContentSliver(data.topArtists, data.isLoading),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentSliver(List<Artist> topArtists, bool isLoading) {
    if (isLoading) {
      return const SliverToBoxAdapter(child: ProfileSkeleton(count: 10));
    }
    if (topArtists.isEmpty) {
      return SliverFillRemaining(
        child: StateDisplayWidget.empty(
          title: 'No top artists found',
          icon: Icons.person_outline,
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            if (i.isOdd) {
              return const Divider(height: 1, color: AppTheme.dividerColor);
            }
            final idx = i ~/ 2;
            return RepaintBoundary(
              child: ArtistTile(artist: topArtists[idx], rank: idx + 1),
            );
          },
          childCount: topArtists.length * 2 - 1,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
        ),
      ),
    );
  }
}
