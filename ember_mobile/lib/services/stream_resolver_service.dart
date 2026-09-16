import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import 'catalog_service.dart';
import 'piped_service.dart';
import 'youtube_importer_service.dart';

class StreamResolverService {
  /// Normalizes title string by stripping noise words
  static String cleanTitle(String raw) {
    return raw
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
        .trim();
  }

  /// Spotube-Style YouTube Candidate Scoring Algorithm
  static int calculateCandidateScore({
    required String targetTitle,
    required String targetArtist,
    required Duration targetDuration,
    required Video candidate,
  }) {
    int score = 0;
    final cTitle = candidate.title.toLowerCase();
    final cAuthor = candidate.author.toLowerCase();
    final tTitle = targetTitle.toLowerCase();
    final tArtist = targetArtist.toLowerCase();

    // 1. Duration Verification
    final candDuration = candidate.duration ?? Duration.zero;
    if (targetDuration > Duration.zero && candDuration > Duration.zero) {
      final diffSeconds = (candDuration.inSeconds - targetDuration.inSeconds).abs();
      if (diffSeconds <= 3) {
        score += 50; // Near-perfect duration match
      } else if (diffSeconds <= 8) {
        score += 35;
      } else if (diffSeconds <= 15) {
        score += 15;
      } else if (diffSeconds > 40) {
        score -= 70; // Likely a 1-hour extended mix or short snippet
      }
    }

    // 2. Artist / Channel Verification
    if (tArtist.isNotEmpty && cAuthor.contains(tArtist)) {
      score += 35;
    }
    if (cAuthor.contains('topic')) {
      score += 25; // Official YouTube Music Topic channel
    }

    // 3. Clean Title Content Matching
    final cleanT = cleanTitle(tTitle);
    if (cTitle.contains(cleanT)) {
      score += 30;
    }
    if (cTitle.contains('official audio') || cTitle.contains('original mix')) {
      score += 15;
    }

    // 4. Noise Penalty
    const blacklist = [
      'live',
      'concert',
      'reaction',
      'slowed',
      'reverb',
      '8d audio',
      'cover by',
      'guitar tutorial',
      'piano tutorial',
      'parody',
      'bass boosted'
    ];
    for (final term in blacklist) {
      if (cTitle.contains(term) && !tTitle.contains(term)) {
        score -= 45;
      }
    }

    return score;
  }

  /// Search YouTube for best matching audio stream using Spotube-style ranking
  static Future<String?> resolveFromYouTube(Song song) async {
    final yt = YoutubeExplode();
    try {
      final cleanT = cleanTitle(song.title);
      final cleanA = song.artist != 'Unknown Artist' ? song.artist.trim() : '';
      final queries = [
        if (cleanA.isNotEmpty) '$cleanA - $cleanT official audio',
        if (cleanA.isNotEmpty) '$cleanT $cleanA',
        cleanT,
      ];

      final scoredCandidates = <({Video video, int score})>[];

      for (final query in queries) {
        try {
          final results = await yt.search.search(query).timeout(const Duration(seconds: 8));
          for (final video in results.take(6)) {
            final score = calculateCandidateScore(
              targetTitle: song.title,
              targetArtist: song.artist,
              targetDuration: song.duration,
              candidate: video,
            );
            if (score > -20) {
              scoredCandidates.add((video: video, score: score));
            }
          }
          if (scoredCandidates.any((c) => c.score >= 50)) break; // Found high-confidence match
        } catch (_) {
          continue;
        }
      }

      scoredCandidates.sort((a, b) => b.score.compareTo(a.score));

      // Try top 3 scored candidates in order
      for (final candidate in scoredCandidates.take(3)) {
        final streamUrl = await YouTubeImporterService.getAudioStreamUrl(candidate.video.id.value);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          return streamUrl;
        }
      }

      // Secondary fallback: Piped search + stream proxy
      try {
        final searchTerms = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
            ? '${song.title} ${song.artist}'
            : song.title;
        final pipedResults = await PipedService.search(searchTerms);
        for (final item in pipedResults.take(3)) {
          final itemUrl = item['url'] as String? ?? '';
          final vid = itemUrl.replaceFirst('/watch?v=', '').trim();
          if (vid.isNotEmpty) {
            final pipedStream = await PipedService.getAudioStream(vid);
            if (pipedStream != null && pipedStream.isNotEmpty) {
              debugPrint('[Piped Fallback] Resolved stream for "${song.title}" [vid=$vid]');
              return pipedStream;
            }
          }
        }
      } catch (e) {
        debugPrint('Piped search fallback error: $e');
      }
    } catch (e) {
      debugPrint('YouTube stream resolution error for "${song.title}": $e');
    } finally {
      yt.close();
    }
    return null;
  }

  /// Tri-Engine (Multi-Thrice) Playback Resolver:
  /// - YouTube Engine (NewPipe): videoId direct audio stream, preserves exact variant (slowed+reverb, remix, etc.)
  /// - Spotify Engine (Spotube): Spotube candidate matching for studio track audio (strict duration & Topic channel)
  /// - JioSaavn Engine: 320kbps direct CDN streaming (aac.saavncdn.com)
  /// - Local/Offline: direct device storage playback
  static Future<List<String>> resolvePlayableStreamCandidates(Song song) async {
    final candidates = <String>[];
    final s = song.streamUrl;

    // ─── 1. LOCAL / OFFLINE FILES ───
    if (s.isNotEmpty && (s.startsWith('/') || s.startsWith('file://'))) {
      return [s];
    }

    // ─── 2. DIRECT MEDIA STREAMS (Already resolved or direct audio file) ───
    // NOTE: googlevideo.com URLs are NOT trusted here — they expire after ~4h
    // and cause 403 Forbidden. Let the YouTube engine re-resolve them.
    if (s.isNotEmpty &&
        !s.startsWith('spotify:') &&
        !s.contains('youtube.com/watch') &&
        !s.contains('youtu.be/') &&
        !s.contains('googlevideo.com') &&
        (s.contains('saavncdn.com') ||
         s.endsWith('.mp3') ||
         s.endsWith('.m4a') ||
         s.endsWith('.mp4') ||
         s.endsWith('.aac') ||
         s.contains('.m4a') ||
         s.contains('.mp3'))) {
      return [s];
    }

    // ─── 3. YOUTUBE ENGINE (NewPipe Architecture) ───
    // If it's a YouTube-sourced track, resolve strictly from YouTube via video ID
    // NEVER substitute JioSaavn or Spotify! Preserves slowed+reverb, live, remix, acoustic!
    final isYt = song.isYouTube || song.id.startsWith('yt_') || s.contains('youtube.com') || s.contains('youtu.be');
    if (isYt) {
      String? videoId;
      if (song.id.startsWith('yt_')) {
        videoId = song.id.replaceFirst('yt_', '');
      }
      videoId ??= YouTubeImporterService.extractVideoId(s);

      if (videoId != null && videoId.isNotEmpty) {
        try {
          final ytStream = await YouTubeImporterService.getAudioStreamUrl(videoId);
          if (ytStream != null && ytStream.isNotEmpty) {
            debugPrint('[NewPipe Engine] YouTube direct stream resolved for "${song.title}" [vid=$videoId]');
            return [ytStream];
          }
        } catch (e) {
          debugPrint('[NewPipe Engine] Direct stream error for "$videoId": $e');
        }
      }

      // YouTube search fallback (stays strictly on YouTube)
      try {
        final ytFallback = await resolveFromYouTube(song);
        if (ytFallback != null && ytFallback.isNotEmpty) {
          debugPrint('[NewPipe Engine] YouTube search fallback resolved for "${song.title}"');
          return [ytFallback];
        }
      } catch (e) {
        debugPrint('[NewPipe Engine] Search fallback error: $e');
      }

      return candidates;
    }

    // ─── 4. SPOTIFY ENGINE (Spotube Architecture) ───
    // Primary: YouTube Music matching (full song audio via youtube_explode + Piped)
    // Secondary: JioSaavn 320kbps (same song, different source)
    // Tertiary: iTunes preview (30-sec, last resort only)
    final isSp = song.isSpotify || song.id.startsWith('sp_') || s.startsWith('spotify:');
    if (isSp) {
      // 4a. YouTube Music matching (Spotube algorithm)
      try {
        debugPrint('[Spotube Engine] Resolving studio audio for Spotify track: "${song.title}" by "${song.artist}"');
        final spotubeStream = await resolveFromYouTube(song);
        if (spotubeStream != null && spotubeStream.isNotEmpty) {
          debugPrint('[Spotube Engine] Successfully matched studio stream for "${song.title}"');
          return [spotubeStream];
        }
      } catch (e) {
        debugPrint('[Spotube Engine] YouTube match error: $e');
      }

      // 4b. JioSaavn 320kbps fallback (full song, high quality)
      try {
        final query = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
            ? '${song.title} ${song.artist}'
            : song.title;
        final saavnMatches = await CatalogService.searchOnline(query, limit: 3);
        for (final match in saavnMatches) {
          if (match.streamUrl.isNotEmpty && match.streamUrl.contains('saavncdn.com')) {
            debugPrint('[Spotube Engine] JioSaavn 320kbps fallback matched for "${song.title}"');
            return [match.streamUrl];
          }
        }
      } catch (e) {
        debugPrint('[Spotube Engine] JioSaavn fallback error: $e');
      }

      // 4c. iTunes preview (30-sec, absolute last resort)
      if (s.contains('itunes.apple.com') && s.isNotEmpty) {
        candidates.add(s);
      }

      return candidates;
    }

    // ─── 5. JIOSAAVN ENGINE (320kbps Audiophile Direct CDN) ───
    // If the song is from JioSaavn, resolve strictly from JioSaavn CDN
    if (song.isJioSaavn || song.source == 'saavn') {
      try {
        final query = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
            ? '${song.title} ${song.artist}'
            : song.title;
        final saavnMatches = await CatalogService.searchOnline(query, limit: 3);
        for (final match in saavnMatches) {
          if (match.streamUrl.isNotEmpty && match.streamUrl.contains('saavncdn.com')) {
            debugPrint('[JioSaavn Engine] Direct 320kbps CDN stream matched for "${song.title}"');
            return [match.streamUrl];
          }
        }
      } catch (e) {
        debugPrint('[JioSaavn Engine] Stream resolution error: $e');
      }
      return candidates;
    }

    // ─── 6. UNKNOWN / GENERAL TRACK RESOLUTION ───
    try {
      final saavnMatches = await CatalogService.searchOnline('${song.title} ${song.artist}', limit: 2);
      for (final match in saavnMatches) {
        if (match.streamUrl.contains('saavncdn.com')) return [match.streamUrl];
      }
    } catch (_) {}

    final fallbackYt = await resolveFromYouTube(song);
    if (fallbackYt != null) return [fallbackYt];

    if (s.isNotEmpty && !s.startsWith('spotify:') && !s.contains('youtube.com/watch') && !s.contains('youtu.be/')) {
      candidates.add(s);
    }

    return candidates;
  }
}
