import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ember_mobile/models/song.dart';
import 'package:ember_mobile/models/playlist.dart';
import 'package:ember_mobile/services/storage_service.dart';
import 'package:ember_mobile/services/catalog_service.dart';
import 'package:ember_mobile/services/lyrics_service.dart';
import 'package:ember_mobile/theme/ember_theme.dart';
import 'package:ember_mobile/widgets/ambient_glow.dart';
import 'package:ember_mobile/widgets/vinyl_disc.dart';
import 'package:ember_mobile/screens/settings_screen.dart';


void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Song Model Tests', () {
    test('Song serialization and deserialization', () {
      const song = Song(
        id: 'test_1',
        title: 'Autumn Rain',
        artist: 'Ember Collective',
        duration: Duration(minutes: 3, seconds: 20),
        artworkUrl: 'https://example.com/art.jpg',
        streamUrl: 'https://example.com/audio.mp3',
        lyrics: 'Rain drops falling down',
        isFavorite: true,
      );

      final map = song.toMap();
      expect(map['id'], 'test_1');
      expect(map['title'], 'Autumn Rain');
      expect(map['duration_ms'], 200000);
      expect(map['is_favorite'], true);

      final revived = Song.fromMap(map);
      expect(revived, equals(song));
      expect(revived.id, song.id);
      expect(revived.title, song.title);
      expect(revived.artist, song.artist);
      expect(revived.duration, song.duration);
      expect(revived.lyrics, song.lyrics);
      expect(revived.isFavorite, true);
    });

    test('Song fromMap with missing or empty keys uses sensible fallbacks', () {
      final song = Song.fromMap({});
      expect(song.id, '');
      expect(song.title, 'Unknown Title');
      expect(song.artist, 'Unknown Artist');
      expect(song.duration, Duration.zero);
      expect(song.isFavorite, false);
      expect(song.lyrics, isNull);
    });

    test('Song copyWith updates specific fields correctly', () {
      const original = Song(
        id: 'orig',
        title: 'Original',
        artist: 'Artist',
        duration: Duration(minutes: 2),
        artworkUrl: '',
        streamUrl: '',
      );

      final updated = original.copyWith(title: 'Updated Title', isFavorite: true);
      expect(updated.title, 'Updated Title');
      expect(updated.isFavorite, true);
      expect(updated.id, original.id);
      expect(updated.artist, original.artist);
    });

    test('Song.isPlaceholder identifies mock songs and allows real songs', () {
      const coffee = Song(
        id: 'lofi_01',
        title: 'Midnight Coffee Steam',
        artist: 'Lofi Coffee Sessions',
        duration: Duration(minutes: 2, seconds: 45),
        artworkUrl: '',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      );
      expect(Song.isPlaceholder(coffee), isTrue);

      const paperTape = Song(
        id: 'mock_02',
        title: 'Midnight Paper Tape',
        artist: 'Ember Collective',
        duration: Duration(minutes: 3, seconds: 12),
        artworkUrl: '',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      );
      expect(Song.isPlaceholder(paperTape), isTrue);

      const realSong = Song(
        id: 'yt_abc123',
        title: 'Believer',
        artist: 'Imagine Dragons',
        duration: Duration(minutes: 3, seconds: 24),
        artworkUrl: 'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
        streamUrl: 'https://www.youtube.com/watch?v=abc123',
      );
      expect(Song.isPlaceholder(realSong), isFalse);
    });
  });

  group('Storage Service Tests', () {
    test('StorageService in-memory CRUD maintains playlists without data loss', () async {
      final storage = StorageService(null);
      expect(storage.loadPlaylists(), isEmpty);

      final pl1 = Playlist(
        id: 'pl_1',
        title: 'Rock Favorites',
        songs: const [
          Song(
            id: 's_1',
            title: 'Song One',
            artist: 'Band A',
            duration: Duration(minutes: 3),
            artworkUrl: '',
            streamUrl: 'https://example.com/1.mp3',
          ),
        ],
        createdAt: DateTime.now(),
      );

      await storage.savePlaylist(pl1);
      expect(storage.loadPlaylists().length, 1);
      expect(storage.loadPlaylists().first.title, 'Rock Favorites');

      final pl2 = Playlist(
        id: 'pl_2',
        title: 'Chill Vibes',
        songs: const [],
        createdAt: DateTime.now(),
      );

      await storage.savePlaylist(pl2);
      expect(storage.loadPlaylists().length, 2);

      await storage.addSongToPlaylist(
        'pl_2',
        const Song(
          id: 's_2',
          title: 'Song Two',
          artist: 'Band B',
          duration: Duration(minutes: 4),
          artworkUrl: '',
          streamUrl: 'https://example.com/2.mp3',
        ),
      );

      final reloaded = storage.loadPlaylists();
      final chill = reloaded.firstWhere((p) => p.id == 'pl_2');
      expect(chill.songs.length, 1);
      expect(chill.songs.first.id, 's_2');

      await storage.deletePlaylist('pl_1');
      expect(storage.loadPlaylists().length, 1);
      expect(storage.loadPlaylists().first.id, 'pl_2');
    });
  });

  group('Catalog Service Tests', () {
    test('Catalog contains all 8 real music categories', () {
      expect(CatalogService.categories.length, 8);
      final keys = CatalogService.categories.map((m) => m.key).toList();
      expect(keys, containsAll(['trending', 'top_hits', 'pop', 'hiphop', 'rock', 'electronic', 'rnb', 'acoustic']));
    });

    test('Catalog search with empty query returns list', () {
      final all = CatalogService.getAllTracks();
      final searched = CatalogService.search('');
      expect(searched.length, all.length);
    });

    test('Catalog fetchTrendingTracks returns track list', () async {
      final tracks = await CatalogService.fetchTrendingTracks(limit: 5);
      expect(tracks, isA<List<Song>>());
    });

    test('Catalog searchOnline returns tracks or falls back cleanly', () async {
      final results = await CatalogService.searchOnline('Believer', limit: 5);
      expect(results, isA<List<Song>>());
    });

    test('Catalog decryptMediaUrl correctly decrypts Saavn encrypted URL', () {
      const enc = 'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDyUAfhmijvFBT8pPh5PqKgzsRHfUZzMKSjj3NUx57Nm2u/4CmI0GLa9hw7tS9a8Gtq';
      final decrypted = CatalogService.decryptMediaUrl(enc);
      expect(decrypted, isNotNull);
      expect(decrypted, startsWith('https://aac.saavncdn.com/'));
      expect(decrypted, endsWith('_320.mp4'));
    });
  });

  group('Lyrics Service Tests', () {
    test('parseLrc correctly parses timestamp and text', () {
      const lrc = '''
[00:15.50] Main track outta your league too, ah
[01:05.80] House so empty, need a centerpiece
[02:00.00] Look what you have done
''';
      final lines = LyricsService.parseLrc(lrc);
      expect(lines.length, 3);
      expect(lines[0].timestamp, const Duration(seconds: 15, milliseconds: 500));
      expect(lines[0].text, 'Main track outta your league too, ah');
      expect(lines[1].timestamp, const Duration(minutes: 1, seconds: 5, milliseconds: 800));
      expect(lines[2].timestamp, const Duration(minutes: 2));
    });

    test('cleanString strips extraneous title annotations', () {
      expect(LyricsService.cleanString('Starboy (feat. Daft Punk)'), 'Starboy');
      expect(LyricsService.cleanString('In The End [Official Video]'), 'In The End');
      expect(LyricsService.cleanString('Something Just Like This (Remastered)'), 'Something Just Like This');
    });
  });

  group('Theme Tokens Tests', () {
    test('EmberColors palette contains warm audio tokens', () {
      expect(EmberColors.obsidianBase, const Color(0xFF0B0907));
      expect(EmberColors.primaryAmber, const Color(0xFFF59E0B));
      expect(EmberColors.primaryAmberHi, const Color(0xFFFFC174));
      expect(EmberColors.secondaryHoney, const Color(0xFFD97706));
    });

    test('Dark theme configures dark brightness and amber primary', () {
      final theme = EmberTheme.buildTheme(useGoogleFonts: false);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, EmberColors.primaryAmber);
      expect(theme.scaffoldBackgroundColor, EmberColors.obsidianBase);
    });
  });

  group('Widget Rendering Tests', () {
    testWidgets('VinylDisc renders correctly and spins', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VinylDisc(size: 100, isPlaying: true),
            ),
          ),
        ),
      );

      expect(find.byType(VinylDisc), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(VinylDisc), findsOneWidget);
    });

    testWidgets('AmbientGlow renders child with shadow', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AmbientGlow(
                isPlaying: true,
                child: SizedBox(width: 50, height: 50),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AmbientGlow), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AmbientGlow), findsOneWidget);
    });

    test('CatalogService.resolvePlayableStream preserves non-YouTube direct streams', () async {
      const directSong = Song(
        id: 'direct_1',
        title: 'Direct Track',
        artist: 'Artist',
        duration: Duration(minutes: 3),
        artworkUrl: 'https://example.com/art.jpg',
        streamUrl: 'https://c.saavncdn.com/test.mp4',
      );
      final resolved = await CatalogService.resolvePlayableStream(directSong);
      expect(resolved, equals('https://c.saavncdn.com/test.mp4'));
    });

  });
}

