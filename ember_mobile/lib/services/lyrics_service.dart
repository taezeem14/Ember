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
    final regExp = RegExp(r'^\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)$');

    for (final rawLine in lrcText.split('\n')) {
      final line = rawLine.trim();
      final match = regExp.firstMatch(line);
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fractionStr = match.group(3) ?? '0';
        final millis = fractionStr.length == 2
            ? (int.tryParse(fractionStr) ?? 0) * 10
            : (int.tryParse(fractionStr) ?? 0);

        final text = match.group(4)?.trim() ?? '';
        lines.add(
          LyricLine(
            timestamp: Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            text: text,
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
