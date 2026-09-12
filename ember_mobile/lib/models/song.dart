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

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.artworkUrl,
    required this.streamUrl,
    this.lyrics,
    this.isFavorite = false,
  });

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    Duration? duration,
    String? artworkUrl,
    String? streamUrl,
    String? lyrics,
    bool? isFavorite,
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
    };
  }

  factory Song.fromMap(Map<String, dynamic> map) {
    return Song(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Unknown Title',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      duration: Duration(milliseconds: (map['duration_ms'] as num?)?.toInt() ?? 0),
      artworkUrl: map['artwork_url'] as String? ?? '',
      streamUrl: map['stream_url'] as String? ?? '',
      lyrics: map['lyrics'] as String?,
      isFavorite: (map['is_favorite'] as bool?) ?? false,
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
}
