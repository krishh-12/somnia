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
