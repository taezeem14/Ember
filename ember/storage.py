"""
storage.py
SQLite-backed persistent storage for local favorites and playback history.

Zero external dependencies (uses Python standard library sqlite3). Atomic,
concurrently safe for desktop reads/writes, and scales effortlessly.

# Written by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

import logging
import sqlite3
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Generator, List, Optional

from .models import Song
from .utils import extract_youtube_id, parse_duration

log = logging.getLogger(__name__)

DB_FILENAME = "ember.db"


class EmberStorage:
    """Manages SQLite database for user favorites, search history, and playback history."""

    def __init__(self, db_path: Path | str) -> None:
        self.db_path = Path(db_path)
        self._lock = threading.RLock()
        self._ensure_tables()

    @contextmanager
    def _connection(self) -> Generator[sqlite3.Connection, None, None]:
        """Context manager guaranteeing connection closure, rollback, and thread safety."""
        with self._lock:
            conn = sqlite3.connect(str(self.db_path), timeout=15.0)
            conn.row_factory = sqlite3.Row
            try:
                yield conn
            except Exception:
                try:
                    conn.rollback()
                except Exception:
                    pass
                raise
            finally:
                conn.close()

    def close(self) -> None:
        """Explicit cleanup hook for application shutdown: checkpoints WAL."""
        with self._lock:
            try:
                with self._connection() as conn:
                    conn.execute("PRAGMA wal_checkpoint(TRUNCATE);")
                    conn.commit()
                log.info("Ember storage closed cleanly with WAL checkpoint")
            except Exception as exc:
                log.debug("WAL checkpoint on close exception: %s", exc)

    def _ensure_tables(self) -> None:
        """Initialize database tables and indexes."""
        try:
            self.db_path.parent.mkdir(parents=True, exist_ok=True)
            with self._connection() as conn:
                conn.execute("PRAGMA journal_mode=WAL;")
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS favorites (
                        video_id TEXT PRIMARY KEY,
                        title TEXT NOT NULL,
                        artist TEXT NOT NULL,
                        duration TEXT,
                        artwork_url TEXT,
                        added_at REAL NOT NULL
                    );
                    """
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS history (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        video_id TEXT NOT NULL,
                        title TEXT NOT NULL,
                        artist TEXT NOT NULL,
                        duration TEXT,
                        artwork_url TEXT,
                        played_at REAL NOT NULL
                    );
                    """
                )
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_history_played ON history(played_at DESC);"
                )
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS search_history (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        query TEXT UNIQUE NOT NULL,
                        searched_at REAL NOT NULL
                    );
                    """
                )
                conn.execute(
                    "CREATE INDEX IF NOT EXISTS idx_search_time ON search_history(searched_at DESC);"
                )
                conn.commit()
            log.info("Ember storage initialized at %s", self.db_path)
        except Exception as exc:
            log.error("Failed to initialize Ember storage at %s: %s", self.db_path, exc)

    # ---------------------------------------------------------------- favorites
    def add_favorite(self, song: Song) -> None:
        """Add or update a track in the favorites collection."""
        if not song or not song.video_id:
            return
        try:
            with self._connection() as conn:
                conn.execute(
                    """
                    INSERT INTO favorites (video_id, title, artist, duration, artwork_url, added_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(video_id) DO UPDATE SET
                        title = excluded.title,
                        artist = excluded.artist,
                        duration = excluded.duration,
                        artwork_url = excluded.artwork_url,
                        added_at = excluded.added_at;
                    """,
                    (
                        song.video_id,
                        song.title,
                        song.artist,
                        song.duration,
                        song.artwork_url,
                        time.time(),
                    ),
                )
                conn.commit()
            log.info("Favorited: %s (%s)", song.title, song.video_id)
        except Exception as exc:
            log.error("Failed to add favorite %s: %s", song.video_id, exc)

    def remove_favorite(self, video_id: str) -> None:
        """Remove a track from favorites."""
        if not video_id:
            return
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM favorites WHERE video_id = ?;", (video_id,))
                conn.commit()
            log.info("Removed favorite: %s", video_id)
        except Exception as exc:
            log.error("Failed to remove favorite %s: %s", video_id, exc)

    def is_favorite(self, video_id: str) -> bool:
        """Check if a given video_id is favorited."""
        if not video_id:
            return False
        try:
            with self._connection() as conn:
                cursor = conn.execute(
                    "SELECT 1 FROM favorites WHERE video_id = ? LIMIT 1;", (video_id,)
                )
                return cursor.fetchone() is not None
        except Exception as exc:
            log.error("Failed to check favorite status for %s: %s", video_id, exc)
            return False

    def get_favorites(self) -> List[Song]:
        """Fetch all favorited songs ordered by addition time (newest first)."""
        songs: List[Song] = []
        try:
            with self._connection() as conn:
                cursor = conn.execute(
                    """
                    SELECT video_id, title, artist, duration, artwork_url
                    FROM favorites
                    ORDER BY added_at DESC;
                    """
                )
                for row in cursor.fetchall():
                    songs.append(
                        Song(
                            video_id=row["video_id"],
                            title=row["title"],
                            artist=row["artist"],
                            duration=row["duration"] or "",
                            artwork_url=row["artwork_url"] or "",
                        )
                    )
        except Exception as exc:
            log.error("Failed to load favorites: %s", exc)
        return songs

    def get_favorite_ids(self) -> set[str]:
        """Fetch set of all favorited video IDs in a single batch query."""
        try:
            with self._connection() as conn:
                cursor = conn.execute("SELECT video_id FROM favorites;")
                return {str(row[0]) for row in cursor.fetchall()}
        except Exception as exc:
            log.error("Failed to fetch favorite IDs: %s", exc)
            return set()

    # ------------------------------------------------------------------ history
    def record_history(self, song: Song) -> None:
        """Record a played track into history, pruning old entries past 300 items."""
        if not song or not song.video_id:
            return
        try:
            with self._connection() as conn:
                conn.execute(
                    """
                    INSERT INTO history (video_id, title, artist, duration, artwork_url, played_at)
                    VALUES (?, ?, ?, ?, ?, ?);
                    """,
                    (
                        song.video_id,
                        song.title,
                        song.artist,
                        song.duration,
                        song.artwork_url,
                        time.time(),
                    ),
                )
                # Keep max 300 history rows to keep database lean
                conn.execute(
                    """
                    DELETE FROM history WHERE id NOT IN (
                        SELECT id FROM history ORDER BY played_at DESC LIMIT 300
                    );
                    """
                )
                conn.commit()
            log.debug("Recorded playback history for %s", song.video_id)
        except Exception as exc:
            log.error("Failed to record history for %s: %s", song.video_id, exc)

    def get_history(self, limit: int = 50) -> List[Song]:
        """Fetch recently played tracks (newest first, unique tracks preserved)."""
        songs: List[Song] = []
        try:
            with self._connection() as conn:
                cursor = conn.execute(
                    """
                    SELECT video_id, title, artist, duration, artwork_url, MAX(played_at) AS last_played
                    FROM history
                    GROUP BY video_id
                    ORDER BY last_played DESC
                    LIMIT ?;
                    """,
                    (limit,),
                )
                for row in cursor.fetchall():
                    songs.append(
                        Song(
                            video_id=row["video_id"],
                            title=row["title"],
                            artist=row["artist"],
                            duration=row["duration"] or "",
                            artwork_url=row["artwork_url"] or "",
                        )
                    )
        except Exception as exc:
            log.error("Failed to fetch playback history: %s", exc)
        return songs

    def clear_history(self) -> None:
        """Clear all playback history."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM history;")
                conn.commit()
            log.info("Playback history cleared")
        except Exception as exc:
            log.error("Failed to clear history: %s", exc)

    def remove_history(self, video_id: str) -> bool:
        """Remove an individual track from playback history."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM history WHERE video_id = ?;", (video_id,))
                conn.commit()
            return True
        except Exception as exc:
            log.error("Failed to remove history for %s: %s", video_id, exc)
            return False

    # ----------------------------------------------------------- search history
    def record_search(self, query: str) -> None:
        """Record a search query in history, keeping the 50 most recent."""
        clean = (query or "").strip()
        if not clean:
            return
        try:
            with self._connection() as conn:
                conn.execute(
                    """
                    INSERT INTO search_history (query, searched_at)
                    VALUES (?, ?)
                    ON CONFLICT(query) DO UPDATE SET searched_at = excluded.searched_at;
                    """,
                    (clean, time.time()),
                )
                conn.execute(
                    """
                    DELETE FROM search_history WHERE id NOT IN (
                        SELECT id FROM search_history ORDER BY searched_at DESC LIMIT 50
                    );
                    """
                )
                conn.commit()
            log.debug("Recorded search query: %r", clean)
        except Exception as exc:
            log.error("Failed to record search query %r: %s", clean, exc)

    def get_recent_searches(self, limit: int = 10) -> List[str]:
        """Fetch recent search queries (most recent first)."""
        queries: List[str] = []
        try:
            with self._connection() as conn:
                cursor = conn.execute(
                    "SELECT query FROM search_history ORDER BY searched_at DESC LIMIT ?;",
                    (max(1, limit),),
                )
                for row in cursor.fetchall():
                    queries.append(str(row["query"]))
        except Exception as exc:
            log.error("Failed to fetch recent searches: %s", exc)
        return queries

    def clear_search_history(self) -> None:
        """Clear all search history."""
        try:
            with self._connection() as conn:
                conn.execute("DELETE FROM search_history;")
                conn.commit()
            log.info("Search history cleared")
        except Exception as exc:
            log.error("Failed to clear search history: %s", exc)

    # ------------------------------------------------------------- export & import
    def export_favorites_json(self) -> str:
        """Export all favorites as formatted JSON."""
        import json
        favs = [s.to_dict() for s in self.get_favorites()]
        return json.dumps(favs, indent=2)

    def import_favorites_json(self, json_data: str) -> int:
        """Import favorites from JSON string in a single atomic transaction."""
        import json
        try:
            items = json.loads(json_data)
            if not isinstance(items, list):
                return 0
            records = []
            now = time.time()
            for item in items:
                if isinstance(item, dict) and item.get("video_id"):
                    s = Song.from_dict(item)
                    if s.video_id:
                        records.append(
                            (s.video_id, s.title, s.artist, s.duration, s.artwork_url, now)
                        )
            if not records:
                return 0
            with self._connection() as conn:
                conn.executemany(
                    """
                    INSERT INTO favorites (video_id, title, artist, duration, artwork_url, added_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(video_id) DO UPDATE SET
                        title = excluded.title,
                        artist = excluded.artist,
                        duration = excluded.duration,
                        artwork_url = excluded.artwork_url,
                        added_at = excluded.added_at;
                    """,
                    records,
                )
                conn.commit()
            log.info("Imported %d favorites from JSON", len(records))
            return len(records)
        except Exception as exc:
            log.error("Failed to import favorites JSON: %s", exc)
            return 0

    def export_favorites_m3u(self) -> str:
        """Export favorites in standard extended M3U8 playlist format."""
        favs = self.get_favorites()
        lines = ["#EXTM3U"]
        for s in favs:
            dur = parse_duration(s.duration)
            lines.append(f"#EXTINF:{dur},{s.artist} - {s.title}")
            lines.append(f"https://www.youtube.com/watch?v={s.video_id}")
        return "\n".join(lines) + "\n"

    def import_favorites_m3u(self, m3u_data: str) -> int:
        """Import tracks from extended M3U/M3U8 string into favorites."""
        if not m3u_data:
            return 0
        records = []
        pending_title = ""
        pending_artist = "Unknown Artist"
        pending_duration = ""
        now = time.time()

        for line in m3u_data.splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith("#EXTINF:"):
                # Format: #EXTINF:seconds,Artist - Title OR #EXTINF:seconds,Title
                info = line[8:].strip()
                comma_idx = info.find(",")
                dur_val = -1
                if comma_idx != -1:
                    raw_dur = info[:comma_idx].strip()
                    try:
                        dur_val = int(raw_dur)
                    except ValueError:
                        dur_val = -1
                    meta = info[comma_idx + 1:].strip()
                else:
                    meta = info
                if dur_val > 0:
                    from .utils import clock
                    pending_duration = clock(dur_val * 1000)
                else:
                    pending_duration = ""
                if " - " in meta:
                    pending_artist, pending_title = meta.split(" - ", 1)
                else:
                    pending_title = meta
                    pending_artist = "Unknown Artist"
            elif not line.startswith("#"):
                # URL or video id line
                vid = extract_youtube_id(line)
                if vid:
                    records.append(
                        (
                            vid,
                            pending_title or "Imported Track",
                            pending_artist or "Unknown Artist",
                            pending_duration,
                            "",
                            now,
                        )
                    )
                    pending_title = ""
                    pending_artist = "Unknown Artist"
                    pending_duration = ""

        if not records:
            return 0

        try:
            with self._connection() as conn:
                conn.executemany(
                    """
                    INSERT INTO favorites (video_id, title, artist, duration, artwork_url, added_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(video_id) DO UPDATE SET
                        title = excluded.title,
                        artist = excluded.artist,
                        duration = excluded.duration,
                        artwork_url = excluded.artwork_url,
                        added_at = excluded.added_at;
                    """,
                    records,
                )
                conn.commit()
            log.info("Imported %d favorites from M3U", len(records))
            return len(records)
        except Exception as exc:
            log.error("Failed to import favorites M3U: %s", exc)
            return 0

