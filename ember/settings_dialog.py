"""
settings_dialog.py
Preferences panel for Ember: theme switching, audio normalization,
endless queue toggle, desktop notifications, and hotkey configuration.

# Written by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

import logging
from typing import Dict, List, Optional

from PyQt6.QtCore import QPoint, QSettings, Qt, pyqtSignal
from PyQt6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QFrame,
    QGraphicsDropShadowEffect,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .config import (
    Palette,
    SETTINGS_AUTO_QUEUE,
    SETTINGS_HOTKEYS,
    SETTINGS_NORMALIZE_VOLUME,
    SETTINGS_THEME,
    SETTINGS_TOAST_ENABLED,
)
from .theme import settings_stylesheet

log = logging.getLogger(__name__)

WINDOWS_CONFLICTS = {
    "Ctrl+C",
    "Ctrl+V",
    "Ctrl+X",
    "Ctrl+Z",
    "Ctrl+A",
    "Alt+F4",
    "Alt+Tab",
    "Ctrl+Alt+Del",
    "Win+L",
    "Win+D",
}

DEFAULT_HOTKEYS: Dict[str, str] = {
    "toggle": "Ctrl+Alt+Space",
    "forward": "Ctrl+Alt+Right",
    "back": "Ctrl+Alt+Left",
    "expand": "Ctrl+Alt+E",
}


class SettingsDialog(QDialog):
    """Preferences dialog with instant theme preview and hotkey conflict detection."""

    theme_changed = pyqtSignal(str)
    normalization_changed = pyqtSignal(bool)
    endless_changed = pyqtSignal(bool)
    toast_changed = pyqtSignal(bool)
    hotkeys_changed = pyqtSignal(dict)

    def __init__(self, settings: QSettings, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.settings = settings
        self._drag_offset: Optional[QPoint] = None

        self.setWindowTitle("Ember Settings")
        self.setWindowFlags(
            Qt.WindowType.Dialog
            | Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setFixedSize(380, 480)

        self._build()
        self._load_values()
        self.setStyleSheet(settings_stylesheet())

    def _build(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(10, 10, 10, 10)

        self.shell = QFrame(self)
        self.shell.setObjectName("Shell")
        outer.addWidget(self.shell)

        shadow = QGraphicsDropShadowEffect(self)
        shadow.setBlurRadius(30)
        shadow.setOffset(0, 8)
        shadow.setColor(Qt.GlobalColor.black)
        self.shell.setGraphicsEffect(shadow)

        layout = QVBoxLayout(self.shell)
        layout.setContentsMargins(20, 16, 20, 16)
        layout.setSpacing(12)

        # Header
        header = QHBoxLayout()
        words = QVBoxLayout()
        title = QLabel("PREFERENCES", self)
        title.setObjectName("SettingsTitle")
        sub = QLabel("tune your ember companion", self)
        sub.setObjectName("SettingsSub")
        words.addWidget(title)
        words.addWidget(sub)
        header.addLayout(words, 1)

        close_btn = QPushButton("✕", self)
        close_btn.setObjectName("PillClose")
        close_btn.setFixedSize(26, 26)
        close_btn.clicked.connect(self.accept)
        header.addWidget(close_btn)
        layout.addLayout(header)

        # Theme selection
        theme_sec = QLabel("APPEARANCE", self)
        theme_sec.setObjectName("SettingsSection")
        layout.addWidget(theme_sec)

        theme_row = QHBoxLayout()
        theme_label = QLabel("Color Palette:", self)
        self.theme_combo = QComboBox(self)
        for theme_name in Palette.list_themes():
            self.theme_combo.addItem(theme_name)
        self.theme_combo.currentTextChanged.connect(self._on_theme_selected)
        theme_row.addWidget(theme_label)
        theme_row.addWidget(self.theme_combo, 1)
        layout.addLayout(theme_row)

        # Audio & Queue tunables
        audio_sec = QLabel("PLAYBACK & QUEUE", self)
        audio_sec.setObjectName("SettingsSection")
        layout.addWidget(audio_sec)

        self.chk_normalize = QCheckBox("Volume Normalization (soften loudness spikes)", self)
        self.chk_normalize.toggled.connect(self._on_normalize_toggled)
        layout.addWidget(self.chk_normalize)

        self.chk_endless = QCheckBox("Endless Recommendation Queue", self)
        self.chk_endless.toggled.connect(self._on_endless_toggled)
        layout.addWidget(self.chk_endless)

        self.chk_toast = QCheckBox("Show Now Playing Desktop Notification", self)
        self.chk_toast.toggled.connect(self._on_toast_toggled)
        layout.addWidget(self.chk_toast)

        # Hotkeys
        hotkey_sec = QLabel("HOTKEY CHORDS", self)
        hotkey_sec.setObjectName("SettingsSection")
        layout.addWidget(hotkey_sec)

        self.hotkey_inputs: Dict[str, QLineEdit] = {}
        labels = [
            ("toggle", "Play / Pause:"),
            ("forward", "Next Track:"),
            ("back", "Previous:"),
            ("expand", "Toggle Panel:"),
        ]
        for key, text in labels:
            hrow = QHBoxLayout()
            hrow.setSpacing(6)
            hlabel = QLabel(text, self)
            hlabel.setFixedWidth(85)
            hinput = QLineEdit(self)
            hinput.setObjectName("SearchField")
            hinput.setFixedHeight(26)
            hinput.textChanged.connect(self._validate_hotkeys)
            self.hotkey_inputs[key] = hinput
            hrow.addWidget(hlabel)
            hrow.addWidget(hinput, 1)
            layout.addLayout(hrow)

        self.conflict_warn = QLabel("", self)
        self.conflict_warn.setStyleSheet("color: #E26D85; font-size: 10px; font-weight: 600;")
        self.conflict_warn.setVisible(False)
        layout.addWidget(self.conflict_warn)

        layout.addStretch(1)

        # Footer
        footer = QHBoxLayout()
        reset_btn = QPushButton("Reset Hotkeys", self)
        reset_btn.setObjectName("Pill")
        reset_btn.clicked.connect(self._reset_hotkeys)
        footer.addWidget(reset_btn)

        footer.addStretch(1)

        save_btn = QPushButton("Done", self)
        save_btn.setObjectName("AmberButton")
        save_btn.setFixedHeight(28)
        save_btn.clicked.connect(self._save_and_close)
        footer.addWidget(save_btn)

        layout.addLayout(footer)

    def _load_values(self) -> None:
        saved_theme = str(self.settings.value(SETTINGS_THEME, "Amber"))
        idx = self.theme_combo.findText(saved_theme)
        if idx >= 0:
            self.theme_combo.setCurrentIndex(idx)

        norm = str(self.settings.value(SETTINGS_NORMALIZE_VOLUME, "false")).lower() in ("true", "1", "yes")
        self.chk_normalize.setChecked(norm)

        endless = str(self.settings.value(SETTINGS_AUTO_QUEUE, "true")).lower() in ("true", "1", "yes")
        self.chk_endless.setChecked(endless)

        toast = str(self.settings.value(SETTINGS_TOAST_ENABLED, "true")).lower() in ("true", "1", "yes")
        self.chk_toast.setChecked(toast)

        for key, default_val in DEFAULT_HOTKEYS.items():
            val = str(self.settings.value(f"{SETTINGS_HOTKEYS}/{key}", default_val))
            if key in self.hotkey_inputs:
                self.hotkey_inputs[key].setText(val)

    def _on_theme_selected(self, theme_name: str) -> None:
        self.settings.setValue(SETTINGS_THEME, theme_name)
        Palette.apply_theme(theme_name)
        self.setStyleSheet(settings_stylesheet())
        self.theme_changed.emit(theme_name)

    def _on_normalize_toggled(self, checked: bool) -> None:
        self.settings.setValue(SETTINGS_NORMALIZE_VOLUME, checked)
        self.normalization_changed.emit(checked)

    def _on_endless_toggled(self, checked: bool) -> None:
        self.settings.setValue(SETTINGS_AUTO_QUEUE, checked)
        self.endless_changed.emit(checked)

    def _on_toast_toggled(self, checked: bool) -> None:
        self.settings.setValue(SETTINGS_TOAST_ENABLED, checked)
        self.toast_changed.emit(checked)

    def _validate_hotkeys(self) -> None:
        conflicts: List[str] = []
        for key, inp in self.hotkey_inputs.items():
            chord = inp.text().strip()
            if chord in WINDOWS_CONFLICTS:
                conflicts.append(chord)
        if conflicts:
            self.conflict_warn.setText(f"Warning: '{', '.join(conflicts)}' conflicts with Windows standard shortcut!")
            self.conflict_warn.setVisible(True)
        else:
            self.conflict_warn.setVisible(False)

    def _reset_hotkeys(self) -> None:
        for key, default_val in DEFAULT_HOTKEYS.items():
            if key in self.hotkey_inputs:
                self.hotkey_inputs[key].setText(default_val)
        self._validate_hotkeys()

    def _save_and_close(self) -> None:
        hotkeys: Dict[str, str] = {}
        for key, inp in self.hotkey_inputs.items():
            chord = inp.text().strip() or DEFAULT_HOTKEYS.get(key, "")
            hotkeys[key] = chord
            self.settings.setValue(f"{SETTINGS_HOTKEYS}/{key}", chord)
        self.settings.sync()
        self.hotkeys_changed.emit(hotkeys)
        self.accept()

    # Drag support
    def mousePressEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_offset = event.globalPosition().toPoint() - self.frameGeometry().topLeft()

    def mouseMoveEvent(self, event) -> None:  # noqa: N802
        if self._drag_offset is not None:
            self.move(event.globalPosition().toPoint() - self._drag_offset)

    def mouseReleaseEvent(self, event) -> None:  # noqa: N802
        self._drag_offset = None
