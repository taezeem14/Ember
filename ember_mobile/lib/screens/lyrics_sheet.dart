import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/ember_theme.dart';

class LyricsSheet extends StatelessWidget {
  final Song song;

  const LyricsSheet({super.key, required this.song});

  static void show(BuildContext context, Song song) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LyricsSheet(song: song),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = song.lyrics ?? 'Instrumental / No lyrics available for this track.';

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: EmberColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: EmberColors.outlineVariant, width: 1)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: EmberColors.textMuted.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyrics',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: EmberColors.primaryAmber,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${song.title} • ${song.artist}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: EmberColors.textMuted,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: EmberColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: EmberColors.outlineVariant, height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: SelectableText(
                lyrics,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: EmberColors.textPrimary,
                      fontSize: 18,
                      height: 2.0,
                      letterSpacing: 0.3,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
