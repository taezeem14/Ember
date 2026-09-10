"""
theme.py
Every stylesheet Ember uses, built from the Palette with string.Template.

Template (not f-strings) because Qt stylesheets are full of braces and
doubling them all would be unreadable.

# Extended/upgraded by Taezeem (@taezeem14) — fork of Ember
"""

from __future__ import annotations

from string import Template
from typing import Any, Dict

from .config import Palette


def _tokens() -> Dict[str, Any]:
    """Extract string design tokens from the active Palette."""
    tokens: Dict[str, Any] = {}
    for name in dir(Palette):
        if not name.startswith("_") and name not in ("THEMES", "list_themes", "apply_theme", "current_theme"):
            val = getattr(Palette, name)
            if isinstance(val, str):
                tokens[name] = val
    return tokens


_PANEL = Template(
    """
QWidget {
    font-family: "Segoe UI", "Trebuchet MS", sans-serif;
    color: $text;
}

/* ---------------------------------------------------------- window shell */
#Shell {
    background: qlineargradient(x1:0, y1:0, x2:0.85, y2:1,
                stop:0 $shell_a, stop:0.58 $void, stop:1 $shell_b);
    border: 1px solid rgba(244, 233, 221, 0.09);
    border-radius: 20px;
}
#Ribbon, #Panel { background: transparent; }

/* --------------------------------------------------------------- typography */
#Display {
    font-family: Georgia, "Iowan Old Style", "Times New Roman", serif;
    font-size: 19px;
    color: $amber_hi;
    letter-spacing: 1px;
}
#Tagline { color: $faint; font-size: 9px; letter-spacing: 2px; }
#RibbonTitle { color: $text; font-size: 12px; font-weight: 600; }
#RibbonArtist { color: $muted; font-size: 11px; }
#HeroTitle { font-family: Georgia, "Iowan Old Style", serif; font-size: 15px; color: $text; }
#HeroArtist { color: $muted; font-size: 11px; }
#SectionLabel { color: $faint; font-size: 9px; letter-spacing: 2px; }
#Clock { color: $faint; font-size: 10px; }
#Hint { color: $faint; font-size: 9px; }

#StatusChip {
    color: $amber_hi;
    font-size: 10px;
    letter-spacing: 0.4px;
    background: rgba(232, 164, 104, 0.10);
    border: 1px solid rgba(232, 164, 104, 0.22);
    border-radius: 9px;
    padding: 3px 9px;
}

/* ------------------------------------------------------------------ cards */
#NowCard {
    background: rgba(244, 233, 221, 0.035);
    border: 1px solid $line;
    border-radius: 16px;
}

/* ----------------------------------------------------------------- inputs */
#SearchField {
    background: $raised;
    border: 1px solid $line;
    border-radius: 12px;
    padding: 8px 12px;
    color: $text;
    font-size: 12px;
    selection-background-color: $amber_lo;
    selection-color: $ink;
}
#SearchField:focus { border: 1px solid $amber; background: #3A2A20; }

/* ---------------------------------------------------------------- buttons */
#AmberButton {
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 $amber_hi, stop:1 $amber);
    color: $ink;
    font-weight: 700;
    font-size: 12px;
    border: none;
    border-radius: 12px;
    padding: 0 16px;
}
#AmberButton:hover { background: $amber_hi; }
#AmberButton:pressed { background: $amber_lo; }
#AmberButton:disabled { background: $raised; color: $faint; }

#RoundPlay {
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 $amber_hi, stop:1 $amber);
    color: $ink;
    font-size: 14px;
    border: none;
    border-radius: 19px;
}
#RoundPlayBig {
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 $amber_hi, stop:1 $amber);
    color: $ink;
    font-size: 19px;
    border: none;
    border-radius: 27px;
}
#RoundPlay:hover, #RoundPlayBig:hover { background: $amber_hi; }
#RoundPlay:pressed, #RoundPlayBig:pressed { background: $amber_lo; }

#Ghost {
    background: transparent;
    color: $muted;
    font-size: 15px;
    border: none;
    border-radius: 16px;
}
#Ghost:hover { background: rgba(244, 233, 221, 0.07); color: $text; }
#Ghost:pressed { background: rgba(244, 233, 221, 0.12); }

#Pill {
    background: rgba(244, 233, 221, 0.05);
    color: $muted;
    font-size: 11px;
    border: none;
    border-radius: 13px;
}
#Pill:hover { background: rgba(244, 233, 221, 0.13); color: $text; }
#PillClose:hover { background: rgba(201, 127, 106, 0.32); color: #FFE8DF; }

#HeartButton {
    background: transparent;
    color: $muted;
    font-size: 14px;
    border: none;
    border-radius: 13px;
}
#HeartButton:hover { color: $clay; background: rgba(201, 127, 106, 0.12); }
#HeartButton[active="true"] { color: $clay; }

#Chip {
    background: rgba(244, 233, 221, 0.05);
    border: 1px solid $line;
    border-radius: 11px;
    color: $muted;
    font-size: 10px;
    letter-spacing: 0.4px;
    padding: 4px 10px;
}
#Chip:hover { color: $text; border: 1px solid $faint; }
#Chip:checked {
    background: rgba(232, 164, 104, 0.16);
    border: 1px solid rgba(232, 164, 104, 0.42);
    color: $amber_hi;
}

#TabButton {
    background: transparent;
    border: none;
    border-radius: 10px;
    color: $muted;
    font-size: 10px;
    letter-spacing: 0.5px;
    padding: 3px 8px;
    font-weight: 600;
}
#TabButton:hover { color: $text; background: rgba(244, 233, 221, 0.06); }
#TabButton:checked {
    background: rgba(232, 164, 104, 0.18);
    color: $amber_hi;
}

/* ---------------------------------------------------------------- sliders */
#Seek::groove:horizontal { height: 5px; background: $raised; border-radius: 3px; }
#Seek::sub-page:horizontal {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 $amber_lo, stop:1 $amber_hi);
    border-radius: 3px;
}
#Seek::handle:horizontal {
    background: $text;
    border: 2px solid $amber;
    width: 9px;
    height: 9px;
    margin: -4px 0;
    border-radius: 7px;
}
#Seek::handle:horizontal:hover { background: $amber_hi; }

#Volume::groove:horizontal { height: 4px; background: $raised; border-radius: 2px; }
#Volume::sub-page:horizontal { background: $muted; border-radius: 2px; }
#Volume::handle:horizontal {
    background: $text;
    width: 7px;
    height: 7px;
    margin: -3px 0;
    border-radius: 5px;
}
#Volume::handle:horizontal:hover { background: $amber_hi; }

/* ------------------------------------------------------------------ queue */
#QueueScroll { background: transparent; border: none; }
#QueueScroll > QWidget > QWidget { background: transparent; }
QScrollBar:vertical { background: transparent; width: 6px; margin: 2px 0; }
QScrollBar::handle:vertical { background: $line; border-radius: 3px; min-height: 28px; }
QScrollBar::handle:vertical:hover { background: $faint; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical { background: transparent; }
"""
)

_MENU = Template(
    """
QMenu {
    background: $surface;
    border: 1px solid $line;
    border-radius: 12px;
    padding: 6px;
}
QMenu::item {
    padding: 7px 20px 7px 14px;
    border-radius: 8px;
    color: $text;
    font-size: 12px;
}
QMenu::item:selected { background: rgba(232, 164, 104, 0.18); color: $amber_hi; }
QMenu::separator { height: 1px; background: $line; margin: 5px 8px; }
QToolTip {
    background: $surface;
    color: $text;
    border: 1px solid $line;
    border-radius: 6px;
    padding: 4px 8px;
}
"""
)

_SETTINGS = Template(
    """
QDialog {
    background: $surface;
    border: 1px solid $line;
    border-radius: 16px;
    color: $text;
}
QLabel { color: $text; font-size: 12px; }
#SettingsTitle {
    font-family: Georgia, "Iowan Old Style", serif;
    font-size: 16px;
    color: $amber_hi;
}
#SettingsSub { color: $faint; font-size: 10px; }
#SettingsSection { color: $amber; font-size: 11px; font-weight: 700; letter-spacing: 1px; }
QCheckBox { color: $text; font-size: 12px; spacing: 8px; }
QCheckBox::indicator { width: 16px; height: 16px; border: 1px solid $line; border-radius: 4px; background: $raised; }
QCheckBox::indicator:checked { background: $amber; border: 1px solid $amber_hi; }
QComboBox {
    background: $raised;
    color: $text;
    border: 1px solid $line;
    border-radius: 8px;
    padding: 5px 10px;
    font-size: 12px;
}
QComboBox QAbstractItemView {
    background: $surface;
    color: $text;
    selection-background-color: $raised;
    border: 1px solid $line;
}
QPushButton#SettingsClose {
    background: $raised;
    color: $text;
    border: 1px solid $line;
    border-radius: 10px;
    padding: 6px 14px;
    font-size: 11px;
}
QPushButton#SettingsClose:hover { background: $line; }
"""
)

_TOAST = Template(
    """
#ToastShell {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 $shell_a, stop:1 $void);
    border: 1px solid rgba(244, 233, 221, 0.12);
    border-radius: 14px;
}
#ToastTitle { color: $text; font-size: 12px; font-weight: 600; }
#ToastArtist { color: $muted; font-size: 11px; }
#ToastBadge { color: $amber_hi; font-size: 9px; letter-spacing: 1px; font-weight: 700; }
"""
)


def panel_stylesheet() -> str:
    """Full stylesheet for the floating panel and everything inside it."""
    return _PANEL.substitute(_tokens())


def popup_stylesheet() -> str:
    """Applied application-wide — only touches menus and tooltips."""
    return _MENU.substitute(_tokens())


def settings_stylesheet() -> str:
    """Stylesheet for the preferences and settings dialog."""
    return _SETTINGS.substitute(_tokens())


def toast_stylesheet() -> str:
    """Stylesheet for the now-playing desktop toast notification."""
    return _TOAST.substitute(_tokens())