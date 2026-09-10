"""Tests for Song dataclass and serialization."""

from __future__ import annotations

from ember.models import Song


def test_song_properties() -> None:
    song = Song(
        video_id="xyz123",
        title="Midnight City",
        artist="M83",
        duration="4:04",
        artwork_url="https://example.com/art.jpg",
    )
    assert song.key == "xyz123"
    assert song.byline == "M83"
    assert str(song) == "Midnight City — M83"


def test_song_byline_fallback() -> None:
    song = Song(
        video_id="abc999",
        title="No Artist Track",
        artist="",
    )
    assert song.byline == "unknown artist"


def test_song_equality() -> None:
    song1 = Song(video_id="id1", title="Title 1", artist="Artist 1")
    song2 = Song(video_id="id1", title="Title 2", artist="Artist 2")
    song3 = Song(video_id="id2", title="Title 1", artist="Artist 1")

    assert song1.is_same_as(song2)
    assert not song1.is_same_as(song3)
    assert not song1.is_same_as(None)


def test_song_dict_serialization() -> None:
    song = Song(
        video_id="test_id",
        title="Test Song",
        artist="Test Artist",
        duration="3:30",
        artwork_url="http://art.png",
    )
    serialized = song.to_dict()
    assert serialized["video_id"] == "test_id"
    assert serialized["title"] == "Test Song"

    restored = Song.from_dict(serialized)
    assert restored.is_same_as(song)
    assert restored.duration == "3:30"
