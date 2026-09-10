"""
app.py
Entry point. Builds the pieces, restores the last session, wires the tray and
the hotkeys, and hands control to Qt.

The panel owns layout. The core owns playback. This module owns the glue and
nothing else.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Any

from PyQt6.QtCore import QSettings, QStandardPaths, QTimer
from PyQt6.QtGui import QKeySequence, QShortcut
from PyQt6.QtWidgets import QApplication

from .catalog import CatalogSource
from .config import (
    APP_NAME,
    APP_TAGLINE,
    DEFAULT_VOLUME,
    ORG_NAME,
    SETTINGS_AUTO_QUEUE,
    SETTINGS_EXPANDED,
    SETTINGS_POS_X,
    SETTINGS_POS_Y,
    SETTINGS_VOLUME,
)
from .panel import FloatingPanel
from .player import PlaybackCore
from .stream import StreamResolver
from .theme import popup_stylesheet
from .tray import InstanceGuard, TrayPresence, ember_icon, write_icon

log = logging.getLogger(__name__)

PLACEHOLDER_X = 24
PLACEHOLDER_Y = 24
SCREEN_INSET = 24
TOPMOST_REFRESH_MS = 4000
ICON_FILENAME = "ember.ico"
LOG_FILENAME = "ember.log"


# ------------------------------------------------------------------- coercion
def _as_int(raw: Any, fallback: int) -> int:
    try:
        return int(raw)
    except (TypeError, ValueError):
        return fallback


def _as_bool(raw: Any, fallback: bool) -> bool:
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


# -------------------------------------------------------------------- logging
def _configure_logging(log_dir: Path) -> None:
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        log_dir = Path(".")

    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stderr)]
    try:
        handlers.append(logging.FileHandler(log_dir / LOG_FILENAME, encoding="utf-8"))
    except OSError:
        pass

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        handlers=handlers,
    )


# ------------------------------------------------------------------ lifecycle
def _surface(panel: FloatingPanel) -> None:
    panel.show()
    panel.raise_()
    panel.activateWindow()
    panel.ensure_topmost()


def _restore_session(panel: FloatingPanel, core: PlaybackCore, settings: QSettings) -> None:
    screen = QApplication.primaryScreen()
    if screen is not None:
        bounds = screen.availableGeometry()
        fallback_x = max(PLACEHOLDER_X, bounds.right() - panel.width() - SCREEN_INSET)
        fallback_y = max(PLACEHOLDER_Y, bounds.bottom() - panel.height() - SCREEN_INSET)
    else:
        fallback_x, fallback_y = PLACEHOLDER_X, PLACEHOLDER_Y

    panel.place(
        _as_int(settings.value(SETTINGS_POS_X), fallback_x),
        _as_int(settings.value(SETTINGS_POS_Y), fallback_y),
    )

    volume = max(0, min(100, _as_int(settings.value(SETTINGS_VOLUME), DEFAULT_VOLUME)))
    core.set_volume(volume)
    panel.volume.set_value(volume)

    endless = _as_bool(settings.value(SETTINGS_AUTO_QUEUE), True)
    core.set_auto_queue(endless)
    panel.endless.blockSignals(True)
    panel.endless.setChecked(endless)
    panel.endless.blockSignals(False)

    if _as_bool(settings.value(SETTINGS_EXPANDED), False):
        panel.expand()


def _persist(panel: FloatingPanel, core: PlaybackCore, settings: QSettings) -> None:
    x, y = panel.current_position()
    settings.setValue(SETTINGS_POS_X, x)
    settings.setValue(SETTINGS_POS_Y, y)
    settings.setValue(SETTINGS_EXPANDED, panel.expanded)
    settings.setValue(SETTINGS_VOLUME, core.volume())
    settings.setValue(SETTINGS_AUTO_QUEUE, core.auto_queue)
    settings.sync()


def _wire_tray(
    tray: TrayPresence,
    panel: FloatingPanel,
    core: PlaybackCore,
    app: QApplication,
) -> None:
    tray.toggle_requested.connect(core.toggle)
    tray.forward_requested.connect(core.forward)
    tray.back_requested.connect(core.back)
    tray.reveal_requested.connect(lambda: _surface(panel))
    tray.quit_requested.connect(app.quit)
    core.playing_changed.connect(tray.set_playing)
    panel.closed.connect(app.quit)


# ----------------------------------------------------------------------- main
def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationDisplayName(APP_NAME)
    app.setOrganizationName(ORG_NAME)
    app.setDesktopFileName("ember")
    app.setQuitOnLastWindowClosed(False)
    app.setWindowIcon(ember_icon())
    app.setStyleSheet(popup_stylesheet())

    data_dir = Path(
        QStandardPaths.writableLocation(QStandardPaths.StandardLocation.AppDataLocation)
        or "."
    )
    _configure_logging(data_dir)
    log.info("%s starting — %s", APP_NAME, APP_TAGLINE)
    write_icon(str(data_dir / ICON_FILENAME))

    guard = InstanceGuard()
    if not guard.claim():
        log.info("another instance is already running")
        return 0

    settings = QSettings(ORG_NAME, APP_NAME)

    catalog = CatalogSource()
    resolver = StreamResolver()
    core = PlaybackCore(catalog, resolver)
    panel = FloatingPanel(core)
    tray = TrayPresence()

    _restore_session(panel, core, settings)
    _wire_tray(tray, panel, core, app)
    guard.reveal_requested.connect(lambda: _surface(panel))

    shortcuts: list[QShortcut] = []
    for sequence, callback in panel.hotkeys():
        shortcut = QShortcut(QKeySequence(sequence), panel)
        shortcut.activated.connect(callback)
        shortcuts.append(shortcut)

    topmost_guard = QTimer(panel)
    topmost_guard.setInterval(TOPMOST_REFRESH_MS)
    topmost_guard.timeout.connect(panel.ensure_topmost)
    topmost_guard.start()

    app.aboutToQuit.connect(lambda: _persist(panel, core, settings))
    app.aboutToQuit.connect(guard.release)

    panel.show()
    panel.ensure_topmost()
    tray.show()

    return app.exec()