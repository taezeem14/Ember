"""Tests for Palette theming and stylesheet rendering."""

from __future__ import annotations

from ember.config import Palette
from ember.theme import panel_stylesheet, popup_stylesheet, settings_stylesheet, toast_stylesheet


def test_palette_default_amber() -> None:
    assert Palette.current_theme == "Amber"
    assert Palette.amber == "#E8A468"
    assert Palette.void == "#1B1411"


def test_palette_theme_switching() -> None:
    themes = Palette.list_themes()
    assert "Amber" in themes
    assert "Emerald" in themes
    assert "Amethyst" in themes
    assert "Solar" in themes
    assert "Rose" in themes

    Palette.apply_theme("Emerald")
    assert Palette.current_theme == "Emerald"
    assert Palette.amber == "#5BC479"

    Palette.apply_theme("Amber")
    assert Palette.current_theme == "Amber"
    assert Palette.amber == "#E8A468"


def test_stylesheet_compilation() -> None:
    for theme in Palette.list_themes():
        Palette.apply_theme(theme)
        panel_css = panel_stylesheet()
        popup_css = popup_stylesheet()
        settings_css = settings_stylesheet()
        toast_css = toast_stylesheet()

        assert "QWidget" in panel_css
        assert "QMenu" in popup_css
        assert "QDialog" in settings_css
        assert "#ToastShell" in toast_css
        # Assert no unrendered placeholders exist
        assert "$text" not in panel_css
        assert "$amber" not in panel_css

    # Reset back to default
    Palette.apply_theme("Amber")
