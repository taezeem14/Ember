"""Tests for FontAwesome icon provider."""

from __future__ import annotations

import sys
from PyQt6.QtWidgets import QApplication
from ember.icons import (
    backward_icon,
    close_icon,
    collapse_icon,
    expand_icon,
    fire_icon,
    forward_icon,
    heart_icon,
    history_icon,
    infinity_icon,
    music_icon,
    pause_icon,
    play_icon,
    queue_icon,
    search_icon,
    settings_icon,
)


def test_fontawesome_icons_instantiate() -> None:
    app = QApplication.instance()
    if app is None:
        app = QApplication(sys.argv)

    assert not play_icon().isNull()
    assert not pause_icon().isNull()
    assert not forward_icon().isNull()
    assert not backward_icon().isNull()
    assert not heart_icon(True).isNull()
    assert not heart_icon(False).isNull()
    assert not search_icon().isNull()
    assert not settings_icon().isNull()
    assert not close_icon().isNull()
    assert not expand_icon().isNull()
    assert not collapse_icon().isNull()
    assert not queue_icon().isNull()
    assert not history_icon().isNull()
    assert not infinity_icon().isNull()
    assert not fire_icon().isNull()
    assert not music_icon().isNull()
