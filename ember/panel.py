"""
panel.py
The floating Ember surface: a compact ribbon that expands into a full panel.

Layout is hand-built rather than designer-generated so the drag maths, the
z-order forcing and the expand/collapse resize all stay in one place. Every
colour comes from config.Palette via theme.panel_stylesheet() — the only
painted widgets are the ones Qt stylesheets cannot express (the vinyl disc,
the volume dial, the equaliser bars).
"""

from __future__ import annotations

import logging
import sys
from typing import Callable, Dict, List, Optional, Tuple

from PyQt6.QtCore import QPoint, QRectF, QSize, Qt, QTimer, pyqtSignal
from PyQt6.QtGui import (
    QColor,
    QFont,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
)
from PyQt6.QtWidgets import (
    QFrame,
    QGraphicsDropShadowEffect,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QSizePolicy,
    QSlider,
    QVBoxLayout,
    QWidget,
)

from .config import (
    ANIM_MS,
    APP_NAME,
    APP_TAGLINE,
    ART_COMPACT,
    ART_HERO,
    ARTWORK_CACHE_LIMIT,
    COMPACT_HEIGHT,
    EXPANDED_HEIGHT,
    PANEL_WIDTH,
    Palette,
    QUEUE_VIEW_HEIGHT,
    SHELL_MARGIN,
    VINYL_DEGREES,
    VINYL_TICK_MS,
)
from .jobs import ArtJob
from .models import Song
from .player import PlaybackCore
from .theme import panel_stylesheet
from .utils import clock, elide_into, looks_like_link, pretty_count

log = logging.getLogger(__name__)

HWND_TOPMOST = -1
SWP_NOSIZE = 0x0001
SWP_NOMOVE = 0x0002
SWP_NOACTIVATE = 0x0010


# ---------------------------------------------------------------- paint helpers
def rounded_pixmap(source: QPixmap, radius: int) -> QPixmap:
    """Clip a pixmap to a rounded square, scaled to fill first."""
    scaled = source.scaled(
        QSize(radius * 2, radius * 2).expandedTo(source.size()),
        Qt.AspectRatioMode.KeepAspectRatioByExpanding,
        Qt.TransformationMode.SmoothTransformation,
    )
    side = min(scaled.width(), scaled.height())
    cropped = scaled.copy(
        (scaled.width() - side) // 2, (scaled.height() - side) // 2, side, side
    )
    canvas = QPixmap(side, side)
    canvas.fill(Qt.GlobalColor.transparent)

    painter = QPainter(canvas)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
    path = QPainterPath()
    path.addRoundedRect(QRectF(0, 0, side, side), side * 0.22, side * 0.22)
    painter.setClipPath(path)
    painter.drawPixmap(0, 0, cropped)
    painter.end()
    return canvas


# ------------------------------------------------------------------ primitives
class Hairline(QFrame):
    """One-pixel separator that inherits the palette line colour."""

    def __init__(self, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.setFixedHeight(1)
        self.setStyleSheet(f"background: {Palette.line}; border: none;")


class SeekBar(QSlider):
    """Horizontal slider that jumps straight to wherever you click."""

    scrubbed = pyqtSignal(int)
    released = pyqtSignal(int)

    def __init__(self, parent: Optional[QWidget] = None) -> None:
        super().__init__(Qt.Orientation.Horizontal, parent)
        self.setObjectName("Seek")
        self.setRange(0, 0)
        self.setSingleStep(1000)
        self.setPageStep(10000)
        self.setFixedHeight(18)
        self._scrubbing = False

    def _value_at(self, x: int) -> int:
        span = max(1, self.width())
        ratio = min(1.0, max(0.0, x / span))
        return int(self.minimum() + ratio * (self.maximum() - self.minimum()))

    def mousePressEvent(self, event) -> None:  # noqa: N802 - Qt naming
        if event.button() == Qt.MouseButton.LeftButton:
            self._scrubbing = True
            value = self._value_at(int(event.position().x()))
            self.setValue(value)
            self.scrubbed.emit(value)
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event) -> None:  # noqa: N802
        if self._scrubbing:
            value = self._value_at(int(event.position().x()))
            self.setValue(value)
            self.scrubbed.emit(value)
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event) -> None:  # noqa: N802
        if self._scrubbing:
            self._scrubbing = False
            self.released.emit(self.value())
        super().mouseReleaseEvent(event)


class VinylDisc(QWidget):
    """Painted record that spins while audio is playing."""

    def __init__(self, diameter: int, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.setFixedSize(diameter, diameter)
        self._angle = 0.0
        self._spinning = False
        self._timer = QTimer(self)
        self._timer.setInterval(VINYL_TICK_MS)
        self._timer.timeout.connect(self._tick)

    def set_spinning(self, spinning: bool) -> None:
        self._spinning = bool(spinning)
        if self._spinning and not self._timer.isActive():
            self._timer.start()
        elif not self._spinning:
            self._timer.stop()

    def _tick(self) -> None:
        self._angle = (self._angle + VINYL_DEGREES) % 360.0
        self.update()

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        side = min(self.width(), self.height())
        painter.translate(self.width() / 2.0, self.height() / 2.0)
        painter.rotate(self._angle)

        disc = QRectF(-side / 2.0, -side / 2.0, side, side)
        gradient = QLinearGradient(disc.topLeft(), disc.bottomRight())
        gradient.setColorAt(0.0, QColor(Palette.raised))
        gradient.setColorAt(1.0, QColor(Palette.void))

        painter.setPen(QPen(QColor(Palette.line), 1.0))
        painter.setBrush(gradient)
        painter.drawEllipse(disc.adjusted(1, 1, -1, -1))

        groove = QPen(QColor(255, 255, 255, 14), 1.0)
        painter.setPen(groove)
        painter.setBrush(Qt.BrushStyle.NoBrush)
        for step in range(3, int(side / 2), 4):
            painter.drawEllipse(QRectF(-step, -step, step * 2, step * 2))

        label_side = side * 0.34
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QColor(Palette.amber))
        painter.drawEllipse(QRectF(-label_side / 2, -label_side / 2, label_side, label_side))

        painter.setBrush(QColor(Palette.void))
        painter.drawEllipse(QRectF(-side * 0.035, -side * 0.035, side * 0.07, side * 0.07))
        painter.end()


class EqualiserBars(QWidget):
    """Three bars that breathe while their row is the playing row."""

    def __init__(self, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.setFixedSize(16, 14)
        self._phase = 0
        self._on = False
        self._timer = QTimer(self)
        self._timer.setInterval(120)
        self._timer.timeout.connect(self._tick)

    def set_on(self, on: bool) -> None:
        self._on = bool(on)
        if self._on and not self._timer.isActive():
            self._timer.start()
        elif not self._on:
            self._timer.stop()
        self.update()

    def _tick(self) -> None:
        self._phase = (self._phase + 1) % 6
        self.update()

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
        painter.setPen(Qt.PenStyle.NoPen)

        if not self._on:
            painter.setBrush(QColor(Palette.faint))
            for column in range(3):
                painter.drawRoundedRect(QRectF(column * 5.0, 9.0, 3.0, 5.0), 1.5, 1.5)
            painter.end()
            return

        painter.setBrush(QColor(Palette.amber_hi))
        profile = (4.0, 11.0, 6.0)
        for column in range(3):
            swing = (self._phase + column * 2) % 6
            height = profile[column] + (swing - 3) * 0.9
            height = max(3.5, min(13.0, height))
            painter.drawRoundedRect(
                QRectF(column * 5.0, 14.0 - height, 3.0, height), 1.5, 1.5
            )
        painter.end()


class VolumeDial(QWidget):
    """Vertical-drag dial. Cozy alternative to a flat volume slider."""

    changed = pyqtSignal(int)

    def __init__(self, value: int, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.setFixedSize(30, 30)
        self.setCursor(Qt.CursorShape.SizeVerCursor)
        self._value = max(0, min(100, int(value)))
        self._drag_origin: Optional[QPoint] = None
        self._drag_value = self._value
        self.setToolTip(f"volume {self._value}%")

    def value(self) -> int:
        return self._value

    def set_value(self, value: int) -> None:
        clamped = max(0, min(100, int(value)))
        if clamped != self._value:
            self._value = clamped
            self.setToolTip(f"volume {clamped}%")
            self.update()

    def mousePressEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_origin = event.globalPosition().toPoint()
            self._drag_value = self._value

    def mouseMoveEvent(self, event) -> None:  # noqa: N802
        if self._drag_origin is None:
            return
        delta = self._drag_origin.y() - event.globalPosition().toPoint().y()
        target = max(0, min(100, self._drag_value + int(delta / 1.2)))
        if target != self._value:
            self._value = target
            self.setToolTip(f"volume {target}%")
            self.changed.emit(target)
            self.update()

    def mouseReleaseEvent(self, event) -> None:  # noqa: N802
        self._drag_origin = None

    def wheelEvent(self, event) -> None:  # noqa: N802
        step = 4 if event.angleDelta().y() > 0 else -4
        target = max(0, min(100, self._value + step))
        if target != self._value:
            self._value = target
            self.setToolTip(f"volume {target}%")
            self.changed.emit(target)
            self.update()

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)

        ring = QRectF(3.0, 3.0, 24.0, 24.0)
        painter.setPen(QPen(QColor(Palette.line), 2.5))
        painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawArc(ring, 0, 360 * 16)

        span = int(-self._value / 100.0 * 360 * 16)
        painter.setPen(QPen(QColor(Palette.amber), 2.5))
        painter.drawArc(ring, 90 * 16, span)

        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QColor(Palette.text))
        painter.drawEllipse(QRectF(12.0, 12.0, 6.0, 6.0))
        painter.end()


class QueueRow(QFrame):
    """One line in the up-next list. Clicking it plays that index."""

    picked = pyqtSignal(int)

    def __init__(self, index: int, song: Song, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.index = index
        self.song = song
        self.setFixedHeight(34)
        self.setCursor(Qt.CursorShape.PointingHandCursor)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 0, 10, 0)
        layout.setSpacing(8)

        self.meter = EqualiserBars(self)
        layout.addWidget(self.meter)

        self.title = QLabel(self)
        self.title.setObjectName("RibbonTitle")
        layout.addWidget(self.title, 1)

        self.stamp = QLabel(self)
        self.stamp.setObjectName("Clock")
        layout.addWidget(self.stamp, 0, Qt.AlignmentFlag.AlignRight)

        self._active = False
        self._hover = False
        elide_into(self.title, song.title, 210)
        self.stamp.setText(song.duration or "")

    def resizeEvent(self, event) -> None:  # noqa: N802
        super().resizeEvent(event)
        elide_into(self.title, self.song.title, max(80, self.title.width() - 6))

    def set_active(self, active: bool) -> None:
        if active == self._active:
            return
        self._active = active
        self.meter.set_on(active)
        self.title.setStyleSheet(
            f"color: {Palette.amber_hi};" if active else f"color: {Palette.text};"
        )
        self.update()

    def enterEvent(self, event) -> None:  # noqa: N802
        self._hover = True
        self.update()

    def leaveEvent(self, event) -> None:  # noqa: N802
        self._hover = False
        self.update()

    def mouseReleaseEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.MouseButton.LeftButton and self.rect().contains(
            event.position().toPoint()
        ):
            self.picked.emit(self.index)

    def paintEvent(self, event) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)

        if self._active:
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(QColor(232, 164, 104, 26))
        elif self._hover:
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(QColor(244, 233, 221, 14))
        else:
            painter.setPen(Qt.PenStyle.NoPen)
            painter.setBrush(Qt.BrushStyle.NoBrush)
        painter.drawRoundedRect(QRectF(0, 1, self.width(), self.height() - 2), 9, 9)

        if self._active:
            painter.setBrush(QColor(Palette.amber))
            painter.drawRoundedRect(QRectF(3, 9, 2.5, self.height() - 18), 1.25, 1.25)
        painter.end()


# ----------------------------------------------------------------- main surface
class FloatingPanel(QWidget):
    """Compact ribbon that expands into the full Ember panel."""

    closed = pyqtSignal()
    endless_toggled = pyqtSignal(bool)

    def __init__(self, core: PlaybackCore, parent: Optional[QWidget] = None) -> None:
        super().__init__(parent)
        self.core = core
        self.expanded = False
        self._drag_offset: Optional[QPoint] = None
        self._scrubbing = False
        self._art_cache: Dict[str, QPixmap] = {}
        self._art_pending: set = set()

        self.setWindowTitle(APP_NAME)
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
        )
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, True)
        self.setStyleSheet(panel_stylesheet())

        self._build()
        self._wire()
        self._apply_size()

    # ------------------------------------------------------------------ build
    def _build(self) -> None:
        outer = QVBoxLayout(self)
        outer.setContentsMargins(SHELL_MARGIN, SHELL_MARGIN, SHELL_MARGIN, SHELL_MARGIN)
        outer.setSpacing(0)

        self.shell = QFrame(self)
        self.shell.setObjectName("Shell")
        outer.addWidget(self.shell)

        shadow = QGraphicsDropShadowEffect(self)
        shadow.setBlurRadius(34)
        shadow.setOffset(0, 8)
        shadow.setColor(QColor(0, 0, 0, 165))
        self.shell.setGraphicsEffect(shadow)

        stage = QVBoxLayout(self.shell)
        stage.setContentsMargins(0, 0, 0, 0)
        stage.setSpacing(0)

        self.ribbon = self._build_ribbon()
        self.panel = self._build_panel()
        stage.addWidget(self.ribbon)
        stage.addWidget(self.panel)

    # ---------------------------------------------------------------- compact
    def _build_ribbon(self) -> QWidget:
        holder = QWidget(self)
        holder.setObjectName("Ribbon")
        holder.setFixedHeight(COMPACT_HEIGHT - 2)

        row = QHBoxLayout(holder)
        row.setContentsMargins(10, 0, 10, 0)
        row.setSpacing(10)

        self.ribbon_art = self._art_label(ART_COMPACT, 9)
        row.addWidget(self.ribbon_art)

        words = QVBoxLayout()
        words.setContentsMargins(0, 0, 0, 0)
        words.setSpacing(1)
        self.ribbon_title = QLabel("nothing playing", holder)
        self.ribbon_title.setObjectName("RibbonTitle")
        self.ribbon_artist = QLabel(APP_TAGLINE, holder)
        self.ribbon_artist.setObjectName("RibbonArtist")
        words.addWidget(self.ribbon_title)
        words.addWidget(self.ribbon_artist)
        row.addLayout(words, 1)

        self.ribbon_prev = self._ghost("⏮", 26)
        self.ribbon_play = self._round("▶", 38)
        self.ribbon_next = self._ghost("⏭", 26)
        row.addWidget(self.ribbon_prev)
        row.addWidget(self.ribbon_play)
        row.addWidget(self.ribbon_next)

        self.ribbon_open = self._pill("⌃", 26)
        self.ribbon_open.setToolTip("open the panel")
        row.addWidget(self.ribbon_open)

        return holder

    # --------------------------------------------------------------- expanded
    def _build_panel(self) -> QWidget:
        holder = QWidget(self)
        holder.setObjectName("Panel")
        holder.setVisible(False)

        column = QVBoxLayout(holder)
        column.setContentsMargins(14, 12, 14, 12)
        column.setSpacing(10)

        column.addLayout(self._build_header())
        column.addWidget(self._build_now_card())
        column.addLayout(self._build_search())
        column.addWidget(self._section("up next"))
        column.addWidget(self._build_queue())
        column.addWidget(Hairline(holder))
        column.addLayout(self._build_footer())

        return holder

    def _build_header(self) -> QHBoxLayout:
        row = QHBoxLayout()
        row.setContentsMargins(2, 0, 0, 0)
        row.setSpacing(8)

        words = QVBoxLayout()
        words.setContentsMargins(0, 0, 0, 0)
        words.setSpacing(0)
        mark = QLabel(APP_NAME, self)
        mark.setObjectName("Display")
        tail = QLabel(APP_TAGLINE.upper(), self)
        tail.setObjectName("Tagline")
        words.addWidget(mark)
        words.addWidget(tail)
        row.addLayout(words, 1)

        self.status = QLabel("ready", self)
        self.status.setObjectName("StatusChip")
        row.addWidget(self.status, 0, Qt.AlignmentFlag.AlignVCenter)

        self.collapse_pill = self._pill("⌄", 26)
        self.collapse_pill.setToolTip("collapse")
        row.addWidget(self.collapse_pill, 0, Qt.AlignmentFlag.AlignVCenter)

        return row

    def _build_now_card(self) -> QWidget:
        card = QFrame(self)
        card.setObjectName("NowCard")

        column = QVBoxLayout(card)
        column.setContentsMargins(12, 12, 12, 10)
        column.setSpacing(9)

        top = QHBoxLayout()
        top.setContentsMargins(0, 0, 0, 0)
        top.setSpacing(11)

        self.hero_art = self._art_label(ART_HERO, 18)
        top.addWidget(self.hero_art, 0, Qt.AlignmentFlag.AlignTop)

        self.disc = VinylDisc(ART_HERO - 22, card)
        top.addWidget(self.disc, 0, Qt.AlignmentFlag.AlignTop)

        words = QVBoxLayout()
        words.setContentsMargins(0, 4, 0, 0)
        words.setSpacing(3)
        self.hero_title = QLabel("pick something to play", card)
        self.hero_title.setObjectName("HeroTitle")
        self.hero_artist = QLabel("—", card)
        self.hero_artist.setObjectName("HeroArtist")
        words.addWidget(self.hero_title)
        words.addWidget(self.hero_artist)
        words.addStretch(1)
        top.addLayout(words, 1)

        column.addLayout(top)

        seek_row = QHBoxLayout()
        seek_row.setContentsMargins(0, 0, 0, 0)
        seek_row.setSpacing(8)

        self.elapsed = QLabel("0:00", card)
        self.elapsed.setObjectName("Clock")
        self.elapsed.setFixedWidth(38)
        seek_row.addWidget(self.elapsed)

        self.seek = SeekBar(card)
        seek_row.addWidget(self.seek, 1)

        self.total = QLabel("0:00", card)
        self.total.setObjectName("Clock")
        self.total.setFixedWidth(38)
        self.total.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        seek_row.addWidget(self.total)

        column.addLayout(seek_row)
        return card

    def _build_search(self) -> QHBoxLayout:
        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)

        self.field = QLineEdit(self)
        self.field.setObjectName("SearchField")
        self.field.setPlaceholderText("search, or paste a link")
        self.field.setFixedHeight(36)
        self.field.setClearButtonEnabled(True)
        row.addWidget(self.field, 1)

        self.find = QPushButton("find", self)
        self.find.setObjectName("AmberButton")
        self.find.setFixedHeight(36)
        self.find.setCursor(Qt.CursorShape.PointingHandCursor)
        row.addWidget(self.find)

        return row

    def _build_queue(self) -> QWidget:
        self.queue_scroll = QScrollArea(self)
        self.queue_scroll.setObjectName("QueueScroll")
        self.queue_scroll.setWidgetResizable(True)
        self.queue_scroll.setFixedHeight(QUEUE_VIEW_HEIGHT)
        self.queue_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.queue_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)

        self.queue_host = QWidget()
        self.queue_list = QVBoxLayout(self.queue_host)
        self.queue_list.setContentsMargins(0, 0, 4, 0)
        self.queue_list.setSpacing(2)
        self.queue_list.addStretch(1)
        self.queue_scroll.setWidget(self.queue_host)

        self._empty = QLabel("search for something warm", self.queue_host)
        self._empty.setObjectName("Hint")
        self._empty.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.queue_list.insertWidget(0, self._empty)

        return self.queue_scroll

    def _build_footer(self) -> QHBoxLayout:
        row = QHBoxLayout()
        row.setContentsMargins(2, 0, 0, 0)
        row.setSpacing(8)

        self.endless = self._chip("endless", True)
        self.endless.setToolTip("keep adding look-alike tracks when the queue runs dry")
        row.addWidget(self.endless)

        self.count = QLabel("0 tracks", self)
        self.count.setObjectName("Hint")
        row.addWidget(self.count)

        row.addStretch(1)

        self.volume = VolumeDial(self.core.volume(), self)
        row.addWidget(self.volume, 0, Qt.AlignmentFlag.AlignVCenter)

        self.quit = self._pill("✕", 26)
        self.quit.setObjectName("PillClose")
        self.quit.setToolTip("close Ember")
        row.addWidget(self.quit)

        return row

    # ------------------------------------------------------------- small parts
    def _art_label(self, side: int, radius: int) -> QLabel:
        label = QLabel(self)
        label.setFixedSize(side, side)
        label.setStyleSheet(
            f"background: rgba(244, 233, 221, 0.05);"
            f"border: 1px solid {Palette.line};"
            f"border-radius: {radius}px;"
        )
        label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        return label

    def _ghost(self, glyph: str, side: int) -> QPushButton:
        button = QPushButton(glyph, self)
        button.setObjectName("Ghost")
        button.setFixedSize(side, side)
        button.setCursor(Qt.CursorShape.PointingHandCursor)
        return button

    def _round(self, glyph: str, side: int) -> QPushButton:
        button = QPushButton(glyph, self)
        button.setObjectName("RoundPlay")
        button.setFixedSize(side, side)
        button.setCursor(Qt.CursorShape.PointingHandCursor)
        return button

    def _pill(self, glyph: str, side: int) -> QPushButton:
        button = QPushButton(glyph, self)
        button.setObjectName("Pill")
        button.setFixedSize(side, side)
        button.setCursor(Qt.CursorShape.PointingHandCursor)
        return button

    def _chip(self, text: str, checked: bool) -> QPushButton:
        button = QPushButton(text, self)
        button.setObjectName("Chip")
        button.setCheckable(True)
        button.setChecked(checked)
        button.setFixedHeight(26)
        button.setCursor(Qt.CursorShape.PointingHandCursor)
        return button

    def _section(self, text: str) -> QLabel:
        label = QLabel(text.upper(), self)
        label.setObjectName("SectionLabel")
        return label

    # ------------------------------------------------------------------- wiring
    def _wire(self) -> None:
        core = self.core

        core.song_changed.connect(self._on_song)
        core.queue_changed.connect(self._on_queue)
        core.cursor_changed.connect(self._on_cursor)
        core.playing_changed.connect(self._on_playing)
        core.progress_changed.connect(self._on_progress)
        core.length_changed.connect(self._on_length)
        core.loading_changed.connect(self._on_loading)
        core.notice.connect(self._on_notice)

        self.ribbon_play.clicked.connect(core.toggle)
        self.ribbon_prev.clicked.connect(core.back)
        self.ribbon_next.clicked.connect(core.forward)
        self.ribbon_open.clicked.connect(self.expand)
        self.collapse_pill.clicked.connect(self.collapse)

        self.seek.scrubbed.connect(self._on_scrub)
        self.seek.released.connect(self._on_scrub_done)
        self.seek.sliderMoved.connect(self._on_scrub)

        self.find.clicked.connect(self._on_find)
        self.field.returnPressed.connect(self._on_find)

        self.volume.changed.connect(self._on_volume)
        self.endless.toggled.connect(self._on_endless)
        self.quit.clicked.connect(self._on_quit)

        self._notice_timer = QTimer(self)
        self._notice_timer.setSingleShot(True)
        self._notice_timer.timeout.connect(lambda: self._set_status("ready"))

    # ------------------------------------------------------------- appearance
    def _apply_size(self) -> None:
        height = COMPACT_HEIGHT if not self.expanded else EXPANDED_HEIGHT
        self.setFixedSize(PANEL_WIDTH + SHELL_MARGIN * 2, height + SHELL_MARGIN * 2)

    def expand(self) -> None:
        if self.expanded:
            return
        self.expanded = True
        self.ribbon.setVisible(False)
        self.panel.setVisible(True)
        self._apply_size()
        self.clamp_to_screen()
        self.ensure_topmost()

    def collapse(self) -> None:
        if not self.expanded:
            return
        self.expanded = False
        self.panel.setVisible(False)
        self.ribbon.setVisible(True)
        self._apply_size()
        self.clamp_to_screen()
        self.ensure_topmost()

    def toggle_expand(self) -> None:
        self.collapse() if self.expanded else self.expand()

    def clamp_to_screen(self) -> None:
        screen = self.screen()
        if screen is None:
            return
        bounds = screen.availableGeometry()
        x = min(max(self.x(), bounds.left()), bounds.right() - self.width())
        y = min(max(self.y(), bounds.top()), bounds.bottom() - self.height())
        self.move(x, y)

    def ensure_topmost(self) -> None:
        """Re-assert z-order. Windows forgets after another window takes focus."""
        if not sys.platform.startswith("win"):
            return
        try:
            import ctypes

            ctypes.windll.user32.SetWindowPos(
                int(self.winId()),
                HWND_TOPMOST,
                0,
                0,
                0,
                0,
                SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE,
            )
        except Exception as exc:  # noqa: BLE001 - platform surface
            log.debug("topmost re-assert skipped: %s", exc)

    # ----------------------------------------------------------------- dragging
    def mousePressEvent(self, event) -> None:  # noqa: N802
        if event.button() == Qt.MouseButton.LeftButton:
            self._drag_offset = event.globalPosition().toPoint() - self.frameGeometry().topLeft()

    def mouseMoveEvent(self, event) -> None:  # noqa: N802
        if self._drag_offset is None:
            return
        self.move(event.globalPosition().toPoint() - self._drag_offset)

    def mouseReleaseEvent(self, event) -> None:  # noqa: N802
        if self._drag_offset is not None:
            self._drag_offset = None
            self.clamp_to_screen()

    # ------------------------------------------------------------- art fetching
    def _request_art(self, song: Song) -> None:
        if not song.artwork_url:
            return
        cached = self._art_cache.get(song.video_id)
        if cached is not None:
            self._paint_art(song.video_id, cached)
            return
        if song.video_id in self._art_pending:
            return

        self._art_pending.add(song.video_id)
        job = ArtJob(song.video_id, song.artwork_url)
        job.signals.arrived.connect(self._on_art)
        self.core.pool.start(job)

    def _on_art(self, song_id: str, payload: bytes) -> None:
        self._art_pending.discard(song_id)
        source = QPixmap()
        if not source.loadFromData(payload):
            return

        if len(self._art_cache) >= ARTWORK_CACHE_LIMIT:
            self._art_cache.pop(next(iter(self._art_cache)), None)
        self._art_cache[song_id] = source
        self._paint_art(song_id, source)

    def _paint_art(self, song_id: str, source: QPixmap) -> None:
        current = self.core.current
        if current is None or current.video_id != song_id:
            return
        self.ribbon_art.setPixmap(rounded_pixmap(source, ART_COMPACT))
        self.hero_art.setPixmap(rounded_pixmap(source, ART_HERO))

    # ------------------------------------------------------------------- slots
    def _on_song(self, song: Song) -> None:
        elide_into(self.ribbon_title, song.title, self.ribbon_title.width() or 160)
        elide_into(self.ribbon_artist, song.byline, self.ribbon_artist.width() or 160)
        elide_into(self.hero_title, song.title, 200)
        elide_into(self.hero_artist, song.byline, 200)

        self.seek.setRange(0, 0)
        self.seek.setValue(0)
        self.elapsed.setText("0:00")
        self.total.setText("0:00")

        cached = self._art_cache.get(song.video_id)
        if cached is not None:
            self._paint_art(song.video_id, cached)
        else:
            self.ribbon_art.clear()
            self.hero_art.clear()
            self._request_art(song)

        self._set_status("tuning in")

    def _on_queue(self, songs: List[Song]) -> None:
        for position in reversed(range(self.queue_list.count())):
            widget = self.queue_list.itemAt(position).widget()
            if isinstance(widget, QueueRow):
                self.queue_list.takeAt(position)
                widget.deleteLater()

        if not songs:
            self._empty.setVisible(True)
            self.count.setText("0 tracks")
            return

        self._empty.setVisible(False)
        for index, song in enumerate(songs):
            row = QueueRow(index, song, self.queue_host)
            row.picked.connect(self.core.play_at)
            self.queue_list.insertWidget(index + 1, row)

        self.count.setText(pretty_count(len(songs), "track"))
        self._on_cursor(self.core.cursor)

    def _on_cursor(self, index: int) -> None:
        for position in range(self.queue_list.count()):
            widget = self.queue_list.itemAt(position).widget()
            if isinstance(widget, QueueRow):
                widget.set_active(widget.index == index)

    def _on_playing(self, playing: bool) -> None:
        self.ribbon_play.setText("⏸" if playing else "▶")
        self.disc.set_spinning(playing)
        self._set_status("playing" if playing else "paused")

    def _on_progress(self, position: int) -> None:
        if self._scrubbing:
            return
        self.seek.setValue(position)
        self.elapsed.setText(clock(position))

    def _on_length(self, duration: int) -> None:
        self.seek.setRange(0, max(0, duration))
        self.total.setText(clock(duration))

    def _on_loading(self, loading: bool) -> None:
        if loading:
            self._set_status("loading")

    def _on_notice(self, message: str) -> None:
        self._set_status(message)

    def _set_status(self, message: str) -> None:
        self.status.setText(message)
        if message != "ready":
            self._notice_timer.start(4000)

    def _on_scrub(self, position: int) -> None:
        self._scrubbing = True
        self.elapsed.setText(clock(position))

    def _on_scrub_done(self, position: int) -> None:
        self._scrubbing = False
        self.core.seek(position)

    def _on_find(self) -> None:
        text = self.field.text().strip()
        if not text:
            return
        if looks_like_link(text):
            self.core.open_link(text)
            self.field.clear()
            return
        self._set_status("searching")
        job = self._search_job(text)
        if job is not None:
            self.core.pool.start(job)

    def _search_job(self, query: str):
        from .jobs import SearchJob

        job = SearchJob(self.core.catalog, query, 12)
        job.signals.done.connect(self._on_search_done)
        job.signals.failed.connect(self._on_search_failed)
        return job

    def _on_search_done(self, query: str, songs: List[Song]) -> None:
        if not songs:
            self._set_status("nothing found")
            return
        self.field.clear()
        self.core.adopt(songs, 0)
        self._set_status(pretty_count(len(songs), "result"))

    def _on_search_failed(self, query: str, message: str) -> None:
        self._set_status("search failed")
        log.warning("search %r failed: %s", query, message)

    def _on_volume(self, percent: int) -> None:
        self.core.set_volume(percent)

    def _on_endless(self, enabled: bool) -> None:
        self.core.set_auto_queue(enabled)
        self.endless_toggled.emit(enabled)
        self._set_status("endless on" if enabled else "endless off")

    def _on_quit(self) -> None:
        self.closed.emit()
        self.close()

    # -------------------------------------------------------------- public API
    def current_position(self) -> Tuple[int, int]:
        return self.x(), self.y()

    def place(self, x: int, y: int) -> None:
        self.move(x, y)
        self.clamp_to_screen()

    def hotkeys(self) -> List[Tuple[str, Callable[[], None]]]:
        """(sequence, callback) pairs the app registers on the window."""
        return [
            ("Ctrl+Alt+Space", self.core.toggle),
            ("Ctrl+Alt+Right", self.core.forward),
            ("Ctrl+Alt+Left", self.core.back),
            ("Ctrl+Alt+Up", self.expand),
            ("Ctrl+Alt+Down", self.collapse),
            ("Ctrl+Alt+E", self.toggle_expand),
            ("Ctrl+Alt+F", self._focus_field),
        ]

    def _focus_field(self) -> None:
        self.expand()
        self.field.setFocus(Qt.FocusReason.ShortcutFocusReason)
        self.field.selectAll()