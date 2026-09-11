"""Tests for LyricsJob and CatalogSource.lyrics."""

from __future__ import annotations

from unittest.mock import MagicMock, patch
from ember.catalog import CatalogSource
from ember.jobs import LyricsJob


def test_lyrics_job_signals() -> None:
    catalog = MagicMock(spec=CatalogSource)
    job = LyricsJob(catalog, "test_vid")
    assert hasattr(job.signals, "done")
    assert hasattr(job.signals, "ready")
    assert hasattr(job.signals, "lyrics_ready")
    assert hasattr(job.signals, "failed")
    assert hasattr(job.signals, "lyrics_failed")


def test_lyrics_job_success_emission() -> None:
    catalog = MagicMock(spec=CatalogSource)
    catalog.lyrics.return_value = "Hello from the other side\nI must have called a thousand times"

    done_events: list[tuple[str, str]] = []
    ready_events: list[tuple[str, str, str]] = []
    failed_events: list[tuple[str, str]] = []

    job = LyricsJob(catalog, "test_vid")
    job.signals.done.connect(lambda vid, text: done_events.append((vid, text)))
    job.signals.lyrics_ready.connect(lambda vid, text, src: ready_events.append((vid, text, src)))
    job.signals.failed.connect(lambda vid, err: failed_events.append((vid, err)))

    job.run()

    assert len(done_events) == 1
    assert done_events[0][0] == "test_vid"
    assert "Hello from the other side" in done_events[0][1]

    assert len(ready_events) == 1
    assert ready_events[0][0] == "test_vid"
    assert "Hello from the other side" in ready_events[0][1]
    assert len(failed_events) == 0


def test_lyrics_job_none_fallback_emission() -> None:
    catalog = MagicMock(spec=CatalogSource)
    catalog.lyrics.return_value = None

    done_events: list[tuple[str, str]] = []
    failed_events: list[tuple[str, str]] = []
    lyrics_failed_events: list[tuple[str, str]] = []

    job = LyricsJob(catalog, "test_vid_instrumental")
    job.signals.done.connect(lambda vid, text: done_events.append((vid, text)))
    job.signals.failed.connect(lambda vid, err: failed_events.append((vid, err)))
    job.signals.lyrics_failed.connect(lambda vid, err: lyrics_failed_events.append((vid, err)))

    job.run()

    assert len(done_events) == 0
    assert len(failed_events) == 1
    assert failed_events[0][0] == "test_vid_instrumental"
    assert "No lyrics found" in failed_events[0][1]
    assert len(lyrics_failed_events) == 1
    assert lyrics_failed_events[0][0] == "test_vid_instrumental"


def test_lyrics_panel_integration_and_progress_scroll() -> None:
    from PyQt6.QtWidgets import QApplication
    from ember.models import Song
    from ember.panel import FloatingPanel
    from ember.player import PlaybackCore
    from ember.stream import StreamResolver

    _ = QApplication.instance() or QApplication([])

    catalog = MagicMock(spec=CatalogSource)
    resolver = MagicMock(spec=StreamResolver)
    core = PlaybackCore(catalog, resolver)
    panel = FloatingPanel(core, None)

    song = Song("vid_test", "Test Title", "Test Artist")
    core.queue = [song]
    core.cursor = 0

    # Switch to lyrics tab
    panel._switch_tab("lyrics")
    assert panel._active_tab == "lyrics"

    # Call _on_progress while on lyrics tab
    panel.seek.setRange(0, 180000)
    panel._on_progress(45000)
    assert panel.seek.value() == 45000

    # Lyrics ready arrival
    panel._on_lyrics_ready("vid_test", "First line\nSecond line\nThird line")
    assert "First line" in panel.lyrics_text.text()

    # Progress update with visible lyrics
    panel.lyrics_scroll.setVisible(True)
    panel._on_progress(90000)
    assert panel.seek.value() == 90000

    # Lyrics failed arrival
    panel._on_lyrics_failed("vid_test", "error")
    assert "Instrumental / No lyrics available" in panel.lyrics_text.text()

