import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';
import 'storage_service.dart';

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

  /// Download audio as MP3/M4A directly to device storage
  static Future<String?> downloadAudio(Song song, StorageService storageService) async {
    final songId = song.id;
    if (_activeDownloads[songId]?.isCompleted == false && _activeDownloads[songId]?.isFailed == false) {
      return null; // Already downloading
    }

    _activeDownloads[songId] = DownloadProgress(songId: songId, progress: 0.0);
    _progressController.add(_activeDownloads[songId]!);

    try {
      final dir = await _getMediaDirectory(isVideo: false);
      final safeTitle = _sanitizeFilename('${song.title} - ${song.artist}');
      final file = File('${dir.path}/$safeTitle.mp3');

      // Check if YouTube track
      if (song.streamUrl.contains('youtube') || song.streamUrl.contains('youtu.be') || song.id.startsWith('yt_')) {
        final yt = YoutubeExplode();
        try {
          final videoId = song.id.startsWith('yt_') ? song.id.substring(3) : song.id;
          final manifest = await yt.videos.streamsClient.getManifest(videoId);
          final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
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
        } finally {
          yt.close();
        }
      } else {
        // Direct CDN stream (e.g. JioSaavn 320kbps stream)
        final request = http.Request('GET', Uri.parse(song.streamUrl));
        final response = await http.Client().send(request);
        final total = response.contentLength ?? 0;
        var received = 0;

        final output = file.openWrite();
        await response.stream.listen((chunk) {
          output.add(chunk);
          received += chunk.length;
          final prog = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.5;
          _activeDownloads[songId] = DownloadProgress(songId: songId, progress: prog);
          _progressController.add(_activeDownloads[songId]!);
        }).asFuture();

        await output.flush();
        await output.close();
      }

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
      debugPrint('Download error: $e');
      _activeDownloads[songId] = DownloadProgress(
        songId: songId,
        progress: 0.0,
        isFailed: true,
        error: e.toString(),
      );
      _progressController.add(_activeDownloads[songId]!);
      return null;
    }
  }

  /// Download MP4 Video directly to device Gallery / Movies
  static Future<String?> downloadVideo(Song song) async {
    final videoIdKey = 'video_${song.id}';
    _activeDownloads[videoIdKey] = DownloadProgress(songId: videoIdKey, progress: 0.0, isVideo: true);
    _progressController.add(_activeDownloads[videoIdKey]!);

    final yt = YoutubeExplode();
    try {
      Video? targetVideo;

      if (song.id.startsWith('yt_')) {
        targetVideo = await yt.videos.get(song.id.substring(3));
      } else {
        // Search YouTube for official video match
        final searchResults = await yt.search.search('${song.title} ${song.artist} official video');
        if (searchResults.isNotEmpty) {
          targetVideo = searchResults.first;
        } else {
          final fallbackSearch = await yt.search.search('${song.title} ${song.artist}');
          if (fallbackSearch.isNotEmpty) {
            targetVideo = fallbackSearch.first;
          }
        }
      }

      if (targetVideo == null) {
        throw Exception('No video found for ${song.title}');
      }

      final manifest = await yt.videos.streamsClient.getManifest(targetVideo.id);
      // Get muxed stream (contains both high-def video AND audio in MP4 container)
      final muxedStreams = manifest.muxed.sortByVideoQuality();
      final streamInfo = muxedStreams.isNotEmpty ? muxedStreams.first : manifest.muxed.withHighestBitrate();

      final dir = await _getMediaDirectory(isVideo: true);
      final safeTitle = _sanitizeFilename('${targetVideo.title} - ${targetVideo.author}');
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
