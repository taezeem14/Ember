"""
gate.py
Passkey activation gate — a frameless, dark-themed dialog that blocks the
app until a valid passkey is entered. Once activated the hash is persisted
in QSettings and the gate is never shown again.

# Written by Muhammad Taezeem Tariq (@taezeem14) — Ember
"""

from __future__ import annotations

import hashlib
import logging
from string import Template

from PyQt6.QtCore import QPoint, QPropertyAnimation, QEasingCurve, QSettings, Qt
from PyQt6.QtGui import QFont, QMouseEvent
from PyQt6.QtWidgets import (
    QApplication,
    QDialog,
    QGraphicsOpacityEffect,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .config import (
    APP_NAME,
    APP_TAGLINE,
    ORG_NAME,
    Palette,
    SETTINGS_ACTIVATED,
)
from .passkeys import is_valid
from .tray import ember_icon

log = logging.getLogger(__name__)

# ------------------------------------------------------------------ constants
_GATE_WIDTH = 380
_GATE_HEIGHT = 340
_HASH_SALT = "ember:gate:v1"


def _hash_key(code: str) -> str:
    """Deterministic SHA-256 hash of the passkey for safe persistence."""
    payload = f"{_HASH_SALT}:{code.strip().upper()}"
    return hashlib.sha256(payload.encode()).hexdigest()


def _gate_stylesheet() -> str:
    """Build the gate stylesheet from current Palette tokens."""
    tokens: dict[str, str] = {}
    for name in dir(Palette):
        if not name.startswith("_") and name not in ("THEMES", "list_themes", "apply_theme", "current_theme"):
            val = getattr(Palette, name)
            if isinstance(val, str):
                tokens[name] = val
                if val.startswith("#") and len(val) == 7:
                    try:
                        r = int(val[1:3], 16)
                        g = int(val[3:5], 16)
                        b = int(val[5:7], 16)
                        tokens[f"{name}_rgb"] = f"{r}, {g}, {b}"
                    except ValueError:
                        pass

    tpl = Template("""
QDialog {
    background: transparent;
}
#GateShell {
    background: qlineargradient(x1:0, y1:0, x2:0.9, y2:1,
                stop:0 $shell_a, stop:0.55 $void, stop:1 $shell_b);
    border: 1px solid rgba($text_rgb, 0.14);
    border-radius: 26px;
}
#GateTitle {
    font-size: 22px;
    font-weight: 800;
    color: $amber_hi;
    letter-spacing: 1.5px;
}
#GateTagline {
    color: $faint;
    font-size: 10px;
    font-weight: 600;
}
#GateHint {
    color: $muted;
    font-size: 10px;
}
#GateError {
    color: $clay;
    font-size: 10px;
    font-weight: 600;
}
#GateInput {
    background: $raised;
    border: 1px solid $line;
    border-radius: 18px;
    padding: 10px 18px;
    color: $text;
    font-size: 14px;
    font-weight: 700;
    font-family: "Consolas", "Courier New", monospace;
    letter-spacing: 2px;
    selection-background-color: $amber_lo;
    selection-color: $ink;
}
#GateInput:focus {
    border: 1px solid $amber;
    border-radius: 18px;
    background: $surface;
}
#GateSubmit {
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 $amber_hi, stop:1 $amber);
    color: $ink;
    font-weight: 700;
    font-size: 12px;
    border: none;
    border-radius: 18px;
    padding: 10px 28px;
}
#GateSubmit:hover {
    background: qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 #FFFFFF, stop:1 $amber_hi);
    border-radius: 18px;
}
#GateSubmit:pressed {
    background: $amber_lo;
    border-radius: 18px;
}
#GateCredit {
    color: $faint;
    font-size: 9px;
    font-style: italic;
}
""")
    return tpl.substitute(tokens)


# ------------------------------------------------------------------ dialog
class PasskeyGate(QDialog):
    """Frameless activation gate — blocks until a valid passkey is submitted."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Dialog
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setFixedSize(_GATE_WIDTH, _GATE_HEIGHT)
        self.setWindowTitle(f"{APP_NAME} — Activation")
        self.setWindowIcon(ember_icon())

        self._drag_origin: QPoint | None = None
        self._activated = False

        self._build_ui()
        self.setStyleSheet(_gate_stylesheet())
        self._center()

    # ─── layout ──────────────────────────────────────────────────────
    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)

        self._shell = QWidget()
        self._shell.setObjectName("GateShell")
        outer.addWidget(self._shell)

        lay = QVBoxLayout(self._shell)
        lay.setContentsMargins(32, 36, 32, 28)
        lay.setSpacing(0)

        # ── ember icon ───────────────────────────────────────────────
        icon_label = QLabel()
        icon_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        pixmap = ember_icon().pixmap(48, 48)
        icon_label.setPixmap(pixmap)
        lay.addWidget(icon_label)
        lay.addSpacing(12)

        # ── title ────────────────────────────────────────────────────
        title = QLabel(APP_NAME.upper())
        title.setObjectName("GateTitle")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(title)
        lay.addSpacing(2)

        tagline = QLabel(APP_TAGLINE)
        tagline.setObjectName("GateTagline")
        tagline.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(tagline)
        lay.addSpacing(20)

        # ── hint ─────────────────────────────────────────────────────
        hint = QLabel("Enter your activation passkey")
        hint.setObjectName("GateHint")
        hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(hint)
        lay.addSpacing(8)

        # ── input ────────────────────────────────────────────────────
        self._input = QLineEdit()
        self._input.setObjectName("GateInput")
        self._input.setPlaceholderText("EMBR-XXXX")
        self._input.setMaxLength(9)
        self._input.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._input.returnPressed.connect(self._submit)
        lay.addWidget(self._input)
        lay.addSpacing(6)

        # ── error label ──────────────────────────────────────────────
        self._error = QLabel("")
        self._error.setObjectName("GateError")
        self._error.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._error.setFixedHeight(16)
        lay.addWidget(self._error)
        lay.addSpacing(8)

        # ── submit button ────────────────────────────────────────────
        self._btn = QPushButton("Activate")
        self._btn.setObjectName("GateSubmit")
        self._btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self._btn.setFixedHeight(40)
        self._btn.clicked.connect(self._submit)
        lay.addWidget(self._btn)

        lay.addStretch()

        # ── credit ───────────────────────────────────────────────────
        credit = QLabel("crafted by Muhammad Taezeem Tariq • @taezeem14")
        credit.setObjectName("GateCredit")
        credit.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lay.addWidget(credit)

    # ─── validation ──────────────────────────────────────────────────
    def _submit(self) -> None:
        code = self._input.text().strip()
        if is_valid(code):
            log.info("passkey accepted — activating Ember")
            settings = QSettings(ORG_NAME, APP_NAME)
            settings.setValue(SETTINGS_ACTIVATED, _hash_key(code))
            settings.sync()
            self._activated = True
            self.accept()
        else:
            self._error.setText("Invalid passkey — please try again")
            self._shake()

    def _shake(self) -> None:
        """Horizontal shake animation on failed validation."""
        origin = self.pos()
        anim = QPropertyAnimation(self, b"pos", self)
        anim.setDuration(400)
        anim.setEasingCurve(QEasingCurve.Type.InOutQuad)
        anim.setKeyValueAt(0.0, origin)
        anim.setKeyValueAt(0.15, origin + QPoint(-12, 0))
        anim.setKeyValueAt(0.30, origin + QPoint(10, 0))
        anim.setKeyValueAt(0.50, origin + QPoint(-8, 0))
        anim.setKeyValueAt(0.70, origin + QPoint(6, 0))
        anim.setKeyValueAt(0.85, origin + QPoint(-3, 0))
        anim.setKeyValueAt(1.0, origin)
        anim.start()
        # prevent garbage collection of the animation
        self._anim = anim

    @property
    def activated(self) -> bool:
        return self._activated

    # ─── window dragging ─────────────────────────────────────────────
    def mousePressEvent(self, event: QMouseEvent | None) -> None:
        if event and event.button() == Qt.MouseButton.LeftButton:
            self._drag_origin = event.globalPosition().toPoint() - self.pos()
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event: QMouseEvent | None) -> None:
        if event and self._drag_origin is not None:
            self.move(event.globalPosition().toPoint() - self._drag_origin)
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event: QMouseEvent | None) -> None:
        self._drag_origin = None
        super().mouseReleaseEvent(event)

    # ─── helpers ─────────────────────────────────────────────────────
    def _center(self) -> None:
        screen = QApplication.primaryScreen()
        if screen:
            geo = screen.availableGeometry()
            x = geo.x() + (geo.width() - self.width()) // 2
            y = geo.y() + (geo.height() - self.height()) // 2
            self.move(x, y)


# ------------------------------------------------------------------ helpers
def is_activated() -> bool:
    """Check whether the app was previously activated."""
    settings = QSettings(ORG_NAME, APP_NAME)
    stored = settings.value(SETTINGS_ACTIVATED, "")
    return bool(stored and isinstance(stored, str) and len(stored) == 64)
