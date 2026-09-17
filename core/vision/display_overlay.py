#!/usr/bin/env python3
"""
Knot Display Identification & Calibration Pattern Overlay
Displays a high-contrast calibration pattern on all connected workstation displays
for taking optimal setup photographs for the Knot Vision & Topology Reasoning Engine.

Features:
- Fullscreen coverage across all multi-display outputs
- High-contrast background (customizable: white, black, neon)
- Machine-readable Node ID, Output Name, Resolution, Scaling, and Primary tags
- Corner crosshair fiducial markers for sub-pixel boundary detection
- Dismisses on click, ESC key, or timeout
"""

import sys
import os
import argparse
import socket
from PyQt6.QtWidgets import QApplication, QWidget, QLabel, QVBoxLayout
from PyQt6.QtGui import QColor, QFont, QPainter, QPen, QBrush
from PyQt6.QtCore import Qt, QTimer

BG_COLORS = {
    "white": ("#ffffff", "#000000", "#06b6d4"),
    "black": ("#0a0f1d", "#ffffff", "#38bdf8"),
    "neon": ("#00ff66", "#000000", "#111827"),
}

class CalibrationWindow(QWidget):
    def __init__(self, screen, screen_idx, node_id, bg_choice="white", duration_sec=15):
        super().__init__()
        self.screen_idx = screen_idx
        self.node_id = node_id
        self.bg_choice = bg_choice.lower()
        self.duration_sec = duration_sec

        bg_hex, text_hex, accent_hex = BG_COLORS.get(self.bg_choice, BG_COLORS["white"])
        self.bg_hex = bg_hex
        self.text_hex = text_hex
        self.accent_hex = accent_hex

        # Position on specific screen
        geom = screen.geometry()
        self.setGeometry(geom)
        self.screen_geom = geom
        self.screen_name = screen.name()

        # Frameless fullscreen
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.WindowStaysOnTopHint)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground, False)

        # Setup auto-close timer
        if self.duration_sec > 0:
            self.timer = QTimer(self)
            self.timer.timeout.connect(self.close)
            self.timer.start(int(self.duration_sec * 1000))

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key.Key_Escape, Qt.Key.Key_Q, Qt.Key.Key_Space):
            QApplication.quit()

    def mousePressEvent(self, event):
        QApplication.quit()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # 1. Fill solid background
        painter.fillRect(self.rect(), QColor(self.bg_hex))

        w = self.width()
        h = self.height()

        # 2. Draw border frame
        border_pen = QPen(QColor(self.accent_hex), 8)
        painter.setPen(border_pen)
        painter.drawRect(4, 4, w - 8, h - 8)

        # 3. Draw Corner Fiducials (+)
        fid_pen = QPen(QColor(self.text_hex), 6)
        painter.setPen(fid_pen)
        fid_size = 60
        fid_margin = 35

        # Top-Left
        painter.drawLine(fid_margin, fid_margin + fid_size//2, fid_margin + fid_size, fid_margin + fid_size//2)
        painter.drawLine(fid_margin + fid_size//2, fid_margin, fid_margin + fid_size//2, fid_margin + fid_size)

        # Top-Right
        painter.drawLine(w - fid_margin - fid_size, fid_margin + fid_size//2, w - fid_margin, fid_margin + fid_size//2)
        painter.drawLine(w - fid_margin - fid_size//2, fid_margin, w - fid_margin - fid_size//2, fid_margin + fid_size)

        # Bottom-Left
        painter.drawLine(fid_margin, h - fid_margin - fid_size//2, fid_margin + fid_size, h - fid_margin - fid_size//2)
        painter.drawLine(fid_margin + fid_size//2, h - fid_margin - fid_size, fid_margin + fid_size//2, h - fid_margin)

        # Bottom-Right
        painter.drawLine(w - fid_margin - fid_size, h - fid_margin - fid_size//2, w - fid_margin, h - fid_margin - fid_size//2)
        painter.drawLine(w - fid_margin - fid_size//2, h - fid_margin - fid_size, w - fid_margin - fid_size//2, h - fid_margin)

        # 4. Draw Center High-Contrast Identification Card
        card_w = min(w - 120, 800)
        card_h = min(h - 120, 420)
        card_x = (w - card_w) // 2
        card_y = (h - card_h) // 2

        # Card Background
        card_bg = QColor("#0f172a" if self.bg_choice == "white" else "#ffffff")
        card_text = QColor("#ffffff" if self.bg_choice == "white" else "#0f172a")
        card_accent = QColor(self.accent_hex)

        painter.setBrush(QBrush(card_bg))
        painter.setPen(QPen(card_accent, 4))
        painter.drawRoundedRect(card_x, card_y, card_w, card_h, 16, 16)

        # Draw Text inside Card
        painter.setPen(QPen(card_text))
        
        # Subtitle
        painter.setFont(QFont("Monospace", 14, QFont.Weight.Medium))
        painter.drawText(card_x + 30, card_y + 45, "KNOT SWARM TOPOLOGY IDENTIFIER")

        # Node ID (Large)
        painter.setFont(QFont("Monospace", 38, QFont.Weight.Bold))
        painter.drawText(card_x + 30, card_y + 115, f"NODE: {self.node_id}")

        # Output Name & Geometry
        painter.setFont(QFont("Monospace", 24, QFont.Weight.DemiBold))
        painter.setPen(QPen(card_accent))
        painter.drawText(card_x + 30, card_y + 175, f"OUTPUT: {self.screen_name}")

        # Display Metrics
        painter.setFont(QFont("Monospace", 18, QFont.Weight.Normal))
        painter.setPen(QPen(card_text))
        geom_str = f"Geometry: {self.screen_geom.width()}x{self.screen_geom.height()} at ({self.screen_geom.x()},{self.screen_geom.y()})"
        painter.drawText(card_x + 30, card_y + 230, geom_str)

        screen_obj = QApplication.screens()[self.screen_idx]
        scale_str = f"DPI: {int(screen_obj.logicalDotsPerInch())} | Ratio: {screen_obj.devicePixelRatio():.2f}x"
        painter.drawText(card_x + 30, card_y + 275, scale_str)

        # Instructions / Dismissal footer
        painter.setFont(QFont("Monospace", 12, QFont.Weight.Light))
        painter.setPen(QPen(QColor("#94a3b8")))
        painter.drawText(card_x + 30, card_y + card_h - 25, "Click anywhere or press ESC to dismiss. Snap photo for Knot Vision.")

def main():
    parser = argparse.ArgumentParser(description="Knot Display Identification Calibration Overlay")
    parser.add_argument("--node", default="", help="Node ID (defaults to hostname)")
    parser.add_argument("--bg", default="white", choices=["white", "black", "neon"], help="Background color")
    parser.add_argument("--duration", type=int, default=15, help="Auto-close duration in seconds (0 for indefinite)")
    args = parser.parse_args()

    app = QApplication(sys.argv)
    screens = app.screens()
    node_id = args.node or socket.gethostname()

    windows = []
    for idx, scr in enumerate(screens):
        win = CalibrationWindow(scr, idx, node_id, bg_choice=args.bg, duration_sec=args.duration)
        win.showFullScreen()
        windows.append(win)

    sys.exit(app.exec())

if __name__ == "__main__":
    main()
