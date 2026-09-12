import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dart_des/dart_des.dart';
import '../models/song.dart';

class MoodPreset {
  final String key;
  final String emoji;
  final String title;
  final String subtitle;
  final String searchQuery;
  final List<Song> tracks;

  const MoodPreset({
    required this.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.searchQuery,
    required this.tracks,
  });
}

class CatalogService {
  static const List<MoodPreset> cozyMoods = [
    MoodPreset(
      key: 'lofi',
      emoji: '☕',
      title: 'Lo-Fi Study Beats',
      subtitle: 'Warm analog warmth & tape flutter',
      searchQuery: 'lofi chill beats study relax',
      tracks: [
        Song(
          id: 'lofi_01',
          title: 'Coffee Steam',
          artist: 'Lofi Coffee Sessions',
          duration: Duration(minutes: 2, seconds: 45),
          artworkUrl: 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=600&q=80',
          streamUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/11/71/d6/1171d6ad-3c96-e027-2af6-58028426588c/mzaf_15137631797407745471.plus.aac.p.m4a',
          lyrics: 'Steam rising from the cup\nLate night clock ticking soft\nGentle keys playing on\nWarm amber glow in the dark.',
        ),
        Song(
          id: 'lofi_02',
          title: 'Midnight Paper Tape',
          artist: 'Ember Collective',
          duration: Duration(minutes: 3, seconds: 12),
          artworkUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=600&q=80',
          streamUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/2f/90/6e/2f906eee-4aa3-ddd3-121e-54dc6a71edfa/mzaf_2956542638534895059.plus.aac.p.m4a',
          lyrics: 'Scribbling thoughts in the margin\nCassette tape spins around\nNo hurry, no rush\nJust the warmth of the sound.',
        ),
      ],
    ),
    MoodPreset(
      key: 'rain',
      emoji: '🌧️',
      title: 'Rainy Day Windows',
      subtitle: 'Gentle raindrops & mellow chords',
      searchQuery: 'rainy day cozy acoustic jazz piano',
      tracks: [
        Song(
          id: 'rain_01',
          title: 'Waterdrops on Glass',
          artist: 'Petrichor Sessions',
          duration: Duration(minutes: 3, seconds: 34),
          artworkUrl: 'https://images.unsplash.com/photo-1515694346937-94d85e41e6f0?w=600&q=80',
          streamUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/ab/f9/cb/abf9cb62-16d9-e137-659a-61bb8e1bc85f/mzaf_16390625194422190597.plus.aac.p.m4a',
          lyrics: 'Droplets racing down the pane\nGray skies outside the frame\nInside the kettle boils\nSafe and quiet in the rain.',
        ),
      ],
    ),
    MoodPreset(
      key: 'jazz',
      emoji: '🎷',
      title: 'Late Night Espresso Jazz',
      subtitle: 'Upright acoustic bass & velvet piano',
      searchQuery: 'late night jazz bar muted trumpet noir',
      tracks: [
        Song(
          id: 'jazz_01',
          title: 'Smoke & Bourbon Keys',
          artist: 'The Amber Quartet',
          duration: Duration(minutes: 4, seconds: 20),
          artworkUrl: 'https://images.unsplash.com/photo-1511192336575-5a79af67a629?w=600&q=80',
          streamUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/11/71/d6/1171d6ad-3c96-e027-2af6-58028426588c/mzaf_15137631797407745471.plus.aac.p.m4a',
          lyrics: 'Walking bass line steady\nBrushes on the snare\nMidnight jazz club candle\nMusic in the air.',
        ),
      ],
    ),
    MoodPreset(
      key: 'fireplace',
      emoji: '🕯️',
      title: 'Cozy Hearthside',
      subtitle: 'Crackling embers & nylon acoustic strings',
      searchQuery: 'warm acoustic fingerstyle guitar cozy',
      tracks: [
        Song(
          id: 'fire_01',
          title: 'Embers Glowing Soft',
          artist: 'Cedar & Pine',
          duration: Duration(minutes: 3, seconds: 15),
          artworkUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=600&q=80',
          streamUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/2f/90/6e/2f906eee-4aa3-ddd3-121e-54dc6a71edfa/mzaf_2956542638534895059.plus.aac.p.m4a',
          lyrics: 'Wood pops in the fireplace\nShadows dance upon the wall\nWrapped in a wool blanket\nListening to the autumn fall.',
        ),
      ],
    ),
    MoodPreset(
      key: 'ambient',
      emoji: '🌌',
      title: 'Midnight Atmosphere',
      subtitle: 'Reverberant acoustic pads & gentle warmth',
      searchQuery: 'chillhop instrumental sleepy night beats',
      tracks: [
        Song(
          id: 'amb_01',
          title: 'Constellations Above',
          artist: 'Solaris Drift',
          duration: Duration(minutes: 5, seconds: 10),
          artworkUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=600&q=80',
          streamUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/ab/f9/cb/abf9cb62-16d9-e137-659a-61bb8e1bc85f/mzaf_16390625194422190597.plus.aac.p.m4a',
          lyrics: 'Stars across the night sky\nDrifting without a care\nCalm ocean of silence\nFloating through the air.',
        ),
      ],
    ),
    MoodPreset(
      key: 'autumn',
      emoji: '🍂',
      title: 'Autumn Amber Breeze',
      subtitle: 'Golden leaves & acoustic warmth',
      searchQuery: 'warm indie folk acoustic golden hour',
      tracks: [
        Song(
          id: 'aut_01',
          title: 'Golden Leaves Falling',
          artist: 'Harvest Moon',
          duration: Duration(minutes: 3, seconds: 48),
          artworkUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&q=80',
          streamUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview221/v4/11/71/d6/1171d6ad-3c96-e027-2af6-58028426588c/mzaf_15137631797407745471.plus.aac.p.m4a',
          lyrics: 'Crisp autumn wind\nRustling in the trees\nWarm cup in both hands\nGentle golden breeze.',
        ),
      ],
    ),
  ];

  static List<Song> getAllTracks() {
    final list = <Song>[];
    for (final mood in cozyMoods) {
      list.addAll(mood.tracks);
    }
    return list;
  }

  /// Synchronous local search for instant typing response and offline playback
  static List<Song> search(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return getAllTracks();
    return getAllTracks().where((song) {
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

    // 3. Offline fallback
    return search(query);
  }

  /// Live query to fetch fresh atmospheric tracks for any cozy mood
  static Future<List<Song>> fetchMoodTracks(String moodKey) async {
    final mood = cozyMoods.firstWhere((m) => m.key == moodKey, orElse: () => cozyMoods.first);
    final results = await searchOnline(mood.searchQuery, limit: 16);
    if (results.isNotEmpty) {
      return results;
    }
    return mood.tracks;
  }

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
}
