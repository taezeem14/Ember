"""Tests for PlaybackCore queue management, pruning, and recommendation validation."""

from __future__ import annotations

import sys
from unittest.mock import MagicMock
from PyQt6.QtWidgets import QApplication

from ember.models import Song
from ember.player import MAX_QUEUE_SIZE, PlaybackCore


def _get_qapp() -> QApplication:
    app = QApplication.instance()
    if app is None:
        app = QApplication(sys.argv)
    return app


def _create_core() -> PlaybackCore:
    _get_qapp()
    mock_catalog = MagicMock()
    mock_resolver = MagicMock()
    core = PlaybackCore(catalog=mock_catalog, resolver=mock_resolver)
    core._start_load = MagicMock()  # type: ignore[method-assign]
    core._start_radio = MagicMock()  # type: ignore[method-assign]
    return core


def test_playback_core_radio_seed_validation_outdated_seed() -> None:
    core = _create_core()
    core.queue = [Song(video_id="song_A", title="Song A", artist="Artist A")]
    core.cursor = 0
    core._radio_seed = "song_B"
    core._advance_after_extend = True

    fresh_songs = [Song(video_id="rec_1", title="Rec 1", artist="Artist")]
    core._on_radio_ready("song_A", fresh_songs)

    assert len(core.queue) == 1
    assert core.queue[0].video_id == "song_A"
    assert not core._advance_after_extend


def test_playback_core_radio_seed_validation_current_mismatch() -> None:
    core = _create_core()
    core.queue = [
        Song(video_id="song_1", title="Song 1", artist="Artist"),
        Song(video_id="song_2", title="Song 2", artist="Artist"),
    ]
    core.cursor = 1
    core._radio_seed = "song_1"

    fresh_songs = [Song(video_id="rec_1", title="Rec 1", artist="Artist")]
    core._on_radio_ready("song_1", fresh_songs)

    assert len(core.queue) == 2


def test_playback_core_max_queue_size_pruning() -> None:
    core = _create_core()
    core.queue = [
        Song(video_id=f"track_{i}", title=f"Track {i}", artist="Artist")
        for i in range(195)
    ]
    core.cursor = 50
    core._radio_seed = "track_50"

    cursor_changed_events: list[int] = []
    core.cursor_changed.connect(lambda c: cursor_changed_events.append(c))

    fresh_songs = [
        Song(video_id=f"new_{i}", title=f"New {i}", artist="Artist")
        for i in range(15)
    ]
    core._on_radio_ready("track_50", fresh_songs)

    assert len(core.queue) == 165
    assert core.cursor == 5
    assert cursor_changed_events == [5]
    assert core.current is not None
    assert core.current.video_id == "track_50"


def test_playback_core_queue_pruning_skipped_when_cursor_low() -> None:
    core = _create_core()
    core.queue = [
        Song(video_id=f"track_{i}", title=f"Track {i}", artist="Artist")
        for i in range(195)
    ]
    core.cursor = 8
    core._radio_seed = "track_8"

    fresh_songs = [
        Song(video_id=f"new_{i}", title=f"New {i}", artist="Artist")
        for i in range(15)
    ]
    core._on_radio_ready("track_8", fresh_songs)

    assert len(core.queue) == 210
    assert core.cursor == 8
