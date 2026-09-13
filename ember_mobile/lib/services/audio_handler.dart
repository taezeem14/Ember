import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';
import 'catalog_service.dart';


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

  bool _eqEnabled = true;
  double _bassBoost = 0.35;
  String _currentPreset = 'Warm Tape';

  EmberAudioHandler() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [
          _equalizer,
          _loudnessEnhancer,
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
      String? streamUrl = song.streamUrl;
      if (streamUrl.contains('youtube.com') ||
          streamUrl.contains('youtu.be') ||
          song.id.startsWith('yt_')) {
        streamUrl = await CatalogService.resolvePlayableStream(song);
      }

      if (streamUrl == null ||
          streamUrl.isEmpty ||
          streamUrl.contains('youtube.com/watch') ||
          streamUrl.contains('youtu.be/')) {
        debugPrint('Cannot play track "${song.title}": audio stream could not be resolved');
        return;
      }

      if (streamUrl.startsWith('/') || streamUrl.startsWith('file://')) {
        // Local offline file
        final localPath = streamUrl.replaceFirst('file://', '');
        final file = File(localPath);
        if (await file.exists()) {
          await _player.setFilePath(localPath);
        } else {
          await _player.setUrl(streamUrl);
        }
      } else {
        await _player.setUrl(streamUrl);
      }
      await _player.play();
      // Re-apply audio effects & preset on newly initialized AudioTrack
      await _updateAudioEffects();
      if (_eqEnabled) {
        await applyEqualizerPreset(_currentPreset);
      }
    } catch (e) {
      debugPrint('Playback error: $e');
    }
  }

  // Equalizer & Audio Shaping Controls with Dynamic Hardware Makeup Gain
  Future<void> _updateAudioEffects() async {
    try {
      await _equalizer.setEnabled(_eqEnabled);
      if (_eqEnabled) {
        // Android's native Equalizer HAL applies 6-12 dB of internal digital attenuation to avoid clipping.
        // To prevent the sound from being suppressed when EQ is enabled, we engage Android's hardware LoudnessEnhancer
        // as an intelligent makeup gain stage (+5.0 dB to +8.5 dB), giving full punch, volume parity, and analog warmth.
        final makeupGain = (0.50 + (_bassBoost * 0.35)).clamp(0.2, 1.0);
        await _loudnessEnhancer.setTargetGain(makeupGain);
        await _loudnessEnhancer.setEnabled(true);
      } else {
        // When EQ is disabled, restore transparent flat output so volume transitions smoothly
        if (_bassBoost > 0.05) {
          await _loudnessEnhancer.setTargetGain((_bassBoost * 0.35).clamp(0.0, 1.0));
          await _loudnessEnhancer.setEnabled(true);
        } else {
          await _loudnessEnhancer.setEnabled(false);
        }
      }
    } catch (e) {
      debugPrint('Error updating audio effects: $e');
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    _eqEnabled = enabled;
    await _updateAudioEffects();
    if (_eqEnabled) {
      await applyEqualizerPreset(_currentPreset);
    }
  }

  Future<void> setBassBoost(double gain) async {
    _bassBoost = gain;
    await _updateAudioEffects();
  }

  Future<void> setBandGain(int bandIndex, double gain) async {
    try {
      final params = await _equalizer.parameters;
      if (bandIndex >= 0 && bandIndex < params.bands.length) {
        final clamped = gain.clamp(params.minDecibels, params.maxDecibels);
        await params.bands[bandIndex].setGain(clamped);
      }
    } catch (_) {}
  }

  Future<void> applyEqualizerPreset(String preset) async {
    _currentPreset = preset;
    try {
      final params = await _equalizer.parameters;
      final bands = params.bands;
      final n = bands.length;
      if (n == 0) return;

      final minDb = params.minDecibels;
      final maxDb = params.maxDecibels;
      double clampGain(double g) => g.clamp(minDb, maxDb);

      switch (preset) {
        case 'Warm Tape':
          // Analog warmth: boosted bass and low mids, gentle top end, no volume-killing cuts
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(2.5));
            } else if (i == 1) {
              await bands[i].setGain(clampGain(1.5));
            } else if (i == n - 1) {
              await bands[i].setGain(clampGain(0.5));
            } else {
              await bands[i].setGain(clampGain(0.5));
            }
          }
          break;
        case 'Lo-Fi':
          // Warm analog mids and soft roll-off without hollowing out the track
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(0.5));
            } else if (i == 1 || i == 2) {
              await bands[i].setGain(clampGain(2.5));
            } else if (i >= n - 2) {
              await bands[i].setGain(clampGain(0.5));
            } else {
              await bands[i].setGain(clampGain(1.0));
            }
          }
          break;
        case 'Bass Boost':
          // Deep, punchy sub and mid bass with crystal clarity
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(4.5));
            } else if (i == 1) {
              await bands[i].setGain(clampGain(3.0));
            } else {
              await bands[i].setGain(clampGain(0.5));
            }
          }
          break;
        case 'Vocal Air':
          // Sparkling vocals, crisp presence, airy treble with solid low-end foundation
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(0.5));
            } else if (i >= n - 2) {
              await bands[i].setGain(clampGain(3.0));
            } else {
              await bands[i].setGain(clampGain(1.5));
            }
          }
          break;
        case 'Acoustic':
          // Warm resonance and articulate strings
          for (int i = 0; i < n; i++) {
            if (i == 0) {
              await bands[i].setGain(clampGain(2.0));
            } else if (i == n - 1) {
              await bands[i].setGain(clampGain(2.5));
            } else {
              await bands[i].setGain(clampGain(1.0));
            }
          }
          break;
        case 'Flat':
        default:
          for (int i = 0; i < n; i++) {
            await bands[i].setGain(clampGain(0.0));
          }
          break;
      }
      await _updateAudioEffects();
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
    _currentSong = null;
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await _player.stop();
    await super.stop();
  }

}
