"""Tests for upgraded features: spring equalizer physics and opacity settings."""

from __future__ import annotations

from ember.config import (
    DEFAULT_OPACITY,
    SETTINGS_ALWAYS_ON_TOP,
    SETTINGS_OPACITY,
    SETTINGS_REPEAT,
    SETTINGS_SPEED,
)
from ember.panel import SpringPhysics
from ember.utils import clock


def test_spring_physics_simulation_steps() -> None:
    pos = [3.5, 3.5, 3.5, 3.5]
    vel = [0.0, 0.0, 0.0, 0.0]

    # Step through 20 simulation frames
    for step_idx in range(1, 21):
        pos, vel = SpringPhysics.step(pos, vel, step_idx)
        assert len(pos) == 4
        assert len(vel) == 4
        for p in pos:
            # Heights are bounded within visual bar canvas [2.5, 13.5]
            assert 2.5 <= p <= 13.5

    # Ensure dynamic movement occurred
    assert any(abs(v) > 0.01 for v in vel)


def test_spring_physics_custom_damping_and_stiffness() -> None:
    pos = [1.0, 1.0]
    vel = [0.0, 0.0]
    new_pos, new_vel = SpringPhysics.step(pos, vel, step_idx=5, stiffness=0.5, damping=0.8)
    assert len(new_pos) == 2
    assert len(new_vel) == 2


def test_feature_settings_keys() -> None:
    assert 60 <= DEFAULT_OPACITY <= 100
    assert SETTINGS_OPACITY == "ui/opacity"
    assert SETTINGS_REPEAT == "playback/repeat"
    assert SETTINGS_SPEED == "playback/speed"
    assert SETTINGS_ALWAYS_ON_TOP == "ui/always_on_top"


def test_remaining_time_countdown_calculation() -> None:
    duration_ms = 210 * 1000  # 3m 30s
    position_ms = 75 * 1000   # 1m 15s

    elapsed_str = clock(position_ms)
    assert elapsed_str == "1:15"

    remaining_ms = max(0, duration_ms - position_ms)
    remaining_str = f"-{clock(remaining_ms)}"
    assert remaining_str == "-2:15"

    # Edge cases
    assert f"-{clock(max(0, duration_ms - duration_ms))}" == "-0:00"
    assert f"-{clock(max(0, 10000 - 20000))}" == "-0:00"


def test_seekbar_range_and_bounds() -> None:
    from PyQt6.QtWidgets import QApplication
    from ember.panel import SeekBar
    _ = QApplication.instance() or QApplication([])

    seek = SeekBar()
    assert seek.maximum() == 0
    assert seek.minimum() == 0
    assert seek.value() == 0

    seek.setRange(0, 180000)
    assert seek.maximum() == 180000
    assert seek.minimum() == 0

    seek.setValue(45000)
    assert seek.value() == 45000

    # Clamping
    seek.setValue(250000)
    assert seek.value() == 180000
    seek.setValue(-500)
    assert seek.value() == 0


def test_volumedial_value_and_alias() -> None:
    from PyQt6.QtWidgets import QApplication
    from ember.panel import VolumeDial
    _ = QApplication.instance() or QApplication([])

    dial = VolumeDial(50)
    assert dial.value() == 50

    dial.set_value(75)
    assert dial.value() == 75

    # Qt compatibility alias
    dial.setValue(35)
    assert dial.value() == 35


def test_stream_resolver_is_url_expired() -> None:
    import time
    from ember.stream import StreamResolver, is_url_expired

    # None or empty
    assert is_url_expired(None) is True
    assert StreamResolver.is_url_expired(None) is True
    assert is_url_expired("") is True

    # Future expiry
    future_ts = int(time.time()) + 3600
    future_url = f"https://rr1---sn.googlevideo.com/videoplayback?expire={future_ts}&id=abc"
    assert is_url_expired(future_url) is False
    assert StreamResolver.is_url_expired(future_url) is False

    # Past expiry
    past_ts = int(time.time()) - 100
    past_url = f"https://rr1---sn.googlevideo.com/videoplayback?expire={past_ts}&id=abc"
    assert is_url_expired(past_url) is True
    assert StreamResolver.is_url_expired(past_url) is True


def test_dominant_color_extractor() -> None:
    import sys
    from PyQt6.QtWidgets import QApplication
    from PyQt6.QtGui import QPixmap, QColor
    from ember.panel import DominantColorExtractor
    from ember.config import Palette

    app = QApplication.instance() or QApplication(sys.argv)

    # Null pixmap fallback
    null_pix = QPixmap()
    assert DominantColorExtractor.extract(null_pix).name() == QColor(Palette.amber).name()

    # Vibrant colored pixmap
    colored = QPixmap(32, 32)
    colored.fill(QColor(245, 158, 11))
    extracted = DominantColorExtractor.extract(colored)
    assert extracted.red() > 200
    assert extracted.green() > 100


def test_studio_spectrum_visualizer() -> None:
    import sys
    from PyQt6.QtWidgets import QApplication
    from ember.panel import StudioSpectrumVisualizer

    app = QApplication.instance() or QApplication(sys.argv)

    vis = StudioSpectrumVisualizer()
    vis.set_levels([0.1, 0.5, 0.9])
    assert len(vis._bands) == 3
    assert vis._bands[2] == 0.9
    assert vis._peaks[2] == 0.9

    # Decaying peak
    vis.set_levels([0.1, 0.2, 0.3])
    assert vis._bands[2] == 0.3
    assert vis._peaks[2] <= 0.9


def test_sound_shaping_view() -> None:
    import sys
    from PyQt6.QtWidgets import QApplication
    from ember.panel import SoundShapingView

    app = QApplication.instance() or QApplication(sys.argv)

    view = SoundShapingView()
    emitted_presets = []
    view.preset_selected.connect(emitted_presets.append)

    view._on_preset("warm")
    assert emitted_presets == ["warm"]
    assert view._sliders[0].value() == 3

    view._on_preset("lofi")
    assert emitted_presets[-1] == "lofi"
    assert view._sliders[0].value() == 5

    emitted_crossfeed = []
    view.crossfeed_toggled.connect(emitted_crossfeed.append)
    view.crossfeed_btn.setChecked(False)
    view.crossfeed_btn.clicked.emit()
    assert emitted_crossfeed == [False]


def test_cozy_moods_catalog() -> None:
    from ember.catalog import COZY_MOODS

    assert "lofi" in COZY_MOODS
    assert "rainy" in COZY_MOODS
    assert "jazz" in COZY_MOODS
    assert "fireside" in COZY_MOODS
    assert "chillhop" in COZY_MOODS
    assert "autumn" in COZY_MOODS
    assert len(COZY_MOODS["lofi"]) > 0



