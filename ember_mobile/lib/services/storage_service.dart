import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class StorageService {
  static const String _favsKey = 'ember_favorites_v1';
  static const String _histKey = 'ember_history_v1';
  static const String _speedKey = 'ember_playback_speed';

  final SharedPreferences? _prefs;
  final List<Song> _memFavorites = [];
  final List<Song> _memHistory = [];
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

  double loadPlaybackSpeed() {
    return _prefs?.getDouble(_speedKey) ?? _memSpeed;
  }

  Future<void> savePlaybackSpeed(double speed) async {
    _memSpeed = speed;
    await _prefs?.setDouble(_speedKey, speed);
  }
}
