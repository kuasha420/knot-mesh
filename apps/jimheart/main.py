#!/usr/bin/env python3
"""
Jim Heart's Magical Key Smash Game (Knot Mesh Edition)
A fullscreen, kid-friendly interactive wonderland for Jim Heart.
Keys pop up in giant, vibrant animations with companion words, emojis, particle bursts, and soothing chimes.
Exit protection: Press and hold ESC continuously for 3.0 seconds to quit.
"""

import math
import random
import sys
import time
from dataclasses import dataclass
from typing import List, Optional, Tuple

from PyQt6.QtCore import QPointF, QRectF, Qt, QTimer
from PyQt6.QtGui import (
    QBrush,
    QColor,
    QFont,
    QFontMetrics,
    QKeyEvent,
    QLinearGradient,
    QMouseEvent,
    QPainter,
    QPainterPath,
    QPen,
    QRadialGradient,
)
from PyQt6.QtWidgets import QApplication, QWidget
from pathlib import Path

# Ensure local dir is on sys.path
_THIS_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _THIS_DIR.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))
if str(_THIS_DIR) not in sys.path:
    sys.path.insert(0, str(_THIS_DIR))

# Import sound bank
try:
    from apps.jimheart.sound_synth import SoundBank
except ImportError:
    from sound_synth import SoundBank

# High-contrast, joyful pastel & neon palette
PALETTE = [
    QColor("#FF4081"),  # Bubblegum Pink
    QColor("#00E676"),  # Electric Mint
    QColor("#FFD600"),  # Sunshine Yellow
    QColor("#00E5FF"),  # Cyan Aqua
    QColor("#FF6D00"),  # Bright Orange
    QColor("#E040FB"),  # Vibrant Lavender
    QColor("#7C4DFF"),  # Royal Violet
    QColor("#FF5252"),  # Coral Red
    QColor("#1DE9B6"),  # Seafoam Teal
]

# Alphabet dictionary with emojis & companion words
ALPHABET_COMPANIONS = {
    "A": ("🍎", "Apple"),
    "B": ("🦋", "Butterfly"),
    "C": ("🐱", "Cat"),
    "D": ("🐶", "Dog"),
    "E": ("🐘", "Elephant"),
    "F": ("🌸", "Flower"),
    "G": ("🎸", "Guitar"),
    "H": ("💖", "Jim Heart (Easter Egg! 💖)"),
    "I": ("🍦", "Ice Cream"),
    "J": ("👑", "JimHa! ✨"),
    "K": ("🪁", "Kite"),
    "L": ("🦁", "Lion"),
    "M": ("🌙", "Moon"),
    "N": ("🌈", "Nature"),
    "O": ("🦉", "Owl"),
    "P": ("🐼", "Panda"),
    "Q": ("👑", "Queen"),
    "R": ("🚀", "Rocket"),
    "S": ("⭐", "Star"),
    "T": ("🐯", "Tiger"),
    "U": ("🦄", "Unicorn"),
    "V": ("🎻", "Violin"),
    "W": ("🌊", "Wave"),
    "X": ("🎁", "Xylophone"),
    "Y": ("⛵", "Yacht"),
    "Z": ("🦓", "Zebra"),
}


@dataclass
class Particle:
    x: float
    y: float
    vx: float
    vy: float
    size: float
    color: QColor
    shape: str  # 'star', 'circle', 'heart', 'confetti'
    life: float  # 0.0 to 1.0 (1.0 = brand new, 0.0 = dead)
    decay_rate: float
    rotation: float
    rot_speed: float


@dataclass
class FloatingBubble:
    x: float
    y: float
    vx: float
    vy: float
    radius: float
    color: QColor
    life: float


class JimHeartGame(QWidget):
    """Fullscreen interactive visual playground with long-hold ESC exit protection."""

    def __init__(self, parent=None, enable_audio=True):
        super().__init__(parent)
        self.setWindowTitle("JimHa's Magical Key Smash Game")
        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        self.setMouseTracking(True)

        # Audio synthesizer bank
        self.enable_audio = enable_audio
        if self.enable_audio:
            self.sound_bank = SoundBank()
            self.sound_bank.init_qt_effects()
        else:
            self.sound_bank = None

        # Display State
        self.current_key_title = "JIMHA"
        self.current_subtitle = "💖 Smash any button to play! 💖"
        self.current_emoji = "✨"
        self.current_color = QColor("#FF4081")

        # Animation state for the main card
        self.card_age = 0.0  # seconds since key press
        self.card_scale = 1.0
        self.card_alpha = 1.0
        self.background_hue = 260.0  # subtle shifting background

        # Particles & Bubbles
        self.particles: List[Particle] = []
        self.bubbles: List[FloatingBubble] = []

        # Background stars
        self.bg_stars: List[Tuple[float, float, float, float]] = []  # (rel_x, rel_y, size, phase)
        for _ in range(70):
            self.bg_stars.append((random.random(), random.random(), random.uniform(2.0, 5.0), random.uniform(0, math.pi * 2)))

        # Escape Hold Exit Protection
        self.esc_hold_required_sec = 3.0
        self.esc_is_pressed = False
        self.esc_press_start_time = 0.0
        self.esc_hold_progress = 0.0  # 0.0 to 1.0

        # Frame timer (60 FPS)
        self.last_frame_time = time.time()
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._on_tick)
        self.timer.start(16)

    def trigger_key(self, title: str, subtitle: str = "", emoji: str = "✨", color: Optional[QColor] = None) -> None:
        """Activate a new key event with spring animations and particle fireworks."""
        self.current_key_title = title
        self.current_subtitle = subtitle
        self.current_emoji = emoji
        self.current_color = color if color is not None else random.choice(PALETTE)
        self.card_age = 0.0
        self.card_scale = 0.2
        self.card_alpha = 1.0

        # Play harmonic pentatonic chime
        if self.sound_bank:
            self.sound_bank.play_key(title)

        # Spawn particle fireworks
        center_x = self.width() / 2.0
        center_y = self.height() / 2.0
        self._spawn_particle_burst(center_x, center_y, count=45)

    def _spawn_particle_burst(self, x: float, y: float, count: int = 35) -> None:
        """Create a vibrant shower of multi-shaped confetti, stars, and hearts."""
        shapes = ["star", "circle", "heart", "confetti"]
        for _ in range(count):
            angle = random.uniform(0, 2 * math.pi)
            speed = random.uniform(150.0, 750.0)
            vx = math.cos(angle) * speed
            vy = math.sin(angle) * speed - random.uniform(50.0, 200.0)
            size = random.uniform(8.0, 24.0)
            color = random.choice(PALETTE)
            shape = random.choice(shapes)
            decay_rate = random.uniform(0.4, 0.9)  # life drops by this per sec
            rot_speed = random.uniform(-360.0, 360.0)

            self.particles.append(
                Particle(
                    x=x,
                    y=y,
                    vx=vx,
                    vy=vy,
                    size=size,
                    color=color,
                    shape=shape,
                    life=1.0,
                    decay_rate=decay_rate,
                    rotation=random.uniform(0, 360),
                    rot_speed=rot_speed,
                )
            )

    def _spawn_bubble(self, x: float, y: float) -> None:
        """Spawn a floating bubble from mouse/touch interaction."""
        radius = random.uniform(16.0, 48.0)
        color = random.choice(PALETTE)
        vx = random.uniform(-40.0, 40.0)
        vy = random.uniform(-120.0, -40.0)
        self.bubbles.append(
            FloatingBubble(
                x=x,
                y=y,
                vx=vx,
                vy=vy,
                radius=radius,
                color=color,
                life=1.0,
            )
        )

    def _on_tick(self) -> None:
        """60 FPS physics, animation update, and ESC hold evaluation."""
        now = time.time()
        dt = max(0.001, min(0.1, now - self.last_frame_time))
        self.last_frame_time = now

        # Update card age and elastic bounce scale
        self.card_age += dt
        if self.card_age < 0.35:
            # Elastic spring: 0.2 -> 1.25 -> 1.0
            progress = self.card_age / 0.35
            # Overshoot bounce formula
            self.card_scale = 0.2 + 0.8 * (1.0 + math.sin(progress * math.pi) * 0.35)
        # Dynamic framerate: 60 FPS when active, 30 FPS when idle
        has_active_fx = bool(self.particles or self.bubbles or self.card_age < 1.2 or self.esc_is_pressed)
        target_interval = 16 if has_active_fx else 33
        if self.timer.interval() != target_interval:
            self.timer.setInterval(target_interval)

        # Slow background hue drift
        self.background_hue = (self.background_hue + dt * 3.0) % 360.0

        # ESC hold progress update
        if self.esc_is_pressed:
            elapsed = now - self.esc_press_start_time
            self.esc_hold_progress = min(1.0, elapsed / self.esc_hold_required_sec)
            if self.esc_hold_progress >= 1.0:
                # Quitting gracefully after full 3-second hold
                self.timer.stop()
                QApplication.quit()
                return
        else:
            self.esc_hold_progress = 0.0

        # Update Particles
        alive_particles: List[Particle] = []
        gravity = 400.0  # px/s^2
        for p in self.particles:
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.vy += gravity * dt
            p.rotation += p.rot_speed * dt
            p.life -= p.decay_rate * dt
            if p.life > 0 and p.y < self.height() + 100:
                alive_particles.append(p)
        self.particles = alive_particles

        # Update Bubbles
        alive_bubbles: List[FloatingBubble] = []
        for b in self.bubbles:
            b.x += b.vx * dt
            b.y += b.vy * dt
            b.life -= 0.15 * dt
            if b.life > 0 and b.y > -100:
                alive_bubbles.append(b)
        self.bubbles = alive_bubbles

        self.update()

    def keyPressEvent(self, event: QKeyEvent) -> None:
        """Handle key presses with toddler-safe ESC hold protection."""
        if event.key() == Qt.Key.Key_Escape:
            # Avoid restarting if OS auto-repeat is active
            if not event.isAutoRepeat() and not self.esc_is_pressed:
                self.esc_is_pressed = True
                self.esc_press_start_time = time.time()
                self.esc_hold_progress = 0.0
            return

        # Any regular key press interrupts ESC hold
        self.esc_is_pressed = False
        self.esc_hold_progress = 0.0

        key_code = event.key()
        text = event.text().strip().upper()

        if text and text in ALPHABET_COMPANIONS:
            emoji, word = ALPHABET_COMPANIONS[text]
            subtitle = f"{text} is for {word} {emoji}"
            self.trigger_key(text, subtitle, emoji)
        elif text and text.isdigit():
            val = int(text)
            stars = "⭐" * max(1, min(val, 10))
            subtitle = f"Number {val}! {stars}"
            self.trigger_key(text, subtitle, "🔢")
        elif key_code == Qt.Key.Key_Space:
            self.trigger_key("SPACE", "🌟 COSMIC SUPERNOVA! 🌟", "✨")
        elif key_code in (Qt.Key.Key_Return, Qt.Key.Key_Enter):
            self.trigger_key("ENTER", "🎉 PARTY TIME CELEBRATION! 🎉", "🎈")
        elif key_code == Qt.Key.Key_Backspace:
            self.trigger_key("POP!", "🫧 BUBBLE POP! 🫧", "🫧")
        elif key_code == Qt.Key.Key_Up:
            self.trigger_key("UP ⬆️", "🚀 ROCKETING TO THE STARS!", "🌌")
        elif key_code == Qt.Key.Key_Down:
            self.trigger_key("DOWN ⬇️", "🌊 DIVING DEEP INTO THE OCEAN!", "🐬")
        elif key_code == Qt.Key.Key_Left:
            self.trigger_key("LEFT ⬅️", "🌪️ SWISHING TO THE LEFT!", "💫")
        elif key_code == Qt.Key.Key_Right:
            self.trigger_key("RIGHT ➡️", "⚡ DASHING TO THE RIGHT!", "⚡")
        else:
            # Fallback for function or symbol keys
            key_name = event.text() if event.text() else f"KEY"
            self.trigger_key(key_name.upper(), "💖 YOU ARE AWESOME JIMHA! 💖", "🌟")

    def keyReleaseEvent(self, event: QKeyEvent) -> None:
        """Cancel ESC hold timer immediately when physical key is released."""
        if event.key() == Qt.Key.Key_Escape:
            if not event.isAutoRepeat():
                self.esc_is_pressed = False
                self.esc_hold_progress = 0.0

    def mousePressEvent(self, event: QMouseEvent) -> None:
        """Spawn sparkling bubbles on mouse clicks or touch taps."""
        pos = event.position()
        self._spawn_bubble(pos.x(), pos.y())
        self._spawn_particle_burst(pos.x(), pos.y(), count=15)
        if self.sound_bank:
            self.sound_bank.play_key("MOUSE")

    def paintEvent(self, event) -> None:
        """Render high-contrast visual feast with anti-aliasing."""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setRenderHint(QPainter.RenderHint.TextAntialiasing)

        width = self.width()
        height = self.height()
        center_x = width / 2.0
        center_y = height / 2.0

        # 1. Dynamic Twilight / Cosmic Gradient Background
        bg_col1 = QColor.fromHsv(int(self.background_hue) % 360, 180, 45)
        bg_col2 = QColor.fromHsv(int(self.background_hue + 50) % 360, 220, 20)
        grad = QLinearGradient(0, 0, width, height)
        grad.setColorAt(0.0, bg_col1)
        grad.setColorAt(1.0, bg_col2)
        painter.fillRect(self.rect(), grad)

        # 2. Twinkling Background Stars
        t_sec = time.time()
        painter.setPen(Qt.PenStyle.NoPen)
        for rel_x, rel_y, size, phase in self.bg_stars:
            twinkle = 0.5 + 0.5 * math.sin(t_sec * 2.5 + phase)
            alpha = int(120 * twinkle)
            painter.setBrush(QColor(255, 255, 255, alpha))
            painter.drawEllipse(QPointF(rel_x * width, rel_y * height), size, size)

        # 3. Floating Bubbles
        for b in self.bubbles:
            alpha = int(220 * b.life)
            c = QColor(b.color)
            c.setAlpha(alpha)
            painter.setBrush(c)
            painter.setPen(QPen(QColor(255, 255, 255, alpha), 2))
            painter.drawEllipse(QPointF(b.x, b.y), b.radius, b.radius)
            # Bubble highlight glint
            painter.setBrush(QColor(255, 255, 255, int(180 * b.life)))
            painter.setPen(Qt.PenStyle.NoPen)
            painter.drawEllipse(
                QPointF(b.x - b.radius * 0.35, b.y - b.radius * 0.35),
                b.radius * 0.25,
                b.radius * 0.25,
            )

        # 4. Animated Particles (Stars, Hearts, Confetti)
        for p in self.particles:
            painter.save()
            painter.translate(p.x, p.y)
            painter.rotate(p.rotation)
            alpha = max(0, min(255, int(255 * p.life)))
            c = QColor(p.color)
            c.setAlpha(alpha)
            painter.setBrush(c)
            painter.setPen(Qt.PenStyle.NoPen)

            if p.shape == "circle":
                painter.drawEllipse(QPointF(0, 0), p.size / 2, p.size / 2)
            elif p.shape == "confetti":
                painter.drawRect(QRectF(-p.size / 2, -p.size / 4, p.size, p.size / 2))
            elif p.shape == "star":
                self._draw_star(painter, 0, 0, p.size / 2, 5)
            elif p.shape == "heart":
                self._draw_heart(painter, 0, 0, p.size)
            painter.restore()

        # 5. Massive Animated Key Display (Center Stage)
        painter.save()
        painter.translate(center_x, center_y)
        painter.scale(self.card_scale, self.card_scale)

        # Glowing Radial Halo behind card
        halo_rad = min(width, height) * 0.45
        radial = QRadialGradient(0, 0, halo_rad)
        glow_color = QColor(self.current_color)
        glow_color.setAlpha(120)
        radial.setColorAt(0.0, glow_color)
        radial.setColorAt(0.7, QColor(glow_color.red(), glow_color.green(), glow_color.blue(), 30))
        radial.setColorAt(1.0, QColor(0, 0, 0, 0))
        painter.setBrush(radial)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.drawEllipse(QPointF(0, 0), halo_rad, halo_rad)

        # Main Character / Title
        font_size = int(min(width, height) * 0.28)
        font = QFont("Cantarell", font_size, QFont.Weight.Black)
        font.setStyleHint(QFont.StyleHint.SansSerif)
        painter.setFont(font)

        # Outline & Drop Shadow for crisp readability
        title_text = self.current_key_title
        metrics = QFontMetrics(font)
        text_rect = metrics.boundingRect(title_text)

        # Draw Shadow
        painter.setPen(QColor(0, 0, 0, 180))
        painter.drawText(int(-text_rect.width() / 2 + 8), int(text_rect.height() / 4 + 8), title_text)

        # Draw Main Text
        painter.setPen(self.current_color)
        painter.drawText(int(-text_rect.width() / 2), int(text_rect.height() / 4), title_text)

        # Companion Subtitle Badge below
        if self.current_subtitle:
            sub_font_size = int(min(width, height) * 0.055)
            sub_font = QFont("Cantarell", max(18, sub_font_size), QFont.Weight.Bold)
            painter.setFont(sub_font)
            sub_metrics = QFontMetrics(sub_font)
            sub_rect = sub_metrics.boundingRect(self.current_subtitle)

            badge_y = text_rect.height() / 4 + 70
            badge_rect = QRectF(
                -sub_rect.width() / 2 - 25,
                badge_y - sub_rect.height() / 2 - 12,
                sub_rect.width() + 50,
                sub_rect.height() + 24,
            )

            # Translucent pill container
            painter.setBrush(QColor(0, 0, 0, 140))
            painter.setPen(QPen(QColor(255, 255, 255, 180), 2))
            painter.drawRoundedRect(badge_rect, 20, 20)

            # Subtitle Text
            painter.setPen(QColor("#FFFFFF"))
            painter.drawText(
                int(-sub_rect.width() / 2),
                int(badge_y + sub_rect.height() / 3),
                self.current_subtitle,
            )

        painter.restore()

        # 6. Exit Protection HUD (Escape Hold Overlay)
        if self.esc_is_pressed or self.esc_hold_progress > 0:
            self._draw_esc_hold_hud(painter, width, height)

    def _draw_star(self, painter: QPainter, cx: float, cy: float, r: float, points: int = 5) -> None:
        """Render a mathematical 5-pointed star."""
        path = QPainterPath()
        inner_r = r * 0.45
        for i in range(points * 2):
            rad = r if i % 2 == 0 else inner_r
            angle = i * math.pi / points - math.pi / 2
            x = cx + rad * math.cos(angle)
            y = cy + rad * math.sin(angle)
            if i == 0:
                path.moveTo(x, y)
            else:
                path.lineTo(x, y)
        path.closeSubpath()
        painter.drawPath(path)

    def _draw_heart(self, painter: QPainter, cx: float, cy: float, size: float) -> None:
        """Render a cute vector heart."""
        path = QPainterPath()
        w = size * 0.8
        h = size * 0.8
        path.moveTo(cx, cy + h * 0.4)
        path.cubicTo(cx - w * 0.6, cy - h * 0.4, cx - w * 0.6, cy - h * 0.8, cx, cy - h * 0.3)
        path.cubicTo(cx + w * 0.6, cy - h * 0.8, cx + w * 0.6, cy - h * 0.4, cx, cy + h * 0.4)
        painter.drawPath(path)

    def _draw_esc_hold_hud(self, painter: QPainter, width: int, height: int) -> None:
        """Draw circular progress indicator when ESC is held down."""
        hud_center_x = width / 2.0
        hud_center_y = height * 0.22
        radius = 55.0

        # Dark overlay backing
        painter.setBrush(QColor(10, 10, 20, 210))
        painter.setPen(QPen(QColor(255, 255, 255, 80), 2))
        painter.drawRoundedRect(
            QRectF(hud_center_x - 220, hud_center_y - 85, 440, 170),
            24,
            24,
        )

        # Circular progress arc
        painter.setPen(QPen(QColor(80, 80, 100), 8))
        painter.drawEllipse(QPointF(hud_center_x, hud_center_y), radius, radius)

        # Active progress arc
        span_angle = int(-360 * self.esc_hold_progress * 16)
        painter.setPen(QPen(QColor("#FF1744"), 8, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
        painter.drawArc(
            QRectF(hud_center_x - radius, hud_center_y - radius, radius * 2, radius * 2),
            90 * 16,
            span_angle,
        )

        # Remaining seconds text
        remaining = max(0.0, self.esc_hold_required_sec * (1.0 - self.esc_hold_progress))
        time_text = f"{remaining:.1f}s"
        font = QFont("Cantarell", 16, QFont.Weight.Bold)
        painter.setFont(font)
        painter.setPen(QColor("#FFFFFF"))
        metrics = QFontMetrics(font)
        tw = metrics.boundingRect(time_text).width()
        painter.drawText(int(hud_center_x - tw / 2), int(hud_center_y + 6), time_text)

        # Labels
        label_font = QFont("Cantarell", 12, QFont.Weight.Bold)
        painter.setFont(label_font)
        painter.setPen(QColor("#FF8A80"))
        top_label = "HOLDING ESC TO EXIT..."
        tl_w = QFontMetrics(label_font).boundingRect(top_label).width()
        painter.drawText(int(hud_center_x - tl_w / 2), int(hud_center_y - 60), top_label)

        hint_font = QFont("Cantarell", 11, QFont.Weight.Medium)
        painter.setFont(hint_font)
        painter.setPen(QColor("#B0BEC5"))
        bot_label = "Release ESC to keep playing"
        bl_w = QFontMetrics(hint_font).boundingRect(bot_label).width()
        painter.drawText(int(hud_center_x - bl_w / 2), int(hud_center_y + 72), bot_label)


def main():
    app = QApplication(sys.argv)
    game = JimHeartGame()
    game.showFullScreen()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
