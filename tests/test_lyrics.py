"""Tests for LyricsJob and CatalogSource.lyrics."""

from __future__ import annotations

from unittest.mock import MagicMock, patch
from ember.catalog import CatalogSource
from ember.jobs import LyricsJob


def test_lyrics_job_signals() -> None:
    catalog = MagicMock(spec=CatalogSource)
    job = LyricsJob(catalog, "test_vid")
    assert hasattr(job.signals, "done")
    assert hasattr(job.signals, "failed")


def test_lyrics_job_success_emission() -> None:
    catalog = MagicMock(spec=CatalogSource)
    catalog.lyrics.return_value = "Hello from the other side\nI must have called a thousand times"

    done_events: list[tuple[str, str]] = []
    failed_events: list[tuple[str, str]] = []

    job = LyricsJob(catalog, "test_vid")
    job.signals.done.connect(lambda vid, text: done_events.append((vid, text)))
    job.signals.failed.connect(lambda vid, err: failed_events.append((vid, err)))

    job.run()

    assert len(done_events) == 1
    assert done_events[0][0] == "test_vid"
    assert "Hello from the other side" in done_events[0][1]
    assert len(failed_events) == 0


def test_lyrics_job_none_fallback_emission() -> None:
    catalog = MagicMock(spec=CatalogSource)
    catalog.lyrics.return_value = None

    done_events: list[tuple[str, str]] = []
    failed_events: list[tuple[str, str]] = []

    job = LyricsJob(catalog, "test_vid_instrumental")
    job.signals.done.connect(lambda vid, text: done_events.append((vid, text)))
    job.signals.failed.connect(lambda vid, err: failed_events.append((vid, err)))

    job.run()

    assert len(done_events) == 0
    assert len(failed_events) == 1
    assert failed_events[0][0] == "test_vid_instrumental"
    assert "No lyrics found" in failed_events[0][1]
