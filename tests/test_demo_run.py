import json

from fastapi.testclient import TestClient

from somnia.db import reset_engine, session_factory
from somnia.main import create_app
from somnia.models import FeatureWindow
from somnia.pipeline import reset_model_cache


def test_motor_case_scores_and_alarms(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    session = client.post("/api/v1/demo/session", json={"role": "patient"})
    assert session.status_code == 200, session.text
    token = session.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    normal = client.post("/api/v1/demo/runs", headers=headers, json={"case": "normal_sleep"})
    assert normal.status_code == 200, normal.text
    assert normal.json()["active_event"] is None
    normal_peak = max(item["score"] for item in normal.json()["readings"])

    motor = client.post("/api/v1/demo/runs", headers=headers, json={"case": "sustained_motor_event"})
    assert motor.status_code == 200, motor.text
    body = motor.json()
    assert body["monitoring_title"] == "Monitoring Active"
    assert body["wearable_connected"] is False
    assert body["synthetic"] is True
    motor_peak = max(item["score"] for item in body["readings"])
    assert motor_peak > normal_peak
    assert len(body["readings"]) == 32
    assert [item["index"] for item in body["readings"]] == list(range(32))
    event = body["active_event"]
    assert event is not None
    assert event["kind"] == "alarm"
    assert event["alarm_status"] == "awaiting_ack"
    assert "seizure probability" not in event["reason"].lower()

    with session_factory()() as db:
        stored = db.query(FeatureWindow).all()
        blob = json.dumps([row.features for row in stored])
    assert "sustained_motor_event" not in blob
    assert "normal_sleep" not in blob

    ack = client.post(f"/api/v1/events/{event['id']}/acknowledge", headers=headers)
    assert ack.status_code == 200
    assert ack.json()["alarm_status"] == "acknowledged"
    assert ack.json()["acknowledged_at"] is not None

    quiet = client.get("/api/v1/live", headers=headers)
    assert quiet.json()["active_event"] is None
    summary = client.get("/api/v1/insights", headers=headers)
    assert summary.status_code == 200, summary.text
    insight = summary.json()
    assert insight["tonight_count"] >= 1
    assert insight["week_count"] >= insight["tonight_count"]
    assert insight["common_time"]
    assert insight["week_alarms"] >= 1
    assert insight["sleep_window"]
    assert "not a diagnosis" in insight["action"].lower()
    cleared = client.post("/api/v1/demo/reset", headers=headers)
    assert cleared.status_code == 200, cleared.text
    assert cleared.json()["readings"] == []
    assert cleared.json()["monitoring_title"] == "Not monitoring"
    empty = client.get("/api/v1/insights", headers=headers).json()
    assert empty["tonight_count"] == 0
    assert empty["week_count"] == 0
    assert empty["has_data"] is False
    reset_engine()
    reset_model_cache()


def test_vultr_narration_replaces_the_rule_text(tmp_path, monkeypatch) -> None:
    from somnia.narrate import clear_cache

    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    monkeypatch.setenv("VULTR_INFERENCE_API_KEY", "test-key")
    monkeypatch.setattr(
        "somnia.narrate._complete",
        lambda prompt: (
            "Movement and heart rate rose together around the same hour.",
            "If you are safe, turn the alarm off",
        ),
    )
    clear_cache()
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    token = client.post("/api/v1/demo/session", json={"role": "patient"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    motor = client.post("/api/v1/demo/runs", headers=headers, json={"case": "sustained_motor_event"})
    assert motor.status_code == 200, motor.text
    insight = client.get("/api/v1/insights", headers=headers).json()
    assert insight["narration"] == "vultr"
    assert "rose together" in insight["cause"]
    assert "not a diagnosis" in insight["action"].lower()
    clear_cache()
    reset_engine()
    reset_model_cache()


def test_patient_feedback_is_saved_and_does_not_change_the_score(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    patient = client.post("/api/v1/demo/session", json={"role": "patient"}).json()["access_token"]
    caregiver = client.post("/api/v1/demo/session", json={"role": "caregiver"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {patient}"}
    motor = client.post("/api/v1/demo/runs", headers=headers, json={"case": "sustained_motor_event"})
    event = motor.json()["active_event"]
    before = event["score_peak"]
    client.post(f"/api/v1/events/{event['id']}/acknowledge", headers=headers)
    saved = client.post(
        f"/api/v1/events/{event['id']}/feedback",
        headers=headers,
        json={"label": "turning_over", "note": "I rolled onto my side"},
    )
    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body["label"] == "turning_over"
    assert body["phrase"] == "I was turning over"
    assert body["note"] == "I rolled onto my side"
    assert body["review_status"] == "patient_noted"
    events = client.get("/api/v1/events", headers=headers).json()["events"]
    assert events[0]["score_peak"] == before
    assert events[0]["review_status"] == "patient_noted"
    denied = client.post(
        f"/api/v1/events/{event['id']}/feedback",
        headers={"Authorization": f"Bearer {caregiver}"},
        json={"label": "awake", "note": ""},
    )
    assert denied.status_code == 403
    cleared = client.post("/api/v1/demo/reset", headers=headers)
    assert cleared.status_code == 200, cleared.text
    reset_engine()
    reset_model_cache()


def test_heart_rate_only_is_an_observation(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    token = client.post("/api/v1/demo/session", json={"role": "patient"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    response = client.post("/api/v1/demo/runs", headers=headers, json={"case": "hr_only"})
    assert response.status_code == 200, response.text
    events = client.get("/api/v1/events", headers=headers).json()["events"]
    assert events
    assert events[0]["kind"] == "observation"
    assert events[0]["alarm_status"] == "not_required"
    reset_engine()
    reset_model_cache()
