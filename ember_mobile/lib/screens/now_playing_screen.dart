import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/player_provider.dart';
import '../theme/ember_theme.dart';
import '../widgets/ambient_glow.dart';
import '../widgets/vinyl_disc.dart';
import '../widgets/synchronized_lyrics_view.dart';
import 'sound_shaping_sheet.dart';
import 'track_options_sheet.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showLyrics = false;

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
                    icon: const FaIcon(FontAwesomeIcons.chevronDown, size: 20, color: EmberColors.textPrimary),
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
                        player.activeCategory.replaceAll('_', ' ').toUpperCase(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: EmberColors.primaryAmber,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  // Three Dots Menu -> Opens comprehensive Track Options Bottom Sheet
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.ellipsis, size: 20, color: EmberColors.textSecondary),
                    onPressed: () => TrackOptionsSheet.show(context, song),
                  ),
                ],
              ),
            ),

            // Center Viewport: Animated flip between Album Art / Vinyl Disc and Karaoke Lyrics
            Expanded(
              flex: 5,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim), child: child),
                ),
                child: _showLyrics
                    ? Container(
                        key: const ValueKey('lyrics_mode'),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: EmberColors.surfaceContainerLow.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: EmberColors.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: const SynchronizedLyricsView(),
                        ),
                      )
                    : Center(
                        key: const ValueKey('vinyl_mode'),
                        child: GestureDetector(
                          onTap: () => setState(() => _showLyrics = true),
                          child: AmbientGlow(
                            isPlaying: player.isPlaying,
                            child: SizedBox(
                              width: 290,
                              height: 250,
                              child: Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  // Vinyl disc peek from right
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
                                            color: Colors.black.withValues(alpha: 0.5),
                                            blurRadius: 20,
                                            offset: const Offset(4, 4),
                                          ),
                                        ],
                                      ),
                                      child: song.artworkUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: song.artworkUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, _, _) => const Center(
                                                child: FaIcon(FontAwesomeIcons.music, size: 48, color: EmberColors.primaryAmber),
                                              ),
                                            )
                                          : const Center(
                                              child: FaIcon(FontAwesomeIcons.music, size: 48, color: EmberColors.primaryAmber),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),

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
                    icon: FaIcon(
                      player.isFavorite(song.id) ? FontAwesomeIcons.solidHeart : FontAwesomeIcons.heart,
                      size: 24,
                      color: player.isFavorite(song.id) ? EmberColors.primaryAmber : EmberColors.textMuted,
                    ),
                    onPressed: () => player.toggleFavorite(song),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Scrubber Bar & Timecodes
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: EmberColors.primaryAmber,
                      inactiveTrackColor: EmberColors.outlineVariant.withValues(alpha: 0.6),
                      thumbColor: EmberColors.textPrimary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      overlayColor: EmberColors.primaryAmber.withValues(alpha: 0.2),
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

            const SizedBox(height: 8),

            // Transport Control Cluster
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: FaIcon(
                      FontAwesomeIcons.shuffle,
                      color: player.isShuffle ? EmberColors.primaryAmber : EmberColors.textMuted,
                      size: 18,
                    ),
                    onPressed: () => player.toggleShuffle(),
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.backwardStep, color: EmberColors.textPrimary, size: 24),
                    onPressed: () => player.skipPrevious(),
                  ),
                  // Hero 68px circular play/pause button with glowing amber shadow
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
                          color: EmberColors.primaryAmber.withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 2,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: FaIcon(
                        player.isPlaying ? FontAwesomeIcons.pause : FontAwesomeIcons.play,
                        color: EmberColors.obsidianBase,
                        size: 24,
                      ),
                      onPressed: () => player.togglePlay(),
                    ),
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.forwardStep, color: EmberColors.textPrimary, size: 24),
                    onPressed: () => player.skipNext(),
                  ),
                  IconButton(
                    icon: FaIcon(
                      FontAwesomeIcons.repeat,
                      color: player.repeatMode != 'off' ? EmberColors.primaryAmber : EmberColors.textMuted,
                      size: 18,
                    ),
                    onPressed: () => player.cycleRepeatMode(),
                  ),
                ],
              ),
            ),

            // Bottom Utility Action Pills (Lyrics Toggle, EQ, Speed, Sleep, Queue)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Direct In-Player Lyrics Toggle Pill
                  _PillAction(
                    icon: FontAwesomeIcons.alignLeft,
                    label: _showLyrics ? 'Cover' : 'Lyrics',
                    active: _showLyrics,
                    onTap: () => setState(() => _showLyrics = !_showLyrics),
                  ),
                  // EQ Sound Shaping Pill
                  _PillAction(
                    icon: FontAwesomeIcons.sliders,
                    label: player.eqPreset.split(' ').first,
                    active: player.eqEnabled,
                    onTap: () => SoundShapingSheet.show(context),
                  ),
                  // Sleep Timer
                  _PillAction(
                    icon: FontAwesomeIcons.moon,
                    label: player.sleepSecondsRemaining > 0
                        ? '${(player.sleepSecondsRemaining / 60).ceil()}m'
                        : 'Sleep',
                    active: player.sleepSecondsRemaining > 0,
                    onTap: () => _showSleepTimerDialog(context, player),
                  ),
                  // Playback Speed
                  _PillAction(
                    icon: FontAwesomeIcons.gaugeHigh,
                    label: '${player.speed.toStringAsFixed(player.speed == player.speed.roundToDouble() ? 1 : 2)}x',
                    active: player.speed != 1.0,
                    onTap: () {
                      final speeds = [1.0, 1.25, 1.5, 0.75];
                      final next = speeds[(speeds.indexOf(player.speed) + 1) % speeds.length];
                      player.setSpeed(next);
                    },
                  ),
                  // Queue Screen
                  _PillAction(
                    icon: FontAwesomeIcons.listUl,
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

class _PillAction extends StatelessWidget {
  final FaIconData icon;
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? EmberColors.primaryAmber.withValues(alpha: 0.18) : EmberColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: active ? EmberColors.primaryAmber : EmberColors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 12, color: active ? EmberColors.primaryAmber : EmberColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active ? EmberColors.primaryAmber : EmberColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
