"""
stream.py
Resolves a track id (or a pasted link) into a direct HTTPS audio stream with
yt-dlp. Nothing is ever written to disk — we only read the resolved URL.

# Extended/upgraded by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

import logging
import time
from typing import Any, Dict, List, Optional

import yt_dlp

from .models import Song

log = logging.getLogger(__name__)

WATCH_URL = "https://www.youtube.com/watch?v={0}"

BASE_OPTIONS: Dict[str, Any] = {
    # M4A first. Windows Media Foundation — the backend QMediaPlayer uses on
    # Windows — cannot demux WebM/Opus past the opening cluster, which is what
    # cuts playback off around the two-minute mark. AAC in an MP4 container it
    # handles cleanly.
    "format": "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio/best",
    "quiet": True,
    "no_warnings": True,
    "noplaylist": True,
    "skip_download": True,
    "retries": 4,
    "socket_timeout": 15,
    "extractor_retries": 4,
}


class StreamResolver:
    """Thin yt-dlp wrapper with retry backoff. Every call is synchronous — jobs run it off-thread."""

    def __init__(self, overrides: Optional[Dict[str, Any]] = None) -> None:
        self.options = dict(BASE_OPTIONS)
        if overrides:
            self.options.update(overrides)

    def _probe(self, target: str, max_attempts: int = 3) -> Dict[str, Any]:
        """Extract info from yt-dlp with retries and exponential backoff."""
        last_exc: Optional[Exception] = None
        for attempt in range(1, max_attempts + 1):
            try:
                with yt_dlp.YoutubeDL(self.options) as ydl:
                    data = ydl.extract_info(target, download=False)
                    if isinstance(data, dict):
                        return data
                    raise RuntimeError("unexpected response structure from extractor")
            except Exception as exc:
                last_exc = exc
                if attempt < max_attempts:
                    sleep_sec = 0.5 * (2 ** (attempt - 1))
                    log.warning(
                        "stream probe %r attempt %d/%d failed: %s. Retrying in %.1fs...",
                        target,
                        attempt,
                        max_attempts,
                        exc,
                        sleep_sec,
                    )
                    time.sleep(sleep_sec)
                else:
                    log.error("stream probe %r failed after %d attempts: %s", target, max_attempts, exc)
        if last_exc is not None:
            raise last_exc
        return {}

    def stream_url(self, video_id: str) -> Optional[str]:
        """Direct audio URL for a track id, or None when nothing playable exists."""
        if not video_id:
            return None
        target = WATCH_URL.format(video_id)
        info = self._probe(target)
        direct = info.get("url")
        if direct and isinstance(direct, str):
            return direct

        raw_formats: List[Dict[str, Any]] = info.get("formats") or []
        formats = [
            fmt
            for fmt in raw_formats
            if fmt.get("acodec") not in (None, "none") and fmt.get("url")
        ]
        if not formats:
            return None

        # Prioritize m4a/mp4 containers for Windows Media Foundation compatibility
        formats.sort(
            key=lambda fmt: (
                fmt.get("ext") != "m4a",
                not str(fmt.get("acodec", "")).startswith("mp4a"),
                -(fmt.get("abr") or 0),
            )
        )
        return formats[0]["url"]

    def describe(self, url: str) -> Optional[Song]:
        """Turn a pasted link into a Song so it can enter the normal queue."""
        if not url or not url.strip():
            return None
        info = self._probe(url.strip())
        video_id = info.get("id")
        if not video_id:
            return None
        return Song(
            video_id=str(video_id),
            title=str(info.get("title") or "untitled"),
            artist=str(info.get("uploader") or info.get("channel") or "youtube"),
            duration=str(info.get("duration_string") or ""),
            artwork_url=str(info.get("thumbnail") or ""),
        )