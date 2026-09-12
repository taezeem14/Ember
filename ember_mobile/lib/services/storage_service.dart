import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';

class StorageService {
  static const String _favsKey = 'ember_favorites_v1';
  static const String _histKey = 'ember_history_v1';
  static const String _speedKey = 'ember_playback_speed';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  List<Song> loadFavorites() {
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
    final encoded = songs.map((s) => jsonEncode(s.toMap())).toList();
    await _prefs.setStringList(_favsKey, encoded);
  }

  List<Song> loadHistory() {
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
    final encoded = songs.take(50).map((s) => jsonEncode(s.toMap())).toList();
    await _prefs.setStringList(_histKey, encoded);
  }

  double loadPlaybackSpeed() {
    return _prefs.getDouble(_speedKey) ?? 1.0;
  }

  Future<void> savePlaybackSpeed(double speed) async {
    await _prefs.setDouble(_speedKey, speed);
  }
}
