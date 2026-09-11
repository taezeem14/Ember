"""Tests for utils module."""

from __future__ import annotations

from ember.utils import (
    as_bool,
    as_int,
    clock,
    extract_youtube_id,
    is_valid_hex_color,
    looks_like_link,
    parse_duration,
    pretty_count,
)


def test_clock_formatting() -> None:
    assert clock(0) == "0:00"
    assert clock(None) == "0:00"  # type: ignore[arg-type]
    assert clock(45000) == "0:45"
    assert clock(125000) == "2:05"
    assert clock(3665000) == "1:01:05"


def test_parse_duration() -> None:
    assert parse_duration("3:45") == 225
    assert parse_duration("1:02:15") == 3735
    assert parse_duration("120") == 120
    assert parse_duration("") == -1
    assert parse_duration("invalid:time:format:extra") == -1
    assert parse_duration("invalid") == -1


def test_extract_youtube_id() -> None:
    assert extract_youtube_id("dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert extract_youtube_id("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert extract_youtube_id("https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert extract_youtube_id("https://youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert extract_youtube_id("https://youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ"
    assert extract_youtube_id("") is None
    assert extract_youtube_id("random text without youtube id") is None


def test_is_valid_hex_color() -> None:
    assert is_valid_hex_color("#E5A93C")
    assert is_valid_hex_color("#ffffff")
    assert is_valid_hex_color("#000000")
    assert not is_valid_hex_color("#fff")
    assert not is_valid_hex_color("E5A93C")
    assert not is_valid_hex_color("#GGGGGG")
    assert not is_valid_hex_color("")


def test_as_bool() -> None:
    assert as_bool(True, False) is True
    assert as_bool("true", False) is True
    assert as_bool("1", False) is True
    assert as_bool("yes", False) is True
    assert as_bool("false", True) is False
    assert as_bool("0", True) is False
    assert as_bool("no", True) is False
    assert as_bool(None, True) is True
    assert as_bool("unknown", True) is True


def test_as_int() -> None:
    assert as_int(42, 0) == 42
    assert as_int("42", 0) == 42
    assert as_int("42.7", 0) == 42
    assert as_int("invalid", 10) == 10
    assert as_int(None, 5) == 5


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
