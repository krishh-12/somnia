import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from somnia.ml import BASELINE_HR, FEATURE_VERSION, MODEL_SEED, anomaly_score, train_model
from somnia.models import (
    AccessToken,
    AnomalyLog,
    Event,
    FeatureWindow,
    ModelVersion,
    MonitoringSession,
    NightLog,
    Patient,
    Review,
    SensorBatch,
    User,
)
from somnia.narrate import NightBars, compile_bars, describe_event
from somnia.signals import CASES, SECONDS, TURN_MOTION, estimate_hrv, synthesize_second

FEEDBACK_LABELS = {
    "turning_over": "I was turning over",
    "awake": "I was awake",
    "unsure": "I'm not sure",
}

ACK_SECONDS = 20
PATIENT_ID = uuid.UUID("11111111-1111-4111-8111-111111111111")
ROLES = {
    "patient": ("Krish Hariharan", "krish.hariharan@demo.somnia.test"),
    "caregiver": ("Casey Morgan", "casey.morgan@demo.somnia.test"),
    "physician": ("Parker Singh", "parker.singh@demo.somnia.test"),
}

class IsolationForestCache:
    def __init__(self, model, threshold: float, model_id: uuid.UUID) -> None:
        self.model = model
        self.threshold = threshold
        self.model_id = model_id


_model: IsolationForestCache | None = None


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


def ensure_ready(db: Session) -> Patient:
    patient = db.get(Patient, PATIENT_ID)
    if patient is None:
        patient = Patient(
            id=PATIENT_ID,
            display_name=ROLES["patient"][0],
            timezone="America/Chicago",
            sleep_start="22:00",
            sleep_end="06:30",
            baseline_hr=BASELINE_HR,
        )
        db.add(patient)
        db.flush()
    else:
        patient.display_name = ROLES["patient"][0]
    for role, (name, email) in ROLES.items():
        user = db.scalar(select(User).where(User.role == role))
        if user is None:
            db.add(User(role=role, display_name=name, email=email))
        else:
            user.display_name = name
            user.email = email
    db.flush()
    global _model
    existing = db.scalar(
        select(ModelVersion)
        .where(ModelVersion.patient_id == patient.id, ModelVersion.feature_version == FEATURE_VERSION)
        .order_by(ModelVersion.created_at.desc())
    )
    if _model is None or existing is None:
        trained, threshold = train_model()
        if existing is None:
            existing = ModelVersion(
                patient_id=patient.id,
                feature_version=FEATURE_VERSION,
                seed=MODEL_SEED,
                threshold=threshold,
                baseline_hr=BASELINE_HR,
                metrics={
                    "algorithm": "IsolationForest",
                    "score": "negative decision_function; higher is more anomalous",
                    "not": "seizure probability",
                },
            )
            db.add(existing)
            db.flush()
        _model = IsolationForestCache(trained, existing.threshold, existing.id)
    db.commit()
    return patient


def reset_model_cache() -> None:
    global _model
    _model = None


def open_demo_session(db: Session, role: str) -> tuple[str, User, Patient]:
    if role not in ROLES:
        raise ValueError("role")
    patient = ensure_ready(db)
    user = db.scalar(select(User).where(User.role == role))
    if user is None:
        raise RuntimeError("demo user missing")
    raw = secrets.token_urlsafe(24)
    db.add(
        AccessToken(
            user_id=user.id,
            token_hash=hash_token(raw),
            expires_at=utcnow() + timedelta(hours=12),
        )
    )
    db.commit()
    return raw, user, patient


def user_for_token(db: Session, raw: str) -> User | None:
    row = db.scalar(select(AccessToken).where(AccessToken.token_hash == hash_token(raw)))
    if row is None or aware(row.expires_at) <= utcnow():
        return None
    return db.get(User, row.user_id)


def _cache(db: Session) -> IsolationForestCache:
    ensure_ready(db)
    if _model is None:
        raise RuntimeError("model missing")
    return _model


def run_case(db: Session, case: str, seed: int = MODEL_SEED) -> MonitoringSession:
    if case not in CASES:
        raise ValueError("case")
    patient = ensure_ready(db)
    cached = _cache(db)
    from somnia.insights import place_on_night

    prior = db.scalar(
        select(func.count()).select_from(MonitoringSession).where(MonitoringSession.patient_id == patient.id)
    ) or 0
    started = place_on_night(patient, int(prior), utcnow())
    session = MonitoringSession(
        patient_id=patient.id,
        source="simulator",
        demo_case=case,
        synthetic=True,
        started_at=started,
    )
    db.add(session)
    db.flush()

    bars = compile_bars(patient.baseline_hr)
    streak = 0
    calm = 0
    hr_streak = 0
    open_event: Event | None = None
    windows: list[FeatureWindow] = []
    for index in range(SECONDS):
        heart_rate, motion_rms, motion_var, hrv, quality, motion = synthesize_second(case, index, seed, int(prior))
        moment = started + timedelta(minutes=index * 2)
        score = anomaly_score(cached.model, heart_rate, motion_rms, motion_var)
        features = {
            "hr": round(heart_rate, 3),
            "hr_delta": round(heart_rate - BASELINE_HR, 3),
            "motion_rms": round(motion_rms, 4),
            "motion_var": round(motion_var, 4),
            "hrv_rmssd": round(hrv, 2),
        }
        db.add(
            SensorBatch(
                patient_id=patient.id,
                session_id=session.id,
                sequence=index,
                started_at=moment,
                source="simulator",
                heart_rate_bpm=heart_rate,
                motion_rms=motion_rms,
                motion_var=motion_var,
                quality=quality,
                payload={"schema_version": 1, "source": "simulator", "motion": motion, "heart_rate_bpm": heart_rate},
            )
        )
        window = FeatureWindow(
            patient_id=patient.id,
            session_id=session.id,
            sequence=index,
            window_end=moment,
            features=features,
            raw_score=score,
            quality=quality,
            model_id=cached.model_id,
        )
        windows.append(window)
        db.add(window)
        qualifying = motion_rms >= bars.motion_bar and heart_rate >= bars.heart_rate_bar
        hr_only = heart_rate >= bars.heart_rate_bar and motion_rms < bars.motion_bar
        if qualifying:
            streak += 1
            calm = 0
            hr_streak = 0
            if streak >= 3 and open_event is None:
                open_event = Event(
                    patient_id=patient.id,
                    session_id=session.id,
                    kind="alarm",
                    alarm_status="awaiting_ack",
                    review_status="unreviewed",
                    started_at=moment,
                    deadline_at=utcnow() + timedelta(seconds=ACK_SECONDS),
                    reason="Sustained anomalous motion and heart rate",
                    score_peak=score,
                    synthetic=True,
                )
                db.add(open_event)
            elif open_event is not None and score > (open_event.score_peak or 0):
                open_event.score_peak = score
        elif hr_only:
            streak = 0
            hr_streak += 1
            calm = 0
            if hr_streak >= 3 and open_event is None:
                open_event = Event(
                    patient_id=patient.id,
                    session_id=session.id,
                    kind="observation",
                    alarm_status="not_required",
                    review_status="unreviewed",
                    started_at=moment,
                    reason="Sustained heart-rate change without a motor pattern",
                    score_peak=score,
                    synthetic=True,
                )
                db.add(open_event)
        else:
            streak = 0
            hr_streak = 0
            calm += 1
            if open_event is not None and open_event.ended_at is None and calm >= 3:
                open_event.ended_at = moment
    session.ended_at = started + timedelta(minutes=(SECONDS - 1) * 2)
    _save_run_log(db, session, open_event, windows, bars)
    db.commit()
    return session


def latest_session(db: Session) -> MonitoringSession | None:
    return db.scalar(select(MonitoringSession).order_by(MonitoringSession.started_at.desc()))


def readings_for(db: Session, session_id: uuid.UUID) -> list[FeatureWindow]:
    return list(
        db.scalars(
            select(FeatureWindow).where(FeatureWindow.session_id == session_id).order_by(FeatureWindow.sequence)
        ).all()
    )


def compounded_readings(db: Session) -> list[tuple[int, FeatureWindow]]:
    sessions = db.scalars(select(MonitoringSession).order_by(MonitoringSession.started_at, MonitoringSession.id)).all()
    rows: list[tuple[int, FeatureWindow]] = []
    for run_index, session in enumerate(sessions):
        for window in readings_for(db, session.id):
            rows.append((run_index, window))
    return rows


def _sample(window: FeatureWindow) -> tuple[float, float, float] | None:
    features = window.features or {}
    heart_rate = features.get("hr")
    motion_rms = features.get("motion_rms")
    if heart_rate is None or motion_rms is None:
        return None
    hrv = features.get("hrv_rmssd")
    if hrv is None:
        hrv = estimate_hrv(float(heart_rate), float(motion_rms))
    return float(heart_rate), float(motion_rms), float(hrv)


def characteristic(
    windows: list[FeatureWindow], bars: NightBars | None = None
) -> tuple[FeatureWindow, str, float, float, float] | None:
    """One profile for a run, chosen from its measurements. Quiet sleep returns nothing."""
    resolved = bars or compile_bars()
    rows = [(window, sample) for window in windows if (sample := _sample(window)) is not None]
    if not rows:
        return None
    seizure = [row for row in rows if row[1][1] >= resolved.motion_bar and row[1][0] >= resolved.heart_rate_bar]
    if seizure:
        window, (heart_rate, motion_rms, hrv) = max(seizure, key=lambda row: row[1][1])
        return window, "seizure_like", heart_rate, motion_rms, hrv
    if max(row[1][0] for row in rows) >= resolved.heart_rate_bar:
        window, (heart_rate, motion_rms, hrv) = max(rows, key=lambda row: row[1][0])
        return window, "heart_rate", heart_rate, motion_rms, hrv
    if max(row[1][1] for row in rows) >= TURN_MOTION:
        window, (heart_rate, motion_rms, hrv) = max(rows, key=lambda row: row[1][1])
        return window, "turn", heart_rate, motion_rms, hrv
    return None


def _save_run_log(
    db: Session, session: MonitoringSession, event: Event | None, windows: list[FeatureWindow], bars: NightBars
) -> None:
    found = characteristic(windows, bars)
    if found is None:
        return
    window, kind, heart_rate, motion_rms, hrv = found
    db.flush()
    likely, detail, source = describe_event(
        kind=kind,
        score=window.raw_score or 0,
        heart_rate=heart_rate,
        motion_rms=motion_rms,
        hrv_rmssd=hrv,
    )
    db.add(
        AnomalyLog(
            session_id=session.id,
            event_id=None if event is None else event.id,
            started_at=window.window_end,
            likely=likely,
            detail=detail,
            source=source,
            kind=kind,
            heart_rate_bpm=round(heart_rate, 1),
            hrv_rmssd=round(hrv, 1),
            motion_rms=round(motion_rms, 2),
            synthetic=True,
        )
    )


def ensure_logs(db: Session) -> None:
    sessions = db.scalars(select(MonitoringSession)).all()
    have = set(db.scalars(select(AnomalyLog.session_id)).all())
    for session in sessions:
        if session.id in have:
            continue
        found = characteristic(readings_for(db, session.id))
        if found is None:
            continue
        window, kind, heart_rate, motion_rms, hrv = found
        likely, detail, source = describe_event(
            kind=kind,
            score=window.raw_score or 0,
            heart_rate=heart_rate,
            motion_rms=motion_rms,
            hrv_rmssd=hrv,
        )
        event = db.scalar(select(Event).where(Event.session_id == session.id))
        db.add(
            AnomalyLog(
                session_id=session.id,
                event_id=None if event is None else event.id,
                started_at=window.window_end,
                likely=likely,
                detail=detail,
                source=source,
                kind=kind,
                heart_rate_bpm=round(heart_rate, 1),
                hrv_rmssd=round(hrv, 1),
                motion_rms=round(motion_rms, 2),
                synthetic=session.synthetic,
            )
        )
    for saved in db.scalars(select(AnomalyLog).where(AnomalyLog.source == "rules")).all():
        likely, detail, source = describe_event(
            kind=saved.kind,
            score=0,
            heart_rate=saved.heart_rate_bpm,
            motion_rms=saved.motion_rms,
            hrv_rmssd=saved.hrv_rmssd,
        )
        if source != "vultr":
            continue
        saved.likely = likely
        saved.detail = detail
        saved.source = source
    db.commit()


def reset_demo_data(db: Session) -> None:
    ensure_ready(db)
    for table in (AnomalyLog, NightLog, Review, Event, FeatureWindow, SensorBatch, MonitoringSession):
        db.execute(delete(table))
    db.commit()


def active_alarm(db: Session) -> Event | None:
    return db.scalar(
        select(Event)
        .where(Event.kind == "alarm", Event.alarm_status == "awaiting_ack")
        .order_by(Event.started_at.desc())
    )


def acknowledge(db: Session, event_id: uuid.UUID) -> Event | None:
    event = db.get(Event, event_id)
    if event is None:
        return None
    if event.alarm_status == "awaiting_ack":
        event.alarm_status = "acknowledged"
        event.acknowledged_at = utcnow()
        event.review_status = "unreviewed"
        db.commit()
    return event


def record_patient_feedback(
    db: Session,
    event_id: uuid.UUID,
    author_name: str,
    label: str,
    note: str,
) -> Review | None:
    event = db.get(Event, event_id)
    if event is None or label not in FEEDBACK_LABELS:
        return None
    cleaned = " ".join(note.split())[:280]
    existing = db.scalar(select(Review).where(Review.event_id == event.id))
    if existing is None:
        existing = Review(event_id=event.id, author_name=author_name, label=label, note=cleaned)
        db.add(existing)
    else:
        existing.author_name = author_name
        existing.label = label
        existing.note = cleaned
    event.review_status = "patient_noted"
    db.commit()
    return existing
