"""
jobs.py
Every blocking operation Ember performs, wrapped as a QRunnable so it can run
on the thread pool. Each job owns a tiny QObject that carries its signals —
QRunnable itself cannot declare them.

# Extended/upgraded by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

import logging
from typing import Any, List, Optional

import requests
from PyQt6.QtCore import QObject, QRunnable, pyqtSignal

from .catalog import CatalogSource
from .models import Song
from .stream import StreamResolver

log = logging.getLogger(__name__)


class _Signals(QObject):
    """Base carrier so each job subclass only declares what it needs."""


# --------------------------------------------------------------------- search
class SearchSignals(_Signals):
    done = pyqtSignal(str, list)
    failed = pyqtSignal(str, str)


class SearchJob(QRunnable):
    """Off-thread catalogue search job."""

    def __init__(self, catalog: CatalogSource, query: str, limit: int = 12, category: str = "songs") -> None:
        super().__init__()
        self.catalog = catalog
        self.query = query
        self.limit = limit
        self.category = category
        self.signals = SearchSignals()
        self.setAutoDelete(True)
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    def run(self) -> None:
        if self._cancelled:
            return
        try:
            results = self.catalog.search(self.query, limit=self.limit, category=self.category)
            if self._cancelled:
                return
            self.signals.done.emit(self.query, results)
        except Exception as exc:  # noqa: BLE001 - network surface
            if self._cancelled:
                return
            log.warning("search job failed for %r: %s", self.query, exc)
            self.signals.failed.emit(self.query, str(exc))


# ---------------------------------------------------------------------- radio
class RadioSignals(_Signals):
    ready = pyqtSignal(str, list)
    failed = pyqtSignal(str, str)


class RadioJob(QRunnable):
    """Off-thread recommendation graph expansion job."""

    def __init__(self, catalog: CatalogSource, seed_id: str, limit: int = 26) -> None:
        super().__init__()
        self.catalog = catalog
        self.seed_id = seed_id
        self.limit = limit
        self.signals = RadioSignals()
        self.setAutoDelete(True)
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    def run(self) -> None:
        if self._cancelled:
            return
        try:
            recommendations = self.catalog.similar(self.seed_id, self.limit)
            if self._cancelled:
                return
            self.signals.ready.emit(self.seed_id, recommendations)
        except Exception as exc:  # noqa: BLE001
            if self._cancelled:
                return
            log.debug("radio job failed for %s: %s", self.seed_id, exc)
            self.signals.failed.emit(self.seed_id, str(exc))


# ----------------------------------------------------------------------- load
class LoadSignals(_Signals):
    ready = pyqtSignal(object, str)
    failed = pyqtSignal(object, str)


class LoadJob(QRunnable):
    """Resolve the audio stream for one song. Emits the Song back with its URL."""

    def __init__(self, song: Song, resolver: StreamResolver) -> None:
        super().__init__()
        self.song = song
        self.resolver = resolver
        self.signals = LoadSignals()
        self.setAutoDelete(True)
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    def run(self) -> None:
        if self._cancelled:
            return
        try:
            url = self.resolver.stream_url(self.song.video_id)
            if self._cancelled:
                return
            if not url:
                raise RuntimeError("no playable audio stream was returned")
            self.signals.ready.emit(self.song, url)
        except Exception as exc:  # noqa: BLE001 - network surface
            if self._cancelled:
                return
            log.warning("stream resolve failed for %s: %s", self.song.video_id, exc)
            self.signals.failed.emit(self.song, str(exc))


# ------------------------------------------------------------------ pasted url
class LinkSignals(_Signals):
    ready = pyqtSignal(object)
    failed = pyqtSignal(str)


class LinkJob(QRunnable):
    """Turn an arbitrary video/song URL into a playable Song dataclass."""

    def __init__(self, resolver: StreamResolver, url: str) -> None:
        super().__init__()
        self.resolver = resolver
        self.url = url
        self.signals = LinkSignals()
        self.setAutoDelete(True)
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    def run(self) -> None:
        if self._cancelled:
            return
        try:
            song = self.resolver.describe(self.url)
            if self._cancelled:
                return
            if song is None:
                raise RuntimeError("that link did not resolve to a track")
            self.signals.ready.emit(song)
        except Exception as exc:  # noqa: BLE001
            if self._cancelled:
                return
            log.warning("link resolve failed for %r: %s", self.url, exc)
            self.signals.failed.emit(str(exc))


# -------------------------------------------------------------------- artwork
class ArtSignals(_Signals):
    arrived = pyqtSignal(str, bytes)
    failed = pyqtSignal(str, str)


class ArtJob(QRunnable):
    """Best-effort cover art download with timeout guards."""

    def __init__(self, song_id: str, url: str, timeout: float = 6.0) -> None:
        super().__init__()
        self.song_id = song_id
        self.url = url
        self.timeout = timeout
        self.signals = ArtSignals()
        self.setAutoDelete(True)
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    def run(self) -> None:
        if self._cancelled:
            return
        try:
            with requests.get(self.url, timeout=self.timeout) as response:
                if self._cancelled:
                    return
                if response.status_code == 200 and response.content:
                    self.signals.arrived.emit(self.song_id, response.content)
                else:
                    self.signals.failed.emit(self.song_id, f"HTTP {response.status_code}")
        except Exception as exc:  # noqa: BLE001
            if self._cancelled:
                return
            log.debug("artwork fetch failed for %s: %s", self.song_id, exc)
            self.signals.failed.emit(self.song_id, str(exc))


# --------------------------------------------------------------------- lyrics
class LyricsSignals(_Signals):
    done = pyqtSignal(str, str)
    ready = pyqtSignal(str, str)
    lyrics_ready = pyqtSignal(str, str, str)
    failed = pyqtSignal(str, str)
    lyrics_failed = pyqtSignal(str, str)


class LyricsJob(QRunnable):
    """Off-thread lyrics fetch job."""

    def __init__(self, catalog: CatalogSource, video_id: str) -> None:
        super().__init__()
        self.catalog = catalog
        self.video_id = video_id
        self.signals = LyricsSignals()
        self.setAutoDelete(True)
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True

    def run(self) -> None:
        if self._cancelled:
            return
        try:
            text = self.catalog.lyrics(self.video_id)
            if self._cancelled:
                return
            if text:
                self.signals.done.emit(self.video_id, text)
                self.signals.ready.emit(self.video_id, text)
                self.signals.lyrics_ready.emit(self.video_id, text, "")
            else:
                self.signals.failed.emit(self.video_id, "No lyrics found for this track")
                self.signals.lyrics_failed.emit(self.video_id, "No lyrics found for this track")
        except Exception as exc:  # noqa: BLE001
            if self._cancelled:
                return
            log.warning("lyrics job failed for %s: %s", self.video_id, exc)
            self.signals.failed.emit(self.video_id, str(exc))
            self.signals.lyrics_failed.emit(self.video_id, str(exc))