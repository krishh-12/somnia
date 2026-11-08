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


def test_every_third_click_crosses_the_study_bar(tmp_path, monkeypatch) -> None:
    from somnia.signals import MOTION_BAR, heart_rate_bar

    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    token = client.post("/api/v1/demo/session", json={"role": "patient"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    runs = []
    for _ in range(3):
        response = client.post("/api/v1/demo/runs", headers=headers, json={"case": "next"})
        assert response.status_code == 200, response.text
        runs.append(response.json())
    assert runs[0]["active_event"] is None
    assert runs[1]["active_event"] is None
    assert max(item["motion_rms"] for item in runs[1]["readings"] if item["run"] == 1) < MOTION_BAR
    alarm = runs[2]["active_event"]
    assert alarm is not None
    assert alarm["kind"] == "alarm"
    motor = [item for item in runs[2]["readings"] if item["run"] == 2]
    assert max(item["motion_rms"] for item in motor) >= MOTION_BAR
    assert max(item["heart_rate_bpm"] for item in motor) >= heart_rate_bar()
    turn = [item for item in runs[1]["readings"] if item["run"] == 1]
    assert min(item["hrv_rmssd"] for item in motor) < min(item["hrv_rmssd"] for item in turn)
    assert runs[2]["motion_bar"] == MOTION_BAR
    assert runs[2]["heart_rate_bar"] == round(heart_rate_bar(), 2)
    with session_factory()() as db:
        stored = db.query(FeatureWindow).all()
        blob = json.dumps([row.features for row in stored])
    assert "sustained_motor_event" not in blob
    assert "next" not in blob
    reset_engine()
    reset_model_cache()


def test_anomaly_log_follows_reset(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    monkeypatch.delenv("VULTR_INFERENCE_API_KEY", raising=False)
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    token = client.post("/api/v1/demo/session", json={"role": "patient"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    for _ in range(3):
        assert client.post("/api/v1/demo/runs", headers=headers, json={"case": "next"}).status_code == 200
    listed = client.get("/api/v1/logs", headers=headers)
    assert listed.status_code == 200, listed.text
    entries = listed.json()["entries"]
    assert [item["kind"] for item in entries] == ["seizure_like", "turn"]
    assert entries[0]["likely"] == "Likely a seizure-like pattern"
    assert entries[1]["likely"] == "Likely a turn in bed"
    assert entries[0]["source"] == "rules"
    assert entries[0]["heart_rate_bpm"] > entries[1]["heart_rate_bpm"]
    assert entries[0]["hrv_rmssd"] < entries[1]["hrv_rmssd"]
    assert "not a diagnosis" in entries[0]["detail"].lower()
    cleared = client.post("/api/v1/demo/reset", headers=headers)
    assert cleared.status_code == 200
    assert client.get("/api/v1/logs", headers=headers).json()["entries"] == []
    reset_engine()
    reset_model_cache()


def test_vultr_log_uses_the_model_label(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    monkeypatch.setenv("VULTR_INFERENCE_API_KEY", "test-key")
    monkeypatch.setattr(
        "somnia.pipeline.describe_event",
        lambda **_kwargs: (
            "Likely a seizure-like pattern",
            "The saved pattern combined movement and heart rate. This is not a diagnosis.",
            "vultr",
        ),
    )
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    token = client.post("/api/v1/demo/session", json={"role": "patient"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    client.post("/api/v1/demo/runs", headers=headers, json={"case": "sustained_motor_event"})
    entry = client.get("/api/v1/logs", headers=headers).json()["entries"][0]
    assert entry["source"] == "vultr"
    assert entry["likely"] == "Likely a seizure-like pattern"
    assert entry["kind"] == "seizure_like"
    assert entry["hrv_rmssd"] < 20
    reset_engine()
    reset_model_cache()


def test_a_period_on_the_vultr_label_is_still_accepted() -> None:
    from somnia.narrate import _parse_log, _plain_summary

    parsed = _parse_log(
        '{"likely": "Likely a seizure-like pattern.", '
        '"detail": "Heart rate rose and variability fell. This is not a diagnosis."}'
    )
    assert parsed == (
        "Likely a seizure-like pattern",
        "Heart rate rose and variability fell. This is not a diagnosis.",
    )
    assert _plain_summary("The night showed a seizure-like pattern.", "This is not a diagnosis.")
    assert not _plain_summary("This was a seizure.", "This is not a diagnosis.")


def test_saved_rule_log_is_rewritten_from_vultr(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{tmp_path}/somnia.db")
    monkeypatch.delenv("VULTR_INFERENCE_API_KEY", raising=False)
    reset_engine()
    reset_model_cache()
    client = TestClient(create_app())
    token = client.post("/api/v1/demo/session", json={"role": "patient"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    client.post("/api/v1/demo/runs", headers=headers, json={"case": "sustained_motor_event"})
    assert client.get("/api/v1/logs", headers=headers).json()["entries"][0]["source"] == "rules"
    monkeypatch.setenv("VULTR_INFERENCE_API_KEY", "test-key")
    monkeypatch.setattr(
        "somnia.pipeline.describe_event",
        lambda **_kwargs: (
            "Likely a seizure-like pattern",
            "Vultr rewrote this line from the saved measurements. This is not a diagnosis.",
            "vultr",
        ),
    )
    rewritten = client.get("/api/v1/logs", headers=headers).json()["entries"][0]
    assert rewritten["source"] == "vultr"
    assert "Vultr rewrote" in rewritten["detail"]
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


def test_vultr_cutoff_estimates_stay_inside_the_demo(monkeypatch) -> None:
    from somnia.narrate import _parse_bars, clear_cache, compile_bars

    monkeypatch.delenv("VULTR_INFERENCE_API_KEY", raising=False)
    clear_cache()
    rules = compile_bars()
    assert rules.source == "rules"
    assert rules.motion_bar == 3.5
    assert rules.heart_rate_bar == 74.4
    assert "not a diagnosis" in rules.note.lower()
    wild = _parse_bars(
        '{"motion_m_s2": 9, "heart_rate_rise": 0.9, "hrv_ms": 2, "note": "wild"}',
        62,
    )
    assert wild is not None
    assert wild.source == "vultr"
    assert wild.motion_bar == 4.8
    assert wild.heart_rate_bar == round(62 * 1.45, 2)
    assert wild.hrv_bar == 18.0
    assert "estimate" in wild.note.lower()
    kept = _parse_bars(
        '{"motion_m_s2": 3.2, "heart_rate_rise": 0.25, "hrv_ms": 22, '
        '"note": "These are estimates from the study ranges. This is not a diagnosis."}',
        62,
    )
    assert kept is not None
    assert kept.motion_bar == 3.2
    assert kept.heart_rate_bar == round(62 * 1.25, 2)
    assert kept.note.startswith("These are estimates")
