import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/playlist.dart';

class StorageService {
  static const String _favsKey = 'ember_favorites_v1';
  static const String _histKey = 'ember_history_v1';
  static const String _speedKey = 'ember_playback_speed';
  static const String _playlistsKey = 'ember_playlists_v1';
  static const String _downloadsKey = 'ember_downloads_v1';
  static const String _eqPresetKey = 'ember_eq_preset';
  static const String _eqEnabledKey = 'ember_eq_enabled';
  static const String _eqBassBoostKey = 'ember_eq_bass_boost';
  static const String _eqBandGainsKey = 'ember_eq_band_gains';

  final SharedPreferences? _prefs;
  final List<Song> _memFavorites = [];
  final List<Song> _memHistory = [];
  final List<Playlist> _memPlaylists = [];
  final List<Song> _memDownloads = [];
  double _memSpeed = 1.0;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return StorageService(prefs);
    } catch (e) {
      return StorageService(null);
    }
  }

  List<Song> loadFavorites() {
    if (_prefs == null) return List.unmodifiable(_memFavorites);
    final raw = _prefs.getStringList(_favsKey) ?? [];
    return raw
        .map((s) {
          try {
            return Song.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();
  }

  Future<void> saveFavorites(List<Song> songs) async {
    _memFavorites.clear();
    _memFavorites.addAll(songs);
    if (_prefs != null) {
      final encoded = songs.map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_favsKey, encoded);
    }
  }

  List<Song> loadHistory() {
    if (_prefs == null) return List.unmodifiable(_memHistory);
    final raw = _prefs.getStringList(_histKey) ?? [];
    return raw
        .map((s) {
          try {
            return Song.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();
  }

  Future<void> saveHistory(List<Song> songs) async {
    _memHistory.clear();
    _memHistory.addAll(songs.take(50));
    if (_prefs != null) {
      final encoded = songs.take(50).map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_histKey, encoded);
    }
  }

  List<Playlist> loadPlaylists() {
    if (_prefs == null) return List.unmodifiable(_memPlaylists);
    final raw = _prefs.getStringList(_playlistsKey) ?? [];
    return raw
        .map((s) {
          try {
            return Playlist.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Playlist>()
        .toList();
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    _memPlaylists.clear();
    _memPlaylists.addAll(playlists);
    if (_prefs != null) {
      final encoded = playlists.map((p) => jsonEncode(p.toMap())).toList();
      await _prefs.setStringList(_playlistsKey, encoded);
    }
  }

  Future<void> savePlaylist(Playlist playlist) async {
    final idx = _memPlaylists.indexWhere((p) => p.id == playlist.id);
    if (idx != -1) {
      _memPlaylists[idx] = playlist;
    } else {
      _memPlaylists.insert(0, playlist);
    }
    await savePlaylists(_memPlaylists);
  }

  Future<void> deletePlaylist(String playlistId) async {
    _memPlaylists.removeWhere((p) => p.id == playlistId);
    await savePlaylists(_memPlaylists);
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    final idx = _memPlaylists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final existing = _memPlaylists[idx];
      if (!existing.songs.any((s) => s.id == song.id)) {
        final updatedSongs = List<Song>.from(existing.songs)..add(song);
        final updated = existing.copyWith(
          songs: updatedSongs,
          coverUrl: existing.coverUrl ?? song.artworkUrl,
        );
        _memPlaylists[idx] = updated;
        await savePlaylists(_memPlaylists);
      }
    }
  }

  List<Song> loadDownloads() {
    if (_prefs == null) return List.unmodifiable(_memDownloads);
    final raw = _prefs.getStringList(_downloadsKey) ?? [];
    return raw
        .map((s) {
          try {
            return Song.fromMap(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();
  }

  Future<void> saveDownloads(List<Song> songs) async {
    _memDownloads.clear();
    _memDownloads.addAll(songs);
    if (_prefs != null) {
      final encoded = songs.map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_downloadsKey, encoded);
    }
  }

  double loadPlaybackSpeed() {
    return _prefs?.getDouble(_speedKey) ?? _memSpeed;
  }

  Future<void> savePlaybackSpeed(double speed) async {
    _memSpeed = speed;
    await _prefs?.setDouble(_speedKey, speed);
  }

  String loadEqualizerPreset() {
    return _prefs?.getString(_eqPresetKey) ?? 'Warm Tape';
  }

  Future<void> saveEqualizerPreset(String preset) async {
    await _prefs?.setString(_eqPresetKey, preset);
  }

  bool loadEqualizerEnabled() {
    return _prefs?.getBool(_eqEnabledKey) ?? true;
  }

  Future<void> saveEqualizerEnabled(bool enabled) async {
    await _prefs?.setBool(_eqEnabledKey, enabled);
  }

  double loadBassBoost() {
    return _prefs?.getDouble(_eqBassBoostKey) ?? 0.35;
  }

  Future<void> saveBassBoost(double gain) async {
    await _prefs?.setDouble(_eqBassBoostKey, gain);
  }

  Map<int, double> loadBandGains() {
    final raw = _prefs?.getString(_eqBandGainsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveBandGains(Map<int, double> gains) async {
    final stringMap = gains.map((k, v) => MapEntry(k.toString(), v));
    await _prefs?.setString(_eqBandGainsKey, jsonEncode(stringMap));
  }
}
