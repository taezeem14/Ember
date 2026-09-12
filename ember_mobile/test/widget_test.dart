import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ember_mobile/models/song.dart';
import 'package:ember_mobile/services/catalog_service.dart';
import 'package:ember_mobile/theme/ember_theme.dart';
import 'package:ember_mobile/widgets/ambient_glow.dart';
import 'package:ember_mobile/widgets/vinyl_disc.dart';

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
  });

  group('Catalog Service Tests', () {
    test('Catalog contains all 6 cozy moods', () {
      expect(CatalogService.cozyMoods.length, 6);
      final keys = CatalogService.cozyMoods.map((m) => m.key).toList();
      expect(keys, containsAll(['lofi', 'rain', 'jazz', 'fireplace', 'ambient', 'autumn']));
    });

    test('Catalog search matches title and artist', () {
      final results = CatalogService.search('Coffee');
      expect(results.isNotEmpty, true);
      expect(results.first.title.toLowerCase(), contains('coffee'));
    });

    test('Catalog search with empty query returns all tracks', () {
      final all = CatalogService.getAllTracks();
      final searched = CatalogService.search('');
      expect(searched.length, all.length);
    });

    test('Catalog fetchMoodTracks returns non-empty track list for all mood keys', () async {
      for (final mood in CatalogService.cozyMoods) {
        final tracks = await CatalogService.fetchMoodTracks(mood.key);
        expect(tracks.isNotEmpty, true, reason: 'Mood ${mood.key} should return tracks');
        expect(tracks.first.title.isNotEmpty, true);
        expect(tracks.first.streamUrl.isNotEmpty, true);
      }
    });

    test('Catalog searchOnline returns tracks or falls back cleanly', () async {
      final results = await CatalogService.searchOnline('Coffee');
      expect(results.isNotEmpty, true);
      expect(results.first.title.isNotEmpty, true);
      expect(results.first.artist.isNotEmpty, true);
      expect(results.first.streamUrl.isNotEmpty, true);
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
  });
}
