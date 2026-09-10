r"""
player.py
PlaybackCore owns the queue, the media player and the thread pool.

Flow for one track:
    play(song)  ->  LoadJob (off-thread stream resolve)  ->  QMediaPlayer.setSource
                \->  RadioJob (off-thread look-alikes)   ->  queue grows behind it
Stream resolution and queue building are two separate jobs so audio starts the
moment the stream is ready instead of waiting on the recommendation call.
"""

from __future__ import annotations

import logging
from typing import List, Optional

from PyQt6.QtCore import QObject, QThreadPool, QUrl, pyqtSignal
from PyQt6.QtMultimedia import QAudioOutput, QMediaPlayer

from .catalog import CatalogSource
from .config import DEFAULT_VOLUME, RADIO_DEPTH, SEEK_MS_BACKSTEP
from .jobs import LinkJob, LoadJob, RadioJob
from .models import Song
from .stream import StreamResolver

log = logging.getLogger(__name__)

MAX_AUTO_SKIP = 3              # consecutive dead tracks before we stop advancing


class PlaybackCore(QObject):
    song_changed = pyqtSignal(object)        # Song now loading / playing
    cursor_changed = pyqtSignal(int)         # index inside the queue
    queue_changed = pyqtSignal(list)         # whole queue replaced or extended
    playing_changed = pyqtSignal(bool)
    progress_changed = pyqtSignal(int)       # ms
    length_changed = pyqtSignal(int)         # ms
    loading_changed = pyqtSignal(bool)
    notice = pyqtSignal(str)                 # short human line for the status chip

    def __init__(self, catalog: CatalogSource, resolver: StreamResolver, parent=None) -> None:
        super().__init__(parent)
        self.catalog = catalog
        self.resolver = resolver

        self.pool = QThreadPool(self)
        self.pool.setMaxThreadCount(6)

        self.player = QMediaPlayer(self)
        self.output = QAudioOutput(self)
        self.player.setAudioOutput(self.output)
        self.output.setVolume(DEFAULT_VOLUME / 100.0)

        self.queue: List[Song] = []
        self.cursor = -1
        self.auto_queue = True

        self._wanted: Optional[str] = None
        self._switching = False
        self._extending = False
        self._advance_after_extend = False
        self._radio_seed: Optional[str] = None
        self._failed_source: Optional[str] = None
        self._error_streak = 0

        self.player.positionChanged.connect(self._relay_progress)
        self.player.durationChanged.connect(self._relay_length)
        self.player.playbackStateChanged.connect(self._relay_state)
        self.player.mediaStatusChanged.connect(self._relay_media_status)
        self.player.errorOccurred.connect(self._relay_error)

    # ------------------------------------------------------------------ state
    @property
    def current(self) -> Optional[Song]:
        if 0 <= self.cursor < len(self.queue):
            return self.queue[self.cursor]
        return None

    def index_of(self, video_id: str) -> int:
        for index, song in enumerate(self.queue):
            if song.video_id == video_id:
                return index
        return -1

    # ------------------------------------------------------------------- queue
    def adopt(self, songs: List[Song], start: int = 0) -> None:
        """Replace the queue wholesale (used for search results) and start playing."""
        if not songs:
            return
        start = max(0, min(start, len(songs) - 1))
        self.queue = list(songs)
        self.cursor = start
        self.queue_changed.emit(self.queue)
        self.cursor_changed.emit(start)
        self.play(self.queue[start], expand=True)

    def play(self, song: Optional[Song], expand: Optional[bool] = None) -> None:
        if song is None:
            return
        if expand is None:
            expand = self.auto_queue

        slot = self.index_of(song.video_id)
        if slot < 0:
            self.queue = [song]
            self.cursor = 0
            self.queue_changed.emit(self.queue)
            self.cursor_changed.emit(0)
        elif slot != self.cursor:
            self.cursor = slot
            self.cursor_changed.emit(slot)

        self._wanted = song.video_id
        self._switching = True
        self.loading_changed.emit(True)
        self.song_changed.emit(song)

        self._start_load(song)
        if expand:
            self._start_radio(song.video_id)

    def play_at(self, index: int) -> None:
        if not 0 <= index < len(self.queue):
            return
        self.cursor = index
        self.cursor_changed.emit(index)
        self.play(self.queue[index], expand=False)

    # --------------------------------------------------------------- transport
    def toggle(self) -> None:
        state = self.player.playbackState()
        if state == QMediaPlayer.PlaybackState.PlayingState:
            self.player.pause()
        elif state == QMediaPlayer.PlaybackState.PausedState:
            self.player.play()
        else:
            current = self.current
            if current is not None:
                self.play(current, expand=False)
            elif self.queue:
                self.play_at(0)

    def forward(self) -> None:
        if self.cursor + 1 < len(self.queue):
            self.play_at(self.cursor + 1)
            return
        if not self.queue or self._extending:
            return

        # Tail of the queue: ask the recommendation graph for more, then advance.
        self._extending = True
        self._advance_after_extend = True
        self.notice.emit("finding more like this")
        self._start_radio(self.queue[-1].video_id, force=True)

    def back(self) -> None:
        if self.player.position() > SEEK_MS_BACKSTEP:
            self.player.setPosition(0)
            return
        if self.cursor > 0:
            self.play_at(self.cursor - 1)
        else:
            self.player.setPosition(0)

    def seek(self, position_ms: int) -> None:
        self.player.setPosition(max(0, int(position_ms)))

    def set_volume(self, percent: int) -> None:
        clamped = max(0, min(100, int(percent)))
        self.output.setVolume(clamped / 100.0)

    def volume(self) -> int:
        return int(round(self.output.volume() * 100))

    def set_auto_queue(self, enabled: bool) -> None:
        self.auto_queue = bool(enabled)

    # ------------------------------------------------------------- entry points
    def open_link(self, url: str) -> None:
        """Resolve a pasted URL into a Song, then play it like anything else."""
        self.notice.emit("reading that link")
        job = LinkJob(self.resolver, url)
        job.signals.ready.connect(self._on_link_song)
        job.signals.failed.connect(self._on_link_failed)
        self.pool.start(job)

    # ------------------------------------------------------------------ loading
    def _start_load(self, song: Song) -> None:
        job = LoadJob(song, self.resolver)
        job.signals.ready.connect(self._on_stream_ready)
        job.signals.failed.connect(self._on_stream_failed)
        self.pool.start(job)

    def _start_radio(self, seed_id: str, force: bool = False) -> None:
        if not force and self._radio_seed == seed_id:
            return
        self._radio_seed = seed_id
        job = RadioJob(self.catalog, seed_id, RADIO_DEPTH)
        job.signals.ready.connect(self._on_radio_ready)
        job.signals.failed.connect(self._on_radio_failed)
        self.pool.start(job)

    # ------------------------------------------------------------------- slots
    def _on_stream_ready(self, song: Song, url: str) -> None:
        if song.video_id != self._wanted:
            return                       # the user already moved on
        song.stream_url = url
        self._failed_source = None
        self._error_streak = 0
        self.player.setSource(QUrl(url))
        self.player.play()
        self._switching = False
        self.loading_changed.emit(False)

    def _on_stream_failed(self, song: Song, message: str) -> None:
        if song.video_id != self._wanted:
            return
        self._switching = False
        self.loading_changed.emit(False)
        self.notice.emit("couldn't pull that track")
        log.warning("playback aborted for %s: %s", song.video_id, message)

    def _on_radio_ready(self, seed_id: str, songs: list) -> None:
        self._extending = False
        current = self.current
        if current is None or current.video_id != seed_id or not songs:
            self._advance_after_extend = False
            return

        known = {song.video_id for song in self.queue}
        fresh = [song for song in songs if song.video_id not in known]
        if fresh:
            self.queue.extend(fresh)
            self.queue_changed.emit(self.queue)

        if self._advance_after_extend:
            self._advance_after_extend = False
            if self.cursor + 1 < len(self.queue):
                self.play_at(self.cursor + 1)

    def _on_radio_failed(self, seed_id: str, message: str) -> None:
        self._extending = False
        self._advance_after_extend = False
        log.debug("radio unavailable for %s: %s", seed_id, message)

    def _on_link_song(self, song: Song) -> None:
        self.adopt([song], 0)

    def _on_link_failed(self, message: str) -> None:
        self.notice.emit("that link didn't work")
        log.warning("link playback failed: %s", message)

    # ------------------------------------------------------------ media relays
    def _relay_progress(self, position_ms: int) -> None:
        self.progress_changed.emit(int(position_ms))

    def _relay_length(self, duration_ms: int) -> None:
        self.length_changed.emit(int(duration_ms))

    def _relay_state(self, state: QMediaPlayer.PlaybackState) -> None:
        self.playing_changed.emit(state == QMediaPlayer.PlaybackState.PlayingState)

    def _relay_media_status(self, status: QMediaPlayer.MediaStatus) -> None:
        if status == QMediaPlayer.MediaStatus.EndOfMedia and not self._switching:
            log.debug("track finished — rolling into the next one")
            self.forward()

    def _relay_error(self, error: QMediaPlayer.Error, message: str) -> None:
        source = self.player.source().toString()
        if source and source == self._failed_source:
            return                       # backend is retry-looping on a dead source
        self._failed_source = source
        log.warning("media player error (%s): %s", error, message)

        self.player.stop()
        self.loading_changed.emit(False)
        self._switching = False

        self._error_streak += 1
        if self._error_streak <= MAX_AUTO_SKIP and self.cursor + 1 < len(self.queue):
            self.notice.emit("skipping a dead track")
            self.forward()
            return

        self._error_streak = 0
        if self.queue:
            self.notice.emit("playback hiccup")