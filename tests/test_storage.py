"""Tests for SQLite-backed persistent storage."""

from __future__ import annotations

import tempfile
from pathlib import Path

from ember.models import Song
from ember.storage import EmberStorage


def test_favorites_crud() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_file = Path(tmp_dir) / "test.db"
        storage = EmberStorage(db_file)

        song = Song(
            video_id="fav123",
            title="Starboy",
            artist="The Weeknd",
            duration="3:50",
            artwork_url="http://art.url",
        )

        assert not storage.is_favorite("fav123")
        storage.add_favorite(song)
        assert storage.is_favorite("fav123")

        favs = storage.get_favorites()
        assert len(favs) == 1
        assert favs[0].video_id == "fav123"
        assert favs[0].title == "Starboy"

        storage.remove_favorite("fav123")
        assert not storage.is_favorite("fav123")
        assert len(storage.get_favorites()) == 0


def test_history_tracking() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_file = Path(tmp_dir) / "test.db"
        storage = EmberStorage(db_file)

        song1 = Song(video_id="h1", title="Track 1", artist="Artist 1")
        song2 = Song(video_id="h2", title="Track 2", artist="Artist 2")

        storage.record_history(song1)
        storage.record_history(song2)

        history = storage.get_history()
        assert len(history) == 2
        # Most recent first
        assert history[0].video_id == "h2"
        assert history[1].video_id == "h1"

        storage.clear_history()
        assert len(storage.get_history()) == 0
