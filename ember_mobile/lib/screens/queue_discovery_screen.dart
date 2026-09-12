import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../services/catalog_service.dart';
import '../theme/ember_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/spectrum_bars.dart';
import 'lyrics_sheet.dart';

class QueueDiscoveryScreen extends StatefulWidget {
  const QueueDiscoveryScreen({super.key});

  @override
  State<QueueDiscoveryScreen> createState() => _QueueDiscoveryScreenState();
}

class _QueueDiscoveryScreenState extends State<QueueDiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: EmberColors.obsidianBase,
      body: SafeArea(
        child: Column(
          children: [
            // Header: Brand & App Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EmberColors.primaryAmber.withOpacity(0.16),
                    ),
                    child: const FaIcon(
                      FontAwesomeIcons.fire,
                      color: EmberColors.primaryAmber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMBER',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: EmberColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0,
                            ),
                      ),
                      Text(
                        'COZY AUDIO COMPANION',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: EmberColors.textMuted,
                              letterSpacing: 1.0,
                            ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.sliders, color: EmberColors.textSecondary, size: 18),
                    onPressed: () => _showSoundDialog(context, player),
                  ),
                ],
              ),
            ),

            // Search Capsule Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: EmberColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(color: EmberColors.outlineVariant.withOpacity(0.5)),
                ),
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(
                  children: [
                    const FaIcon(FontAwesomeIcons.magnifyingGlass, size: 15, color: EmberColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: EmberColors.textPrimary, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search any song, artist, album...',
                          hintStyle: TextStyle(color: EmberColors.textMuted, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) => player.search(val),
                      ),
                    ),
                    if (player.isSearching)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: EmberColors.primaryAmber,
                          ),
                        ),
                      ),
                    if (_searchController.text.isNotEmpty && !player.isSearching)
                      IconButton(
                        icon: const FaIcon(FontAwesomeIcons.xmark, size: 14, color: EmberColors.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          player.search('');
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Cozy Moods Quick Picks Horizontal Bar
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                itemCount: CatalogService.cozyMoods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final mood = CatalogService.cozyMoods[i];
                  final isSelected = player.activeMood == mood.key;
                  return InkWell(
                    onTap: () => player.selectMood(mood.key),
                    borderRadius: BorderRadius.circular(9999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? EmberColors.primaryAmber.withOpacity(0.2)
                            : EmberColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(9999),
                        border: Border.all(
                          color: isSelected
                              ? EmberColors.primaryAmber
                              : EmberColors.outlineVariant.withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(mood.emoji, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 6),
                          Text(
                            mood.title.split(' ').first,
                            style: TextStyle(
                              color: isSelected ? EmberColors.primaryAmber : EmberColors.textSecondary,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Category Filter Tabs (Queue, Favorites, History, Lyrics)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(
                children: [
                  _TabPill(
                    label: 'Queue',
                    active: player.activeTab == 'queue',
                    onTap: () => player.setTab('queue'),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'Favorites',
                    active: player.activeTab == 'favorites',
                    onTap: () => player.setTab('favorites'),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'History',
                    active: player.activeTab == 'history',
                    onTap: () => player.setTab('history'),
                  ),
                  const SizedBox(width: 8),
                  _TabPill(
                    label: 'Lyrics',
                    active: player.activeTab == 'lyrics',
                    onTap: () => player.setTab('lyrics'),
                  ),
                  const Spacer(),
                  if (player.activeTab == 'queue' && player.queue.isNotEmpty)
                    InkWell(
                      onTap: () => player.clearQueue(),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: FaIcon(FontAwesomeIcons.trashCan, size: 16, color: EmberColors.textMuted),
                      ),
                    ),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: _buildTabContent(context, player),
            ),

            // Docked Frosted Mini Player
            const MiniPlayer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, PlayerProvider player) {
    if (player.activeTab == 'lyrics') {
      final cur = player.currentSong;
      if (cur == null || cur.lyrics == null) {
        return const Center(
          child: Text('No lyrics available', style: TextStyle(color: EmberColors.textMuted)),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SelectableText(
          cur.lyrics!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: EmberColors.textPrimary,
            fontSize: 16,
            height: 1.9,
          ),
        ),
      );
    }

    List<Song> songList;
    if (_searchController.text.isNotEmpty) {
      songList = player.searchResults;
    } else if (player.activeTab == 'favorites') {
      songList = player.favorites;
    } else if (player.activeTab == 'history') {
      songList = player.history;
    } else {
      songList = player.queue;
    }

    if (player.isSearching && _searchController.text.isNotEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.5,
              color: EmberColors.primaryAmber,
            ),
            SizedBox(height: 14),
            Text(
              'Searching global catalogue...',
              style: TextStyle(color: EmberColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (songList.isEmpty) {
      final isSearch = _searchController.text.isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(
              isSearch ? FontAwesomeIcons.magnifyingGlass : FontAwesomeIcons.music,
              size: 36,
              color: EmberColors.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              isSearch
                  ? 'No songs found for "${_searchController.text}"'
                  : player.activeTab == 'favorites'
                      ? 'No favorites pinned yet ♡'
                      : player.activeTab == 'history'
                          ? 'No playback history yet'
                          : 'Search any song, artist or pick a mood above',
              style: const TextStyle(color: EmberColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      itemCount: songList.length,
      itemBuilder: (context, index) {
        final song = songList[index];
        final isCurrent = player.currentSong?.id == song.id;

        return Dismissible(
          key: ValueKey('${song.id}_$index'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: EmberColors.error.withOpacity(0.8),
            child: const FaIcon(FontAwesomeIcons.trashCan, color: Colors.white, size: 18),
          ),
          onDismissed: (_) {
            if (player.activeTab == 'queue') {
              player.removeTrackAt(index);
            } else if (player.activeTab == 'favorites') {
              player.toggleFavorite(song);
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: isCurrent
                  ? EmberColors.primaryAmber.withOpacity(0.12)
                  : EmberColors.surfaceContainerLow.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent ? EmberColors.primaryAmber.withOpacity(0.6) : Colors.transparent,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              leading: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.artworkUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: song.artworkUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const FaIcon(FontAwesomeIcons.music, size: 16, color: EmberColors.primaryAmber),
                          )
                        : const FaIcon(FontAwesomeIcons.music, size: 16, color: EmberColors.primaryAmber),
                  ),
                  if (isCurrent)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: SpectrumBars(
                          isPlaying: player.isPlaying,
                          height: 16,
                          barCount: 4,
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrent ? EmberColors.primaryAmber : EmberColors.textPrimary,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: EmberColors.textMuted, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: FaIcon(
                      player.isFavorite(song.id) ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                      size: 18,
                      color: player.isFavorite(song.id) ? EmberColors.primaryAmber : EmberColors.textMuted,
                    ),
                    onPressed: () => player.toggleFavorite(song),
                  ),
                  if (song.lyrics != null)
                    IconButton(
                      icon: const FaIcon(FontAwesomeIcons.alignLeft, size: 16, color: EmberColors.textMuted),
                      onPressed: () => LyricsSheet.show(context, song),
                    ),
                ],
              ),
              onTap: () {
                player.playSong(song, contextQueue: songList);
              },
            ),
          ),
        );
      },
    );
  }

  void _showSoundDialog(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EmberColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sound Shaping & Equalizer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: EmberColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 14),
                const Text('EQ Presets', style: TextStyle(color: EmberColors.textMuted, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in ['Warm Tape', 'Lo-Fi', 'Acoustic', 'Vocal Air', 'Flat'])
                      ChoiceChip(
                        label: Text(p),
                        selected: p == 'Warm Tape',
                        selectedColor: EmberColors.primaryAmber,
                        labelStyle: TextStyle(
                          color: p == 'Warm Tape' ? EmberColors.obsidianBase : EmberColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        backgroundColor: EmberColors.surfaceContainerLow,
                        onSelected: (_) => Navigator.pop(context),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Spatial Crossfeed', style: TextStyle(color: EmberColors.textPrimary, fontSize: 14)),
                    Switch(
                      value: true,
                      activeColor: EmberColors.primaryAmber,
                      onChanged: (_) => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? EmberColors.primaryAmber : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? EmberColors.obsidianBase : EmberColors.textMuted,
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
