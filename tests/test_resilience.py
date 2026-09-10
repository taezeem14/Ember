"""Tests for retry backoff resilience in catalog and stream."""

from __future__ import annotations

import pytest

from ember.catalog import _with_retry, CatalogSource
from ember.models import Song


def test_retry_success_on_first_attempt() -> None:
    calls = 0

    def mock_fn() -> str:
        nonlocal calls
        calls += 1
        return "success"

    result = _with_retry(mock_fn, max_attempts=3, base_delay=0.01)
    assert result == "success"
    assert calls == 1


def test_retry_success_after_failure() -> None:
    calls = 0

    def fail_twice() -> str:
        nonlocal calls
        calls += 1
        if calls < 3:
            raise ConnectionError("temporary network drop")
        return "recovered"

    result = _with_retry(fail_twice, max_attempts=3, base_delay=0.01)
    assert result == "recovered"
    assert calls == 3


def test_retry_eventual_failure() -> None:
    def always_fail() -> None:
        raise TimeoutError("connection timed out")

    with pytest.raises(TimeoutError):
        _with_retry(always_fail, max_attempts=2, base_delay=0.01)


def test_catalog_build_parser() -> None:
    valid_raw = {
        "videoId": "vid_abc",
        "title": "Song Title",
        "artists": [{"name": "Artist 1"}, {"name": "Artist 2"}],
        "duration": "3:45",
        "thumbnails": [
            {"url": "http://small.jpg", "width": 100, "height": 100},
            {"url": "http://large.jpg", "width": 500, "height": 500},
        ],
    }
    song = CatalogSource._build(valid_raw)
    assert song is not None
    assert song.video_id == "vid_abc"
    assert song.artist == "Artist 1, Artist 2"
    assert song.artwork_url == "http://large.jpg"
