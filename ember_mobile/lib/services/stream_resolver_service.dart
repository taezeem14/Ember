import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'catalog_service.dart';

class StreamResolverService {
  /// Normalizes title string by stripping noise words, collapsing whitespace,
  /// and falling back to the raw title if cleaned result is empty.
  static String cleanTitle(String raw) {
    final cleaned = raw
        .replaceAll(
          RegExp(
            r'\((?:official|music|video|audio|lyrics|hd|4k|visualizer|remastered|lyric|prod\.|feat\.|ft\.).*?\)',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[(?:official|music|video|audio|lyrics|hd|4k|visualizer|remastered|lyric|prod\.|feat\.|ft\.).*?\]',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'[\-_|]', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isNotEmpty ? cleaned : raw.trim();
  }

  /// Pure JioSaavn 320kbps Stream Resolver:
  /// Streams directly from JioSaavn's High-Definition CDN (aac.saavncdn.com)
  /// with automatic fallback to 160kbps and 96kbps if 320kbps is unavailable on CDN.
  /// Enforces CatalogService.verifyMatch to guarantee the exact song plays.
  static Future<List<String>> resolvePlayableStreamCandidates(Song song) async {
    final s = song.streamUrl;

    // ─── 1. LOCAL / OFFLINE FILES ───
    final isWindowsPath = s.length >= 3 && s[1] == ':' && (s[2] == '\\' || s[2] == '/');
    if (s.isNotEmpty && (s.startsWith('/') || s.startsWith('file://') || isWindowsPath)) {
      return [s];
    }

    // ─── 2. DIRECT JIOSAAVN CDN MEDIA STREAM ───
    if (s.isNotEmpty && s.contains('saavncdn.com')) {
      return _buildBitrateList(s);
    }

    // ─── 3. DIRECT AUDIO URLS (any common audio format, including with query params) ───
    if (s.isNotEmpty &&
        !s.startsWith('spotify:') &&
        !s.contains('youtube.com') &&
        !s.contains('youtu.be') &&
        !s.contains('itunes.apple.com')) {
      final uri = Uri.tryParse(s);
      final path = (uri?.path ?? s).toLowerCase();
      final isAudio = const ['.mp3', '.m4a', '.mp4', '.aac', '.flac', '.ogg', '.opus', '.wav', '.m3u8']
          .any((ext) => path.endsWith(ext));
      if (isAudio) {
        return [s];
      }
    }

    // ─── 4. JIOSAAVN 320kbps CDN SEARCH RESOLUTION ───
    // Resolves full audio strictly via JioSaavn with verifyMatch token validation
    try {
      final cleanT = cleanTitle(song.title);
      final cleanA = song.artist != 'Unknown Artist' && song.artist.isNotEmpty ? song.artist.trim() : '';
      final queries = [
        if (cleanA.isNotEmpty) '$cleanT $cleanA',
        cleanT,
      ];

      for (final query in queries) {
        final matches = await CatalogService.searchOnline(query, limit: 6);
        for (final match in matches) {
          if (match.streamUrl.isNotEmpty && match.streamUrl.contains('saavncdn.com')) {
            // Check title and artist match
            final isVerified = CatalogService.verifyMatch(
              targetTitle: song.title,
              targetArtist: song.artist,
              candidateTitle: match.title,
              candidateArtist: match.artist,
            );

            if (isVerified) {
              debugPrint('[JioSaavn Engine] Verified 320kbps CDN stream resolved for "${song.title}"');
              return _buildBitrateList(match.streamUrl);
            }
          }
        }
      }

      // No verified match found — do NOT return unverified results to prevent wrong song playback
      debugPrint('[JioSaavn Engine] No verified match found for "${song.title}" — returning empty candidates');
    } catch (e) {
      debugPrint('[JioSaavn Engine] Stream resolution error for "${song.title}": $e');
    }

    return const [];
  }

  /// Build a bitrate fallback list (320kbps → 160kbps → 96kbps) for JioSaavn CDN streams
  static List<String> _buildBitrateList(String stream) {
    final list = <String>[stream];
    // Match _320.mp4 or _320.m4a
    final bitratePattern = RegExp(r'_320\.(mp4|m4a)');
    if (bitratePattern.hasMatch(stream)) {
      list.add(stream.replaceAll(bitratePattern, r'_160.$1'));
      list.add(stream.replaceAll(bitratePattern, r'_96.$1'));
    }
    return list;
  }
}
