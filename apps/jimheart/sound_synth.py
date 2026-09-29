"""
Sound synthesis module for Jim Heart's Key Smash Game.
Generates and caches soothing pentatonic chimes using standard Python wave and math libraries.
Zero external audio generation dependencies.
"""

import math
import os
import shutil
import struct
import subprocess
import wave
from pathlib import Path
from typing import Dict, List, Optional

# Soothing pentatonic frequencies (Hz) across octaves 4, 5, and 6
PENTATONIC_FREQUENCIES: List[float] = [
    261.63,  # C4
    293.66,  # D4
    329.63,  # E4
    392.00,  # G4
    440.00,  # A4
    523.25,  # C5
    587.33,  # D5
    659.25,  # E5
    783.99,  # G5
    880.00,  # A5
    1046.50, # C6
]


def generate_chime_wav(
    filepath: Path,
    frequency: float,
    sample_rate: int = 44100,
    duration: float = 0.55,
) -> None:
    """
    Synthesize a celestial music-box chime with harmonic overtones and gentle decay.
    """
    filepath.parent.mkdir(parents=True, exist_ok=True)
    n_samples = int(sample_rate * duration)
    data = bytearray()

    for i in range(n_samples):
        t = i / sample_rate
        # Fast 5ms attack envelope to prevent clicks
        if t < 0.005:
            attack = t / 0.005
        else:
            attack = 1.0

        # Gentle exponential decay
        decay = math.exp(-5.0 * t)
        envelope = attack * decay

        # Fundamental + harmonic overtones (celesta / bell color)
        s1 = math.sin(2.0 * math.pi * frequency * t)
        s2 = 0.28 * math.sin(2.0 * math.pi * (2.0 * frequency) * t)
        s3 = 0.12 * math.sin(2.0 * math.pi * (3.0 * frequency) * t)
        s4 = 0.05 * math.sin(2.0 * math.pi * (4.2 * frequency) * t)
        combined = (s1 + s2 + s3 + s4) / 1.45

        # 16-bit PCM integer range
        sample_val = int(32767.0 * 0.65 * envelope * combined)
        sample_val = max(-32767, min(32767, sample_val))
        data.extend(struct.pack("<h", sample_val))

    with wave.open(str(filepath), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(data)


class SoundBank:
    """
    Manages the bank of generated sound files and plays them smoothly.
    """

    def __init__(self, cache_dir: Optional[Path] = None):
        if cache_dir is None:
            cache_dir = Path.home() / ".cache" / "knot-jimheart" / "sounds"
        self.cache_dir = cache_dir
        self.sound_paths: List[Path] = []
        self._qsound_effects: List = []
        self._note_index: int = 0
        self.ensure_sounds()

    def ensure_sounds(self) -> None:
        """Ensure all pentatonic chimes are synthesized and available on disk."""
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.sound_paths = []
        for idx, freq in enumerate(PENTATONIC_FREQUENCIES):
            wav_path = self.cache_dir / f"chime_{idx}_{int(freq)}hz.wav"
            if not wav_path.exists() or wav_path.stat().st_size == 0:
                generate_chime_wav(wav_path, freq)
            self.sound_paths.append(wav_path)

    def init_qt_effects(self) -> None:
        """Optional Qt initialization for latency-free in-process audio."""
        try:
            from PyQt6.QtCore import QUrl
            from PyQt6.QtMultimedia import QSoundEffect

            self._qsound_effects = []
            for path in self.sound_paths:
                effect = QSoundEffect()
                effect.setSource(QUrl.fromLocalFile(str(path)))
                effect.setVolume(0.7)
                self._qsound_effects.append(effect)
        except Exception:
            self._qsound_effects = []

    def play_key(self, key_text: str = "") -> None:
        """
        Play a harmonious chime corresponding to the key pressed.
        Cycles musically through the pentatonic scale.
        """
        if not self.sound_paths:
            return

        if key_text:
            idx = (ord(key_text[0]) + self._note_index) % len(self.sound_paths)
        else:
            idx = self._note_index % len(self.sound_paths)
        self._note_index = (self._note_index + 1) % len(self.sound_paths)

        # Prefer Qt in-memory audio if initialized
        if self._qsound_effects and idx < len(self._qsound_effects):
            effect = self._qsound_effects[idx]
            effect.play()
            return

        # Fallback to system command (pw-play / paplay / aplay)
        wav_file = self.sound_paths[idx]
        for player in ["pw-play", "paplay", "aplay"]:
            if shutil.which(player):
                subprocess.Popen(
                    [player, str(wav_file)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                break
