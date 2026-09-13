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
      final service = StorageService(prefs);
      await service.purgeAllPlaceholders();
      return service;
    } catch (e) {
      return StorageService(null);
    }
  }

  /// Purges all legacy mock / placeholder songs from all storage keys permanently
  Future<void> purgeAllPlaceholders() async {
    final favs = loadFavorites();
    await saveFavorites(favs);

    final hist = loadHistory();
    await saveHistory(hist);

    final pl = loadPlaylists();
    await savePlaylists(pl);

    final dl = loadDownloads();
    await saveDownloads(dl);
  }

  List<Song> loadFavorites() {
    if (_prefs == null) {
      return List.unmodifiable(_memFavorites.where((s) => !Song.isPlaceholder(s)));
    }
    final raw = _prefs.getStringList(_favsKey) ?? [];
    final cleaned = raw
        .map((s) {
          try {
            final song = Song.fromMap(jsonDecode(s) as Map<String, dynamic>);
            return Song.isPlaceholder(song) ? null : song;
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();

    _memFavorites.clear();
    _memFavorites.addAll(cleaned);

    if (raw.length != cleaned.length) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      _prefs.setStringList(_favsKey, encoded);
    }

    return cleaned;
  }

  Future<void> saveFavorites(List<Song> songs) async {
    final cleaned = songs.where((s) => !Song.isPlaceholder(s)).toList();
    _memFavorites.clear();
    _memFavorites.addAll(cleaned);
    if (_prefs != null) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_favsKey, encoded);
    }
  }

  List<Song> loadHistory() {
    if (_prefs == null) {
      return List.unmodifiable(_memHistory.where((s) => !Song.isPlaceholder(s)));
    }
    final raw = _prefs.getStringList(_histKey) ?? [];
    final cleaned = raw
        .map((s) {
          try {
            final song = Song.fromMap(jsonDecode(s) as Map<String, dynamic>);
            return Song.isPlaceholder(song) ? null : song;
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();

    _memHistory.clear();
    _memHistory.addAll(cleaned);

    if (raw.length != cleaned.length) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      _prefs.setStringList(_histKey, encoded);
    }

    return cleaned;
  }

  Future<void> saveHistory(List<Song> songs) async {
    final cleaned = songs.where((s) => !Song.isPlaceholder(s)).take(50).toList();
    _memHistory.clear();
    _memHistory.addAll(cleaned);
    if (_prefs != null) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
      await _prefs.setStringList(_histKey, encoded);
    }
  }

  List<Playlist> loadPlaylists() {
    if (_prefs == null) {
      return List.unmodifiable(_memPlaylists);
    }
    final raw = _prefs.getStringList(_playlistsKey) ?? [];
    final list = <Playlist>[];
    for (final s in raw) {
      try {
        final pl = Playlist.fromMap(jsonDecode(s) as Map<String, dynamic>);
        final sanitizedSongs = pl.songs.where((song) => !Song.isPlaceholder(song)).toList();
        list.add(pl.copyWith(songs: sanitizedSongs));
      } catch (_) {}
    }

    _memPlaylists.clear();
    _memPlaylists.addAll(list);

    return list;
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
    final list = List<Playlist>.from(loadPlaylists());
    final idx = list.indexWhere((p) => p.id == playlist.id);
    if (idx != -1) {
      list[idx] = playlist;
    } else {
      list.insert(0, playlist);
    }
    await savePlaylists(list);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final list = List<Playlist>.from(loadPlaylists());
    list.removeWhere((p) => p.id == playlistId);
    await savePlaylists(list);
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    if (Song.isPlaceholder(song)) return;
    final list = List<Playlist>.from(loadPlaylists());
    final idx = list.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final existing = list[idx];
      if (!existing.songs.any((s) => s.id == song.id)) {
        final updatedSongs = List<Song>.from(existing.songs)..add(song);
        final updated = existing.copyWith(
          songs: updatedSongs,
          coverUrl: existing.coverUrl ?? (song.artworkUrl.isNotEmpty ? song.artworkUrl : null),
        );
        list[idx] = updated;
        await savePlaylists(list);
      }
    }
  }

  List<Song> loadDownloads() {
    if (_prefs == null) {
      return List.unmodifiable(_memDownloads.where((s) => !Song.isPlaceholder(s)));
    }
    final raw = _prefs.getStringList(_downloadsKey) ?? [];
    final cleaned = raw
        .map((s) {
          try {
            final song = Song.fromMap(jsonDecode(s) as Map<String, dynamic>);
            return Song.isPlaceholder(song) ? null : song;
          } catch (_) {
            return null;
          }
        })
        .whereType<Song>()
        .toList();

    _memDownloads.clear();
    _memDownloads.addAll(cleaned);

    return cleaned;
  }

  Future<void> saveDownloads(List<Song> songs) async {
    final cleaned = songs.where((s) => !Song.isPlaceholder(s)).toList();
    _memDownloads.clear();
    _memDownloads.addAll(cleaned);
    if (_prefs != null) {
      final encoded = cleaned.map((s) => jsonEncode(s.toMap())).toList();
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
