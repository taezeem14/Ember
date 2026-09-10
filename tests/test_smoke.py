"""Smoke import tests for Ember."""

from __future__ import annotations

import ember
import ember.app
import ember.catalog
import ember.config
import ember.jobs
import ember.models
import ember.panel
import ember.player
import ember.settings_dialog
import ember.storage
import ember.stream
import ember.theme
import ember.toast
import ember.tray
import ember.utils


def test_package_metadata() -> None:
    assert hasattr(ember, "__version__")
    assert ember.__version__ == "1.0.0"


def test_modules_loaded() -> None:
    assert ember.config.APP_NAME == "Ember"
    assert ember.models.Song is not None
    assert ember.storage.EmberStorage is not None
    assert ember.toast.NowPlayingToast is not None
    assert ember.settings_dialog.SettingsDialog is not None
    assert ember.tray.TrayPresence is not None


def test_tray_presence_instantiation() -> None:
    import sys
    from PyQt6.QtWidgets import QApplication
    app = QApplication.instance() or QApplication(sys.argv)
    tray = ember.tray.TrayPresence()
    assert tray.icon is not None
    assert tray.menu is not None
