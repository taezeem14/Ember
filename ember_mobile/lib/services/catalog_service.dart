import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dart_des/dart_des.dart';
import '../models/song.dart';
import 'youtube_importer_service.dart';

class MusicCategory {
  final String key;
  final String emoji;
  final String title;
  final String subtitle;
  final String searchQuery;

  const MusicCategory({
    required this.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.searchQuery,
  });
}

class CatalogService {
  static const List<MusicCategory> categories = [
    MusicCategory(
      key: 'trending',
      emoji: '🚀',
      title: 'Trending Now',
      subtitle: 'Top charts & viral hits',
      searchQuery: 'Trending Songs Hits',
    ),
    MusicCategory(
      key: 'top_hits',
      emoji: '🎧',
      title: 'Global Top 50',
      subtitle: 'The hottest tracks worldwide',
      searchQuery: 'Top Global Hits 2026',
    ),
    MusicCategory(
      key: 'pop',
      emoji: '🎹',
      title: 'Pop & Dance',
      subtitle: 'Upbeat melodies & anthems',
      searchQuery: 'Pop Dance Chart Hits',
    ),
    MusicCategory(
      key: 'hiphop',
      emoji: '🎤',
      title: 'Hip-Hop & Rap',
      subtitle: 'Beats, bars & urban hits',
      searchQuery: 'Hip Hop Rap Top Tracks',
    ),
    MusicCategory(
      key: 'rock',
      emoji: '🎸',
      title: 'Rock & Alternative',
      subtitle: 'Anthems, guitars & indie rock',
      searchQuery: 'Rock Classics Alternative',
    ),
    MusicCategory(
      key: 'electronic',
      emoji: '⚡',
      title: 'Electronic & EDM',
      subtitle: 'Club energy & festival sound',
      searchQuery: 'EDM Electronic Dance Festival',
    ),
    MusicCategory(
      key: 'rnb',
      emoji: '✨',
      title: 'R&B & Soul',
      subtitle: 'Smooth grooves & late night rhythms',
      searchQuery: 'RnB Soul Hits Smooth',
    ),
    MusicCategory(
      key: 'acoustic',
      emoji: '🌿',
      title: 'Acoustic & Indie',
      subtitle: 'Organic instruments & vocals',
      searchQuery: 'Indie Acoustic Singer Songwriter',
    ),
  ];

  static final Map<String, List<Song>> _categoryCache = {};

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

  static final List<int> _desKey = utf8.encode('38346591');

  /// Decrypt JioSaavn encrypted media URLs using DES in ECB mode
  static String? decryptMediaUrl(String? encryptedMediaUrl) {
    if (encryptedMediaUrl == null || encryptedMediaUrl.trim().isEmpty) return null;
    try {
      final des = DES(key: _desKey, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS7);
      final encryptedBytes = base64.decode(encryptedMediaUrl.trim());
      final decryptedBytes = des.decrypt(encryptedBytes);
      final rawUrl = utf8.decode(decryptedBytes).trim();
      // Upgrade from default 96kbps to 320kbps high-definition full song stream
      return rawUrl.replaceAll('_96.mp4', '_320.mp4');
    } catch (e) {
      debugPrint('Error decrypting media URL: $e');
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

  /// Real-world online music catalog search with full-length 320kbps song streaming
  static Future<List<Song>> searchOnline(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return getAllTracks();

    // 1. Primary: Search full-length song catalogue with 320kbps streams
    try {
      final saavnUrl = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&includeMetaTags=1&p=1&n=$limit&q=${Uri.encodeComponent(q)}',
      );
      final resp = await http.get(saavnUrl, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 5));

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

            final trackId = item['id']?.toString() ?? UniqueKey().toString();
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
              ),
            );
          }
        }

        if (parsed.isNotEmpty) {
          return parsed;
        }
      }
    } catch (e) {
      debugPrint('Primary full song search error: $e');
    }

    // 2. Secondary Fallback: Global iTunes catalogue (proven reliable audio streaming)
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

            final trackId = item['trackId']?.toString() ?? UniqueKey().toString();
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

    // 3. Tertiary: YouTube music search via InnerTube
    try {
      final ytSongs = await YouTubeImporterService.searchYouTube(q, limit: limit);
      if (ytSongs.isNotEmpty) {
        return ytSongs;
      }
    } catch (e) {
      debugPrint('YouTube search fallback error: $e');
    }

    // 4. Offline fallback
    return search(query);

  }

  /// Fetch today's real trending full-length songs (320kbps)
  static Future<List<Song>> fetchTrendingTracks({int limit = 20}) async {
    return fetchCategoryTracks('trending', limit: limit);
  }

  /// Fetch full-length 320kbps songs for a specific music category
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

  /// Dynamic recommendation system: fetch tracks related to current song
  static Future<List<Song>> fetchRecommendations(Song song, {int limit = 10}) async {
    final parsed = <Song>[];

    // 1. If native catalog track, query JioSaavn recommendation API
    if (!song.id.startsWith('yt_') && !song.id.startsWith('lofi_') && !song.id.startsWith('rain_')) {
      try {
        final recoUrl = Uri.parse(
          'https://www.jiosaavn.com/api.php?__call=reco.getreco&api_version=4&_format=json&_marker=0&ctx=android&songid=${song.id}',
        );
        final resp = await http.get(recoUrl, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200) {
          final list = jsonDecode(resp.body) as List? ?? [];
          for (final item in list.take(limit)) {
            if (item is Map<String, dynamic>) {
              final title = _unescape(item['song'] ?? item['title']);
              final artist = _unescape(item['singers'] ?? item['primary_artists'] ?? item['music']);
              final encrypted = item['encrypted_media_url'] as String?;
              if (title.isEmpty || encrypted == null || encrypted.isEmpty) continue;

              final streamUrl = decryptMediaUrl(encrypted);
              if (streamUrl == null || streamUrl.isEmpty) continue;

              final trackId = item['id']?.toString() ?? UniqueKey().toString();
              if (trackId == song.id) continue;

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
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Recommendation fetch error: $e');
      }
    }

    if (parsed.isNotEmpty) {
      return parsed;
    }

    // 2. Fallback: query online search for the artist or genre
    try {
      final query = song.artist != 'Unknown Artist' && song.artist.isNotEmpty
          ? song.artist
          : song.title;
      final online = await searchOnline(query, limit: limit);
      final filtered = online.where((s) => s.id != song.id).toList();
      if (filtered.isNotEmpty) {
        return filtered;
      }
    } catch (_) {}

    // 3. Ambient fallback: Return tracks from same mood or popular tracks
    return getAllTracks().where((s) => s.id != song.id).take(limit).toList();
  }

  /// Resolves any song's stream URL into a directly playable media stream with multi-tier fallback
  static Future<String?> resolvePlayableStream(Song song) async {
    final s = song.streamUrl;
    final isYt = s.contains('youtube.com') || s.contains('youtu.be') || song.id.startsWith('yt_');
    if (!isYt && s.isNotEmpty) {
      return s;
    }

    final cleanTitle = song.title
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]|Official|Music|Video|Audio|HD|4K|Lyrics|Visualizer', caseSensitive: false), '')
        .trim();
    final cleanArtist = (song.artist == 'Unknown Artist' ||
            song.artist.toLowerCase().contains('topic') ||
            song.artist.toLowerCase().contains('vevo'))
        ? ''
        : song.artist.trim();
    final query = cleanArtist.isNotEmpty ? '$cleanTitle $cleanArtist' : cleanTitle;

    // 1. High-speed primary: Query JioSaavn full-length 320kbps catalogue
    try {
      final saavnUrl = Uri.parse(
        'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&includeMetaTags=1&p=1&n=3&q=${Uri.encodeComponent(query)}',
      );
      final resp = await http.get(saavnUrl, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['results'] as List? ?? [];
        for (final item in list) {
          final enc = item['encrypted_media_url'] as String?;
          if (enc != null && enc.isNotEmpty) {
            final stream = decryptMediaUrl(enc);
            if (stream != null && stream.isNotEmpty) {
              debugPrint('Resolved YouTube track "${song.title}" via Saavn 320kbps CDN');
              return stream;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Saavn resolve error: $e');
    }

    // 1b. If artist was present, try title only on Saavn
    if (cleanArtist.isNotEmpty) {
      try {
        final saavnUrl2 = Uri.parse(
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&includeMetaTags=1&p=1&n=3&q=${Uri.encodeComponent(cleanTitle)}',
        );
        final resp2 = await http.get(saavnUrl2, headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 3));
        if (resp2.statusCode == 200) {
          final data2 = jsonDecode(resp2.body) as Map<String, dynamic>;
          final list2 = data2['results'] as List? ?? [];
          for (final item in list2) {
            final enc = item['encrypted_media_url'] as String?;
            if (enc != null && enc.isNotEmpty) {
              final stream = decryptMediaUrl(enc);
              if (stream != null && stream.isNotEmpty) {
                debugPrint('Resolved YouTube track "${song.title}" via Saavn title-only CDN');
                return stream;
              }
            }
          }
        }
      } catch (_) {}
    }

    // 2. Secondary fallback: Global iTunes catalogue (proven reliable audio streaming)
    try {
      final itunesUrl = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(cleanTitle.isNotEmpty ? cleanTitle : song.title)}&entity=song&limit=3',
      );
      final resp = await http.get(itunesUrl).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['results'] as List? ?? [];
        for (final item in list) {
          final prev = item['previewUrl'] as String?;
          if (prev != null && prev.isNotEmpty) {
            debugPrint('Resolved track "${song.title}" via iTunes fallback');
            return prev;
          }
        }
      }
    } catch (e) {
      debugPrint('iTunes resolve error: $e');
    }

    // 3. Tertiary fallback: YouTube MP4 stream extraction
    try {
      final ytStream = await YouTubeImporterService.resolvePlayableUrl(song);
      if (ytStream != null && ytStream.isNotEmpty) {
        return ytStream;
      }
    } catch (e) {
      debugPrint('YouTube stream extraction error: $e');
    }

    return null;
  }

}

