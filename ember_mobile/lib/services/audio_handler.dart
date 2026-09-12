import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';

Future<AudioHandler> initAudioHandler() async {
  try {
    return await AudioService.init(
      builder: () => EmberAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.taezeem.ember.channel.audio',
        androidNotificationChannelName: 'Ember Music Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    ).timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        debugPrint('AudioService.init timeout -> using fallback local EmberAudioHandler');
        return EmberAudioHandler();
      },
    );
  } catch (e, st) {
    debugPrint('AudioService.init error: $e\n$st -> using fallback local EmberAudioHandler');
    return EmberAudioHandler();
  }
}

class EmberAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudnessEnhancer = AndroidLoudnessEnhancer();
  late final AudioPlayer _player;

  Song? _currentSong;
  AsyncCallback? _onSkipNext;
  AsyncCallback? _onSkipPrevious;
  AsyncCallback? _onCompleted;

  EmberAudioHandler() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [
          _loudnessEnhancer,
          _equalizer,
        ],
      ),
    );
    _initAudioStreams();
  }

  AudioPlayer get player => _player;
  Song? get currentSong => _currentSong;
  AndroidEqualizer get equalizer => _equalizer;
  AndroidLoudnessEnhancer get loudnessEnhancer => _loudnessEnhancer;

  void setNavigationCallbacks({
    AsyncCallback? onSkipNext,
    AsyncCallback? onSkipPrevious,
    AsyncCallback? onCompleted,
  }) {
    _onSkipNext = onSkipNext;
    _onSkipPrevious = onSkipPrevious;
    _onCompleted = onCompleted;
  }

  void _initAudioStreams() {
    // Broadcast playback state changes
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 3],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: event.currentIndex,
        ),
      );
    });

    // Auto-advance when song finishes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onCompleted?.call();
      }
    });
  }

  Future<void> playSong(Song song) async {
    _currentSong = song;
    mediaItem.add(
      MediaItem(
        id: song.id,
        album: 'Ember',
        title: song.title,
        artist: song.artist,
        duration: song.duration,
        artUri: song.artworkUrl.isNotEmpty ? Uri.tryParse(song.artworkUrl) : null,
      ),
    );

    try {
      if (song.streamUrl.startsWith('/') || song.streamUrl.startsWith('file://')) {
        // Local offline file
        final localPath = song.streamUrl.replaceFirst('file://', '');
        final file = File(localPath);
        if (await file.exists()) {
          await _player.setFilePath(localPath);
        } else {
          await _player.setUrl(song.streamUrl);
        }
      } else {
        await _player.setUrl(song.streamUrl);
      }
      await _player.play();
    } catch (e) {
      debugPrint('Playback error: $e');
      try {
        await _player.play();
      } catch (_) {}
    }
  }

  // Equalizer & Audio Shaping Controls
  Future<void> setEqualizerEnabled(bool enabled) async {
    try {
      await _equalizer.setEnabled(enabled);
    } catch (_) {}
  }

  Future<void> setBassBoost(double gain) async {
    try {
      await _loudnessEnhancer.setTargetGain(gain.clamp(-1.0, 1.0));
      await _loudnessEnhancer.setEnabled(gain.abs() > 0.01);
    } catch (_) {}
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    try {
      final params = await _equalizer.parameters;
      if (bandIndex >= 0 && bandIndex < params.bands.length) {
        await params.bands[bandIndex].setGain(gain);
      }
    } catch (_) {}
  }

  Future<void> applyEqualizerPreset(String preset) async {
    try {
      final params = await _equalizer.parameters;
      final bands = params.bands;
      final n = bands.length;
      if (n == 0) return;

      switch (preset) {
        case 'Warm Tape':
          // Analog warmth: boosted bass and low mids, smooth rolled-off top end
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(3.0);
            } else if (i == 1) {
              await bands[i].setGain(2.0);
            } else if (i == n - 1) {
              await bands[i].setGain(-2.0);
            } else {
              await bands[i].setGain(0.0);
            }
          }
          await setBassBoost(0.4);
          break;
        case 'Lo-Fi':
          // Bandpass filter simulation: cut sub-bass, punchy mids, damped treble
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(-3.5);
            } else if (i == 1 || i == 2) {
              await bands[i].setGain(3.0);
            } else if (i >= n - 2) {
              await bands[i].setGain(-4.0);
            } else {
              await bands[i].setGain(1.0);
            }
          }
          await setBassBoost(0.2);
          break;
        case 'Bass Boost':
          // Heavy punch: sub and mid-bass elevated
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(6.0);
            } else if (i == 1) {
              await bands[i].setGain(4.0);
            } else {
              await bands[i].setGain(0.0);
            }
          }
          await setBassBoost(0.75);
          break;
        case 'Vocal Air':
          // Crisp vocals & acoustic shimmer: slight bass cut, high-mid and air boost
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(-1.5);
            } else if (i >= n - 2) {
              await bands[i].setGain(4.5);
            } else {
              await bands[i].setGain(1.5);
            }
          }
          await setBassBoost(0.0);
          break;
        case 'Acoustic':
          // Warm body with airy strings
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(2.5);
            } else if (i == n - 1) {
              await bands[i].setGain(3.0);
            } else {
              await bands[i].setGain(0.5);
            }
          }
          await setBassBoost(0.25);
          break;
        case 'Flat':
        default:
          for (int i = 0; i < n; i++) {
            await bands[i].setGain(0.0);
          }
          await setBassBoost(0.0);
          break;
      }
    } catch (e) {
      debugPrint('Apply preset error: $e');
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_onSkipNext != null) {
      await _onSkipNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_onSkipPrevious != null) {
      await _onSkipPrevious!();
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }
}
