import 'package:flutter/foundation.dart';

@immutable
class Song {
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String artworkUrl;
  final String streamUrl;
  final String? lyrics;
  final bool isFavorite;
  final String source;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.artworkUrl,
    required this.streamUrl,
    this.lyrics,
    this.isFavorite = false,
    this.source = 'unknown',
  });

  bool get isSpotify => source == 'spotify' || id.startsWith('sp_') || streamUrl.startsWith('spotify:');
  bool get isYouTube => source == 'youtube' || id.startsWith('yt_') || streamUrl.contains('youtu');
  bool get isJioSaavn => source == 'saavn' || id.startsWith('saavn_') || streamUrl.contains('saavncdn.com');
  bool get isUnknown => !isSpotify && !isYouTube && !isJioSaavn;

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    Duration? duration,
    String? artworkUrl,
    String? streamUrl,
    String? lyrics,
    bool? isFavorite,
    String? source,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      lyrics: lyrics ?? this.lyrics,
      isFavorite: isFavorite ?? this.isFavorite,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'duration_ms': duration.inMilliseconds,
      'artwork_url': artworkUrl,
      'stream_url': streamUrl,
      'lyrics': lyrics,
      'is_favorite': isFavorite,
      'source': source,
    };
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'] as String? ?? '';
    final rawStream = map['stream_url'] as String? ?? '';
    final explicitSource = map['source'] as String?;
    final inferredSource = explicitSource ??
        (rawId.startsWith('yt_') || rawStream.contains('youtu') ? 'youtube' :
         rawId.startsWith('saavn_') || rawStream.contains('saavncdn.com') ? 'saavn' :
         'spotify');

    return Song(
      id: rawId,
      title: map['title'] as String? ?? 'Unknown Title',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      duration: Duration(milliseconds: (map['duration_ms'] as num?)?.toInt() ?? 0),
      artworkUrl: map['artwork_url'] as String? ?? '',
      streamUrl: rawStream,
      lyrics: map['lyrics'] as String?,
      isFavorite: map['is_favorite'] as bool? ?? false,
      source: inferredSource,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Song && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Song(id: $id, title: $title, artist: $artist)';

  /// Identifies legacy mock/placeholder tracks (e.g. Coffee Steam, SoundHelix previews)
  static bool isPlaceholder(Song song) {
    final t = song.title.toLowerCase();
    final a = song.artist.toLowerCase();
    final s = song.streamUrl.toLowerCase();
    final i = song.id.toLowerCase();

    if (i.startsWith('lofi_') ||
        i.startsWith('rain_') ||
        i.startsWith('jazz_') ||
        i.startsWith('fire_') ||
        i.startsWith('amb_') ||
        i.startsWith('aut_') ||
        i.startsWith('mock_')) {
      return true;
    }

    if (s.contains('soundhelix.com')) {
      return true;
    }

    if (t.contains('coffee steam') ||
        t.contains('paper notebook') ||
        t.contains('paper tape') ||
        t.contains('waterdrops on glass') ||
        t.contains('autumn rain in kyoto') ||
        t.contains('smoke & bourbon') ||
        t.contains('embers glowing soft') ||
        t.contains('constellations above') ||
        t.contains('golden leaves falling')) {
      return true;
    }

    if (a.contains('lofi coffee') ||
        a.contains('komorebi') ||
        a.contains('ember collective') ||
        a.contains('petrichor') ||
        a.contains('sora trio') ||
        a.contains('amber quartet') ||
        a.contains('cedar & pine') ||
        a.contains('solaris drift') ||
        a.contains('harvest moon')) {
      return true;
    }

    return false;
  }
}
