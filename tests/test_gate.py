"""Tests for passkeys and gate modules."""

from __future__ import annotations

import pytest
from PyQt6.QtCore import QSettings

from ember.config import APP_NAME, ORG_NAME, SETTINGS_ACTIVATED
from ember.gate import _hash_key, is_activated
from ember.passkeys import PASSKEYS, is_valid


def test_passkeys_count() -> None:
    """Verify exactly 100 unique passkeys are configured."""
    assert len(PASSKEYS) == 100


def test_passkeys_format() -> None:
    """Verify every passkey adheres to the EMBR-XXXX format."""
    for key in PASSKEYS:
        assert key.startswith("EMBR-")
        assert len(key) == 9
        # Alphanumeric suffix of 4 chars
        assert key[5:].isalnum()


def test_is_valid() -> None:
    """Test passkey validation including case insensitivity and whitespace."""
    # Pick a known key
    sample = next(iter(PASSKEYS))
    assert is_valid(sample)
    assert is_valid(sample.lower())
    assert is_valid(f"  {sample.lower()}  ")

    # Invalid cases
    assert not is_valid("INVALID-KEY")
    assert not is_valid("EMBR-ZZZZ")
    assert not is_valid("")
    assert not is_valid(None)  # type: ignore[arg-type]
    assert not is_valid(12345)  # type: ignore[arg-type]


def test_hash_key() -> None:
    """Test that passkey hashing is deterministic and produces SHA-256 hex digest."""
    h1 = _hash_key("EMBR-A7K9")
    h2 = _hash_key("embr-a7k9")
    h3 = _hash_key("  EMBR-A7K9  ")
    assert h1 == h2 == h3
    assert len(h1) == 64
    assert isinstance(h1, str)


def test_is_activated_persistence() -> None:
    """Test activation check against QSettings."""
    settings = QSettings(ORG_NAME, APP_NAME)
    original = settings.value(SETTINGS_ACTIVATED, None)
    try:
        # Clear activation
        settings.remove(SETTINGS_ACTIVATED)
        settings.sync()
        assert not is_activated()

        # Set valid hash
        settings.setValue(SETTINGS_ACTIVATED, _hash_key("EMBR-A7K9"))
        settings.sync()
        assert is_activated()
    finally:
        # Restore original state if there was one
        if original is not None:
            settings.setValue(SETTINGS_ACTIVATED, original)
        else:
            settings.remove(SETTINGS_ACTIVATED)
        settings.sync()
