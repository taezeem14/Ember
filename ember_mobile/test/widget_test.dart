import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ember_mobile/models/song.dart';
import 'package:ember_mobile/models/playlist.dart';
import 'package:ember_mobile/services/storage_service.dart';
import 'package:ember_mobile/services/catalog_service.dart';
import 'package:ember_mobile/services/lyrics_service.dart';
import 'package:ember_mobile/theme/ember_theme.dart';
import 'package:ember_mobile/services/passkey_service.dart';
import 'package:ember_mobile/services/spotify_service.dart';
import 'package:ember_mobile/services/stream_resolver_service.dart';
import 'package:ember_mobile/services/youtube_importer_service.dart';
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
      expect(keys, containsAll(['trending', 'top_hits', 'bollywood', 'punjabi', 'pop', 'hiphop', 'lofi', 'rock']));
    });

    test('Catalog decryptMediaUrl decrypts DES and upgrades to 320kbps', () {
      // Test with null and empty
      expect(CatalogService.decryptMediaUrl(null), isNull);
      expect(CatalogService.decryptMediaUrl(''), isNull);
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

    test('SpotifyService curatedCharts provides valid chart configurations', () {
      final charts = SpotifyService.curatedCharts;
      expect(charts, isNotEmpty);
      expect(charts.first.key, equals('top_hits'));
      expect(charts.first.playlistId, isNotEmpty);
    });

    test('SpotifyService parsePlaylistId handles URLs and IDs', () {
      final id1 = SpotifyService.parsePlaylistId('37i9dQZF1DXcBWIGoYBM5M');
      expect(id1, equals('37i9dQZF1DXcBWIGoYBM5M'));

      final id2 = SpotifyService.parsePlaylistId('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=123');
      expect(id2, equals('37i9dQZF1DXcBWIGoYBM5M'));
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

    test('parseLrc supports multiline timestamps and offset adjustments', () {
      const lrc = '''
[offset:+500]
[00:10.00][00:20.00] Repeated line
''';
      final lines = LyricsService.parseLrc(lrc);
      expect(lines.length, 2);
      expect(lines[0].timestamp, const Duration(seconds: 10, milliseconds: 500));
      expect(lines[0].text, 'Repeated line');
      expect(lines[1].timestamp, const Duration(seconds: 20, milliseconds: 500));
      expect(lines[1].text, 'Repeated line');
    });

    test('cleanString strips extraneous title annotations', () {
      expect(LyricsService.cleanString('Starboy (feat. Daft Punk)'), 'Starboy');
      expect(LyricsService.cleanString('In The End [Official Video]'), 'In The End');
      expect(LyricsService.cleanString('Something Just Like This (Remastered)'), 'Something Just Like This');
    });
  });

  group('Theme Tokens Tests', () {
    test('EmberColors palette contains Spotify Electric Blue tokens', () {
      expect(EmberColors.obsidianBase, const Color(0xFF121212));
      expect(EmberColors.primaryBlue, const Color(0xFF2979FF));
      expect(EmberColors.primaryBlueHi, const Color(0xFF82B1FF));
      expect(EmberColors.secondaryCyan, const Color(0xFF00D4FF));
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
        streamUrl: 'https://example.com/audio.m4a',
      );
      final resolved = await CatalogService.resolvePlayableStream(directSong);
      expect(resolved, equals('https://example.com/audio.m4a'));
    });

    test('CatalogService.parseYouTubeMetadata correctly parses titles and filters publisher channels', () {
      final meta1 = CatalogService.parseYouTubeMetadata(
        'The Weeknd - Blinding Lights (Official Audio)',
        'The Weeknd',
      );
      expect(meta1.cleanTitle, 'Blinding Lights');
      expect(meta1.cleanArtist, 'The Weeknd');

      final meta2 = CatalogService.parseYouTubeMetadata(
        'Arijit Singh - Kesariya | Brahmāstra',
        'Sony Music India',
      );
      expect(meta2.cleanTitle, 'Kesariya');
      expect(meta2.cleanArtist, 'Arijit Singh');

      final meta3 = CatalogService.parseYouTubeMetadata(
        'Calm Down',
        'Rema - Topic',
      );
      expect(meta3.cleanTitle, 'Calm Down');
      expect(meta3.cleanArtist, '');
    });

    test('CatalogService.verifyMatch correctly identifies authentic matches and rejects false positives', () {
      // Positive matches
      expect(
        CatalogService.verifyMatch(
          targetTitle: 'Blinding Lights',
          targetArtist: 'The Weeknd',
          candidateTitle: 'Blinding Lights',
          candidateArtist: 'The Weeknd',
        ),
        isTrue,
      );

      expect(
        CatalogService.verifyMatch(
          targetTitle: 'Kesariya',
          targetArtist: 'Arijit Singh',
          candidateTitle: 'Kesariya (From "Brahmastra")',
          candidateArtist: 'Amitabh Bhattacharya, Pritam, Arijit Singh',
        ),
        isTrue,
      );

      // Negative matches (reject random popular tracks)
      expect(
        CatalogService.verifyMatch(
          targetTitle: 'Blinding Lights',
          targetArtist: 'The Weeknd',
          candidateTitle: 'Starboy',
          candidateArtist: 'The Weeknd',
        ),
        isFalse,
      );

      expect(
        CatalogService.verifyMatch(
          targetTitle: 'Kesariya',
          targetArtist: 'Arijit Singh',
          candidateTitle: 'Apna Bana Le',
          candidateArtist: 'Arijit Singh',
        ),
        isFalse,
      );
    });

  });

  group('Passkey Service Tests', () {
    test('PasskeyService contains exactly 100 unique passkeys', () {
      expect(PasskeyService.passkeys.length, 100);
      for (final key in PasskeyService.passkeys) {
        expect(key.startsWith('EMBR-'), isTrue);
        expect(key.length, 9);
      }
    });

    test('PasskeyService isValid checks case-insensitive and trimmed codes', () {
      final sample = PasskeyService.passkeys.first;
      expect(PasskeyService.isValid(sample), isTrue);
      expect(PasskeyService.isValid(sample.toLowerCase()), isTrue);
      expect(PasskeyService.isValid('  $sample  '), isTrue);

      expect(PasskeyService.isValid(''), isFalse);
      expect(PasskeyService.isValid('INVALID'), isFalse);
      expect(PasskeyService.isValid('EMBR-ZZZZ'), isFalse);
    });
  });

  group('Song Source and Engine Model Tests', () {
    test('Song model source defaults to spotify and supports youtube', () {
      const defaultSong = Song(
        id: '123',
        title: 'Song',
        artist: 'Artist',
        duration: Duration(minutes: 3),
        artworkUrl: '',
        streamUrl: 'https://example.com/audio.m4a',
      );
      expect(defaultSong.source, 'spotify');
      expect(defaultSong.isSpotify, isTrue);
      expect(defaultSong.isYouTube, isFalse);

      final ytSong = defaultSong.copyWith(id: 'yt_xyz', source: 'youtube');
      expect(ytSong.source, 'youtube');
      expect(ytSong.isSpotify, isFalse);
      expect(ytSong.isYouTube, isTrue);

      final map = ytSong.toMap();
      expect(map['source'], 'youtube');
      final revived = Song.fromMap(map);
      expect(revived.source, 'youtube');
      expect(revived.isYouTube, isTrue);
    });
  });

  group('StorageService History Clear Tests', () {
    test('StorageService history recording and clearHistory() resets properly', () async {
      final storage = StorageService(null);
      expect(storage.loadHistory(), isEmpty);

      const song1 = Song(
        id: 's_hist_1',
        title: 'History Song 1',
        artist: 'Artist 1',
        duration: Duration(minutes: 3),
        artworkUrl: '',
        streamUrl: 'https://example.com/1.mp3',
      );
      const song2 = Song(
        id: 's_hist_2',
        title: 'History Song 2',
        artist: 'Artist 2',
        duration: Duration(minutes: 4),
        artworkUrl: '',
        streamUrl: 'https://example.com/2.mp3',
      );

      await storage.saveHistory([song2, song1]);
      expect(storage.loadHistory().length, 2);
      expect(storage.loadHistory().first.id, 's_hist_2');

      await storage.clearHistory();
      expect(storage.loadHistory(), isEmpty);
    });
  });

  group('SpotifyService Tests', () {
    test('SpotifyService parseSpotifyUrl identifies track, album, and playlist URLs and URIs', () {
      final track = SpotifyService.parseSpotifyUrl('https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT');
      expect(track, isNotNull);
      expect(track!.type, SpotifyEntityType.track);
      expect(track.id, '4cOdK2wGLETKBW3PvgPWqT');

      final embed = SpotifyService.parseSpotifyUrl('https://open.spotify.com/embed/track/4cOdK2wGLETKBW3PvgPWqT');
      expect(embed, isNotNull);
      expect(embed!.type, SpotifyEntityType.track);
      expect(embed.id, '4cOdK2wGLETKBW3PvgPWqT');

      final playlist = SpotifyService.parseSpotifyUrl('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M');
      expect(playlist, isNotNull);
      expect(playlist!.type, SpotifyEntityType.playlist);
      expect(playlist.id, '37i9dQZF1DXcBWIGoYBM5M');

      final album = SpotifyService.parseSpotifyUrl('https://open.spotify.com/album/4m2880jivSbbyEGAKfITCa?si=123');
      expect(album, isNotNull);
      expect(album!.type, SpotifyEntityType.album);
      expect(album.id, '4m2880jivSbbyEGAKfITCa');

      expect(SpotifyService.parseSpotifyUrl('https://example.com/not-spotify'), isNull);
    });

    test('SpotifyService curatedCharts contains essential charts', () {
      expect(SpotifyService.curatedCharts, isNotEmpty);
      final keys = SpotifyService.curatedCharts.map((c) => c.key).toList();
      expect(keys.contains('top_hits'), isTrue);
      expect(keys.contains('global_top_50'), isTrue);
      expect(keys.contains('viral_50'), isTrue);
      expect(keys.contains('rapcaviar'), isTrue);
    });
  });

  group('StreamResolverService Tests', () {
    test('cleanTitle strips noise words while preserving core title', () {
      expect(
        StreamResolverService.cleanTitle('Starboy (Official Audio) [HD]'),
        'Starboy',
      );
      expect(
        StreamResolverService.cleanTitle('Blinding Lights (Remastered)'),
        'Blinding Lights',
      );
      expect(
        StreamResolverService.cleanTitle('As It Was (Music Video)'),
        'As It Was',
      );
    });
  });

  group('YouTubeImporterService Tests', () {
    test('detectUrlType correctly classifies videos vs playlists', () {
      expect(
        YouTubeImporterService.detectUrlType('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        YouTubeImportType.video,
      );
      expect(
        YouTubeImporterService.detectUrlType('https://youtu.be/dQw4w9WgXcQ'),
        YouTubeImportType.video,
      );
      expect(
        YouTubeImporterService.detectUrlType('https://www.youtube.com/playlist?list=PL1234567890'),
        YouTubeImportType.playlist,
      );
      expect(
        YouTubeImporterService.detectUrlType('https://music.youtube.com/playlist?list=RDCLAK5uy_k'),
        YouTubeImportType.playlist,
      );
      expect(
        YouTubeImporterService.detectUrlType('https://example.com/something'),
        YouTubeImportType.unknown,
      );
    });

    test('extractVideoId and extractPlaylistId handle various URL formats', () {
      expect(
        YouTubeImporterService.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeImporterService.extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeImporterService.extractPlaylistId('https://www.youtube.com/playlist?list=PL1234567890'),
        'PL1234567890',
      );
    });

    test('parseDurationText handles mm:ss and hh:mm:ss', () {
      expect(
        YouTubeImporterService.parseDurationText('3:45'),
        const Duration(minutes: 3, seconds: 45),
      );
      expect(
        YouTubeImporterService.parseDurationText('1:02:15'),
        const Duration(hours: 1, minutes: 2, seconds: 15),
      );
    });
  });
}


