"""
settings_dialog.py
Preferences panel for Ember: theme switching, audio normalization,
endless queue toggle, desktop notifications, and hotkey configuration.

# Extended/upgraded by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

import logging
from typing import Dict, List, Optional

from PyQt6.QtCore import QPoint, QSettings, QSize, Qt, QUrl, pyqtSignal
from PyQt6.QtGui import QDesktopServices, QKeySequence
from PyQt6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDialog,
    QFileDialog,
    QFrame,
    QGraphicsDropShadowEffect,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSlider,
    QVBoxLayout,
    QWidget,
)

from .config import (
    DEFAULT_OPACITY,
    Palette,
    SETTINGS_ALWAYS_ON_TOP,
    SETTINGS_AUTO_QUEUE,
    SETTINGS_HOTKEYS,
    SETTINGS_NORMALIZE_VOLUME,
    SETTINGS_OPACITY,
    SETTINGS_THEME,
    SETTINGS_TOAST_ENABLED,
)
from .icons import (
    close_icon,
    code_fork_icon,
    keyboard_icon,
    palette_icon,
    settings_icon,
    sliders_icon,
    user_icon,
)
from .storage import EmberStorage
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
    """Preferences dialog with FontAwesome vector icons and hotkey conflict detection."""

    theme_changed = pyqtSignal(str)
    opacity_changed = pyqtSignal(int)
    always_on_top_changed = pyqtSignal(bool)
    normalization_changed = pyqtSignal(bool)
    endless_changed = pyqtSignal(bool)
    toast_changed = pyqtSignal(bool)
    hotkeys_changed = pyqtSignal(dict)

    def __init__(
        self,
        settings: QSettings,
        parent: Optional[QWidget] = None,
        storage: Optional[EmberStorage] = None,
    ) -> None:
        super().__init__(parent)
        self.settings = settings
        self.storage = storage
        self._drag_offset: Optional[QPoint] = None

        self.setWindowTitle("Ember Settings")
        self.setWindowFlags(
            Qt.WindowType.Dialog
            | Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setFixedSize(450, 680)

        self._build()
        self._load_values()
        self.setStyleSheet(settings_stylesheet())

    def _build(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(10, 10, 10, 10)

        self.shell = QFrame(self)
        self.shell.setObjectName("Shell")
        outer.addWidget(self.shell)

        shell_layout = QVBoxLayout(self.shell)
        shell_layout.setContentsMargins(18, 16, 18, 16)
        shell_layout.setSpacing(10)

        # Header with FA Gear Icon (pinned)
        header = QHBoxLayout()
        icon_lbl = QLabel(self)
        icon_lbl.setPixmap(settings_icon(Palette.amber_hi).pixmap(20, 20))
        words = QVBoxLayout()
        title = QLabel("PREFERENCES & TUNABLES", self)
        title.setObjectName("SettingsTitle")
        sub = QLabel("tune your desktop music companion", self)
        sub.setObjectName("SettingsSub")
        words.addWidget(title)
        words.addWidget(sub)
        header.addWidget(icon_lbl)
        header.addLayout(words, 1)

        close_btn = QPushButton(self)
        close_btn.setObjectName("PillClose")
        close_btn.setFixedSize(26, 26)
        close_btn.setIcon(close_icon())
        close_btn.setIconSize(QSize(13, 13))
        close_btn.clicked.connect(self.accept)
        header.addWidget(close_btn)
        shell_layout.addLayout(header)

        # Scrollable Body Container
        scroll = QScrollArea(self.shell)
        scroll.setObjectName("SettingsScroll")
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)

        body = QWidget()
        body.setObjectName("SettingsBody")
        layout = QVBoxLayout(body)
        layout.setContentsMargins(0, 0, 4, 0)
        layout.setSpacing(11)

        # Theme selection
        theme_hdr = QHBoxLayout()
        pal_ico = QLabel(self)
        pal_ico.setPixmap(palette_icon(Palette.amber).pixmap(14, 14))
        theme_sec = QLabel("APPEARANCE", self)
        theme_sec.setObjectName("SettingsSection")
        theme_hdr.addWidget(pal_ico)
        theme_hdr.addWidget(theme_sec)
        theme_hdr.addStretch(1)
        layout.addLayout(theme_hdr)

        theme_row = QHBoxLayout()
        theme_label = QLabel("Color Palette:", self)
        self.theme_combo = QComboBox(self)
        for theme_name in Palette.list_themes():
            self.theme_combo.addItem(theme_name)
        self.theme_combo.currentTextChanged.connect(self._on_theme_selected)
        theme_row.addWidget(theme_label)
        theme_row.addWidget(self.theme_combo, 1)
        layout.addLayout(theme_row)

        # Glass opacity slider
        opacity_row = QHBoxLayout()
        opacity_label = QLabel("Glass Opacity:", self)
        self.opacity_slider = QSlider(Qt.Orientation.Horizontal, self)
        self.opacity_slider.setRange(60, 100)
        self.opacity_slider.setValue(DEFAULT_OPACITY)
        self.opacity_val_lbl = QLabel(f"{DEFAULT_OPACITY}%", self)
        self.opacity_val_lbl.setFixedWidth(36)
        self.opacity_slider.valueChanged.connect(self._on_opacity_changed)
        opacity_row.addWidget(opacity_label)
        opacity_row.addWidget(self.opacity_slider, 1)
        opacity_row.addWidget(self.opacity_val_lbl)
        layout.addLayout(opacity_row)

        # Audio & Queue tunables
        audio_hdr = QHBoxLayout()
        slide_ico = QLabel(self)
        slide_ico.setPixmap(sliders_icon(Palette.amber).pixmap(14, 14))
        audio_sec = QLabel("PLAYBACK & QUEUE", self)
        audio_sec.setObjectName("SettingsSection")
        audio_hdr.addWidget(slide_ico)
        audio_hdr.addWidget(audio_sec)
        audio_hdr.addStretch(1)
        layout.addLayout(audio_hdr)

        self.chk_always_on_top = QCheckBox("Keep window always on top", self)
        self.chk_always_on_top.toggled.connect(self._on_always_on_top_toggled)
        layout.addWidget(self.chk_always_on_top)

        self.chk_normalize = QCheckBox("Volume Normalization (soften loudness spikes)", self)
        self.chk_normalize.toggled.connect(self._on_normalize_toggled)
        layout.addWidget(self.chk_normalize)

        self.chk_endless = QCheckBox("Endless Recommendation Queue", self)
        self.chk_endless.toggled.connect(self._on_endless_toggled)
        layout.addWidget(self.chk_endless)

        self.chk_toast = QCheckBox("Show Now Playing Desktop Notification", self)
        self.chk_toast.toggled.connect(self._on_toast_toggled)
        layout.addWidget(self.chk_toast)

        # Playlist & Library section
        lib_hdr = QHBoxLayout()
        lib_sec = QLabel("PLAYLIST & FAVORITES", self)
        lib_sec.setObjectName("SettingsSection")
        lib_hdr.addWidget(lib_sec)
        lib_hdr.addStretch(1)
        layout.addLayout(lib_hdr)

        lib_grid = QGridLayout()
        lib_grid.setHorizontalSpacing(8)
        lib_grid.setVerticalSpacing(8)
        self.btn_export_json = QPushButton("Export JSON", self)
        self.btn_export_json.setObjectName("Pill")
        self.btn_export_json.setFixedHeight(28)
        self.btn_export_json.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_export_json.clicked.connect(self._export_favorites_json)
        lib_grid.addWidget(self.btn_export_json, 0, 0)

        self.btn_export_m3u = QPushButton("Export M3U", self)
        self.btn_export_m3u.setObjectName("Pill")
        self.btn_export_m3u.setFixedHeight(28)
        self.btn_export_m3u.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_export_m3u.clicked.connect(self._export_favorites_m3u)
        lib_grid.addWidget(self.btn_export_m3u, 0, 1)

        self.btn_import_json = QPushButton("Import JSON", self)
        self.btn_import_json.setObjectName("Pill")
        self.btn_import_json.setFixedHeight(28)
        self.btn_import_json.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_import_json.clicked.connect(self._import_favorites_json)
        lib_grid.addWidget(self.btn_import_json, 1, 0)

        self.btn_import_m3u = QPushButton("Import M3U", self)
        self.btn_import_m3u.setObjectName("Pill")
        self.btn_import_m3u.setFixedHeight(28)
        self.btn_import_m3u.setCursor(Qt.CursorShape.PointingHandCursor)
        self.btn_import_m3u.clicked.connect(self._import_favorites_m3u)
        lib_grid.addWidget(self.btn_import_m3u, 1, 1)

        layout.addLayout(lib_grid)

        self.lib_status_lbl = QLabel("", self)
        self.lib_status_lbl.setStyleSheet("color: #E5A93C; font-size: 10px; font-weight: 600;")
        self.lib_status_lbl.setVisible(False)
        layout.addWidget(self.lib_status_lbl)

        # Hotkeys
        hotkey_hdr = QHBoxLayout()
        key_ico = QLabel(self)
        key_ico.setPixmap(keyboard_icon(Palette.amber).pixmap(14, 14))
        hotkey_sec = QLabel("HOTKEY CHORDS", self)
        hotkey_sec.setObjectName("SettingsSection")
        hotkey_hdr.addWidget(key_ico)
        hotkey_hdr.addWidget(hotkey_sec)
        hotkey_hdr.addStretch(1)
        layout.addLayout(hotkey_hdr)

        self.hotkey_inputs: Dict[str, QLineEdit] = {}
        hotkey_grid = QGridLayout()
        hotkey_grid.setHorizontalSpacing(10)
        hotkey_grid.setVerticalSpacing(6)
        labels = [
            ("toggle", "Play/Pause:", 0, 0),
            ("forward", "Next Track:", 0, 1),
            ("back", "Previous:", 1, 0),
            ("expand", "Toggle Panel:", 1, 1),
        ]
        for key, text, r, c in labels:
            hrow = QHBoxLayout()
            hrow.setSpacing(4)
            hlabel = QLabel(text, self)
            hlabel.setFixedWidth(74)
            hinput = QLineEdit(self)
            hinput.setObjectName("SearchField")
            hinput.setFixedHeight(26)
            hinput.textChanged.connect(self._validate_hotkeys)
            self.hotkey_inputs[key] = hinput
            hrow.addWidget(hlabel)
            hrow.addWidget(hinput, 1)
            hotkey_grid.addLayout(hrow, r, c)
        layout.addLayout(hotkey_grid)

        self.conflict_warn = QLabel("", self)
        self.conflict_warn.setStyleSheet("color: #E26D85; font-size: 10px; font-weight: 700;")
        self.conflict_warn.setVisible(False)
        layout.addWidget(self.conflict_warn)

        # Credits & Attribution
        credits_hdr = QHBoxLayout()
        credits_ico = QLabel(self)
        credits_ico.setPixmap(code_fork_icon(Palette.amber).pixmap(14, 14))
        credits_sec = QLabel("CREDITS & ATTRIBUTION", self)
        credits_sec.setObjectName("SettingsSection")
        credits_hdr.addWidget(credits_ico)
        credits_hdr.addWidget(credits_sec)
        credits_hdr.addStretch(1)
        layout.addLayout(credits_hdr)

        credits_card = QFrame(self)
        credits_card.setObjectName("CreditsCard")
        credits_layout = QVBoxLayout(credits_card)
        credits_layout.setContentsMargins(12, 10, 12, 10)
        credits_layout.setSpacing(8)

        # Taezeem row (Fork Maintainer)
        row1 = QHBoxLayout()
        row1.setSpacing(8)
        u1_ico = QLabel(credits_card)
        u1_ico.setPixmap(user_icon(Palette.amber_hi).pixmap(14, 14))
        row1.addWidget(u1_ico)

        info1 = QVBoxLayout()
        info1.setSpacing(2)
        name1_row = QHBoxLayout()
        name1_row.setSpacing(6)
        name1 = QLabel("Muhammad Taezeem Tariq Matta", credits_card)
        name1.setObjectName("CreditName")
        badge1 = QLabel("MAINTAINER", credits_card)
        badge1.setObjectName("CreditBadge")
        name1_row.addWidget(name1)
        name1_row.addWidget(badge1)
        name1_row.addStretch(1)

        role1 = QLabel("Fork Architect • UI, Lyrics, Storage & Resilience", credits_card)
        role1.setObjectName("CreditRole")
        info1.addLayout(name1_row)
        info1.addWidget(role1)
        row1.addLayout(info1, 1)

        gh1_btn = QPushButton("GitHub", credits_card)
        gh1_btn.setObjectName("Pill")
        gh1_btn.setFixedHeight(28)
        gh1_btn.setFixedWidth(68)
        gh1_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        gh1_btn.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/taezeem14")))
        row1.addWidget(gh1_btn)
        credits_layout.addLayout(row1)

        # Mayank Malaviya row (Original Creator)
        row2 = QHBoxLayout()
        row2.setSpacing(8)
        u2_ico = QLabel(credits_card)
        u2_ico.setPixmap(user_icon(Palette.clay).pixmap(14, 14))
        row2.addWidget(u2_ico)

        info2 = QVBoxLayout()
        info2.setSpacing(2)
        name2_row = QHBoxLayout()
        name2_row.setSpacing(6)
        name2 = QLabel("Mayank Malaviya", credits_card)
        name2.setObjectName("CreditName")
        badge2 = QLabel("ORIGINAL CREATOR", credits_card)
        badge2.setObjectName("CreditBadgeOg")
        name2_row.addWidget(name2)
        name2_row.addWidget(badge2)
        name2_row.addStretch(1)

        role2 = QLabel("Original Ember Concept & Initial Architecture", credits_card)
        role2.setObjectName("CreditRole")
        info2.addLayout(name2_row)
        info2.addWidget(role2)
        row2.addLayout(info2, 1)

        gh2_btn = QPushButton("GitHub", credits_card)
        gh2_btn.setObjectName("Pill")
        gh2_btn.setFixedHeight(28)
        gh2_btn.setFixedWidth(68)
        gh2_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        gh2_btn.clicked.connect(lambda: QDesktopServices.openUrl(QUrl("https://github.com/AIwolfie")))
        row2.addWidget(gh2_btn)
        credits_layout.addLayout(row2)

        layout.addWidget(credits_card)

        layout.addStretch(1)
        scroll.setWidget(body)
        shell_layout.addWidget(scroll, 1)

        # Footer (pinned at bottom)
        footer = QHBoxLayout()
        reset_btn = QPushButton("Reset Hotkeys", self)
        reset_btn.setObjectName("Pill")
        reset_btn.setFixedHeight(28)
        reset_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        reset_btn.clicked.connect(self._reset_hotkeys)
        footer.addWidget(reset_btn)

        footer.addStretch(1)

        save_btn = QPushButton("Save && Done", self)
        save_btn.setObjectName("AmberButton")
        save_btn.setFixedHeight(28)
        save_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        save_btn.clicked.connect(self._save_and_close)
        footer.addWidget(save_btn)

        shell_layout.addLayout(footer)

    def _load_values(self) -> None:
        saved_theme = str(self.settings.value(SETTINGS_THEME, "Amber"))
        idx = self.theme_combo.findText(saved_theme)
        if idx >= 0:
            self.theme_combo.setCurrentIndex(idx)

        try:
            saved_opacity = int(self.settings.value(SETTINGS_OPACITY, DEFAULT_OPACITY))
        except (ValueError, TypeError):
            saved_opacity = DEFAULT_OPACITY
        saved_opacity = max(60, min(100, saved_opacity))
        self.opacity_slider.setValue(saved_opacity)
        self.opacity_val_lbl.setText(f"{saved_opacity}%")

        ontop = str(self.settings.value(SETTINGS_ALWAYS_ON_TOP, "true")).lower() in ("true", "1", "yes")
        self.chk_always_on_top.setChecked(ontop)

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

    def _on_opacity_changed(self, value: int) -> None:
        self.opacity_val_lbl.setText(f"{value}%")
        self.settings.setValue(SETTINGS_OPACITY, value)
        self.settings.sync()
        self.opacity_changed.emit(value)

    def _on_theme_selected(self, theme_name: str) -> None:
        self.settings.setValue(SETTINGS_THEME, theme_name)
        self.settings.sync()
        Palette.apply_theme(theme_name)
        self.setStyleSheet(settings_stylesheet())
        self.theme_changed.emit(theme_name)

    def _on_always_on_top_toggled(self, checked: bool) -> None:
        self.settings.setValue(SETTINGS_ALWAYS_ON_TOP, checked)
        self.settings.sync()
        self.always_on_top_changed.emit(checked)

    def _on_normalize_toggled(self, checked: bool) -> None:
        self.settings.setValue(SETTINGS_NORMALIZE_VOLUME, checked)
        self.settings.sync()
        self.normalization_changed.emit(checked)

    def _on_endless_toggled(self, checked: bool) -> None:
        self.settings.setValue(SETTINGS_AUTO_QUEUE, checked)
        self.settings.sync()
        self.endless_changed.emit(checked)

    def _on_toast_toggled(self, checked: bool) -> None:
        self.settings.setValue(SETTINGS_TOAST_ENABLED, checked)
        self.settings.sync()
        self.toast_changed.emit(checked)

    def _export_favorites_json(self) -> None:
        if not self.storage:
            self.lib_status_lbl.setText("Storage not available.")
            self.lib_status_lbl.setVisible(True)
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Export Favorites (JSON)", "ember_favorites.json", "JSON Files (*.json)"
        )
        if path:
            try:
                data = self.storage.export_favorites_json()
                with open(path, "w", encoding="utf-8") as f:
                    f.write(data)
                self.lib_status_lbl.setText("Favorites exported to JSON.")
                self.lib_status_lbl.setVisible(True)
            except Exception as exc:
                self.lib_status_lbl.setText(f"Export failed: {exc}")
                self.lib_status_lbl.setVisible(True)

    def _export_favorites_m3u(self) -> None:
        if not self.storage:
            self.lib_status_lbl.setText("Storage not available.")
            self.lib_status_lbl.setVisible(True)
            return
        path, _ = QFileDialog.getSaveFileName(
            self, "Export Favorites (M3U)", "ember_playlist.m3u", "M3U Playlist (*.m3u *.m3u8)"
        )
        if path:
            try:
                data = self.storage.export_favorites_m3u()
                with open(path, "w", encoding="utf-8") as f:
                    f.write(data)
                self.lib_status_lbl.setText("Favorites exported to M3U.")
                self.lib_status_lbl.setVisible(True)
            except Exception as exc:
                self.lib_status_lbl.setText(f"Export failed: {exc}")
                self.lib_status_lbl.setVisible(True)

    def _import_favorites_json(self) -> None:
        if not self.storage:
            self.lib_status_lbl.setText("Storage not available.")
            self.lib_status_lbl.setVisible(True)
            return
        path, _ = QFileDialog.getOpenFileName(
            self, "Import Favorites (JSON)", "", "JSON Files (*.json)"
        )
        if path:
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = f.read()
                count = self.storage.import_favorites_json(data)
                self.lib_status_lbl.setText(f"Imported {count} songs into favorites.")
                self.lib_status_lbl.setVisible(True)
            except Exception as exc:
                self.lib_status_lbl.setText(f"Import failed: {exc}")
                self.lib_status_lbl.setVisible(True)

    def _import_favorites_m3u(self) -> None:
        if not self.storage:
            self.lib_status_lbl.setText("Storage not available.")
            self.lib_status_lbl.setVisible(True)
            return
        path, _ = QFileDialog.getOpenFileName(
            self, "Import Favorites (M3U)", "", "M3U Playlist (*.m3u *.m3u8);;All Files (*.*)"
        )
        if path:
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    data = f.read()
                count = self.storage.import_favorites_m3u(data)
                self.lib_status_lbl.setText(f"Imported {count} songs from M3U.")
                self.lib_status_lbl.setVisible(True)
            except Exception as exc:
                self.lib_status_lbl.setText(f"Import failed: {exc}")
                self.lib_status_lbl.setVisible(True)

    def _validate_hotkeys(self) -> None:
        conflicts: List[str] = []
        seen_chords: Dict[str, str] = {}
        for key, inp in self.hotkey_inputs.items():
            chord = inp.text().strip()
            if not chord:
                continue
            seq = QKeySequence(chord)
            if seq.isEmpty():
                conflicts.append(f"'{chord}' (invalid syntax)")
            elif chord in WINDOWS_CONFLICTS:
                conflicts.append(f"'{chord}' (Windows system)")
            elif chord in seen_chords:
                conflicts.append(f"'{chord}' (duplicate)")
            seen_chords[chord] = key
        if conflicts:
            self.conflict_warn.setText(f"Warning: {', '.join(conflicts)} conflict detected!")
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
