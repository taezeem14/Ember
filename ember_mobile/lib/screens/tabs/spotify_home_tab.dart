import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../models/song.dart';
import '../../models/playlist.dart';
import '../../providers/player_provider.dart';
import '../../services/spotify_service.dart';
import '../../theme/ember_theme.dart';
import '../settings_screen.dart';
import '../sound_shaping_sheet.dart';
import '../track_options_sheet.dart';

class SpotifyHomeTab extends StatefulWidget {
  final VoidCallback onOpenLibrary;
  final VoidCallback onOpenSearch;

  const SpotifyHomeTab({
    super.key,
    required this.onOpenLibrary,
    required this.onOpenSearch,
  });

  @override
  State<SpotifyHomeTab> createState() => _SpotifyHomeTabState();
}

class _SpotifyHomeTabState extends State<SpotifyHomeTab> {
  String _selectedPill = 'All';

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = context.read<PlayerProvider>();
      player.loadSpotifyChart('top_hits');
      player.loadYouTubeTrending();
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: EmberColors.obsidianBase,
      body: CustomScrollView(
        slivers: [
          // 1. Top Bar with Greeting & Quick Actions
          SliverAppBar(
            backgroundColor: EmberColors.obsidianBase.withValues(alpha: 0.95),
            elevation: 0,
            floating: true,
            pinned: false,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: Text(
              _getGreeting(),
              style: const TextStyle(
                color: EmberColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            actions: [
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.sliders, size: 16, color: EmberColors.textPrimary),
                tooltip: 'Audiophile Equalizer',
                onPressed: () => SoundShapingSheet.show(context),
              ),
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.clockRotateLeft, size: 16, color: EmberColors.textPrimary),
                tooltip: 'Listening History',
                onPressed: widget.onOpenLibrary,
              ),
              IconButton(
                icon: const FaIcon(FontAwesomeIcons.gear, size: 16, color: EmberColors.textPrimary),
                tooltip: 'Settings',
                onPressed: () => SettingsScreen.show(context),
              ),
              const SizedBox(width: 8),
            ],
          ),

          // 2. Filter Pills Row (All, Music, Podcasts, Charts)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Music', 'Podcasts', 'Charts'].map((pill) {
                    final isSelected = _selectedPill == pill;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedPill = pill);
                          if (pill == 'Charts') {
                            player.loadSpotifyChart('global_top_50');
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected ? EmberColors.primaryBlue : EmberColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(9999),
                            border: Border.all(
                              color: isSelected ? EmberColors.primaryBlue : EmberColors.outlineVariant,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            pill,
                            style: TextStyle(
                              color: isSelected ? Colors.black : EmberColors.textPrimary,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // 3. Quick Access 2-Column Grid (6 Recently Played / Flagship Cards)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3.1,
              ),
              delegate: SliverChildListDelegate([
                _buildQuickAccessCard(
                  title: 'Liked Songs',
                  isLikedSongs: true,
                  onTap: widget.onOpenLibrary,
                  isPlaying: player.favorites.any((s) => s.id == player.currentSong?.id),
                ),
                _buildQuickAccessCard(
                  title: "Today's Top Hits",
                  imageUrl: 'https://i.scdn.co/image/ab67706f00000002b28c86be566710fa53cf2cc8',
                  onTap: () => _playSpotifyChart(context, 'top_hits'),
                ),
                _buildQuickAccessCard(
                  title: 'Global Top 50',
                  imageUrl: 'https://charts-images.scdn.co/assets_generated/regional_global_daily_default.jpg',
                  onTap: () => _playSpotifyChart(context, 'global_top_50'),
                ),
                _buildQuickAccessCard(
                  title: 'Viral 50 Global',
                  imageUrl: 'https://charts-images.scdn.co/assets_generated/viral_global_daily_default.jpg',
                  onTap: () => _playSpotifyChart(context, 'viral_50'),
                ),
                _buildQuickAccessCard(
                  title: 'RapCaviar',
                  imageUrl: 'https://i.scdn.co/image/ab67706f000000029bb7b01d18bb7b6f6f212282',
                  onTap: () => _playSpotifyChart(context, 'rapcaviar'),
                ),
                _buildQuickAccessCard(
                  title: 'Lo-Fi Beats',
                  imageUrl: 'https://i.scdn.co/image/ab67706f0000000259b35b62e49c7f9984950ce6',
                  onTap: () => _playSpotifyChart(context, 'lofi_beats'),
                ),
              ]),
            ),
          ),

          // 4. Section: Featured Spotify Charts Carousel
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              title: 'Featured Spotify Charts',
              subtitle: 'The hottest tracks on Spotify right now',
              actionText: 'See all',
              onAction: widget.onOpenSearch,
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 216,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: SpotifyService.curatedCharts.length,
                itemBuilder: (context, index) {
                  final chart = SpotifyService.curatedCharts[index];
                  return _buildChartCarouselCard(chart, () => _playSpotifyChart(context, chart.key));
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // 5. Section: Trending on YouTube Music
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              title: 'Trending on YouTube Music',
              subtitle: 'Top music videos & viral audio tracks',
              actionText: 'Play all',
              onAction: () {
                if (player.youtubeTracks.isNotEmpty) {
                  player.playPlaylist(
                    Playlist(
                      id: 'yt_trending_all',
                      title: 'Trending on YouTube Music',
                      description: 'Top trending tracks on YouTube Music',
                      songs: player.youtubeTracks,
                      createdAt: DateTime.now(),
                      coverUrl: player.youtubeTracks.first.artworkUrl,
                    ),
                  );
                }
              },
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: player.isLoadingYouTube
                  ? const Center(child: CircularProgressIndicator(color: EmberColors.primaryBlue))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: player.youtubeTracks.take(12).length,
                      itemBuilder: (context, index) {
                        final track = player.youtubeTracks[index];
                        return _buildTrackCarouselCard(track, () => player.playSong(track));
                      },
                    ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // 6. Section: Spotify Curated Tracklist (Today's Top Hits)
          SliverToBoxAdapter(
            child: _buildSectionHeader(
              title: "Today's Top Hits",
              subtitle: 'Curated by Spotify • Streamed in High Definition',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (player.spotifyTracks.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(color: EmberColors.primaryBlue)),
                    );
                  }
                  final track = player.spotifyTracks[index];
                  final isCurrent = player.currentSong?.id == track.id;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? EmberColors.primaryBlue.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      dense: true,
                      visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
                      leading: Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: track.artworkUrl,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => Container(
                                width: 44,
                                height: 44,
                                color: EmberColors.surfaceContainerHigh,
                                child: const FaIcon(FontAwesomeIcons.music, size: 16, color: EmberColors.textMuted),
                              ),
                            ),
                          ),
                          if (isCurrent && player.isPlaying)
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: FaIcon(FontAwesomeIcons.volumeHigh, size: 14, color: EmberColors.primaryBlue),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? EmberColors.primaryBlue : EmberColors.textPrimary,
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: EmberColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: FaIcon(
                              player.isFavorite(track.id) ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                              size: 14,
                              color: player.isFavorite(track.id) ? EmberColors.primaryBlue : EmberColors.textMuted,
                            ),
                            onPressed: () => player.toggleFavorite(track),
                          ),
                          IconButton(
                            icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 13, color: EmberColors.textMuted),
                            onPressed: () => TrackOptionsSheet.show(context, track),
                          ),
                        ],
                      ),
                      onTap: () => player.playSong(track),
                    ),
                  );
                },
                childCount: player.spotifyTracks.isEmpty ? 1 : player.spotifyTracks.take(20).length,
              ),
            ),
          ),

          // Extra bottom padding for floating mini-player & bottom nav
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ],
      ),
    );
  }

  void _playSpotifyChart(BuildContext context, String chartKey) async {
    final player = context.read<PlayerProvider>();
    await player.loadSpotifyChart(chartKey);
    if (player.spotifyTracks.isNotEmpty) {
      final chart = SpotifyService.curatedCharts.firstWhere(
        (c) => c.key == chartKey,
        orElse: () => SpotifyService.curatedCharts.first,
      );
      player.playPlaylist(
        Playlist(
          id: 'sp_${chart.key}',
          title: chart.title,
          description: chart.subtitle,
          songs: player.spotifyTracks,
          createdAt: DateTime.now(),
          coverUrl: chart.coverUrl,
        ),
      );
    }
  }

  Widget _buildQuickAccessCard({
    required String title,
    String? imageUrl,
    bool isLikedSongs = false,
    required VoidCallback onTap,
    bool isPlaying = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          color: EmberColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            if (isLikedSongs)
              Container(
                width: 52,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D47A1), Color(0xFF2979FF), Color(0xFF00D4FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: FaIcon(FontAwesomeIcons.solidHeart, size: 18, color: Colors.white),
                ),
              )
            else
              CachedNetworkImage(
                imageUrl: imageUrl ?? '',
                width: 52,
                height: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  width: 52,
                  color: EmberColors.surfaceContainerHigh,
                  child: const Center(child: FaIcon(FontAwesomeIcons.music, size: 16, color: EmberColors.textMuted)),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: EmberColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (isPlaying)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: FaIcon(FontAwesomeIcons.volumeHigh, size: 12, color: EmberColors.primaryBlue),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: EmberColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.4,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: EmberColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionText != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionText,
                style: const TextStyle(
                  color: EmberColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChartCarouselCard(SpotifyChartInfo chart, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: chart.coverUrl,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  width: 140,
                  height: 140,
                  color: EmberColors.surfaceContainerHigh,
                  child: const Center(child: FaIcon(FontAwesomeIcons.music, size: 28, color: EmberColors.textMuted)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              chart.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EmberColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              chart.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EmberColors.textSecondary,
                fontSize: 11,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackCarouselCard(Song track, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 135,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: track.artworkUrl,
                width: 135,
                height: 135,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Container(
                  width: 135,
                  height: 135,
                  color: EmberColors.surfaceContainerHigh,
                  child: const Center(child: FaIcon(FontAwesomeIcons.music, size: 28, color: EmberColors.textMuted)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EmberColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EmberColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
