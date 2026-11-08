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
# Wrist-accelerometer detectors flag convulsive seizures when strong rhythmic movement continues,
# not when someone turns once (Beniczky et al., Epilepsia, 2013). This line sits above a brief
# turn (~2.3 m/s²) and below that sustained pattern. It is not a published cutoff in m/s².
MOTION_BAR = 3.5
# Low end of the 20–70% heart-rate rise used by cardiac seizure detection.
HR_RISE = 0.20
_VARIED = ("normal_sleep", "turn_in_bed", "hr_only")


def heart_rate_bar(baseline: float = BASELINE_HR) -> float:
    return baseline * (1 + HR_RISE)


def case_for_click(completed: int) -> str:
    """Every third demo click is the seizure-like pattern. The others rotate."""
    click = completed + 1
    if click % 3 == 0:
        return "sustained_motor_event"
    slot = click - (click // 3) - 1
    return _VARIED[slot % len(_VARIED)]


def _shape(case: str, index: int, variation: int = 0) -> tuple[float, float, float, str]:
    """Amplitude, frequency Hz, heart rate, sample quality. Case name stays here."""
    quiet = (0.03, 0.2, BASELINE_HR, "good")
    if case == "normal_sleep":
        wobble = (variation % 3) * 0.01
        return (0.03 + wobble, 0.2, BASELINE_HR + (variation % 4), "good")
    if case == "turn_in_bed":
        if 3 <= index <= 4:
            return (2.2 + (variation % 3) * 0.15, 0.6 + (variation % 2) * 0.2, BASELINE_HR + 3 + (variation % 3), "good")
        return quiet
    if case == "sustained_motor_event":
        if 5 <= index <= 12:
            # 2–5 Hz is the rhythmic band used for convulsive movement. Each third click differs.
            frequency = 2.4 + (variation % 3) * 0.8
            amplitude = 5.2 + (variation % 3) * 0.45
            heart = heart_rate_bar() + 30 + (variation % 4) * 4
            return (amplitude, frequency, heart, "good")
        return quiet
    if case == "hr_only":
        if 5 <= index <= 12:
            return (0.04, 0.2, heart_rate_bar() + 24 + (variation % 3) * 6, "good")
        return quiet
    raise ValueError("unknown case")


def synthesize_second(case: str, index: int, seed: int, variation: int = 0) -> tuple[float, float, float, str, list[dict]]:
    amplitude, frequency, heart_rate, quality = _shape(case, index, variation)
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
