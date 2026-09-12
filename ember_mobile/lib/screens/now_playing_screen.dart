import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../theme/ember_theme.dart';
import '../widgets/ambient_glow.dart';
import '../widgets/vinyl_disc.dart';
import 'lyrics_sheet.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    if (song == null) {
      return Scaffold(
        backgroundColor: EmberColors.obsidianBase,
        appBar: AppBar(leading: const BackButton()),
        body: const Center(child: Text('No song selected')),
      );
    }

    final elapsed = player.position;
    final total = player.duration;
    final remaining = total > elapsed ? total - elapsed : Duration.zero;

    return Scaffold(
      backgroundColor: EmberColors.obsidianBase,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: EmberColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Column(
                    children: [
                      Text(
                        'PLAYING FROM',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: EmberColors.textMuted,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        player.activeMood?.toUpperCase() ?? 'EMBER COZY QUEUE',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: EmberColors.primaryAmber,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded, size: 24, color: EmberColors.textSecondary),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),

            // Hero Artwork with Ambient Glow and Vinyl Peek
            Center(
              child: AmbientGlow(
                isPlaying: player.isPlaying,
                child: SizedBox(
                  width: 290,
                  height: 250,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Vinyl peek peeking from right
                      Positioned(
                        right: 0,
                        child: VinylDisc(
                          size: 210,
                          isPlaying: player.isPlaying,
                        ),
                      ),
                      // Square album cover
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 230,
                          height: 230,
                          decoration: BoxDecoration(
                            color: EmberColors.surfaceContainerHigh,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.5),
                                blurRadius: 20,
                                offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: song.artworkUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: song.artworkUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(Icons.music_note_rounded, size: 64, color: EmberColors.primaryAmber),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.music_note_rounded, size: 64, color: EmberColors.primaryAmber),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(flex: 1),

            // Title, Artist, and Favorite
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: EmberColors.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: EmberColors.textSecondary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      player.isFavorite(song.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 28,
                      color: player.isFavorite(song.id) ? EmberColors.primaryAmber : EmberColors.textMuted,
                    ),
                    onPressed: () => player.toggleFavorite(song),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Scrubber Bar & Timecodes
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: EmberColors.primaryAmber,
                      inactiveTrackColor: EmberColors.outlineVariant.withOpacity(0.6),
                      thumbColor: EmberColors.textPrimary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      overlayColor: EmberColors.primaryAmber.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: total.inMilliseconds > 0
                          ? elapsed.inMilliseconds.clamp(0, total.inMilliseconds).toDouble()
                          : 0.0,
                      max: total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0,
                      onChanged: (val) {
                        player.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(elapsed),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: EmberColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          '-${_formatDuration(remaining)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: EmberColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Transport Control Cluster
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: player.isShuffle ? EmberColors.primaryAmber : EmberColors.textMuted,
                      size: 24,
                    ),
                    onPressed: () => player.toggleShuffle(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: EmberColors.textPrimary, size: 36),
                    onPressed: () => player.skipPrevious(),
                  ),
                  // Hero 64px circular play/pause button with glowing amber shadow
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [EmberColors.primaryAmberHi, EmberColors.primaryAmber],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: EmberColors.primaryAmber.withOpacity(0.45),
                          blurRadius: 22,
                          spreadRadius: 2,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: EmberColors.obsidianBase,
                        size: 38,
                      ),
                      onPressed: () => player.togglePlay(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: EmberColors.textPrimary, size: 36),
                    onPressed: () => player.skipNext(),
                  ),
                  IconButton(
                    icon: Icon(
                      player.repeatMode == 'one' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      color: player.repeatMode != 'off' ? EmberColors.primaryAmber : EmberColors.textMuted,
                      size: 24,
                    ),
                    onPressed: () => player.cycleRepeatMode(),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),

            // Lyrics Preview Card (Stitch design)
            if (song.lyrics != null && song.lyrics!.isNotEmpty)
              GestureByKey(
                onTap: () => LyricsSheet.show(context, song),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: EmberColors.surfaceContainerLow.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: EmberColors.outlineVariant.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lyrics_outlined, size: 20, color: EmberColors.primaryAmber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          song.lyrics!.split('\n').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: EmberColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                      const Icon(Icons.arrow_upward_rounded, size: 16, color: EmberColors.textMuted),
                    ],
                  ),
                ),
              ),

            // Bottom Utility Action Pills
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _PillAction(
                    icon: Icons.bedtime_outlined,
                    label: player.sleepSecondsRemaining > 0
                        ? '${(player.sleepSecondsRemaining / 60).ceil()}m'
                        : 'Sleep',
                    active: player.sleepSecondsRemaining > 0,
                    onTap: () => _showSleepTimerDialog(context, player),
                  ),
                  _PillAction(
                    icon: Icons.speed_rounded,
                    label: '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 1 : 2)}x',
                    active: player.speed != 1.0,
                    onTap: () {
                      final speeds = [1.0, 1.25, 1.5, 0.75];
                      final next = speeds[(speeds.indexOf(player.speed) + 1) % speeds.length];
                      player.setSpeed(next);
                    },
                  ),
                  _PillAction(
                    icon: Icons.queue_music_rounded,
                    label: 'Queue',
                    active: false,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerDialog(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EmberColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sleep Timer',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: EmberColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                for (final mins in [15, 30, 45, 60])
                  ListTile(
                    title: Text('$mins minutes', style: const TextStyle(color: EmberColors.textPrimary)),
                    onTap: () {
                      player.startSleepTimer(mins);
                      Navigator.pop(context);
                    },
                  ),
                if (player.sleepSecondsRemaining > 0)
                  ListTile(
                    title: const Text('Turn Off Timer', style: TextStyle(color: EmberColors.error)),
                    onTap: () {
                      player.cancelSleepTimer();
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GestureByKey extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const GestureByKey({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: child,
    );
  }
}

class _PillAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillAction({
    required this.icon,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? EmberColors.primaryAmber.withOpacity(0.18) : EmberColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: active ? EmberColors.primaryAmber : EmberColors.outlineVariant.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? EmberColors.primaryAmber : EmberColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active ? EmberColors.primaryAmber : EmberColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
