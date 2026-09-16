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
    // Accommodate official music videos which frequently have 15-30s intro/outro scenes
    final candDuration = candidate.duration ?? Duration.zero;
    if (targetDuration > Duration.zero && candDuration > Duration.zero) {
      final diffSeconds = (candDuration.inSeconds - targetDuration.inSeconds).abs();
      if (diffSeconds <= 5) {
        score += 50; // Near-perfect duration match
      } else if (diffSeconds <= 15) {
        score += 35;
      } else if (diffSeconds <= 40) {
        score += 20; // Official music video with intro/outro
      } else if (diffSeconds <= 70) {
        score += 10;
      } else if (diffSeconds > 180) {
        score -= 60; // 1-hour loops or 20-minute compilation mixes
      }
    }

    // 2. Artist / Channel Verification (alphanumeric normalized)
    String normalize(String s) => s.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normCandAuthor = normalize(cAuthor);
    final normTargetArtist = normalize(tArtist);
    if (normTargetArtist.isNotEmpty &&
        (normCandAuthor.contains(normTargetArtist) || normTargetArtist.contains(normCandAuthor))) {
      score += 35;
    }
    if (cAuthor.contains('topic')) {
      score += 30; // Official YouTube Music Topic channel
    }

    // 3. Clean Title Content Matching
    final cleanT = cleanTitle(tTitle).toLowerCase();
    if (cleanT.isNotEmpty && cTitle.contains(cleanT)) {
      score += 30;
    }
    if (cTitle.contains('official audio') || cTitle.contains('original mix') || cTitle.contains('audio')) {
      score += 15;
    }

    // 4. Noise Penalty - filter out tutorials and parodies
    const blacklist = [
      'reaction',
      'guitar tutorial',
      'piano tutorial',
      'parody',
      'bass boosted',
    ];
    for (final term in blacklist) {
      if (cTitle.contains(term) && !tTitle.contains(term)) {
        score -= 40;
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
            if (score > -25) {
              scoredCandidates.add((video: video, score: score));
            }
          }
          if (scoredCandidates.any((c) => c.score >= 45)) break; // Found high-confidence match
        } catch (_) {
          continue;
        }
      }

      scoredCandidates.sort((a, b) => b.score.compareTo(a.score));

      // Try top 5 scored candidates in order
      for (final candidate in scoredCandidates.take(5)) {
        final streamUrl = await YouTubeImporterService.getAudioStreamUrl(candidate.video.id.value);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          return streamUrl;
        }
      }

      // ULTIMATE SPOTUBE FALLBACK: If heuristic scoring yielded no stream, search YouTube
      // directly and try the top 3 videos without filtering
      try {
        final queryStr = '$cleanT ${cleanA.isNotEmpty ? cleanA : ''}'.trim();
        final directResults = await yt.search.search(queryStr).timeout(const Duration(seconds: 6));
        for (final video in directResults.take(3)) {
          final streamUrl = await YouTubeImporterService.getAudioStreamUrl(video.id.value);
          if (streamUrl != null && streamUrl.isNotEmpty) {
            debugPrint('[YouTube Direct Fallback] Matched stream for "${song.title}" [vid=${video.id.value}]');
            return streamUrl;
          }
        }
      } catch (e) {
        debugPrint('YouTube direct search fallback error: $e');
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
  /// - YouTube Engine (NewPipe): videoId direct audio streams (MP4/AAC & WebM/Opus), preserves exact variant
  /// - Spotify Engine (Spotube): Spotube matching for full-length studio track audio (NO 30s previews)
  /// - JioSaavn Engine: 320kbps direct CDN streaming with verifyMatch token validation & 160k/96k fallbacks
  /// - Local/Offline: direct device storage playback
  static Future<List<String>> resolvePlayableStreamCandidates(Song song) async {
    final candidates = <String>[];
    final s = song.streamUrl;

    // ─── 1. LOCAL / OFFLINE FILES ───
    if (s.isNotEmpty && (s.startsWith('/') || s.startsWith('file://'))) {
      return [s];
    }

    // ─── 2. DIRECT MEDIA STREAMS (Already resolved or direct audio file) ───
    // Excludes googlevideo.com (expires ~4h) and itunes.apple.com (30s preview)
    if (s.isNotEmpty &&
        !s.startsWith('spotify:') &&
        !s.contains('youtube.com/watch') &&
        !s.contains('youtu.be/') &&
        !s.contains('googlevideo.com') &&
        !s.contains('itunes.apple.com') &&
        (s.contains('saavncdn.com') ||
         s.endsWith('.mp3') ||
         s.endsWith('.m4a') ||
         s.endsWith('.mp4') ||
         s.endsWith('.aac') ||
         s.contains('.m4a') ||
         s.contains('.mp3'))) {
      if (s.contains('saavncdn.com') && s.contains('_320.mp4')) {
        return [
          s,
          s.replaceAll('_320.mp4', '_160.mp4'),
          s.replaceAll('_320.mp4', '_96.mp4'),
        ];
      }
      return [s];
    }

    // ─── 3. YOUTUBE ENGINE (NewPipe Architecture) ───
    // Resolves strictly from YouTube to preserve exact variant (slowed+reverb, remix, acoustic, live)
    final isYt = song.isYouTube || song.id.startsWith('yt_') || s.contains('youtube.com') || s.contains('youtu.be');
    if (isYt) {
      String? videoId;
      if (song.id.startsWith('yt_')) {
        videoId = song.id.replaceFirst('yt_', '');
      }
      videoId ??= YouTubeImporterService.extractVideoId(s);

      if (videoId != null && videoId.isNotEmpty) {
        try {
          // Return all candidate audio streams (AAC 128k, Opus 160k, AAC 48k)
          final ytStreams = await YouTubeImporterService.getAudioStreamUrls(videoId);
          if (ytStreams.isNotEmpty) {
            debugPrint('[NewPipe Engine] Resolved ${ytStreams.length} stream candidates for "${song.title}" [vid=$videoId]');
            return ytStreams;
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
    // Primary: YouTube Music matching for full studio track audio
    // Secondary: JioSaavn 320kbps verified exact match
    // NEVER returns 30-second previews!
    final isSp = song.isSpotify || song.id.startsWith('sp_') || s.startsWith('spotify:');
    if (isSp) {
      // 4a. YouTube Music matching (Spotube algorithm)
      try {
        debugPrint('[Spotube Engine] Resolving full studio audio for Spotify track: "${song.title}" by "${song.artist}"');
        final spotubeStream = await resolveFromYouTube(song);
        if (spotubeStream != null && spotubeStream.isNotEmpty) {
          debugPrint('[Spotube Engine] Successfully matched full studio stream for "${song.title}"');
          return [spotubeStream];
        }
      } catch (e) {
        debugPrint('[Spotube Engine] YouTube match error: $e');
      }

      // 4b. JioSaavn 320kbps verified fallback (MUST match title & artist)
      try {
        final query = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
            ? '${song.title} ${song.artist}'
            : song.title;
        final saavnMatches = await CatalogService.searchOnline(query, limit: 5);
        for (final match in saavnMatches) {
          if (match.streamUrl.isNotEmpty &&
              match.streamUrl.contains('saavncdn.com') &&
              CatalogService.verifyMatch(
                targetTitle: song.title,
                targetArtist: song.artist,
                candidateTitle: match.title,
                candidateArtist: match.artist,
              )) {
            debugPrint('[Spotube Engine] JioSaavn 320kbps verified fallback matched for "${song.title}"');
            final matchUrl = match.streamUrl;
            final list = <String>[matchUrl];
            if (matchUrl.contains('_320.mp4')) {
              list.add(matchUrl.replaceAll('_320.mp4', '_160.mp4'));
              list.add(matchUrl.replaceAll('_320.mp4', '_96.mp4'));
            }
            return list;
          }
        }
      } catch (e) {
        debugPrint('[Spotube Engine] JioSaavn fallback error: $e');
      }

      return candidates;
    }

    // ─── 5. JIOSAAVN ENGINE (320kbps Audiophile Direct CDN) ───
    // Enforces verifyMatch token validation so the wrong song is NEVER played
    if (song.isJioSaavn || song.source == 'saavn') {
      if (s.contains('saavncdn.com')) {
        final list = <String>[s];
        if (s.contains('_320.mp4')) {
          list.add(s.replaceAll('_320.mp4', '_160.mp4'));
          list.add(s.replaceAll('_320.mp4', '_96.mp4'));
        }
        return list;
      }
      try {
        final query = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
            ? '${song.title} ${song.artist}'
            : song.title;
        final saavnMatches = await CatalogService.searchOnline(query, limit: 5);
        for (final match in saavnMatches) {
          if (match.streamUrl.isNotEmpty &&
              match.streamUrl.contains('saavncdn.com') &&
              CatalogService.verifyMatch(
                targetTitle: song.title,
                targetArtist: song.artist,
                candidateTitle: match.title,
                candidateArtist: match.artist,
              )) {
            debugPrint('[JioSaavn Engine] Verified 320kbps CDN stream matched for "${song.title}"');
            final matchUrl = match.streamUrl;
            final list = <String>[matchUrl];
            if (matchUrl.contains('_320.mp4')) {
              list.add(matchUrl.replaceAll('_320.mp4', '_160.mp4'));
              list.add(matchUrl.replaceAll('_320.mp4', '_96.mp4'));
            }
            return list;
          }
        }
      } catch (e) {
        debugPrint('[JioSaavn Engine] Stream resolution error: $e');
      }
      return candidates;
    }

    // ─── 6. UNKNOWN / GENERAL TRACK RESOLUTION ───
    try {
      final saavnMatches = await CatalogService.searchOnline('${song.title} ${song.artist}', limit: 3);
      for (final match in saavnMatches) {
        if (match.streamUrl.contains('saavncdn.com') &&
            CatalogService.verifyMatch(
              targetTitle: song.title,
              targetArtist: song.artist,
              candidateTitle: match.title,
              candidateArtist: match.artist,
            )) {
          return [match.streamUrl];
        }
      }
    } catch (_) {}

    final fallbackYt = await resolveFromYouTube(song);
    if (fallbackYt != null) return [fallbackYt];

    if (s.isNotEmpty &&
        !s.startsWith('spotify:') &&
        !s.contains('youtube.com/watch') &&
        !s.contains('youtu.be/') &&
        !s.contains('itunes.apple.com')) {
      candidates.add(s);
    }

    return candidates;
  }
}
