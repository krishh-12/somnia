from collections import Counter
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.orm import Session

from somnia.models import Event, Patient
from somnia.narrate import phrase
from somnia.pipeline import PATIENT_ID, aware, ensure_ready


def _clock(value: str) -> tuple[int, int]:
    hour, minute = value.split(":")
    return int(hour), int(minute)


def sleep_bounds(patient: Patient, now: datetime) -> tuple[datetime, datetime]:
    """The sleep night that contains now, or the most recent one if now is daytime."""
    zone = ZoneInfo(patient.timezone)
    local = now.astimezone(zone)
    start_hour, start_minute = _clock(patient.sleep_start)
    end_hour, end_minute = _clock(patient.sleep_end)
    start = local.replace(hour=start_hour, minute=start_minute, second=0, microsecond=0)
    end = local.replace(hour=end_hour, minute=end_minute, second=0, microsecond=0)
    if (end_hour, end_minute) <= (start_hour, start_minute):
        if (local.hour, local.minute) < (end_hour, end_minute):
            start -= timedelta(days=1)
        else:
            end += timedelta(days=1)
    elif local < start:
        start -= timedelta(days=1)
        end -= timedelta(days=1)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def place_on_night(patient: Patient, run_index: int, now: datetime) -> datetime:
    """Put each test on a later slice of the same night so the graph reads as time of night."""
    start, end = sleep_bounds(patient, now)
    slot = timedelta(minutes=32)
    stride = timedelta(minutes=40)
    usable = max((end - start) - slot, slot)
    offset = timedelta(minutes=15) + (run_index * stride) % usable
    return start + offset


def _hour_label(hour: int) -> str:
    suffix = "AM" if hour < 12 else "PM"
    shown = hour % 12 or 12
    return f"{shown} {suffix}"


def build_insights(db: Session, now: datetime | None = None) -> dict:
    patient = ensure_ready(db)
    moment = now or datetime.now(timezone.utc)
    night_start, night_end = sleep_bounds(patient, moment)
    week_start = night_end - timedelta(days=7)
    zone = ZoneInfo(patient.timezone)
    events = list(db.scalars(select(Event).where(Event.patient_id == PATIENT_ID)).all())
    tonight = [event for event in events if night_start <= aware(event.started_at) < night_end]
    week = [event for event in events if aware(event.started_at) >= week_start]
    hours = Counter(aware(event.started_at).astimezone(zone).hour for event in week)
    common_hour = None
    common_count = 0
    if hours:
        common_count = max(hours.values())
        common_hour = min(hour for hour, count in hours.items() if count == common_count)
    alarms = sum(1 for event in week if event.kind == "alarm")
    observations = sum(1 for event in week if event.kind == "observation")
    tonight_alarms = sum(1 for event in tonight if event.kind == "alarm")
    tonight_observations = sum(1 for event in tonight if event.kind == "observation")
    turned_off = sum(1 for event in week if event.acknowledged_at is not None)
    waiting = sum(1 for event in week if event.alarm_status == "awaiting_ack")
    peaks = [event.score_peak for event in week if event.score_peak is not None]
    common_time = None if common_hour is None else f"Around {_hour_label(common_hour)}"
    cause, action, narration = phrase(
        alarms=alarms,
        observations=observations,
        tonight=len(tonight),
        week=len(week),
        common_time=common_time,
        has_data=bool(week),
    )
    return {
        "tonight_count": len(tonight),
        "week_count": len(week),
        "tonight_alarms": tonight_alarms,
        "tonight_observations": tonight_observations,
        "week_alarms": alarms,
        "week_observations": observations,
        "turned_off_count": turned_off,
        "waiting_count": waiting,
        "peak_score": None if not peaks else round(max(peaks), 2),
        "sleep_window": f"{patient.sleep_start}–{patient.sleep_end}",
        "common_time": common_time,
        "common_time_count": common_count,
        "cause": cause,
        "action": action,
        "narration": narration,
        "synthetic": True,
        "has_data": bool(week),
    }
