"""
stream.py
Resolves a track id (or a pasted link) into a direct HTTPS audio stream with
yt-dlp. Nothing is ever written to disk — we only read the resolved URL.

# Extended/upgraded by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

import html
import logging
import re
import time
from typing import Any, Dict, List, Optional, Tuple

import yt_dlp

from .models import Song

log = logging.getLogger(__name__)

WATCH_URL = "https://www.youtube.com/watch?v={0}"

# Conditions yt-dlp cannot recover from by trying again: the extractor needs an
# authenticated session or video is permanently unavailable.
PERMANENT_FAILURE_MARKERS = (
    "sign in to confirm your age",
    "sign in to confirm you're not a bot",
    "sign in to confirm you’re not a bot",
    "this video is age-restricted",
    "video unavailable",
    "private video",
    "members-only",
    "premieres in",
    "live event will begin in",
    "this live event has ended",
    "who has blocked it on copyright grounds",
    "blocked it on copyright grounds",
    "not available in your country",
    "account associated with this video has been terminated",
    "removed for violating",
    "inappropriate content",
)


def _is_permanent_failure(exc: BaseException) -> bool:
    """True when the extractor error will not resolve on a retry."""
    text = str(exc).lower()
    return any(marker in text for marker in PERMANENT_FAILURE_MARKERS)


def is_url_expired(url: Optional[str], buffer_seconds: int = 90) -> bool:
    """Check if a signed googlevideo streaming URL has expired or is near expiry."""
    if not url:
        return True
    match = re.search(r"[?&]expire=(\d+)", url)
    if match:
        try:
            expire_ts = int(match.group(1))
            return time.time() + buffer_seconds >= expire_ts
        except (ValueError, TypeError):
            pass
    return False


def _safe_float(val: Any) -> float:
    try:
        return float(val) if val is not None else 0.0
    except (ValueError, TypeError):
        return 0.0


BASE_OPTIONS: Dict[str, Any] = {
    # Prefer clean M4A/AAC for Windows Media Foundation stability
    "format": "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio/best",
    "quiet": True,
    "no_warnings": True,
    "noplaylist": True,
    "skip_download": True,
    "retries": 0,
    "socket_timeout": 15,
    "extractor_retries": 0,
    "extractor_args": {
        "youtube": {
            "player_client": ["android", "web"],
        }
    },
}


class StreamResolver:
    """Thin yt-dlp wrapper with retry backoff. Every call is synchronous — jobs run it off-thread."""

    def __init__(self, overrides: Optional[Dict[str, Any]] = None) -> None:
        self.options = dict(BASE_OPTIONS)
        if overrides:
            self.options.update(overrides)

    @staticmethod
    def is_url_expired(url: Optional[str], buffer_seconds: int = 90) -> bool:
        """Check if a signed streaming URL has expired or is near expiry."""
        return is_url_expired(url, buffer_seconds=buffer_seconds)

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
                if _is_permanent_failure(exc):
                    log.warning("stream probe %r blocked permanently: %s", target, exc)
                    raise
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
        try:
            info = self._probe(target)
        except Exception as exc:
            log.error("stream_url failed for %s: %s", video_id, exc)
            return None

        # Unwrap if wrapped inside playlist structure
        if info.get("_type") == "playlist" or "entries" in info:
            entries = info.get("entries")
            if entries:
                first = next((e for e in entries if isinstance(e, dict)), None)
                if first:
                    info = first

        raw_formats: List[Dict[str, Any]] = info.get("formats") or []
        formats: List[Dict[str, Any]] = []
        for fmt in raw_formats:
            acodec = str(fmt.get("acodec") or "").lower()
            url = fmt.get("url")
            protocol = str(fmt.get("protocol") or "").lower()
            if acodec in ("", "none") or not url or "dash" in protocol or "frag" in protocol:
                continue
            formats.append(fmt)

        direct = info.get("url")
        if not formats:
            if direct and isinstance(direct, str):
                return direct
            return None

        def _rank(fmt: Dict[str, Any]) -> Tuple[int, int, float, float]:
            ext = str(fmt.get("ext") or "").lower()
            acodec = str(fmt.get("acodec") or "").lower()
            vcodec = str(fmt.get("vcodec") or "none").lower()
            is_audio_only = vcodec in ("none", "")
            is_mp4 = ext == "m4a" or acodec.startswith("mp4a")
            is_webm = ext == "webm" or acodec.startswith("opus")
            abr = _safe_float(fmt.get("abr"))
            filesize = _safe_float(fmt.get("filesize") or fmt.get("filesize_approx"))

            # Rank:
            # 1. Pure audio (0) before video-with-audio (1)
            # 2. M4A/AAC (0) before other (1), WebM/Opus last (2)
            # 3. Higher bitrate first (-abr)
            # 4. Smallest filesize first if video; normal size first if audio
            return (
                0 if is_audio_only else 1,
                0 if is_mp4 else (2 if is_webm else 1),
                -abr,
                filesize if is_audio_only else -filesize,
            )

        formats.sort(key=_rank)
        return formats[0].get("url")

    def describe(self, url: str) -> Optional[Song]:
        """Turn a pasted link into a Song so it can enter the normal queue."""
        if not url or not url.strip():
            return None
        try:
            info = self._probe(url.strip())
        except Exception as exc:
            log.error("describe failed for %r: %s", url, exc)
            return None

        if info.get("_type") == "playlist" or "entries" in info:
            entries = info.get("entries")
            if entries:
                first = next((e for e in entries if isinstance(e, dict)), None)
                if first:
                    info = first

        video_id = info.get("id")
        if not video_id:
            return None

        raw_title = info.get("title") or "untitled"
        title = html.unescape(str(raw_title))

        raw_artist = info.get("uploader") or info.get("channel") or info.get("uploader_id") or "youtube"
        artist = html.unescape(str(raw_artist))

        duration_str = info.get("duration_string")
        if not duration_str and info.get("duration"):
            try:
                total_sec = int(info["duration"])
                duration_str = f"{total_sec // 60}:{total_sec % 60:02d}"
            except (ValueError, TypeError):
                duration_str = ""

        artwork_url = info.get("thumbnail") or ""
        if not artwork_url and info.get("thumbnails"):
            thumbs = [
                t.get("url")
                for t in info["thumbnails"]
                if isinstance(t, dict) and t.get("url")
            ]
            if thumbs:
                artwork_url = thumbs[-1]

        return Song(
            video_id=str(video_id),
            title=title,
            artist=artist,
            duration=str(duration_str or ""),
            artwork_url=str(artwork_url or ""),
        )