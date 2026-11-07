import math

import numpy as np

from somnia.ml import BASELINE_HR

CASES = (
    "normal_sleep",
    "turn_in_bed",
    "sustained_motor_event",
    "hr_only",
)
SECONDS = 16


def _shape(case: str, index: int) -> tuple[float, float, float, str]:
    """Amplitude, frequency Hz, heart rate, sample quality. Case name stays here."""
    quiet = (0.03, 0.2, BASELINE_HR, "good")
    if case == "normal_sleep":
        return quiet
    if case == "turn_in_bed":
        if 3 <= index <= 4:
            return (2.4, 0.7, BASELINE_HR + 4, "good")
        return quiet
    if case == "sustained_motor_event":
        if 5 <= index <= 12:
            return (6.0, 4.0, 118.0, "good")
        return quiet
    if case == "hr_only":
        if 5 <= index <= 12:
            return (0.04, 0.2, 122.0, "good")
        return quiet
    raise ValueError("unknown case")


def synthesize_second(case: str, index: int, seed: int) -> tuple[float, float, float, str, list[dict]]:
    amplitude, frequency, heart_rate, quality = _shape(case, index)
    rng = np.random.default_rng(seed + index * 17)
    motion: list[dict] = []
    magnitudes: list[float] = []
    for sample_index, offset_ms in enumerate(range(0, 1000, 40)):
        moment = index + sample_index / 25
        wobble = float(rng.normal(0, 0.008))
        x = amplitude * math.sin(2 * math.pi * frequency * moment) + wobble
        y = amplitude * 0.65 * math.sin(2 * math.pi * frequency * moment + 1.1) + wobble
        z = amplitude * 0.45 * math.cos(2 * math.pi * frequency * moment) + wobble
        magnitude = math.sqrt(x * x + y * y + z * z)
        magnitudes.append(magnitude)
        motion.append(
            {
                "offset_ms": offset_ms,
                "x": round(x, 4),
                "y": round(y, 4),
                "z": round(z, 4),
                "quality": quality,
            }
        )
    rms = math.sqrt(sum(value * value for value in magnitudes) / len(magnitudes))
    mean = sum(magnitudes) / len(magnitudes)
    variance = sum((value - mean) ** 2 for value in magnitudes) / len(magnitudes)
    return heart_rate, rms, variance, quality, motion
