import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import 'storage_service.dart';
import 'youtube_importer_service.dart';

class DownloadProgress {
  final String songId;
  final double progress; // 0.0 to 1.0
  final bool isCompleted;
  final bool isFailed;
  final String? error;
  final String? localFilePath;
  final bool isVideo;

  const DownloadProgress({
    required this.songId,
    required this.progress,
    this.isCompleted = false,
    this.isFailed = false,
    this.error,
    this.localFilePath,
    this.isVideo = false,
  });
}

class DownloadService {
  static final Map<String, DownloadProgress> _activeDownloads = {};
  static final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  static Stream<DownloadProgress> get progressStream => _progressController.stream;
  static Map<String, DownloadProgress> get activeDownloads => _activeDownloads;

  static String _sanitizeFilename(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// Locate or create appropriate public/accessible media directory on Android
  static Future<Directory> _getMediaDirectory({bool isVideo = false}) async {
    // 1. Try public Android standard directory
    try {
      final baseDir = isVideo
          ? Directory('/storage/emulated/0/Movies/Ember')
          : Directory('/storage/emulated/0/Download/Ember');

      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      return baseDir;
    } catch (_) {}

    // 2. Fallback to app external storage
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final dir = Directory('${ext.path}/Ember');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir;
      }
    } catch (_) {}

    // 3. Fallback to standard app documents directory
    return await getApplicationDocumentsDirectory();
  }

  /// Resolve any song (Spotify or YouTube) to a valid YouTube Video ID
  static Future<String?> _resolveVideoId(YoutubeExplode yt, Song song) async {
    if (song.id.startsWith('yt_')) {
      return song.id.substring(3);
    }

    final fromUrl = YouTubeImporterService.extractVideoId(song.streamUrl);
    if (fromUrl != null && fromUrl.isNotEmpty) {
      return fromUrl;
    }

    try {
      final cleanTitle = song.title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '').trim();
      final query = '${cleanTitle.isNotEmpty ? cleanTitle : song.title} ${song.artist}'.trim();
      final searchResults = await yt.search.search(query).timeout(const Duration(seconds: 5));
      if (searchResults.isNotEmpty) {
        return searchResults.first.id.value;
      }
    } catch (e) {
      debugPrint('Error searching video ID for download: $e');
    }
    return null;
  }

  /// Download audio directly to device storage for offline playback
  static Future<String?> downloadAudio(Song song, StorageService storageService) async {
    final songId = song.id;
    if (_activeDownloads[songId]?.isCompleted == false && _activeDownloads[songId]?.isFailed == false) {
      return null; // Already downloading
    }

    _activeDownloads[songId] = DownloadProgress(songId: songId, progress: 0.0);
    _progressController.add(_activeDownloads[songId]!);

    // 1. Direct JioSaavn CDN audio download (320kbps full song)
    if (song.streamUrl.contains('saavncdn.com') ||
        (!song.streamUrl.contains('youtube.com') && !song.streamUrl.contains('youtu.be') && song.streamUrl.startsWith('http'))) {
      try {
        final dir = await _getMediaDirectory(isVideo: false);
        final safeTitle = _sanitizeFilename('${song.title} - ${song.artist}');
        final file = File('${dir.path}/$safeTitle.mp4');

        final client = http.Client();
        final req = http.Request('GET', Uri.parse(song.streamUrl));
        final response = await client.send(req);
        final total = response.contentLength ?? 0;
        var received = 0;
        final sink = file.openWrite();

        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
          _activeDownloads[songId] = DownloadProgress(songId: songId, progress: prog);
          _progressController.add(_activeDownloads[songId]!);
        }

        await sink.flush();
        await sink.close();
        client.close();

        final downloadedSong = song.copyWith(streamUrl: file.path);
        final currentDownloads = storageService.loadDownloads();
        currentDownloads.removeWhere((s) => s.id == song.id);
        currentDownloads.add(downloadedSong);
        await storageService.saveDownloads(currentDownloads);

        _activeDownloads[songId] = DownloadProgress(
          songId: songId,
          progress: 1.0,
          isCompleted: true,
          localFilePath: file.path,
        );
        _progressController.add(_activeDownloads[songId]!);
        return file.path;
      } catch (e) {
        debugPrint('Direct JioSaavn CDN audio download error: $e');
      }
    }

    final yt = YoutubeExplode();
    try {
      final videoId = await _resolveVideoId(yt, song);
      if (videoId == null || videoId.isEmpty) {
        throw Exception('Could not resolve audio stream for "${song.title}"');
      }

      final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 8));

      // Prefer MP4/M4A AAC container for universal Android hardware playback, fallback to any audio
      StreamInfo? audioStreamInfo;
      final mp4Audio = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      if (mp4Audio.isNotEmpty) {
        audioStreamInfo = mp4Audio.withHighestBitrate();
      } else if (manifest.audioOnly.isNotEmpty) {
        audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      } else if (manifest.audio.isNotEmpty) {
        audioStreamInfo = manifest.audio.withHighestBitrate();
      } else {
        throw Exception('No audio stream found for "${song.title}"');
      }

      final dir = await _getMediaDirectory(isVideo: false);
      final safeTitle = _sanitizeFilename('${song.title} - ${song.artist}');
      final ext = audioStreamInfo.container.name.toLowerCase() == 'mp4' ? 'm4a' : audioStreamInfo.container.name.toLowerCase();
      final file = File('${dir.path}/$safeTitle.$ext');

      final stream = yt.videos.streamsClient.get(audioStreamInfo);
      final output = file.openWrite();
      var received = 0;
      final total = audioStreamInfo.size.totalBytes;

      await for (final chunk in stream) {
        output.add(chunk);
        received += chunk.length;
        final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
        _activeDownloads[songId] = DownloadProgress(songId: songId, progress: prog);
        _progressController.add(_activeDownloads[songId]!);
      }
      await output.flush();
      await output.close();

      // Record in storage as downloaded
      final downloadedSong = song.copyWith(
        streamUrl: file.path, // Use local path for offline playback
      );
      final currentDownloads = storageService.loadDownloads();
      currentDownloads.removeWhere((s) => s.id == song.id);
      currentDownloads.add(downloadedSong);
      await storageService.saveDownloads(currentDownloads);

      _activeDownloads[songId] = DownloadProgress(
        songId: songId,
        progress: 1.0,
        isCompleted: true,
        localFilePath: file.path,
      );
      _progressController.add(_activeDownloads[songId]!);
      return file.path;
    } catch (e) {
      debugPrint('Audio download error: $e');
      _activeDownloads[songId] = DownloadProgress(
        songId: songId,
        progress: 0.0,
        isFailed: true,
        error: e.toString(),
      );
      _progressController.add(_activeDownloads[songId]!);
      return null;
    } finally {
      yt.close();
    }
  }

  /// Download MP4 Video directly to device Movies/Ember folder
  static Future<String?> downloadVideo(Song song) async {
    final videoIdKey = 'video_${song.id}';
    _activeDownloads[videoIdKey] = DownloadProgress(songId: videoIdKey, progress: 0.0, isVideo: true);
    _progressController.add(_activeDownloads[videoIdKey]!);

    final yt = YoutubeExplode();
    try {
      final videoId = await _resolveVideoId(yt, song);
      if (videoId == null || videoId.isEmpty) {
        throw Exception('No video found for "${song.title}"');
      }

      final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 8));

      // 1. Prioritize muxed stream (contains BOTH high-definition video and audio in MP4 container)
      StreamInfo? streamInfo;
      final muxedStreams = manifest.muxed.sortByVideoQuality();
      if (muxedStreams.isNotEmpty) {
        streamInfo = muxedStreams.first;
      } else if (manifest.videoOnly.isNotEmpty) {
        streamInfo = manifest.videoOnly.withHighestBitrate();
      } else if (manifest.streams.isNotEmpty) {
        streamInfo = manifest.streams.first;
      }

      if (streamInfo == null) {
        throw Exception('No playable video stream found for "${song.title}"');
      }

      final dir = await _getMediaDirectory(isVideo: true);
      final safeTitle = _sanitizeFilename('${song.title} - ${song.artist}');
      final file = File('${dir.path}/$safeTitle.mp4');

      final stream = yt.videos.streamsClient.get(streamInfo);
      final output = file.openWrite();
      var received = 0;
      final total = streamInfo.size.totalBytes;

      await for (final chunk in stream) {
        output.add(chunk);
        received += chunk.length;
        final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
        _activeDownloads[videoIdKey] = DownloadProgress(
          songId: videoIdKey,
          progress: prog,
          isVideo: true,
        );
        _progressController.add(_activeDownloads[videoIdKey]!);
      }

      await output.flush();
      await output.close();

      _activeDownloads[videoIdKey] = DownloadProgress(
        songId: videoIdKey,
        progress: 1.0,
        isCompleted: true,
        localFilePath: file.path,
        isVideo: true,
      );
      _progressController.add(_activeDownloads[videoIdKey]!);
      return file.path;
    } catch (e) {
      debugPrint('Video download error: $e');
      _activeDownloads[videoIdKey] = DownloadProgress(
        songId: videoIdKey,
        progress: 0.0,
        isFailed: true,
        error: e.toString(),
        isVideo: true,
      );
      _progressController.add(_activeDownloads[videoIdKey]!);
      return null;
    } finally {
      yt.close();
    }
  }
}
