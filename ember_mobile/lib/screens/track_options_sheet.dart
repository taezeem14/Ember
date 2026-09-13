import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../theme/ember_theme.dart';
import 'sound_shaping_sheet.dart';

class TrackOptionsSheet extends StatelessWidget {
  final Song song;

  const TrackOptionsSheet({super.key, required this.song});

  static void show(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: EmberColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TrackOptionsSheet(song: song),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, PlayerProvider player) {
    final titleController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: EmberColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add to Playlist',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            color: EmberColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    IconButton(
                      icon: const FaIcon(FontAwesomeIcons.plus, size: 16, color: EmberColors.primaryAmber),
                      onPressed: () {
                        showDialog(
                          context: ctx,
                          builder: (dCtx) => AlertDialog(
                            backgroundColor: EmberColors.surfaceContainerHigh,
                            title: const Text('New Playlist', style: TextStyle(color: EmberColors.textPrimary)),
                            content: TextField(
                              controller: titleController,
                              autofocus: true,
                              style: const TextStyle(color: EmberColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Playlist name...',
                                hintStyle: TextStyle(color: EmberColors.textMuted),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx),
                                child: const Text('Cancel', style: TextStyle(color: EmberColors.textMuted)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: EmberColors.primaryAmber),
                                onPressed: () {
                                  if (titleController.text.trim().isNotEmpty) {
                                    player.createPlaylist(titleController.text.trim());
                                    Navigator.pop(dCtx);
                                  }
                                },
                                child: const Text('Create', style: TextStyle(color: EmberColors.obsidianBase, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (player.playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          const Text('No playlists yet', style: TextStyle(color: EmberColors.textMuted)),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: EmberColors.primaryAmber),
                            onPressed: () {
                              player.createPlaylist('My Favorites');
                              Navigator.pop(ctx);
                            },
                            icon: const FaIcon(FontAwesomeIcons.plus, size: 14, color: EmberColors.obsidianBase),
                            label: const Text('Create "My Favorites"', style: TextStyle(color: EmberColors.obsidianBase, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final p in player.playlists)
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: EmberColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: FaIcon(FontAwesomeIcons.music, size: 16, color: EmberColors.primaryAmber),
                        ),
                      ),
                      title: Text(p.title, style: const TextStyle(color: EmberColors.textPrimary, fontWeight: FontWeight.w600)),
                      subtitle: Text('${p.songs.length} tracks', style: const TextStyle(color: EmberColors.textMuted, fontSize: 12)),
                      onTap: () {
                        player.addSongToPlaylist(p.id, song);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: EmberColors.surfaceContainerHigh,
                            content: Text('Added to "${p.title}"', style: const TextStyle(color: EmberColors.primaryAmberHi)),
                          ),
                        );
                      },
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpecsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EmberColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const FaIcon(FontAwesomeIcons.circleInfo, size: 18, color: EmberColors.primaryAmber),
            const SizedBox(width: 10),
            Text('Track Tech Specs', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: EmberColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SpecRow(label: 'Track Title', value: song.title),
            _SpecRow(label: 'Artist', value: song.artist),
            _SpecRow(label: 'Audio Stream Bitrate', value: '320 kbps (High Definition)'),
            _SpecRow(label: 'Audio Codec', value: 'MPEG-4 AAC-LC'),
            _SpecRow(label: 'Sample Rate', value: '44.1 kHz / 16-bit Stereo'),
            _SpecRow(label: 'Duration', value: '${song.duration.inMinutes}:${(song.duration.inSeconds % 60).toString().padLeft(2, '0')}'),
            _SpecRow(label: 'Source', value: song.id.startsWith('yt_') ? 'YouTube Audio' : 'Ember Global CDN'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: EmberColors.primaryAmber, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final isDownloaded = player.isDownloaded(song.id);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: EmberColors.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Song Summary Header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: song.artworkUrl.isNotEmpty
                      ? Image.network(song.artworkUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => const FaIcon(FontAwesomeIcons.music, size: 20, color: EmberColors.primaryAmber))
                      : const FaIcon(FontAwesomeIcons.music, size: 20, color: EmberColors.primaryAmber),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: EmberColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: EmberColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: EmberColors.outlineVariant, height: 1),
            const SizedBox(height: 8),

            // Action Options
            if (player.currentSong?.id == song.id)
              _OptionTile(
                icon: FontAwesomeIcons.stop,
                iconColor: EmberColors.error,
                title: 'Stop Playback / Cut Song',
                subtitle: 'Immediately stop playing and dismiss active song',
                onTap: () {
                  Navigator.pop(context);
                  player.stopPlayback();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: EmberColors.surfaceContainerHigh,
                      content: Text('Playback stopped', style: TextStyle(color: EmberColors.textPrimary)),
                    ),
                  );
                },
              ),
            _OptionTile(
              icon: FontAwesomeIcons.folderPlus,
              title: 'Add to Playlist',

              subtitle: 'Save track into custom playlist',
              onTap: () {
                Navigator.pop(context);
                _showAddToPlaylistDialog(context, player);
              },
            ),
            _OptionTile(
              icon: isDownloaded ? FontAwesomeIcons.circleCheck : FontAwesomeIcons.download,
              iconColor: isDownloaded ? EmberColors.primaryAmber : null,
              title: isDownloaded ? 'Downloaded (Offline Ready)' : 'Download Audio (MP3)',
              subtitle: 'Save full 320kbps audio to Downloads/Music',
              onTap: () async {
                Navigator.pop(context);
                if (!isDownloaded) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: EmberColors.surfaceContainerHigh,
                      content: Text('Downloading "${song.title}" MP3...', style: const TextStyle(color: EmberColors.primaryAmber)),
                    ),
                  );
                  final path = await player.downloadAudio(song);
                  if (path != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: EmberColors.surfaceContainerHigh,
                        content: Text('Saved to Downloads/Ember!', style: const TextStyle(color: EmberColors.primaryAmberHi)),
                      ),
                    );
                  }
                }
              },
            ),
            _OptionTile(
              icon: FontAwesomeIcons.video,
              title: 'Download Video (MP4)',
              subtitle: 'Save HD video directly to device Gallery/Movies',
              onTap: () async {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: EmberColors.surfaceContainerHigh,
                    content: Text('Downloading MP4 video for "${song.title}"...', style: const TextStyle(color: EmberColors.primaryAmber)),
                  ),
                );
                final path = await player.downloadVideo(song);
                if (path != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: EmberColors.surfaceContainerHigh,
                      content: Text('Video saved to Gallery / Movies!', style: const TextStyle(color: EmberColors.primaryAmberHi)),
                    ),
                  );
                }
              },
            ),
            _OptionTile(
              icon: FontAwesomeIcons.radio,
              title: 'Start Radio / Add More Like This',
              subtitle: 'Queue similar tracks with smart recommendations',
              onTap: () {
                Navigator.pop(context);
                player.startRadio(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: EmberColors.surfaceContainerHigh,
                    content: Text('Started Ember Radio based on "${song.title}"', style: const TextStyle(color: EmberColors.primaryAmberHi)),
                  ),
                );
              },
            ),
            _OptionTile(
              icon: FontAwesomeIcons.forward,
              title: 'Play Next',
              subtitle: 'Insert track right after current song',
              onTap: () {
                Navigator.pop(context);
                player.playNext(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: EmberColors.surfaceContainerHigh,
                    content: Text('"${song.title}" will play next', style: const TextStyle(color: EmberColors.primaryAmberHi)),
                  ),
                );
              },
            ),
            _OptionTile(
              icon: FontAwesomeIcons.listOl,
              title: 'Add to Queue',
              subtitle: 'Append track to the bottom of the queue',
              onTap: () {
                Navigator.pop(context);
                player.addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: EmberColors.surfaceContainerHigh,
                    content: Text('Added "${song.title}" to queue', style: const TextStyle(color: EmberColors.primaryAmberHi)),
                  ),
                );
              },
            ),
            _OptionTile(
              icon: FontAwesomeIcons.sliders,
              title: 'Equalizer & Sound Shaping',
              subtitle: 'Tune frequencies, presets & bass boost',
              onTap: () {
                Navigator.pop(context);
                SoundShapingSheet.show(context);
              },
            ),
            _OptionTile(
              icon: FontAwesomeIcons.circleInfo,
              title: 'Technical Specs & Details',
              subtitle: 'Bitrate, codec, duration & stream info',
              onTap: () {
                Navigator.pop(context);
                _showSpecsDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final FaIconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      leading: FaIcon(icon, size: 18, color: iconColor ?? EmberColors.primaryAmber),
      title: Text(title, style: const TextStyle(color: EmberColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: EmberColors.textMuted, fontSize: 11)),
      onTap: onTap,
    );
  }
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;

  const _SpecRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: EmberColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(value, style: const TextStyle(color: EmberColors.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }
}
