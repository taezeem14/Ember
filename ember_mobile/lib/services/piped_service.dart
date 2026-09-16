import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Piped API service — YouTube audio proxy with multi-instance failover.
///
/// Used as a FALLBACK when youtube_explode_dart fails (e.g. cipher changes,
/// throttling, or InnerTube player rejections). Piped instances proxy audio
/// through their servers, bypassing IP-binding issues.
///
/// Instance priority: Try each instance in order, skip on timeout/error.
class PipedService {
  PipedService._();

  static const _instances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.in.projectsegfau.lt',
    'https://api.piped.privacydev.net',
    'https://pipedapi.leptons.xyz',
  ];

  /// Cache resolved streams for 3 hours (googlevideo URLs expire ~6h,
  /// but proxied URLs may have shorter TTLs).
  static final Map<String, _CachedStream> _cache = {};
  static const _cacheTtl = Duration(hours: 3);

  /// Resolve the best audio stream URL for a YouTube video ID.
  ///
  /// Returns a proxied audio URL that works on any network, or null if
  /// all instances fail.
  static Future<String?> getAudioStream(String videoId) async {
    // Check cache first
    final cached = _cache[videoId];
    if (cached != null && DateTime.now().difference(cached.timestamp) < _cacheTtl) {
      return cached.url;
    }

    for (final instance in _instances) {
      try {
        final url = Uri.parse('$instance/streams/$videoId');
        final resp = await http.get(url, headers: {
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 6));

        if (resp.statusCode != 200) continue;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final audioStreams = data['audioStreams'] as List? ?? [];
        final proxyUrl = data['proxyUrl'] as String?;

        if (audioStreams.isEmpty) continue;

        // Sort by bitrate descending, prefer M4A/AAC for Android hardware decoder compatibility
        final sorted = List<Map<String, dynamic>>.from(
          audioStreams.map((s) => s as Map<String, dynamic>),
        );
        sorted.sort((a, b) {
          final bitrateA = (a['bitrate'] as num?) ?? 0;
          final bitrateB = (b['bitrate'] as num?) ?? 0;
          // Prefer M4A/AAC over WebM/Opus
          final formatA = (a['format'] as String? ?? '').toUpperCase();
          final formatB = (b['format'] as String? ?? '').toUpperCase();
          final isM4aA = formatA.contains('M4A') || formatA.contains('MP4') ? 1 : 0;
          final isM4aB = formatB.contains('M4A') || formatB.contains('MP4') ? 1 : 0;
          if (isM4aA != isM4aB) return isM4aB - isM4aA;
          return bitrateB.compareTo(bitrateA);
        });

        final best = sorted.first;
        String streamUrl = best['url'] as String? ?? '';

        if (streamUrl.isEmpty) continue;

        // Rewrite direct googlevideo.com URL to go through the Piped proxy
        // This prevents 403 IP-binding errors on mobile networks
        if (proxyUrl != null && proxyUrl.isNotEmpty && streamUrl.contains('googlevideo.com')) {
          final parsed = Uri.parse(streamUrl);
          final proxyBase = Uri.parse(proxyUrl);
          streamUrl = Uri(
            scheme: proxyBase.scheme,
            host: proxyBase.host,
            port: proxyBase.port,
            path: parsed.path,
            query: parsed.query,
          ).toString();
        }

        // Cache the result
        _cache[videoId] = _CachedStream(url: streamUrl, timestamp: DateTime.now());
        debugPrint('[PipedService] Resolved audio for "$videoId" via $instance (${best['format']} ${best['quality']})');
        return streamUrl;
      } catch (e) {
        debugPrint('[PipedService] Instance $instance failed for "$videoId": $e');
        continue;
      }
    }

    debugPrint('[PipedService] All instances failed for "$videoId"');
    return null;
  }

  /// Search YouTube via Piped. Returns a list of video results.
  /// Each result has: id, title, uploaderName, duration, thumbnail.
  static Future<List<Map<String, dynamic>>> search(String query) async {
    for (final instance in _instances) {
      try {
        final url = Uri.parse('$instance/search?q=${Uri.encodeComponent(query)}&filter=music_songs');
        final resp = await http.get(url, headers: {
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 6));

        if (resp.statusCode != 200) continue;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final items = data['items'] as List? ?? [];
        return items
            .where((item) => (item['type'] as String? ?? '') == 'stream')
            .map((item) => item as Map<String, dynamic>)
            .take(10)
            .toList();
      } catch (e) {
        debugPrint('[PipedService] Search failed on $instance: $e');
        continue;
      }
    }
    return [];
  }

  /// Evict expired cache entries.
  static void cleanCache() {
    final now = DateTime.now();
    _cache.removeWhere((_, v) => now.difference(v.timestamp) >= _cacheTtl);
  }
}

class _CachedStream {
  final String url;
  final DateTime timestamp;
  const _CachedStream({required this.url, required this.timestamp});
}
