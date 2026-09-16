import 'dart:convert';
import 'package:dart_des/dart_des.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'stream_resolver_service.dart';

class MusicCategory {
  final String key;
  final FaIconData icon;
  final String title;
  final String subtitle;
  final String searchQuery;

  const MusicCategory({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.searchQuery,
  });
}

class CatalogService {
  static const List<MusicCategory> categories = [
    MusicCategory(
      key: 'trending',
      icon: FontAwesomeIcons.fire,
      title: 'Trending Now',
      subtitle: 'Top charts & viral hits',
      searchQuery: 'Trending Hindi Punjabi English',
    ),
    MusicCategory(
      key: 'top_hits',
      icon: FontAwesomeIcons.headphones,
      title: 'Global Top 50',
      subtitle: 'The hottest tracks worldwide',
      searchQuery: 'Top 50 Global Hits',
    ),
    MusicCategory(
      key: 'bollywood',
      icon: FontAwesomeIcons.music,
      title: 'Bollywood Hits',
      subtitle: 'Top Hindi blockbuster songs',
      searchQuery: 'Bollywood Top Hits',
    ),
    MusicCategory(
      key: 'punjabi',
      icon: FontAwesomeIcons.drum,
      title: 'Punjabi Bangers',
      subtitle: 'Bhangra, urban & high energy',
      searchQuery: 'Punjabi Top Hits',
    ),
    MusicCategory(
      key: 'pop',
      icon: FontAwesomeIcons.compactDisc,
      title: 'Pop & Dance',
      subtitle: 'Upbeat melodies & anthems',
      searchQuery: 'Pop Dance English Hits',
    ),
    MusicCategory(
      key: 'hiphop',
      icon: FontAwesomeIcons.microphoneLines,
      title: 'Hip-Hop & Rap',
      subtitle: 'Beats, bars & urban hits',
      searchQuery: 'Hip Hop Rap Hits',
    ),
    MusicCategory(
      key: 'lofi',
      icon: FontAwesomeIcons.headphones,
      title: 'Lo-Fi Chill',
      subtitle: 'Atmospheric study & relax beats',
      searchQuery: 'Lo-Fi Chill Beats',
    ),
    MusicCategory(
      key: 'rock',
      icon: FontAwesomeIcons.guitar,
      title: 'Rock & Alternative',
      subtitle: 'Anthems, guitars & indie rock',
      searchQuery: 'Rock Classics Anthems',
    ),
  ];

  static final Map<String, List<Song>> _categoryCache = {};

  static final List<int> _desKey = utf8.encode('38346591');

  /// Decrypt JioSaavn encrypted media URLs using DES in ECB mode, upgraded to 320kbps
  static String? decryptMediaUrl(String? encryptedMediaUrl) {
    if (encryptedMediaUrl == null || encryptedMediaUrl.trim().isEmpty) return null;
    try {
      final des = DES(key: _desKey, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
      final encryptedBytes = base64.decode(encryptedMediaUrl.trim());
      final decryptedBytes = des.decrypt(encryptedBytes);
      final rawUrl = utf8.decode(decryptedBytes).trim();
      // Upgrade from standard 96kbps to 320kbps high-definition full song stream
      return rawUrl.replaceAll('_96.mp4', '_320.mp4');
    } catch (e) {
      debugPrint('Error decrypting JioSaavn media URL: $e');
      return null;
    }
  }

  static String _unescape(dynamic text) {
    if (text == null) return '';
    return text
        .toString()
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  static List<Song> getAllTracks() {
    final list = <Song>[];
    for (final tracks in _categoryCache.values) {
      for (final track in tracks) {
        if (!list.any((s) => s.id == track.id)) {
          list.add(track);
        }
      }
    }
    return list;
  }

  /// Synchronous local search for instant typing response and offline playback
  static List<Song> search(String query) {
    final q = query.toLowerCase().trim();
    final all = getAllTracks();
    if (q.isEmpty) return all;
    return all.where((song) {
      return song.title.toLowerCase().contains(q) ||
          song.artist.toLowerCase().contains(q) ||
          (song.lyrics?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// Real-world online music catalog search with 320kbps JioSaavn CDN streams
  static Future<List<Song>> searchOnline(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return getAllTracks();

    // 1. Primary: JioSaavn 320kbps Direct CDN Engine
    try {
      final saavnUrl = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&includeMetaTags=1&p=1&n=$limit&q=${Uri.encodeComponent(q)}',
      );
      final resp = await http.get(saavnUrl, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }).timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawResults = data['results'] as List? ?? [];
        final parsed = <Song>[];

        for (final item in rawResults) {
          if (item is Map<String, dynamic>) {
            final title = _unescape(item['song'] ?? item['title']);
            final artist = _unescape(item['singers'] ?? item['primary_artists'] ?? item['music']);
            final encrypted = item['encrypted_media_url'] as String?;
            if (title.isEmpty || encrypted == null || encrypted.isEmpty) continue;

            final streamUrl = decryptMediaUrl(encrypted);
            if (streamUrl == null || streamUrl.isEmpty) continue;

            final trackId = item['id']?.toString() ?? 'saavn_${UniqueKey().toString()}';
            final durationSec = int.tryParse('${item['duration']}') ?? 180;
            final rawArt = item['image'] as String? ?? '';
            final artworkUrl = rawArt.replaceAll('150x150', '500x500').replaceAll('50x50', '500x500');

            parsed.add(
              Song(
                id: trackId,
                title: title,
                artist: artist.isNotEmpty ? artist : 'Unknown Artist',
                duration: Duration(seconds: durationSec),
                artworkUrl: artworkUrl,
                streamUrl: streamUrl,
                source: 'saavn',
              ),
            );
          }
        }

        if (parsed.isNotEmpty) {
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('JioSaavn primary search error: $e');
    }

    // 2. Secondary Fallback: Global iTunes catalogue
    try {
      final itunesUrl = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(q)}&entity=song&limit=$limit',
      );
      final resp = await http.get(itunesUrl).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawResults = data['results'] as List? ?? [];
        final parsed = <Song>[];

        for (final item in rawResults) {
          if (item is Map<String, dynamic>) {
            final trackName = item['trackName'] as String?;
            final artistName = item['artistName'] as String?;
            final previewUrl = item['previewUrl'] as String?;
            if (trackName == null || previewUrl == null || previewUrl.isEmpty) continue;

            final trackId = 'itunes_${item['trackId']?.toString() ?? UniqueKey().toString()}';
            final durationMs = (item['trackTimeMillis'] as num?)?.toInt() ?? 180000;
            final rawArt = item['artworkUrl100'] as String? ?? '';
            final artworkUrl = rawArt.replaceAll('100x100bb', '600x600bb');

            parsed.add(
              Song(
                id: trackId,
                title: trackName,
                artist: artistName ?? 'Unknown Artist',
                duration: Duration(milliseconds: durationMs),
                artworkUrl: artworkUrl,
                streamUrl: previewUrl,
                source: 'itunes',
              ),
            );
          }
        }

        if (parsed.isNotEmpty) {
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('iTunes search fallback error: $e');
    }

    // 3. Offline cache fallback
    return search(query);
  }

  /// Fetch trending 320kbps songs from JioSaavn
  static Future<List<Song>> fetchTrendingTracks({int limit = 20}) async {
    if (_categoryCache.containsKey('trending') && _categoryCache['trending']!.isNotEmpty) {
      return _categoryCache['trending']!;
    }

    final tracks = await searchOnline('Trending Top Songs 2026', limit: limit);
    if (tracks.isNotEmpty) {
      _categoryCache['trending'] = tracks;
      return tracks;
    }

    return fetchCategoryTracks('trending', limit: limit);
  }

  /// Fetch songs for a specific music category
  static Future<List<Song>> fetchCategoryTracks(String categoryKey, {int limit = 20}) async {
    if (_categoryCache.containsKey(categoryKey) && _categoryCache[categoryKey]!.isNotEmpty) {
      return _categoryCache[categoryKey]!;
    }
    final category = categories.firstWhere(
      (c) => c.key == categoryKey,
      orElse: () => categories.first,
    );
    final results = await searchOnline(category.searchQuery, limit: limit);
    if (results.isNotEmpty) {
      _categoryCache[categoryKey] = results;
      return results;
    }
    return _categoryCache[categoryKey] ?? [];
  }

  /// Backward-compatible alias
  static Future<List<Song>> fetchMoodTracks(String key) => fetchCategoryTracks(key);

  /// Dynamic recommendation system: fetch tracks related to current song via JioSaavn
  static Future<List<Song>> fetchRecommendations(Song song, {int limit = 10}) async {
    try {
      final query = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
          ? '${song.artist} songs'
          : song.title;
      final online = await searchOnline(query, limit: limit + 2);
      final filtered = online.where((s) => s.id != song.id).take(limit).toList();
      if (filtered.isNotEmpty) {
        return filtered;
      }
    } catch (_) {}

    return getAllTracks().where((s) => s.id != song.id).take(limit).toList();
  }

  /// Smart metadata cleaner: extracts clean song title, artist, and search query
  static ({String cleanTitle, String cleanArtist, String searchQuery}) parseYouTubeMetadata(String rawTitle, String rawAuthor) {
    var t = rawTitle
        .replaceAll(RegExp(r'\((?:official|music|video|audio|lyrics|hd|4k|visualizer|remastered|lyric|prod\.|feat\.|ft\.).*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[(?:official|music|video|audio|lyrics|hd|4k|visualizer|remastered|lyric|prod\.|feat\.|ft\.).*?\]', caseSensitive: false), '')
        .trim();

    if (t.contains('|')) {
      t = t.split('|').first.trim();
    }

    String extractedArtist = '';
    String extractedTitle = t;

    if (t.contains(' - ') || t.contains(' – ') || t.contains(' — ')) {
      final delimiter = t.contains(' - ') ? ' - ' : (t.contains(' – ') ? ' – ' : ' — ');
      final parts = t.split(delimiter);
      if (parts.length >= 2) {
        extractedArtist = parts[0].trim();
        extractedTitle = parts.sublist(1).join(delimiter).trim();
      }
    }

    final lowerAuthor = rawAuthor.toLowerCase();
    final isPublisher = lowerAuthor.contains('vevo') ||
        lowerAuthor.contains('topic') ||
        lowerAuthor.contains('records') ||
        lowerAuthor.contains('record') ||
        lowerAuthor.contains('music') ||
        lowerAuthor.contains('company') ||
        lowerAuthor.contains('label') ||
        rawAuthor == 'Unknown Artist';

    String finalArtist = extractedArtist;
    if (finalArtist.isEmpty && !isPublisher) {
      finalArtist = rawAuthor.trim();
    }

    extractedTitle = extractedTitle
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(?:official|video|audio|lyrics|hd|4k|full song|lyric video)\b', caseSensitive: false), '')
        .trim();

    if (extractedTitle.isEmpty) extractedTitle = t;

    final searchQuery = finalArtist.isNotEmpty ? '$extractedTitle $finalArtist' : extractedTitle;
    return (
      cleanTitle: extractedTitle,
      cleanArtist: finalArtist,
      searchQuery: searchQuery,
    );
  }

  /// High-confidence verification between target track and streaming result
  static bool verifyMatch({
    required String targetTitle,
    required String targetArtist,
    required String candidateTitle,
    required String candidateArtist,
  }) {
    String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final normTargetTitle = normalize(targetTitle);
    final normCandTitle = normalize(candidateTitle);

    if (normTargetTitle.isEmpty || normCandTitle.isEmpty) return false;

    bool titleMatches = normTargetTitle == normCandTitle ||
        normCandTitle.contains(normTargetTitle) ||
        normTargetTitle.contains(normCandTitle);

    if (!titleMatches) {
      final targetTokens = targetTitle.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
      final candTokens = candidateTitle.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
      if (targetTokens.isNotEmpty && candTokens.isNotEmpty) {
        final intersection = targetTokens.intersection(candTokens);
        if (intersection.length >= (targetTokens.length * 0.5).ceil()) {
          titleMatches = true;
        }
      }
    }

    if (!titleMatches) return false;

    final normTargetArtist = normalize(targetArtist);
    final normCandArtist = normalize(candidateArtist);

    if (normTargetArtist.isNotEmpty) {
      final artistTokens = targetArtist.toLowerCase().split(RegExp(r'[\s,&x]+')).where((w) => w.length > 2).toList();
      if (artistTokens.isNotEmpty) {
        final matchesAny = artistTokens.any((token) =>
            normCandArtist.contains(normalize(token)) || normCandTitle.contains(normalize(token)));
        if (!matchesAny) return false;
      }
    }

    return true;
  }

  /// Resolves viable playable stream candidates using StreamResolverService
  static Future<List<String>> resolvePlayableStreamCandidates(Song song) async {
    return StreamResolverService.resolvePlayableStreamCandidates(song);
  }

  /// Resolves any song's stream URL into a directly playable media stream
  static Future<String?> resolvePlayableStream(Song song) async {
    final candidates = await resolvePlayableStreamCandidates(song);
    if (candidates.isNotEmpty) {
      return candidates.first;
    }
    return null;
  }
}
