import 'package:flutter/foundation.dart';
import '../models/song.dart';
import 'catalog_service.dart';
import 'youtube_importer_service.dart';

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

  /// Tri-Engine Stream Resolver (Spotify + YouTube Music + JioSaavn):
  /// - YouTube tracks resolve directly via youtube_explode_dart + Piped proxy failover.
  /// - JioSaavn tracks stream directly from JioSaavn's 320kbps CDN with 160k/96k fallbacks.
  /// - Spotify & general tracks resolve via JioSaavn 320kbps CDN (verified match),
  ///   with seamless failover to YouTube Music / Piped if not in JioSaavn (e.g. indie tracks, mixes).
  static Future<List<String>> resolvePlayableStreamCandidates(Song song) async {
    final s = song.streamUrl;

    // ─── 1. LOCAL / OFFLINE FILES ───
    final isWindowsPath = s.length >= 3 && s[1] == ':' && (s[2] == '\\' || s[2] == '/');
    if (s.isNotEmpty && (s.startsWith('/') || s.startsWith('file://') || isWindowsPath)) {
      return [s];
    }

    // ─── 2. YOUTUBE / YOUTUBE MUSIC TRACKS ───
    // Source-aware: YouTube songs resolve via YouTube Explode with Piped proxy failover
    final isYouTubeTrack = song.isYouTube ||
        s.contains('youtube.com') ||
        s.contains('youtu.be') ||
        song.id.startsWith('yt_');
    if (isYouTubeTrack) {
      final videoId = YouTubeImporterService.extractVideoId(s) ??
          (song.id.startsWith('yt_') ? song.id.replaceFirst('yt_', '') : null);
      if (videoId != null && videoId.isNotEmpty) {
        debugPrint('[Tri-Engine: YouTube] Resolving audio streams for "$videoId" ("${song.title}")...');
        final ytStreams = await YouTubeImporterService.getAudioStreamUrls(videoId);
        if (ytStreams.isNotEmpty) {
          debugPrint('[Tri-Engine: YouTube] Resolved ${ytStreams.length} stream candidate(s) for "${song.title}"');
          return ytStreams;
        }
      }
    }

    // ─── 3. DIRECT JIOSAAVN CDN MEDIA STREAM ───
    if (s.isNotEmpty && s.contains('saavncdn.com')) {
      return _buildBitrateList(s);
    }

    // ─── 4. DIRECT AUDIO URLS (mp3, m4a, mp4, aac, flac, ogg, opus, wav, m3u8) ───
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

    // ─── 5. JIOSAAVN 320kbps SEARCH RESOLUTION (Tier 1) ───
    final cleanT = cleanTitle(song.title);
    final cleanA = song.artist != 'Unknown Artist' && song.artist.isNotEmpty ? song.artist.trim() : '';
    try {
      final queries = [
        if (cleanA.isNotEmpty) '$cleanT $cleanA',
        cleanT,
      ];

      for (final query in queries) {
        final matches = await CatalogService.searchOnline(query, limit: 6);
        for (final match in matches) {
          if (match.streamUrl.isNotEmpty && match.streamUrl.contains('saavncdn.com')) {
            final isVerified = CatalogService.verifyMatch(
              targetTitle: song.title,
              targetArtist: song.artist,
              candidateTitle: match.title,
              candidateArtist: match.artist,
            );

            if (isVerified) {
              debugPrint('[Tri-Engine: JioSaavn] Verified 320kbps stream resolved for "${song.title}"');
              return _buildBitrateList(match.streamUrl);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Tri-Engine: JioSaavn] Search error for "${song.title}": $e');
    }

    // ─── 6. YOUTUBE MUSIC / PIPED FALLBACK RESOLUTION (Tier 2) ───
    // If not found or not verified on JioSaavn (e.g. indie tracks like "Kashmiri" by Ajeet Katara,
    // remixes, covers, live versions), seamlessly resolve via YouTube Music / Piped
    try {
      debugPrint('[Tri-Engine: YouTube Fallback] Searching YouTube Music for "${song.title}" by "${song.artist}"...');
      final ytQuery = cleanA.isNotEmpty ? '$cleanT $cleanA audio' : '$cleanT audio';
      final ytResults = await YouTubeImporterService.searchYouTube(ytQuery, limit: 5);

      for (final ytSong in ytResults) {
        final videoId = YouTubeImporterService.extractVideoId(ytSong.streamUrl) ??
            (ytSong.id.startsWith('yt_') ? ytSong.id.replaceFirst('yt_', '') : null);
        if (videoId != null && videoId.isNotEmpty) {
          final streams = await YouTubeImporterService.getAudioStreamUrls(videoId);
          if (streams.isNotEmpty) {
            debugPrint('[Tri-Engine: YouTube Fallback] Successfully resolved "${song.title}" via YouTube ($videoId)');
            return streams;
          }
        }
      }
    } catch (e) {
      debugPrint('[Tri-Engine: YouTube Fallback] Resolution error for "${song.title}": $e');
    }

    debugPrint('[Tri-Engine] All engines exhausted for "${song.title}"');
    return const [];
  }

  /// Build a bitrate fallback list (320kbps → 160kbps → 96kbps) for JioSaavn CDN streams
  static List<String> _buildBitrateList(String stream) {
    final list = <String>[stream];
    final bitratePattern = RegExp(r'_320\.(mp4|m4a)');
    if (bitratePattern.hasMatch(stream)) {
      list.add(stream.replaceAll(bitratePattern, r'_160.$1'));
      list.add(stream.replaceAll(bitratePattern, r'_96.$1'));
    }
    return list;
  }
}
