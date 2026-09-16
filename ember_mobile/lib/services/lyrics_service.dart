import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });

  @override
  String toString() => '[${timestamp.inSeconds}s]: $text';
}

class LyricsResult {
  final List<LyricLine> syncedLyrics;
  final String plainLyrics;
  final bool hasSynced;

  const LyricsResult({
    required this.syncedLyrics,
    required this.plainLyrics,
    required this.hasSynced,
  });

  static const empty = LyricsResult(
    syncedLyrics: [],
    plainLyrics: '',
    hasSynced: false,
  );
}

class LyricsService {
  static final Map<String, LyricsResult> _cache = {};

  static String cleanString(String input) {
    return input
        .replaceAll(RegExp(r'\s*[\(\[](feat\.|ft\.|official|video|audio|remastered|lyric video|from|version|bonus|deluxe)[^\)\]]*[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*(feat\.|ft\.|official|video|audio|remastered|lyric video|remaster).*$', caseSensitive: false), '')
        .trim();
  }

  static List<LyricLine> parseLrc(String lrcText) {
    final lines = <LyricLine>[];
    Duration globalOffset = Duration.zero;

    final tagRegex = RegExp(r'\[([a-zA-Z]+|\d+):([^\]]+)\]');
    final timeRegex = RegExp(r'^(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?$');

    for (final rawLine in lrcText.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final tagMatches = tagRegex.allMatches(trimmed).toList();
      if (tagMatches.isEmpty) continue;

      final lastTag = tagMatches.last;
      final lineText = trimmed.substring(lastTag.end).trim();
      final lineTimestamps = <Duration>[];

      for (final match in tagMatches) {
        final key = match.group(1)!;
        final value = match.group(2)!;

        if (key.toLowerCase() == 'offset') {
          final offsetMs = int.tryParse(value) ?? 0;
          globalOffset = Duration(milliseconds: offsetMs);
          continue;
        }

        if (int.tryParse(key) == null) {
          // Metadata tag like [ar:Artist], skip
          continue;
        }

        final timeMatch = timeRegex.firstMatch('$key:$value');
        if (timeMatch != null) {
          final mins = int.tryParse(timeMatch.group(1) ?? '0') ?? 0;
          final secs = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
          final frac = timeMatch.group(3) ?? '0';

          int millis = 0;
          if (frac.length == 1) {
            millis = (int.tryParse(frac) ?? 0) * 100;
          } else if (frac.length == 2) {
            millis = (int.tryParse(frac) ?? 0) * 10;
          } else {
            millis = int.tryParse(frac.substring(0, 3)) ?? 0;
          }

          lineTimestamps.add(Duration(minutes: mins, seconds: secs, milliseconds: millis));
        }
      }

      for (final ts in lineTimestamps) {
        final adjustedTs = ts + globalOffset;
        lines.add(
          LyricLine(
            timestamp: adjustedTs.isNegative ? Duration.zero : adjustedTs,
            text: lineText.isEmpty ? '...' : lineText,
          ),
        );
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  static Future<LyricsResult> fetchLyrics(String title, String artist) async {
    final cleanTitle = cleanString(title);
    final cleanArtist = cleanString(artist);
    final cacheKey = '${cleanTitle.toLowerCase()}___${cleanArtist.toLowerCase()}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      // 1. Direct match by track and artist
      final getUrl = Uri.https('lrclib.net', '/api/get', {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      });
      final resp = await http.get(getUrl, headers: {'User-Agent': 'EmberMusicApp/1.0'}).timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final syncedStr = data['syncedLyrics'] as String?;
        final plainStr = data['plainLyrics'] as String? ?? '';

        final syncedLines = syncedStr != null ? parseLrc(syncedStr) : <LyricLine>[];
        final result = LyricsResult(
          syncedLyrics: syncedLines,
          plainLyrics: plainStr.isNotEmpty ? plainStr : syncedLines.map((l) => l.text).join('\n'),
          hasSynced: syncedLines.isNotEmpty,
        );
        _cache[cacheKey] = result;
        return result;
      }

      // 2. Search fallback
      final queryParam = '$cleanTitle $cleanArtist'.trim();
      final searchUrl = Uri.https('lrclib.net', '/api/search', {
        'q': queryParam,
      });
      final searchResp = await http.get(searchUrl, headers: {'User-Agent': 'EmberMusicApp/1.0'}).timeout(const Duration(seconds: 5));

      if (searchResp.statusCode == 200) {
        final list = jsonDecode(searchResp.body) as List? ?? [];
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final syncedStr = first['syncedLyrics'] as String?;
          final plainStr = first['plainLyrics'] as String? ?? '';
          final syncedLines = syncedStr != null ? parseLrc(syncedStr) : <LyricLine>[];
          final result = LyricsResult(
            syncedLyrics: syncedLines,
            plainLyrics: plainStr.isNotEmpty ? plainStr : syncedLines.map((l) => l.text).join('\n'),
            hasSynced: syncedLines.isNotEmpty,
          );
          _cache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('Lyrics fetch error: $e');
    }

    return LyricsResult.empty;
  }
}
