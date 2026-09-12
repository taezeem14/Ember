import 'song.dart';

class Playlist {
  final String id;
  final String title;
  final String description;
  final List<Song> songs;
  final DateTime createdAt;
  final String? coverUrl;

  const Playlist({
    required this.id,
    required this.title,
    this.description = '',
    required this.songs,
    required this.createdAt,
    this.coverUrl,
  });

  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    List<Song>? songs,
    DateTime? createdAt,
    String? coverUrl,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      songs: songs ?? this.songs,
      createdAt: createdAt ?? this.createdAt,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'songs': songs.map((s) => s.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'coverUrl': coverUrl,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Untitled Playlist',
      description: map['description']?.toString() ?? '',
      songs: (map['songs'] as List? ?? [])
          .map((item) => Song.fromMap(item is Map<String, dynamic> ? item : {}))
          .toList(),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      coverUrl: map['coverUrl'] as String?,
    );
  }
}
