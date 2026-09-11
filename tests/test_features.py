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

