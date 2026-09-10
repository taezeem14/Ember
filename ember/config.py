"""
config.py
Branding, palette, geometry and tunables for Ember.

Everything visual lives here so the theme can be re-tuned in one place
without touching layout logic.
"""

from __future__ import annotations

APP_NAME = "Ember"
APP_TAGLINE = "cozy listening"
ORG_NAME = "Ember Audio"
APP_ID = "ember.desktop.companion"

# ---------------------------------------------------------------- geometry
PANEL_WIDTH = 392
SHELL_MARGIN = 10          # transparent gutter that gives the drop shadow room
COMPACT_HEIGHT = 62        # ribbon shell height
ART_COMPACT = 38
ART_HERO = 76
QUEUE_VIEW_HEIGHT = 168
EXPANDED_HEIGHT = 512      # full panel shell height

# ---------------------------------------------------------------- behaviour
RADIO_DEPTH = 26           # how many look-alike tracks we pull per seed
SEARCH_DEPTH = 12
DEFAULT_VOLUME = 78
SEEK_MS_BACKSTEP = 3500    # "previous" restarts the song if we're past this
VINYL_TICK_MS = 55
VINYL_DEGREES = 0.5        # rotation per tick while audio is playing
ARTWORK_CACHE_LIMIT = 64
ANIM_MS = 240

# ---------------------------------------------------------------- settings keys
SETTINGS_POS_X = "panel/x"
SETTINGS_POS_Y = "panel/y"
SETTINGS_EXPANDED = "panel/expanded"
SETTINGS_VOLUME = "audio/volume"
SETTINGS_AUTO_QUEUE = "queue/endless"


class Palette:
    """Warm, low-light palette. Espresso base, amber light, cream type."""

    void = "#1B1411"
    shell_a = "#281B15"
    shell_b = "#191210"
    surface = "#2A1E18"
    raised = "#34241C"
    line = "#3E2C22"

    text = "#F4E9DD"
    muted = "#B79B86"
    faint = "#8A7060"

    amber = "#E8A468"
    amber_hi = "#F5C495"
    amber_lo = "#C07A38"

    clay = "#C97F6A"
    sage = "#9FBFA3"

    ink = "#2A1A0E"        # text drawn on top of amber fills