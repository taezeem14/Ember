"""Tests for utils module."""

from __future__ import annotations

from ember.utils import clock, looks_like_link, pretty_count


def test_clock_formatting() -> None:
    assert clock(0) == "0:00"
    assert clock(45000) == "0:45"
    assert clock(125000) == "2:05"
    assert clock(3665000) == "1:01:05"


def test_looks_like_link() -> None:
    assert looks_like_link("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert looks_like_link("http://youtu.be/dQw4w9WgXcQ")
    assert looks_like_link("https://music.youtube.com/watch?v=123")
    assert not looks_like_link("Taylor Swift Cruel Summer")
    assert not looks_like_link("")


def test_pretty_count() -> None:
    assert pretty_count(1, "track") == "1 track"
    assert pretty_count(0, "track") == "0 tracks"
    assert pretty_count(12, "track") == "12 tracks"
    assert pretty_count(1, "entry", "entries") == "1 entry"
    assert pretty_count(5, "entry", "entries") == "5 entries"
