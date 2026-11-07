import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from somnia.db import db_session
from somnia.models import Event, FeatureWindow
from somnia.pipeline import (
    acknowledge,
    active_alarm,
    aware,
    ensure_ready,
    compounded_readings,
    latest_session,
    open_demo_session,
    reset_demo_data,
    run_case,
    user_for_token,
)
from somnia.signals import CASES

router = APIRouter(prefix="/api/v1")


class DemoBody(BaseModel):
    role: str = Field(pattern="^(patient|caregiver|physician)$")


class RunBody(BaseModel):
    case: str


class SessionOut(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    role: str
    display_name: str
    patient_id: uuid.UUID
    patient_name: str


class ReadingOut(BaseModel):
    index: int
    run: int
    sequence: int
    at: datetime
    heart_rate_bpm: float | None
    motion_rms: float | None
    score: float | None
    quality: str


class EventOut(BaseModel):
    id: uuid.UUID
    kind: str
    alarm_status: str
    review_status: str
    started_at: datetime
    ended_at: datetime | None
    deadline_at: datetime | None
    acknowledged_at: datetime | None
    reason: str
    score_peak: float | None
    synthetic: bool


class LiveOut(BaseModel):
    patient_name: str
    sleep_window: str
    monitoring: str
    monitoring_title: str
    detail: str
    wearable_connected: bool
    wearable_label: str
    baseline_hr: float
    model_threshold: float | None
    demo_case: str | None
    synthetic: bool
    readings: list[ReadingOut]
    active_event: EventOut | None


class EventList(BaseModel):
    events: list[EventOut]


def current_user(
    db: Session = Depends(db_session),
    authorization: str | None = Header(default=None),
):
    if authorization is None or not authorization.lower().startswith("bearer "):
        from fastapi import HTTPException

        raise HTTPException(status_code=401, detail="Sign in with a demo role")
    user = user_for_token(db, authorization.split(" ", 1)[1].strip())
    if user is None:
        from fastapi import HTTPException

        raise HTTPException(status_code=401, detail="Demo session expired")
    return user


def _event_out(event: Event) -> EventOut:
    return EventOut(
        id=event.id,
        kind=event.kind,
        alarm_status=event.alarm_status,
        review_status=event.review_status,
        started_at=aware(event.started_at),
        ended_at=aware(event.ended_at) if event.ended_at else None,
        deadline_at=aware(event.deadline_at) if event.deadline_at else None,
        acknowledged_at=aware(event.acknowledged_at) if event.acknowledged_at else None,
        reason=event.reason,
        score_peak=event.score_peak,
        synthetic=event.synthetic,
    )


def _reading(index: int, run: int, window: FeatureWindow) -> ReadingOut:
    features = window.features or {}
    return ReadingOut(
        index=index,
        run=run,
        sequence=window.sequence,
        at=aware(window.window_end),
        heart_rate_bpm=features.get("hr"),
        motion_rms=features.get("motion_rms"),
        score=window.raw_score,
        quality=window.quality,
    )


def snapshot(db: Session) -> LiveOut:
    patient = ensure_ready(db)
    session = latest_session(db)
    rows = compounded_readings(db)
    alarm = active_alarm(db)
    has_readings = bool(rows)
    if has_readings:
        title = "Monitoring Active"
        monitoring = "simulation_active"
        detail = "Each test adds to this graph. Reset clears it."
    else:
        title = "Not monitoring"
        monitoring = "idle"
        detail = "The graph is empty until a test is scored."
    from somnia.pipeline import _model

    return LiveOut(
        patient_name=patient.display_name,
        sleep_window=f"{patient.sleep_start}–{patient.sleep_end} {patient.timezone}",
        monitoring=monitoring,
        monitoring_title=title,
        detail=detail,
        wearable_connected=False,
        wearable_label="Wearable import not connected",
        baseline_hr=patient.baseline_hr,
        model_threshold=None if _model is None else _model.threshold,
        demo_case=None if session is None else session.demo_case,
        synthetic=True if session is None else session.synthetic,
        readings=[_reading(index, run, window) for index, (run, window) in enumerate(rows)],
        active_event=None if alarm is None else _event_out(alarm),
    )


@router.post("/demo/session", response_model=SessionOut)
def demo_session(body: DemoBody, db: Session = Depends(db_session)) -> SessionOut:
    raw, user, patient = open_demo_session(db, body.role)
    return SessionOut(
        access_token=raw,
        role=user.role,
        display_name=user.display_name,
        patient_id=patient.id,
        patient_name=patient.display_name,
    )


@router.get("/live", response_model=LiveOut)
def live(_user=Depends(current_user), db: Session = Depends(db_session)) -> LiveOut:
    return snapshot(db)


@router.post("/demo/runs", response_model=LiveOut)
def demo_run(body: RunBody, user=Depends(current_user), db: Session = Depends(db_session)) -> LiveOut:
    from fastapi import HTTPException

    if user.role != "patient":
        raise HTTPException(status_code=403, detail="Only the patient demo view runs a test")
    if body.case not in CASES:
        raise HTTPException(status_code=422, detail="Unknown test case")
    run_case(db, body.case)
    return snapshot(db)


@router.post("/demo/reset", response_model=LiveOut)
def demo_reset(user=Depends(current_user), db: Session = Depends(db_session)) -> LiveOut:
    from fastapi import HTTPException

    if user.role != "patient":
        raise HTTPException(status_code=403, detail="Only the patient demo can reset saved readings")
    reset_demo_data(db)
    return snapshot(db)


@router.get("/events", response_model=EventList)
def events(_user=Depends(current_user), db: Session = Depends(db_session)) -> EventList:
    rows = db.scalars(select(Event).order_by(Event.started_at.desc())).all()
    return EventList(events=[_event_out(row) for row in rows])


@router.post("/events/{event_id}/acknowledge", response_model=EventOut)
def ack(event_id: uuid.UUID, user=Depends(current_user), db: Session = Depends(db_session)) -> EventOut:
    from fastapi import HTTPException

    if user.role != "patient":
        raise HTTPException(status_code=403, detail="The patient demo view acknowledges the alarm")
    event = acknowledge(db, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="Event not found")
    return _event_out(event)
