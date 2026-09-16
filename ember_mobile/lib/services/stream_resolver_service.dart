import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import 'catalog_service.dart';
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

      Video? bestMatch;
      int highestScore = -100;

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
            if (score > highestScore) {
              highestScore = score;
              bestMatch = video;
            }
          }
          if (highestScore >= 50) break; // Found high-confidence match
        } catch (_) {
          continue;
        }
      }

      if (bestMatch != null && highestScore > -20) {
        final streamUrl = await YouTubeImporterService.getAudioStreamUrl(bestMatch.id.value);
        return streamUrl;
      }
    } catch (e) {
      debugPrint('YouTube stream resolution error for "${song.title}": $e');
    } finally {
      yt.close();
    }
    return null;
  }

  /// Source-Aware Stream Resolution Engine:
  /// - YouTube songs → resolve via their actual YouTube video ID (preserves exact version: slowed, reverb, remix, etc.)
  /// - JioSaavn songs → play direct CDN 320kbps stream
  /// - Local/offline files → play directly
  /// - Unknown source → try JioSaavn search, then iTunes, then YouTube search as last resort
  static Future<List<String>> resolvePlayableStreamCandidates(Song song) async {
    final candidates = <String>[];
    final s = song.streamUrl;

    // ─── 1. LOCAL / OFFLINE / DIRECT CDN ───
    // Already a directly playable URL or local file — use as-is
    if (s.isNotEmpty &&
        (s.contains('saavncdn.com') ||
         s.startsWith('/') ||
         s.startsWith('file://') ||
         s.contains('itunes.apple.com') ||
         s.contains('googlevideo.com') ||
         s.contains('rr') && s.contains('.googlevideo.com'))) {
      return [s];
    }

    // ─── 2. YOUTUBE-SOURCED SONGS → Resolve via actual video ID ───
    // This preserves the EXACT version the user imported (slowed+reverb, remix, live, etc.)
    // NEVER substitute a JioSaavn search result for a YouTube-imported song
    final isYouTubeSong = song.id.startsWith('yt_') ||
        s.contains('youtube.com/watch') ||
        s.contains('youtu.be/') ||
        song.source == 'youtube';

    if (isYouTubeSong) {
      // Extract the video ID from the song
      String? videoId;
      if (song.id.startsWith('yt_')) {
        videoId = song.id.replaceFirst('yt_', '');
      }
      if (videoId == null || videoId.isEmpty) {
        videoId = YouTubeImporterService.extractVideoId(s);
      }

      if (videoId != null && videoId.isNotEmpty) {
        try {
          final ytStream = await YouTubeImporterService.getAudioStreamUrl(videoId);
          if (ytStream != null && ytStream.isNotEmpty) {
            debugPrint('YouTube direct stream resolved for "${song.title}" [vid=$videoId]');
            return [ytStream];
          }
        } catch (e) {
          debugPrint('YouTube direct stream error for "$videoId": $e');
        }
      }

      // YouTube fallback: search YouTube by title (still stays on YouTube, never JioSaavn)
      try {
        final ytFallback = await resolveFromYouTube(song);
        if (ytFallback != null && ytFallback.isNotEmpty) {
          debugPrint('YouTube search fallback resolved for "${song.title}"');
          return [ytFallback];
        }
      } catch (e) {
        debugPrint('YouTube search fallback error: $e');
      }

      // If YouTube completely fails, don't return empty — try other sources as emergency
      debugPrint('WARNING: YouTube resolution completely failed for "${song.title}". Trying emergency fallbacks...');
    }

    // ─── 3. JIOSAAVN-SOURCED SONGS → 320kbps Direct CDN ───
    // Only search JioSaavn for songs that actually came from JioSaavn or have no known source
    if (!isYouTubeSong) {
      try {
        final query = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
            ? '${song.title} ${song.artist}'
            : song.title;
        final saavnMatches = await CatalogService.searchOnline(query, limit: 3);
        for (final match in saavnMatches) {
          if (match.streamUrl.isNotEmpty && match.streamUrl.contains('saavncdn.com')) {
            candidates.add(match.streamUrl);
            return candidates;
          }
        }
      } catch (e) {
        debugPrint('JioSaavn stream resolution error: $e');
      }
    }

    // ─── 4. ITUNES PREVIEW FALLBACK ───
    final meta = YouTubeImporterService.parseYouTubeMetadata(song.title, song.artist);
    try {
      final itunesUrl = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(meta.searchQuery)}&entity=song&limit=3',
      );
      final resp = await http.get(itunesUrl).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['results'] as List? ?? [];
        for (final item in list) {
          final prev = item['previewUrl'] as String?;
          if (prev != null && prev.isNotEmpty) {
            candidates.add(prev);
            break;
          }
        }
      }
    } catch (_) {}

    // ─── 5. LAST RESORT: YouTube search (for non-YouTube songs that failed JioSaavn) ───
    if (candidates.isEmpty && !isYouTubeSong) {
      final ytAudio = await resolveFromYouTube(song);
      if (ytAudio != null && ytAudio.isNotEmpty) {
        candidates.add(ytAudio);
      }
    }

    if (candidates.isEmpty && s.isNotEmpty && !s.startsWith('spotify:') &&
        !s.contains('youtube.com/watch') && !s.contains('youtu.be/')) {
      candidates.add(s);
    }

    return candidates;
  }
}
