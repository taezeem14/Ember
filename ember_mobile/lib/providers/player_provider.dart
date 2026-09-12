import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../services/catalog_service.dart';
import '../services/storage_service.dart';

class PlayerProvider extends ChangeNotifier {
  final EmberAudioHandler _audioHandler;
  final StorageService _storageService;

  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _isShuffle = false;
  String _repeatMode = 'off'; // 'off', 'all', 'one'
  String _activeTab = 'queue'; // 'queue', 'favorites', 'history', 'lyrics'
  String? _activeMood;
  String _searchQuery = '';
  List<Song> _searchResults = [];
  List<Song> _favorites = [];
  List<Song> _history = [];

  Timer? _sleepTimer;
  int _sleepSecondsRemaining = 0;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  PlayerProvider(this._audioHandler, this._storageService) {
    _init();
  }

  // Getters
  List<Song> get queue => _queue;
  int get currentIndex => _currentIndex;
  Song? get currentSong => _queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length ? _queue[_currentIndex] : null;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;
  bool get isShuffle => _isShuffle;
  String get repeatMode => _repeatMode;
  String get activeTab => _activeTab;
  String? get activeMood => _activeMood;
  String get searchQuery => _searchQuery;
  List<Song> get searchResults => _searchResults;
  List<Song> get favorites => _favorites;
  List<Song> get history => _history;
  int get sleepSecondsRemaining => _sleepSecondsRemaining;

  void _init() {
    _favorites = _storageService.loadFavorites();
    _history = _storageService.loadHistory();
    _speed = _storageService.loadPlaybackSpeed();

    // Seed default queue with warm Lo-Fi tracks
    _queue = List.from(CatalogService.cozyMoods.first.tracks);
    _searchResults = CatalogService.getAllTracks();

    // Listen to player streams
    _posSub = _audioHandler.player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    _durSub = _audioHandler.player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _stateSub = _audioHandler.player.playerStateStream.listen((state) {
      final playing = state.playing;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }
    });
  }

  Future<void> playSong(Song song, {List<Song>? contextQueue}) async {
    if (contextQueue != null) {
      _queue = List.from(contextQueue);
      _currentIndex = _queue.indexWhere((s) => s.id == song.id);
      if (_currentIndex == -1) {
        _queue.insert(0, song);
        _currentIndex = 0;
      }
    } else {
      final existing = _queue.indexWhere((s) => s.id == song.id);
      if (existing != -1) {
        _currentIndex = existing;
      } else {
        _queue.add(song);
        _currentIndex = _queue.length - 1;
      }
    }

    _recordHistory(song);
    _duration = song.duration;
    notifyListeners();
    await _audioHandler.playSong(song);
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      await _audioHandler.pause();
    } else {
      if (currentSong != null) {
        await _audioHandler.play();
      } else if (_queue.isNotEmpty) {
        await playSong(_queue[0]);
      }
    }
  }

  Future<void> skipNext() async {
    if (_queue.isEmpty) return;
    if (_repeatMode == 'one') {
      await _audioHandler.seek(Duration.zero);
      await _audioHandler.play();
      return;
    }

    int nextIdx = _currentIndex + 1;
    if (nextIdx >= _queue.length) {
      if (_repeatMode == 'all') {
        nextIdx = 0;
      } else {
        return; // End of queue
      }
    }
    _currentIndex = nextIdx;
    await playSong(_queue[_currentIndex]);
  }

  Future<void> skipPrevious() async {
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
      await playSong(_queue[_currentIndex]);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
    await _audioHandler.seek(position);
  }

  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _storageService.savePlaybackSpeed(speed);
    await _audioHandler.setSpeed(speed);
    notifyListeners();
  }

  void cycleRepeatMode() {
    if (_repeatMode == 'off') {
      _repeatMode = 'all';
    } else if (_repeatMode == 'all') {
      _repeatMode = 'one';
    } else {
      _repeatMode = 'off';
    }
    notifyListeners();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle && _queue.length > 1) {
      final cur = currentSong;
      _queue.shuffle();
      if (cur != null) {
        _queue.remove(cur);
        _queue.insert(0, cur);
        _currentIndex = 0;
      }
    }
    notifyListeners();
  }

  void setTab(String tab) {
    _activeTab = tab;
    notifyListeners();
  }

  void selectMood(String moodKey) {
    _activeMood = moodKey;
    final found = CatalogService.cozyMoods.firstWhere(
      (m) => m.key == moodKey,
      orElse: () => CatalogService.cozyMoods.first,
    );
    _queue = List.from(found.tracks);
    _currentIndex = 0;
    notifyListeners();
    if (_queue.isNotEmpty) {
      playSong(_queue[0]);
    }
  }

  void search(String query) {
    _searchQuery = query;
    _searchResults = CatalogService.search(query);
    notifyListeners();
  }

  Future<void> toggleFavorite(Song song) async {
    final idx = _favorites.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      _favorites.removeAt(idx);
    } else {
      _favorites.add(song.copyWith(isFavorite: true));
    }
    await _storageService.saveFavorites(_favorites);
    notifyListeners();
  }

  bool isFavorite(String songId) {
    return _favorites.any((s) => s.id == songId);
  }

  void _recordHistory(Song song) {
    _history.removeWhere((s) => s.id == song.id);
    _history.insert(0, song);
    _storageService.saveHistory(_history);
  }

  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _sleepSecondsRemaining = minutes * 60;
    notifyListeners();

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepSecondsRemaining > 0) {
        _sleepSecondsRemaining--;
        notifyListeners();
      } else {
        cancelSleepTimer();
        _audioHandler.pause();
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepSecondsRemaining = 0;
    notifyListeners();
  }

  void removeTrackAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) {
      skipNext();
    }
    _queue.removeAt(index);
    if (_currentIndex > index) {
      _currentIndex--;
    }
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _sleepTimer?.cancel();
    super.dispose();
  }
}
