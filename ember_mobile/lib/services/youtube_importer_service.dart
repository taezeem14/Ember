import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/song.dart';
import '../models/playlist.dart';

enum YouTubeImportType { video, playlist, unknown }

class YouTubeImportResult {
  final YouTubeImportType type;
  final Song? song;
  final Playlist? playlist;
  final String? error;

  const YouTubeImportResult({
    required this.type,
    this.song,
    this.playlist,
    this.error,
  });
}

class YouTubeImporterService {
  static YouTubeImportType detectUrlType(String url) {
    final clean = url.trim();
    if (clean.contains('list=') || clean.contains('/playlist')) {
      return YouTubeImportType.playlist;
    }
    if (clean.contains('watch?v=') || clean.contains('youtu.be/') || clean.contains('/shorts/')) {
      return YouTubeImportType.video;
    }
    return YouTubeImportType.unknown;
  }

  static String? extractVideoId(String url) {
    try {
      return VideoId.parseVideoId(url.trim());
    } catch (_) {
      final regExp = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11})');
      final match = regExp.firstMatch(url);
      return match?.group(1);
    }
  }

  static String? extractPlaylistId(String url) {
    try {
      return PlaylistId.parsePlaylistId(url.trim());
    } catch (_) {
      final regExp = RegExp(r'list=([0-9A-Za-z_-]+)');
      final match = regExp.firstMatch(url);
      return match?.group(1);
    }
  }

  static Duration parseDurationText(String? text) {
    if (text == null || text.trim().isEmpty) {
      return const Duration(minutes: 3, seconds: 30);
    }
    final parts = text.trim().split(':');
    try {
      if (parts.length == 3) {
        return Duration(
          hours: int.parse(parts[0]),
          minutes: int.parse(parts[1]),
          seconds: int.parse(parts[2]),
        );
      } else if (parts.length == 2) {
        return Duration(
          minutes: int.parse(parts[0]),
          seconds: int.parse(parts[1]),
        );
      }
    } catch (_) {}
    return const Duration(minutes: 3, seconds: 30);
  }

  static final Map<String, ({String url, DateTime cachedAt})> _streamCache = {};

  /// Resolve direct playable audio stream URL from a YouTube video ID
  static Future<String?> getAudioStreamUrl(String videoId) async {
    final cleanId = videoId.replaceFirst('yt_', '').trim();
    if (cleanId.isEmpty) return null;

    final cached = _streamCache[cleanId];
    if (cached != null && DateTime.now().difference(cached.cachedAt).inHours < 4) {
      return cached.url;
    }

    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(cleanId).timeout(const Duration(seconds: 9));

      // 1. Android hardware decoder preference: MP4 / AAC audio stream (compatible with all devices like Redmi Note 5 Pro)
      final mp4Audio = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (mp4Audio.isNotEmpty) {
        final audioStream = mp4Audio.withHighestBitrate();
        final url = audioStream.url.toString();
        _streamCache[cleanId] = (url: url, cachedAt: DateTime.now());
        return url;
      }

      // 2. Muxed MP4 (e.g. 360p video with AAC audio) fallback
      final muxedMp4 = manifest.muxed.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (muxedMp4.isNotEmpty) {
        final stream = muxedMp4.withHighestBitrate();
        final url = stream.url.toString();
        _streamCache[cleanId] = (url: url, cachedAt: DateTime.now());
        return url;
      }

      // 3. Fallback to any audio stream (e.g. WebM/Opus)
      if (manifest.audioOnly.isNotEmpty) {
        final audioStream = manifest.audioOnly.withHighestBitrate();
        final url = audioStream.url.toString();
        _streamCache[cleanId] = (url: url, cachedAt: DateTime.now());
        return url;
      }
      return null;
    } catch (e) {
      debugPrint('Error resolving YouTube audio stream for $cleanId: $e');
      return null;
    } finally {
      yt.close();
    }
  }

  /// Resolve any song's stream URL into a directly playable media stream
  static Future<String?> resolvePlayableUrl(Song song) async {
    final s = song.streamUrl;
    if (s.contains('youtube.com/watch') || s.contains('youtu.be/') || song.id.startsWith('yt_')) {
      final vid = extractVideoId(s) ?? (song.id.startsWith('yt_') ? song.id.replaceFirst('yt_', '') : null);
      if (vid != null && vid.isNotEmpty) {
        final stream = await getAudioStreamUrl(vid);
        if (stream != null && stream.isNotEmpty) {
          return stream;
        }
      }
      return null; // Return null so audio player never tries to play an HTML webpage
    }
    return s;
  }


  /// NewPipe-style extraction for YouTube Mixes (list=RD..., list=RDMM, radio mixes)
  static Future<Playlist?> _importYouTubeMix(String? videoId, String playlistId) async {
    try {
      final body = jsonEncode({
        "context": {
          "client": {
            "clientName": "WEB",
            "clientVersion": "2.20240101.00.00",
            "hl": "en",
            "gl": "US"
          }
        },
        if (videoId != null && videoId.isNotEmpty) "videoId": videoId,
        "playlistId": playlistId
      });

      final resp = await http.post(
        Uri.parse('https://www.youtube.com/youtubei/v1/next?prettyPrint=false'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: body,
      ).timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final plData = json['contents']?['twoColumnWatchNextResults']?['playlist']?['playlist'];
        if (plData == null) return null;

        final title = plData['title'] as String? ?? 'YouTube Mix';
        final author = plData['ownerName']?['simpleText'] as String? ?? 'YouTube Mix';
        final contents = plData['contents'] as List? ?? [];
        final songs = <Song>[];

        for (final item in contents.take(50)) {
          final renderer = item['playlistPanelVideoRenderer'];
          if (renderer != null) {
            final vId = renderer['videoId'] as String?;
            if (vId == null || vId.isEmpty) continue;

            final trackTitle = renderer['title']?['simpleText'] as String? ??
                renderer['title']?['runs']?[0]?['text'] as String? ??
                'YouTube Track';
            final trackAuthor = renderer['shortBylineText']?['runs']?[0]?['text'] as String? ?? author;
            final durText = renderer['lengthText']?['simpleText'] as String?;
            final thumbs = renderer['thumbnail']?['thumbnails'] as List?;
            final art = (thumbs != null && thumbs.isNotEmpty)
                ? thumbs.last['url'] as String? ?? 'https://i.ytimg.com/vi/$vId/hqdefault.jpg'
                : 'https://i.ytimg.com/vi/$vId/hqdefault.jpg';

            songs.add(
              Song(
                id: 'yt_$vId',
                title: trackTitle,
                artist: trackAuthor,
                duration: parseDurationText(durText),
                artworkUrl: art,
                streamUrl: 'https://www.youtube.com/watch?v=$vId',
              ),
            );
          }
        }

        if (songs.isNotEmpty) {
          return Playlist(
            id: 'yt_mix_$playlistId',
            title: title,
            description: 'YouTube Mix • ${songs.length} tracks',
            songs: songs,
            createdAt: DateTime.now(),
            coverUrl: songs.first.artworkUrl,
          );
        }
      }
    } catch (e) {
      debugPrint('Error importing YouTube Mix via next endpoint: $e');
    }
    return null;
  }

  /// Import either a video, standard playlist, or Mix from any YouTube / YouTube Music URL
  static Future<YouTubeImportResult> importFromUrl(String url) async {
    final clean = url.trim();
    final type = detectUrlType(clean);

    if (type == YouTubeImportType.playlist) {
      final playlistId = extractPlaylistId(clean);
      final videoId = extractVideoId(clean);

      if (playlistId == null) {
        return const YouTubeImportResult(type: YouTubeImportType.unknown, error: 'Invalid YouTube Playlist URL');
      }

      // 1. If this is a YouTube Mix (RD..., RDMM, RDEM, RDCLAK...) or contains a video context, try Mix parser first
      if (playlistId.startsWith('RD') || playlistId.startsWith('UL') || clean.contains('list=RD')) {
        final mixPlaylist = await _importYouTubeMix(videoId, playlistId);
        if (mixPlaylist != null && mixPlaylist.songs.isNotEmpty) {
          return YouTubeImportResult(type: YouTubeImportType.playlist, playlist: mixPlaylist);
        }
      }

      // 2. Standard user or channel playlist via youtube_explode_dart
      final yt = YoutubeExplode();
      try {
        String title = 'YouTube Playlist';
        String description = 'Imported YouTube Playlist';
        String? coverUrl;

        try {
          final ytPlaylist = await yt.playlists.get(playlistId);
          if (ytPlaylist.title.isNotEmpty) title = ytPlaylist.title;
          description = ytPlaylist.description;
        } catch (_) {}

        final songs = <Song>[];
        try {
          await for (final video in yt.playlists.getVideos(playlistId).take(50)) {
            final trackId = 'yt_${video.id.value}';
            final artwork = video.thumbnails.highResUrl.isNotEmpty
                ? video.thumbnails.highResUrl
                : video.thumbnails.standardResUrl;

            songs.add(
              Song(
                id: trackId,
                title: video.title,
                artist: video.author,
                duration: video.duration ?? const Duration(minutes: 3, seconds: 30),
                artworkUrl: artwork,
                streamUrl: 'https://www.youtube.com/watch?v=${video.id.value}',
              ),
            );
          }
        } catch (e) {
          debugPrint('getVideos fallback triggered: $e');
        }

        // 3. If youtube_explode yielded no videos, fallback to YouTube next API
        if (songs.isEmpty) {
          final fallbackMix = await _importYouTubeMix(videoId, playlistId);
          if (fallbackMix != null && fallbackMix.songs.isNotEmpty) {
            return YouTubeImportResult(type: YouTubeImportType.playlist, playlist: fallbackMix);
          }
          return const YouTubeImportResult(type: YouTubeImportType.playlist, error: 'No playable tracks found in playlist');
        }

        coverUrl = songs.isNotEmpty ? songs.first.artworkUrl : null;
        final playlist = Playlist(
          id: 'yt_pl_$playlistId',
          title: title,
          description: description,
          songs: songs,
          createdAt: DateTime.now(),
          coverUrl: coverUrl,
        );

        return YouTubeImportResult(type: YouTubeImportType.playlist, playlist: playlist);
      } catch (e) {
        return YouTubeImportResult(type: YouTubeImportType.playlist, error: e.toString());
      } finally {
        yt.close();
      }
    } else if (type == YouTubeImportType.video) {
      final videoId = extractVideoId(clean);
      if (videoId == null) {
        return const YouTubeImportResult(type: YouTubeImportType.unknown, error: 'Invalid YouTube Video URL');
      }

      final yt = YoutubeExplode();
      try {
        final video = await yt.videos.get(videoId);
        final streamUrl = await getAudioStreamUrl(videoId) ?? 'https://www.youtube.com/watch?v=$videoId';
        final artwork = video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.standardResUrl;

        final song = Song(
          id: 'yt_${video.id.value}',
          title: video.title,
          artist: video.author,
          duration: video.duration ?? const Duration(minutes: 3, seconds: 30),
          artworkUrl: artwork,
          streamUrl: streamUrl,
        );

        return YouTubeImportResult(type: YouTubeImportType.video, song: song);
      } catch (e) {
        return YouTubeImportResult(type: YouTubeImportType.video, error: e.toString());
      } finally {
        yt.close();
      }
    }

    return const YouTubeImportResult(type: YouTubeImportType.unknown, error: 'Unrecognized YouTube URL');
  }

  /// NewPipe-style InnerTube music search returning full-length tracks with high-resolution thumbnails
  static Future<List<Song>> searchYouTube(String query, {int limit = 25}) async {
    try {
      final body = jsonEncode({
        "context": {
          "client": {
            "clientName": "WEB",
            "clientVersion": "2.20240101.00.00",
            "hl": "en",
            "gl": "US",
          }
        },
        "query": query,
      });

      final resp = await http.post(
        Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: body,
      ).timeout(const Duration(seconds: 7));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final sections = json['contents']?['twoColumnSearchResultsRenderer']?['primaryContents']?['sectionListRenderer']?['contents'] as List? ?? [];
        final songs = <Song>[];

        for (final sec in sections) {
          final items = sec['itemSectionRenderer']?['contents'] as List? ?? [];
          for (final item in items) {
            final v = item['videoRenderer'];
            if (v != null) {
              final vId = v['videoId'] as String?;
              if (vId == null || vId.isEmpty) continue;

              final title = v['title']?['runs']?[0]?['text'] as String? ??
                  v['title']?['simpleText'] as String? ??
                  'YouTube Song';
              final author = v['ownerText']?['runs']?[0]?['text'] as String? ??
                  v['shortBylineText']?['runs']?[0]?['text'] as String? ??
                  'YouTube';
              final durText = v['lengthText']?['simpleText'] as String?;

              songs.add(
                Song(
                  id: 'yt_$vId',
                  title: title,
                  artist: author,
                  duration: parseDurationText(durText),
                  artworkUrl: 'https://i.ytimg.com/vi/$vId/hqdefault.jpg',
                  streamUrl: 'https://www.youtube.com/watch?v=$vId',
                ),
              );

              if (songs.length >= limit) break;
            }
          }
          if (songs.length >= limit) break;
        }

        return songs;
      }
    } catch (e) {
      debugPrint('InnerTube search error: $e');
    }
    return [];
  }
}
