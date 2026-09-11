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


def test_get_favorite_ids() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_file = Path(tmp_dir) / "test.db"
        storage = EmberStorage(db_file)

        assert storage.get_favorite_ids() == set()
        storage.add_favorite(Song(video_id="id1", title="Song 1", artist="Artist 1"))
        storage.add_favorite(Song(video_id="id2", title="Song 2", artist="Artist 2"))
        assert storage.get_favorite_ids() == {"id1", "id2"}
        storage.remove_favorite("id1")
        assert storage.get_favorite_ids() == {"id2"}


def test_remove_history_item() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_file = Path(tmp_dir) / "test.db"
        storage = EmberStorage(db_file)

        storage.record_history(Song(video_id="h1", title="Track 1", artist="Artist 1"))
        storage.record_history(Song(video_id="h2", title="Track 2", artist="Artist 2"))
        assert len(storage.get_history()) == 2

        assert storage.remove_history("h1")
        history = storage.get_history()
        assert len(history) == 1
        assert history[0].video_id == "h2"


def test_export_import_favorites_json() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_file = Path(tmp_dir) / "test.db"
        storage = EmberStorage(db_file)

        storage.add_favorite(Song(video_id="v1", title="Song 1", artist="Artist 1", duration="3:30"))
        storage.add_favorite(Song(video_id="v2", title="Song 2", artist="Artist 2", duration="4:15"))

        json_export = storage.export_favorites_json()
        assert "v1" in json_export
        assert "Song 1" in json_export

        # Fresh database importing the exported JSON
        db2 = Path(tmp_dir) / "test2.db"
        storage2 = EmberStorage(db2)
        count = storage2.import_favorites_json(json_export)
        assert count == 2
        assert storage2.is_favorite("v1")
        assert storage2.is_favorite("v2")

        # Importing invalid JSON handles gracefully
        assert storage2.import_favorites_json("invalid json string") == 0


def test_export_favorites_m3u() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        db_file = Path(tmp_dir) / "test.db"
        storage = EmberStorage(db_file)

        storage.add_favorite(Song(video_id="abc1234", title="Nightcall", artist="Kavinsky", duration="4:19"))

        m3u = storage.export_favorites_m3u()
        assert m3u.startswith("#EXTM3U\n")
        assert "#EXTINF:259,Kavinsky - Nightcall" in m3u
        assert "https://www.youtube.com/watch?v=abc1234" in m3u
