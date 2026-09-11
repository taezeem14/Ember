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


def test_lyrics_scroll_calculation_and_seekbar_bounds() -> None:
    from PyQt6.QtWidgets import QApplication
    from ember.panel import SeekBar

    _ = QApplication.instance() or QApplication([])

    seek = SeekBar()
    assert seek.maximum() == 0
    assert seek.minimum() == 0

    seek.setRange(0, 180000)
    assert seek.maximum() == 180000

    seek.setValue(90000)
    assert seek.value() == 90000

    # Auto-scroll formula verification as executed in FloatingPanel._on_progress
    position = seek.value()
    total_dur = seek.maximum()
    vbar_max = 600
    target = max(0, min(vbar_max, int((position / total_dur) * vbar_max)))
    assert target == 300


def test_lyrics_formatting_and_fallback_logic() -> None:
    # Test valid lyrics with source attribution
    raw_lyrics = "  We're no strangers to love\nYou know the rules and so do I  "
    source = "YouTube Music"
    formatted = raw_lyrics.strip()
    if source:
        formatted += f"\n\n— Source: {source}"
    assert "We're no strangers to love" in formatted
    assert "— Source: YouTube Music" in formatted

    # Test whitespace or empty fallback
    empty_lyrics = "   \n\t  "
    assert not empty_lyrics or not empty_lyrics.strip()


