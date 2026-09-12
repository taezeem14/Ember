import '../models/song.dart';

class MoodPreset {
  final String key;
  final String emoji;
  final String title;
  final String subtitle;
  final List<Song> tracks;

  const MoodPreset({
    required this.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.tracks,
  });
}

class CatalogService {
  static const List<MoodPreset> cozyMoods = [
    MoodPreset(
      key: 'lofi',
      emoji: '☕',
      title: 'Lo-Fi Study Beats',
      subtitle: 'Warm analog warmth & tape flutter',
      tracks: [
        Song(
          id: 'lofi_01',
          title: 'Midnight Coffee Steam',
          artist: 'Komorebi Sound',
          duration: Duration(minutes: 2, seconds: 45),
          artworkUrl: 'https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
          lyrics: 'Steam rising from the cup\nLate night clock ticking soft\nGentle keys playing on\nWarm amber glow in the dark.',
        ),
        Song(
          id: 'lofi_02',
          title: 'Paper Notebooks & Tape',
          artist: 'Ember Collective',
          duration: Duration(minutes: 3, seconds: 12),
          artworkUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
          lyrics: 'Scribbling thoughts in the margin\nCassette tape spins around\nNo hurry, no rush\nJust the warmth of the sound.',
        ),
      ],
    ),
    MoodPreset(
      key: 'rain',
      emoji: '🌧️',
      title: 'Rainy Day Windows',
      subtitle: 'Gentle raindrops & mellow chords',
      tracks: [
        Song(
          id: 'rain_01',
          title: 'Waterdrops on Glass',
          artist: 'Petrichor Sessions',
          duration: Duration(minutes: 3, seconds: 34),
          artworkUrl: 'https://images.unsplash.com/photo-1515694346937-94d85e41e6f0?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
          lyrics: 'Droplets racing down the pane\nGray skies outside the frame\nInside the kettle boils\nSafe and quiet in the rain.',
        ),
        Song(
          id: 'rain_02',
          title: 'Autumn Rain In Kyoto',
          artist: 'Sora Trio',
          duration: Duration(minutes: 4, seconds: 05),
          artworkUrl: 'https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
          lyrics: 'Stone lanterns wet with moss\nPebbles washed clean\nPiano notes echoing\nA tranquil, quiet scene.',
        ),
      ],
    ),
    MoodPreset(
      key: 'jazz',
      emoji: '🎷',
      title: 'Late Night Espresso Jazz',
      subtitle: 'Upright acoustic bass & velvet piano',
      tracks: [
        Song(
          id: 'jazz_01',
          title: 'Smoke & Bourbon Keys',
          artist: 'The Amber Quartet',
          duration: Duration(minutes: 4, seconds: 20),
          artworkUrl: 'https://images.unsplash.com/photo-1511192336575-5a79af67a629?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
          lyrics: 'Walking bass line steady\nBrushes on the snare\nMidnight jazz club candle\nMusic in the air.',
        ),
      ],
    ),
    MoodPreset(
      key: 'fireplace',
      emoji: '🕯️',
      title: 'Cozy Hearthside',
      subtitle: 'Crackling embers & nylon acoustic strings',
      tracks: [
        Song(
          id: 'fire_01',
          title: 'Embers Glowing Soft',
          artist: 'Cedar & Pine',
          duration: Duration(minutes: 3, seconds: 15),
          artworkUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
          lyrics: 'Wood pops in the fireplace\nShadows dance upon the wall\nWrapped in a wool blanket\nListening to the autumn fall.',
        ),
      ],
    ),
    MoodPreset(
      key: 'ambient',
      emoji: '🌌',
      title: 'Midnight Atmosphere',
      subtitle: 'Reverberant acoustic pads & gentle warmth',
      tracks: [
        Song(
          id: 'amb_01',
          title: 'Constellations Above',
          artist: 'Solaris Drift',
          duration: Duration(minutes: 5, seconds: 10),
          artworkUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
          lyrics: 'Stars across the night sky\nDrifting without a care\nCalm ocean of silence\nFloating through the air.',
        ),
      ],
    ),
    MoodPreset(
      key: 'autumn',
      emoji: '🍂',
      title: 'Autumn Amber Breeze',
      subtitle: 'Golden leaves & acoustic warmth',
      tracks: [
        Song(
          id: 'aut_01',
          title: 'Golden Leaves Falling',
          artist: 'Harvest Moon',
          duration: Duration(minutes: 3, seconds: 48),
          artworkUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500&q=80',
          streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
          lyrics: 'Crisp autumn wind\nRustling in the trees\nWarm cup in both hands\nGentle golden breeze.',
        ),
      ],
    ),
  ];

  static List<Song> getAllTracks() {
    final list = <Song>[];
    for (final mood in cozyMoods) {
      list.addAll(mood.tracks);
    }
    return list;
  }

  static List<Song> search(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return getAllTracks();
    return getAllTracks().where((song) {
      return song.title.toLowerCase().contains(q) ||
          song.artist.toLowerCase().contains(q) ||
          (song.lyrics?.toLowerCase().contains(q) ?? false);
    }).toList();
  }
}
