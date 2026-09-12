import 'package:flutter/foundation.dart';
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
      final regExp = RegExp(r'(?:v=|\/)([0-9A-Za-z_-]{11}).*');
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

  /// Resolve direct playable audio stream URL from a YouTube video ID
  static Future<String?> getAudioStreamUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioStream = manifest.audioOnly.withHighestBitrate();
      return audioStream.url.toString();
    } catch (e) {
      debugPrint('Error resolving YouTube audio stream: $e');
      return null;
    } finally {
      yt.close();
    }
  }

  /// Import either a video or a playlist from a YouTube URL
  static Future<YouTubeImportResult> importFromUrl(String url) async {
    final clean = url.trim();
    final type = detectUrlType(clean);

    if (type == YouTubeImportType.playlist) {
      final playlistId = extractPlaylistId(clean);
      if (playlistId == null) {
        return const YouTubeImportResult(type: YouTubeImportType.unknown, error: 'Invalid YouTube Playlist URL');
      }

      final yt = YoutubeExplode();
      try {
        final ytPlaylist = await yt.playlists.get(playlistId);
        final songs = <Song>[];

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
              duration: video.duration ?? const Duration(minutes: 3),
              artworkUrl: artwork,
              streamUrl: 'https://www.youtube.com/watch?v=${video.id.value}',
            ),
          );
        }

        final playlist = Playlist(
          id: 'yt_pl_${ytPlaylist.id.value}',
          title: ytPlaylist.title.isNotEmpty ? ytPlaylist.title : 'YouTube Playlist',
          description: ytPlaylist.description,
          songs: songs,
          createdAt: DateTime.now(),
          coverUrl: songs.isNotEmpty ? songs.first.artworkUrl : null,
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
          duration: video.duration ?? const Duration(minutes: 3),
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
}
