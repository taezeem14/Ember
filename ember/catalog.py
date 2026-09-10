"""
catalog.py
Read-only access to the public YouTube Music catalogue: free-text search and
the "watch playlist" recommendation graph used to keep playback endless.
"""

from __future__ import annotations

import logging
from typing import List, Optional

from ytmusicapi import YTMusic

from .models import Song

log = logging.getLogger(__name__)


def _artist_line(item: dict) -> str:
    raw = item.get("artists") or item.get("author") or []
    if isinstance(raw, dict):
        raw = [raw]
    if isinstance(raw, list):
        names = [entry.get("name") for entry in raw if isinstance(entry, dict) and entry.get("name")]
        if names:
            return ", ".join(names)
    if isinstance(raw, str) and raw.strip():
        return raw.strip()
    return "unknown artist"


def _artwork_url(item: dict) -> str:
    raw = item.get("thumbnails") or item.get("thumbnail") or []
    if isinstance(raw, dict):
        raw = [raw]
    if isinstance(raw, list) and raw:
        tail = raw[-1]
        if isinstance(tail, dict):
            return tail.get("url") or ""
    return ""


class CatalogSource:
    """Wraps the guest (no-login) YouTube Music client."""

    def __init__(self) -> None:
        self.api = YTMusic()
        log.info("catalogue client ready")

    # ------------------------------------------------------------------ reads
    def search(self, query: str, limit: int = 12) -> List[Song]:
        """Free-text song search. Raises on transport failure so the UI can say so."""
        query = (query or "").strip()
        if not query:
            return []

        found: List[Song] = []
        for item in self.api.search(query, filter="songs", limit=limit):
            song = self._build(item, duration_key="duration")
            if song is not None:
                found.append(song)
        log.info("search %r -> %d track(s)", query, len(found))
        return found

    def similar(self, seed_id: str, limit: int = 26) -> List[Song]:
        """Tracks the recommendation graph puts next to `seed_id`. Best effort."""
        related: List[Song] = []
        seen = {seed_id}
        try:
            watch = self.api.get_watch_playlist(videoId=seed_id, limit=limit)
        except Exception as exc:                      # noqa: BLE001 - network surface
            log.debug("radio lookup failed for %s: %s", seed_id, exc)
            return related

        for item in watch.get("tracks") or []:
            song = self._build(item, duration_key="length")
            if song is None or song.video_id in seen:
                continue
            seen.add(song.video_id)
            related.append(song)
        log.debug("radio for %s -> %d track(s)", seed_id, len(related))
        return related

    # ----------------------------------------------------------------- parsing
    @staticmethod
    def _build(item: dict, duration_key: str = "duration") -> Optional[Song]:
        if not isinstance(item, dict):
            return None
        video_id = item.get("videoId")
        if not video_id:
            return None
        duration = item.get(duration_key) or ""
        return Song(
            video_id=video_id,
            title=item.get("title") or "untitled",
            artist=_artist_line(item),
            duration=str(duration),
            artwork_url=_artwork_url(item),
        )