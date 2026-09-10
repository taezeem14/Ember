"""Data shapes shared across Ember."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional


@dataclass
class Song:
    """One playable track and the metadata needed to draw it."""

    video_id: str
    title: str
    artist: str
    duration: str = ""
    artwork_url: str = ""
    stream_url: Optional[str] = None

    @property
    def key(self) -> str:
        return self.video_id

    @property
    def byline(self) -> str:
        return self.artist or "unknown artist"

    def is_same_as(self, other: Optional["Song"]) -> bool:
        return other is not None and other.video_id == self.video_id

    def __str__(self) -> str:  # handy in logs
        return f"{self.title} — {self.byline}"