import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide Playlist;
import '../models/song.dart';
import '../models/playlist.dart';
import 'piped_service.dart';

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

  /// Smart YouTube metadata cleaner: extracts true song title, artist, and clean search query
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
        lowerAuthor.contains('series') ||
        lowerAuthor.contains('studio') ||
        lowerAuthor.contains('studios') ||
        lowerAuthor.contains('company') ||
        lowerAuthor.contains('label') ||
        lowerAuthor.contains('nation') ||
        lowerAuthor.contains('clouds') ||
        lowerAuthor.contains('chill') ||
        lowerAuthor.contains('sound') ||
        lowerAuthor.contains('entertainment') ||
        lowerAuthor.contains('media') ||
        rawAuthor == 'Unknown Artist';

    String finalArtist = extractedArtist;
    if (finalArtist.isEmpty && !isPublisher) {
      finalArtist = rawAuthor.trim();
    }

    extractedTitle = extractedTitle
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(?:official|video|audio|lyrics|hd|4k|full song|lyric video)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(?:feat\.|ft\.)\s+[A-Za-z0-9\s,&]+', caseSensitive: false), '')
        .trim();

    if (extractedTitle.isEmpty) extractedTitle = t;

    final searchQuery = finalArtist.isNotEmpty ? '$extractedTitle $finalArtist' : extractedTitle;
    return (
      cleanTitle: extractedTitle,
      cleanArtist: finalArtist,
      searchQuery: searchQuery,
    );
  }

  /// Returns all playable audio streams for a YouTube video ID in order of preference:
  /// 1. MP4 / AAC streams (optimal hardware decoding on Android)
  /// 2. WebM / Opus streams (audiophile audio quality)
  /// 3. Muxed MP4 stream fallback
  static Future<List<String>> getAudioStreamUrls(String videoId) async {
    final cleanId = videoId.replaceFirst('yt_', '').trim();
    if (cleanId.isEmpty) return [];

    final cached = _streamCache[cleanId];
    if (cached != null && DateTime.now().difference(cached.cachedAt).inHours < 4) {
      return [cached.url];
    }

    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(cleanId).timeout(const Duration(milliseconds: 9000));
      final candidates = <String>[];

      // 1. MP4 / AAC audio streams sorted by highest bitrate first
      final mp4Audio = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (mp4Audio.isNotEmpty) {
        mp4Audio.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        for (final s in mp4Audio) {
          candidates.add(s.url.toString());
        }
      }

      // 2. WebM / Opus audio streams sorted by highest bitrate first
      final webmAudio = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'webm').toList();
      if (webmAudio.isNotEmpty) {
        webmAudio.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        for (final s in webmAudio) {
          candidates.add(s.url.toString());
        }
      }

      // 3. Muxed MP4 fallback
      final muxedMp4 = manifest.muxed.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (muxedMp4.isNotEmpty) {
        candidates.add(muxedMp4.withHighestBitrate().url.toString());
      }

      if (candidates.isNotEmpty) {
        _streamCache[cleanId] = (url: candidates.first, cachedAt: DateTime.now());
        return candidates;
      }
    } catch (e) {
      debugPrint('[YouTube] youtube_explode_dart getAudioStreamUrls error for $cleanId: $e');
    } finally {
      yt.close();
    }

    // Fallback: Piped API proxy
    try {
      final pipedUrl = await PipedService.getAudioStream(cleanId);
      if (pipedUrl != null && pipedUrl.isNotEmpty) {
        _streamCache[cleanId] = (url: pipedUrl, cachedAt: DateTime.now());
        return [pipedUrl];
      }
    } catch (e) {
      debugPrint('[YouTube] Piped proxy fallback error for $cleanId: $e');
    }

    return [];
  }

  /// Resolve direct playable audio stream URL from a YouTube video ID.
  static Future<String?> getAudioStreamUrl(String videoId) async {
    final urls = await getAudioStreamUrls(videoId);
    return urls.isNotEmpty ? urls.first : null;
  }

  /// Non-blocking prefetch of streams for the first few tracks of a playlist
  static void prefetchPlaylistStreams(List<Song> songs) {
    for (final song in songs.take(3)) {
      final vid = extractVideoId(song.streamUrl) ?? (song.id.startsWith('yt_') ? song.id.replaceFirst('yt_', '') : null);
      if (vid != null && vid.isNotEmpty) {
        getAudioStreamUrl(vid).catchError((_) => null);
      }
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
            final meta = parseYouTubeMetadata(trackTitle, trackAuthor);
            final durText = renderer['lengthText']?['simpleText'] as String?;
            final thumbs = renderer['thumbnail']?['thumbnails'] as List?;
            final art = (thumbs != null && thumbs.isNotEmpty)
                ? thumbs.last['url'] as String? ?? 'https://i.ytimg.com/vi/$vId/hqdefault.jpg'
                : 'https://i.ytimg.com/vi/$vId/hqdefault.jpg';

            songs.add(
              Song(
                id: 'yt_$vId',
                title: meta.cleanTitle,
                artist: meta.cleanArtist.isNotEmpty ? meta.cleanArtist : trackAuthor,
                duration: parseDurationText(durText),
                artworkUrl: art,
                streamUrl: 'https://www.youtube.com/watch?v=$vId',
                source: 'youtube',
              ),
            );
          }
        }

        if (songs.isNotEmpty) {
          prefetchPlaylistStreams(songs);
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

            final meta = parseYouTubeMetadata(video.title, video.author);
            songs.add(
              Song(
                id: trackId,
                title: meta.cleanTitle,
                artist: meta.cleanArtist.isNotEmpty ? meta.cleanArtist : video.author,
                duration: video.duration ?? const Duration(minutes: 3, seconds: 30),
                artworkUrl: artwork,
                streamUrl: 'https://www.youtube.com/watch?v=${video.id.value}',
                source: 'youtube',
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

        prefetchPlaylistStreams(songs);
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
        final streamUrl = await getAudioStreamUrl(videoId) ?? '';
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
          source: 'youtube',
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

  /// Alias for searchYouTube
  static Future<List<Song>> searchInnerTube(String query, {int limit = 25}) =>
      searchYouTube(query, limit: limit);

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
                  source: 'youtube',
                ),
              );

              if (songs.length >= limit) break;
            }
          }
          if (songs.length >= limit) break;
        }

        if (songs.isNotEmpty) return songs;
      }
    } catch (e) {
      debugPrint('InnerTube search error: $e');
    }

    // Fallback 1: YoutubeExplode search
    try {
      final yt = YoutubeExplode();
      try {
        final searchList = await yt.search.search(query).timeout(const Duration(seconds: 6));
        final fallbackSongs = <Song>[];
        for (final video in searchList.take(limit)) {
          fallbackSongs.add(
            Song(
              id: 'yt_${video.id.value}',
              title: video.title,
              artist: video.author,
              duration: video.duration ?? const Duration(minutes: 3, seconds: 30),
              artworkUrl: video.thumbnails.highResUrl.isNotEmpty
                  ? video.thumbnails.highResUrl
                  : 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg',
              streamUrl: 'https://www.youtube.com/watch?v=${video.id.value}',
              source: 'youtube',
            ),
          );
        }
        if (fallbackSongs.isNotEmpty) {
          debugPrint('[YouTube Search] Fallback via YoutubeExplode found ${fallbackSongs.length} tracks');
          return fallbackSongs;
        }
      } finally {
        yt.close();
      }
    } catch (e) {
      debugPrint('[YouTube Search] YoutubeExplode fallback error: $e');
    }

    // Fallback 2: Piped API search
    try {
      final pipedItems = await PipedService.search(query);
      if (pipedItems.isNotEmpty) {
        final pipedSongs = pipedItems.take(limit).map((item) {
          final rawUrl = item['url'] as String? ?? '';
          final vid = rawUrl.replaceFirst('/watch?v=', '').trim();
          final durSecs = (item['duration'] as num?)?.toInt() ?? 210;
          return Song(
            id: 'yt_$vid',
            title: item['title'] as String? ?? 'YouTube Track',
            artist: item['uploaderName'] as String? ?? 'Artist',
            duration: Duration(seconds: durSecs),
            artworkUrl: item['thumbnail'] as String? ?? (vid.isNotEmpty ? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg' : ''),
            streamUrl: 'https://www.youtube.com/watch?v=$vid',
            source: 'youtube',
          );
        }).toList();
        if (pipedSongs.isNotEmpty) {
          debugPrint('[YouTube Search] Fallback via Piped found ${pipedSongs.length} tracks');
          return pipedSongs;
        }
      }
    } catch (e) {
      debugPrint('[YouTube Search] Piped search fallback error: $e');
    }

    return [];
  }
}
