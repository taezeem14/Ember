"""
utils.py
Small helpers with no dependencies on the rest of the package.

# Extended/upgraded by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

import re
from typing import Any, Optional

from PyQt6.QtCore import Qt
from PyQt6.QtGui import QFontMetrics
from PyQt6.QtWidgets import QLabel


def clock(ms: int) -> str:
    """Milliseconds to a human clock string. Drops the hour field when unused."""
    total = max(0, int(ms or 0)) // 1000
    hours, rest = divmod(total, 3600)
    minutes, seconds = divmod(rest, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes}:{seconds:02d}"


def parse_duration(text: str) -> int:
    """Parse clock format ('M:SS', 'H:MM:SS', or raw seconds) to total seconds."""
    if not text:
        return -1
    raw = str(text).strip()
    if ":" not in raw:
        try:
            return max(-1, int(raw))
        except ValueError:
            return -1
    parts = raw.split(":")
    try:
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
    except (ValueError, TypeError):
        return -1
    return -1


def elide_into(label: QLabel, text: str, width: int) -> None:
    """Write text into a fixed-width label, ellipsised to fit, tooltip full value."""
    label.ensurePolished()
    clean_text = (text or "").replace("\r", "").replace("\n", " ").strip()
    metrics = QFontMetrics(label.font())
    label.setText(metrics.elidedText(clean_text, Qt.TextElideMode.ElideRight, max(24, width)))
    label.setToolTip(clean_text[:1000])


def looks_like_link(text: str) -> bool:
    """True when the field holds something we should hand straight to the resolver."""
    probe = (text or "").strip().lower()
    return (
        probe.startswith("http://")
        or probe.startswith("https://")
        or "youtu.be/" in probe
        or "youtube.com/watch" in probe
        or "youtube.com/embed" in probe
        or "youtube.com/shorts" in probe
    )


_HEX_COLOR_RE = re.compile(r"^#(?:[0-9a-fA-F]{6})$")
_YOUTUBE_ID_RE = re.compile(r"(?:v=|youtu\.be/|embed/|shorts/)([a-zA-Z0-9_-]{11})")


def extract_youtube_id(text: str) -> Optional[str]:
    """Extract an 11-character YouTube video ID from a URL or raw ID."""
    if not text:
        return None
    cleaned = text.strip()
    if len(cleaned) == 11 and re.match(r"^[a-zA-Z0-9_-]{11}$", cleaned):
        return cleaned
    match = _YOUTUBE_ID_RE.search(cleaned)
    return match.group(1) if match else None


def is_valid_hex_color(hex_str: str) -> bool:
    """Validate whether a string is a valid 7-character hex color code (#RRGGBB)."""
    return bool(hex_str and _HEX_COLOR_RE.match(hex_str.strip()))


def as_bool(raw: Any, fallback: bool) -> bool:
    """Safely coerce any setting value to a boolean."""
    if raw is None:
        return fallback
    if isinstance(raw, bool):
        return raw
    text = str(raw).strip().lower()
    if text in {"true", "1", "yes", "on"}:
        return True
    if text in {"false", "0", "no", "off"}:
        return False
    return fallback


def as_int(raw: Any, fallback: int) -> int:
    """Safely coerce any setting value to an integer."""
    try:
        return int(float(raw))
    except (TypeError, ValueError):
        return fallback


def pretty_count(value: int, singular: str, plural: str = "") -> str:
    """'1 track' / '12 tracks' without the caller doing the branch."""
    word = singular if value == 1 else (plural or singular + "s")
    return f"{value} {word}"