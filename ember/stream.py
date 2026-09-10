"""
stream.py
Resolves a track id (or a pasted link) into a direct HTTPS audio stream with
yt-dlp. Nothing is ever written to disk — we only read the resolved URL.
"""

from __future__ import annotations

import logging
from typing import Optional

import yt_dlp

from .models import Song

log = logging.getLogger(__name__)

WATCH_URL = "https://www.youtube.com/watch?v={0}"

BASE_OPTIONS = {
    # M4A first. Windows Media Foundation — the backend QMediaPlayer uses on
    # Windows — cannot demux WebM/Opus past the opening cluster, which is what
    # cuts playback off around the two-minute mark. AAC in an MP4 container it
    # handles cleanly.
    "format": "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio/best",
    "quiet": True,
    "no_warnings": True,
    "noplaylist": True,
    "skip_download": True,
    "retries": 3,
    "socket_timeout": 20,
    "extractor_retries": 3,
}


class StreamResolver:
    """Thin yt-dlp wrapper. Every call is synchronous — jobs run it off-thread."""

    def __init__(self, overrides: Optional[dict] = None) -> None:
        self.options = dict(BASE_OPTIONS)
        if overrides:
            self.options.update(overrides)

    def _probe(self, target: str) -> dict:
        with yt_dlp.YoutubeDL(self.options) as ydl:
            return ydl.extract_info(target, download=False)

    def stream_url(self, video_id: str) -> Optional[str]:
        """Direct audio URL for a track id, or None when nothing playable exists."""
        info = self._probe(WATCH_URL.format(video_id))
        direct = info.get("url")
        if direct:
            return direct
        formats = [
            fmt
            for fmt in (info.get("formats") or [])
            if fmt.get("acodec") not in (None, "none") and fmt.get("url")
        ]
        # Same reason as BASE_OPTIONS: an MP4 container is the one Windows can
        # seek inside. WebM is a fallback, not a first choice.
        formats.sort(key=lambda fmt: fmt.get("ext") != "m4a")
        return formats[0]["url"] if formats else None

    def describe(self, url: str) -> Optional[Song]:
        """Turn a pasted link into a Song so it can enter the normal queue."""
        info = self._probe(url)
        video_id = info.get("id")
        if not video_id:
            return None
        return Song(
            video_id=video_id,
            title=info.get("title") or "untitled",
            artist=info.get("uploader") or info.get("channel") or "youtube",
            duration=info.get("duration_string") or "",
            artwork_url=info.get("thumbnail") or "",
        )