import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../services/audio_handler.dart';
import '../services/catalog_service.dart';
import '../services/download_service.dart';
import '../services/lyrics_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_importer_service.dart';

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
  List<Song> _unshuffledQueue = [];
  String _repeatMode = 'off'; // 'off', 'all', 'one'
  String _activeTab = 'queue'; // 'queue', 'playlists', 'favorites', 'downloads', 'history'
  String _activeCategory = 'trending';
  String _searchQuery = '';
  List<Song> _searchResults = [];
  List<Song> _favorites = [];
  List<Song> _history = [];
  List<Playlist> _playlists = [];
  List<Song> _downloads = [];
  List<Song> _recommendations = [];
  List<Song> _categoryTracks = [];
  bool _isAutoplayEnabled = true;

  // Equalizer state
  String _eqPreset = 'Warm Tape';
  bool _eqEnabled = true;
  double _bassBoost = 0.35;
  Map<int, double> _bandGains = {};

  LyricsResult _lyrics = LyricsResult.empty;
  bool _isLoadingLyrics = false;

  Timer? _sleepTimer;
  int _sleepSecondsRemaining = 0;
  Timer? _searchDebounce;
  bool _isSearching = false;

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
  String get activeCategory => _activeCategory;
  String? get activeMood => _activeCategory;
  String get searchQuery => _searchQuery;
  List<Song> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  List<Song> get favorites => _favorites;
  List<Song> get history => _history;
  List<Playlist> get playlists => _playlists;
  List<Song> get downloads => _downloads;
  List<Song> get recommendations => _recommendations;
  List<Song> get categoryTracks => _categoryTracks;
  bool get isAutoplayEnabled => _isAutoplayEnabled;
  int get sleepSecondsRemaining => _sleepSecondsRemaining;

  String get eqPreset => _eqPreset;
  bool get eqEnabled => _eqEnabled;
  double get bassBoost => _bassBoost;
  Map<int, double> get bandGains => _bandGains;
  EmberAudioHandler get audioHandler => _audioHandler;

  LyricsResult get lyrics => _lyrics;
  List<LyricLine> get syncedLyrics => _lyrics.syncedLyrics;
  String get plainLyrics => _lyrics.plainLyrics;
  bool get hasSyncedLyrics => _lyrics.hasSynced;
  bool get isLoadingLyrics => _isLoadingLyrics;

  int get currentLyricIndex {
    if (_lyrics.syncedLyrics.isEmpty) return -1;
    final pos = _position;
    for (int i = _lyrics.syncedLyrics.length - 1; i >= 0; i--) {
      if (pos >= _lyrics.syncedLyrics[i].timestamp) {
        return i;
      }
    }
    return 0;
  }

  void _init() {
    _favorites = _storageService.loadFavorites();
    _history = _storageService.loadHistory();
    _playlists = _storageService.loadPlaylists();
    _downloads = _storageService.loadDownloads();
    _speed = _storageService.loadPlaybackSpeed();
    _eqPreset = _storageService.loadEqualizerPreset();
    _eqEnabled = _storageService.loadEqualizerEnabled();
    _bassBoost = _storageService.loadBassBoost();
    _bandGains = _storageService.loadBandGains();

    // Wire up hardware / notification / completion navigation callbacks
    _audioHandler.setNavigationCallbacks(
      onSkipNext: () => skipNext(),
      onSkipPrevious: () => skipPrevious(),
      onCompleted: () => _handleSongCompleted(),
    );

    // Apply saved EQ preset & settings
    _audioHandler.setEqualizerEnabled(_eqEnabled);
    _audioHandler.setBassBoost(_bassBoost);
    _audioHandler.applyEqualizerPreset(_eqPreset);

    // Ensure all restored lists are completely free of legacy mock/placeholder tracks
    _favorites = _favorites.where((s) => !Song.isPlaceholder(s)).toList();
    _history = _history.where((s) => !Song.isPlaceholder(s)).toList();
    _downloads = _downloads.where((s) => !Song.isPlaceholder(s)).toList();
    _playlists = _playlists
        .map((p) => p.copyWith(songs: p.songs.where((s) => !Song.isPlaceholder(s)).toList()))
        .toList();

    // Restore previous queue from history or offline downloads, avoiding mock placeholder tracks
    if (_history.isNotEmpty) {
      _queue = List.from(_history.take(20));
    } else if (_downloads.isNotEmpty) {
      _queue = List.from(_downloads);
    } else {
      _queue = [];
    }

    // Load initial trending discovery tracks
    _loadInitialDiscoveryTracks();

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

  Future<void> _handleSongCompleted() async {
    if (_repeatMode == 'one') {
      await _audioHandler.seek(Duration.zero);
      await _audioHandler.play();
      return;
    }

    if (_currentIndex < _queue.length - 1) {
      await skipNext();
      return;
    }

    // At the end of queue
    if (_repeatMode == 'all' && _queue.isNotEmpty) {
      _currentIndex = 0;
      await playSong(_queue[0]);
      return;
    }

    // Infinite Autoplay Radio: auto-load and append recommendations
    if (_isAutoplayEnabled && _recommendations.isNotEmpty) {
      final nextSong = _recommendations.first;
      _queue.add(nextSong);
      _currentIndex = _queue.length - 1;
      _recommendations.removeAt(0);
      await playSong(nextSong);
      return;
    }
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
    _loadLyrics(song);
    _loadRecommendations(song);
    await _audioHandler.playSong(song);
  }

  Future<void> _loadLyrics(Song song) async {
    _isLoadingLyrics = true;
    _lyrics = LyricsResult.empty;
    notifyListeners();

    try {
      final res = await LyricsService.fetchLyrics(song.title, song.artist);
      if (currentSong?.id == song.id) {
        _lyrics = res;
        _isLoadingLyrics = false;
        notifyListeners();
      }
    } catch (_) {
      if (currentSong?.id == song.id) {
        _isLoadingLyrics = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadRecommendations(Song song) async {
    try {
      final reco = await CatalogService.fetchRecommendations(song, limit: 12);
      if (currentSong?.id == song.id) {
        _recommendations = reco;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> startRadio(Song song) async {
    final reco = await CatalogService.fetchRecommendations(song, limit: 15);
    _queue = [song, ...reco];
    _currentIndex = 0;
    notifyListeners();
    await playSong(song);
  }

  void toggleAutoplay() {
    _isAutoplayEnabled = !_isAutoplayEnabled;
    notifyListeners();
  }

  Future<void> retryFetchLyrics() async {
    final cur = currentSong;
    if (cur != null) {
      await _loadLyrics(cur);
    }
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

  /// Completely halt playback, dismiss active song, and return to no song playing state
  Future<void> stopPlayback() async {
    try {
      await _audioHandler.stop();
    } catch (_) {}
    _currentIndex = -1;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _lyrics = LyricsResult.empty;
    _isLoadingLyrics = false;
    notifyListeners();
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
      } else if (_isAutoplayEnabled && _recommendations.isNotEmpty) {
        await _handleSongCompleted();
        return;
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
      _unshuffledQueue = List.from(_queue);
      final cur = currentSong;
      _queue.shuffle();
      if (cur != null) {
        _queue.remove(cur);
        _queue.insert(0, cur);
        _currentIndex = 0;
      }
    } else if (!_isShuffle && _unshuffledQueue.isNotEmpty) {
      final cur = currentSong;
      _queue = List.from(_unshuffledQueue);
      if (cur != null) {
        _currentIndex = _queue.indexWhere((s) => s.id == cur.id);
        if (_currentIndex == -1) _currentIndex = 0;
      }
    }
    notifyListeners();
  }

  void setTab(String tab) {
    _activeTab = tab;
    notifyListeners();
  }

  Future<void> _loadInitialDiscoveryTracks() async {
    _activeCategory = 'trending';
    _isSearching = true;
    notifyListeners();
    try {
      final trending = await CatalogService.fetchTrendingTracks();
      final nonPlaceholders = trending.where((s) => !Song.isPlaceholder(s)).toList();
      if (nonPlaceholders.isNotEmpty) {
        _categoryTracks = nonPlaceholders;
        _searchResults = nonPlaceholders;
        if (_queue.isEmpty) {
          _queue = List.from(nonPlaceholders);
        }
      }
    } catch (e) {
      debugPrint('Error loading initial trending tracks: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> selectCategory(String categoryKey) async {
    _activeCategory = categoryKey;
    _activeTab = 'discover';
    _isSearching = true;
    notifyListeners();
    try {
      final liveTracks = await CatalogService.fetchCategoryTracks(categoryKey);
      final nonPlaceholders = liveTracks.where((s) => !Song.isPlaceholder(s)).toList();
      if (nonPlaceholders.isNotEmpty && _activeCategory == categoryKey) {
        _categoryTracks = nonPlaceholders;
        _searchResults = nonPlaceholders;
        if (_queue.isEmpty) {
          _queue = List.from(nonPlaceholders);
        }
      }
    } catch (e) {
      debugPrint('Error selecting category: $e');
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> playCategoryTracks(List<Song> tracks, {int startIndex = 0}) async {
    final validTracks = tracks.where((s) => !Song.isPlaceholder(s)).toList();
    if (validTracks.isEmpty) return;
    _queue = List.from(validTracks);
    _currentIndex = startIndex.clamp(0, _queue.length - 1);
    notifyListeners();
    await playSong(_queue[_currentIndex]);
  }

  void addTracksToQueue(List<Song> tracks) {
    final validTracks = tracks.where((s) => !Song.isPlaceholder(s)).toList();
    if (validTracks.isEmpty) return;
    _queue.addAll(validTracks);
    notifyListeners();
  }

  // Backward-compatible alias
  Future<void> selectMood(String moodKey) => selectCategory(moodKey);

  void search(String query) {
    _searchQuery = query;
    _searchDebounce?.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _isSearching = false;
      _searchResults = CatalogService.getAllTracks();
      notifyListeners();
      return;
    }

    // Immediately display local instant results so the UI responds in 0ms
    _searchResults = CatalogService.search(trimmed);
    _isSearching = true;
    notifyListeners();

    // Debounce 350ms before firing live online music search
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final onlineResults = await CatalogService.searchOnline(trimmed);
        if (_searchQuery == query) {
          _searchResults = onlineResults;
          _isSearching = false;
          notifyListeners();
        }
      } catch (_) {
        if (_searchQuery == query) {
          _isSearching = false;
          notifyListeners();
        }
      }
    });
  }

  // Queue manipulation
  void playNext(Song song) {
    final existingIdx = _queue.indexWhere((s) => s.id == song.id);
    if (existingIdx != -1) {
      _queue.removeAt(existingIdx);
      if (existingIdx < _currentIndex) _currentIndex--;
    }
    final targetIdx = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(targetIdx, song);
    notifyListeners();
  }

  void addToQueue(Song song) {
    if (!_queue.any((s) => s.id == song.id)) {
      _queue.add(song);
      notifyListeners();
    }
  }

  void removeTrackAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (_currentIndex >= _queue.length) {
      _currentIndex = (_queue.length - 1).clamp(0, _queue.length);
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final cur = currentSong;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);

    if (cur != null) {
      _currentIndex = _queue.indexOf(cur);
    }
    notifyListeners();
  }

  void clearQueue() {
    final cur = currentSong;
    _queue.clear();
    if (cur != null) {
      _queue.add(cur);
      _currentIndex = 0;
    } else {
      _currentIndex = 0;
    }
    notifyListeners();
  }

  // Playlists
  Future<void> createPlaylist(String title, {String description = ''}) async {
    final newPlaylist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isNotEmpty ? title.trim() : 'New Playlist',
      description: description,
      songs: [],
      createdAt: DateTime.now(),
    );
    await _storageService.savePlaylist(newPlaylist);
    _playlists = _storageService.loadPlaylists();
    notifyListeners();
  }

  Future<void> addSongToPlaylist(String playlistId, Song song) async {
    await _storageService.addSongToPlaylist(playlistId, song);
    _playlists = _storageService.loadPlaylists();
    notifyListeners();
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      final p = _playlists[idx];
      final updated = p.copyWith(
        songs: p.songs.where((s) => s.id != songId).toList(),
      );
      await _storageService.savePlaylist(updated);
      _playlists = _storageService.loadPlaylists();
      notifyListeners();
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _storageService.deletePlaylist(playlistId);
    _playlists = _storageService.loadPlaylists();
    notifyListeners();
  }

  Future<void> playPlaylist(Playlist playlist) async {
    if (playlist.songs.isNotEmpty) {
      _queue = List.from(playlist.songs);
      _currentIndex = 0;
      notifyListeners();
      await playSong(_queue[0]);
    }
  }

  // YouTube Importer
  Future<String> importYouTubeUrl(String url) async {
    final res = await YouTubeImporterService.importFromUrl(url);
    if (res.error != null) {
      return 'Import failed: ${res.error}';
    }

    if (res.type == YouTubeImportType.playlist && res.playlist != null) {
      await _storageService.savePlaylist(res.playlist!);
      _playlists = _storageService.loadPlaylists();
      notifyListeners();
      return 'Imported & saved "${res.playlist!.title}" (${res.playlist!.songs.length} tracks)';
    } else if (res.type == YouTubeImportType.video && res.song != null) {
      addToQueue(res.song!);
      notifyListeners();
      return 'Imported "${res.song!.title}" to queue';
    }
    return 'Import failed';
  }

  // Offline Downloads
  bool isDownloaded(String songId) {
    return _downloads.any((s) => s.id == songId);
  }

  Future<String?> downloadAudio(Song song) async {
    final path = await DownloadService.downloadAudio(song, _storageService);
    if (path != null) {
      _downloads = _storageService.loadDownloads();
      notifyListeners();
    }
    return path;
  }

  Future<String?> downloadVideo(Song song) async {
    return await DownloadService.downloadVideo(song);
  }

  Future<void> deleteDownload(String songId) async {
    _downloads.removeWhere((s) => s.id == songId);
    await _storageService.saveDownloads(_downloads);
    notifyListeners();
  }

  // Equalizer
  Future<void> setEqualizerPreset(String preset) async {
    _eqPreset = preset;
    await _storageService.saveEqualizerPreset(preset);
    await _audioHandler.applyEqualizerPreset(preset);
    notifyListeners();
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    _eqEnabled = enabled;
    await _storageService.saveEqualizerEnabled(enabled);
    await _audioHandler.setEqualizerEnabled(enabled);
    notifyListeners();
  }

  Future<void> setBassBoost(double gain) async {
    _bassBoost = gain;
    await _storageService.saveBassBoost(gain);
    await _audioHandler.setBassBoost(gain);
    notifyListeners();
  }

  Future<void> setBandGain(int index, double gain) async {
    _bandGains[index] = gain;
    await _storageService.saveBandGains(_bandGains);
    await _audioHandler.setBandGain(index, gain);
    notifyListeners();
  }

  // Favorites & History
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

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _sleepTimer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}
