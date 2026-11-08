import json
import os
from dataclasses import dataclass

import urllib.request

from somnia.ml import BASELINE_HR
from somnia.signals import HR_RISE, MOTION_BAR

_cache: dict[tuple, tuple[str, str]] = {}
_bars: "NightBars | None" = None

_STUDY_NOTES = (
    "Sources for an estimate, not printed cutoffs. "
    "Cardiac seizure detection uses a heart-rate rise of about 20–70% from rest. "
    "Beniczky et al., Epilepsia 2013: a wrist accelerometer flags convulsive seizures when strong "
    "rhythmic movement continues, not one turn. A brief turn is near 2.3 m/s² and a sustained "
    "pattern is near 5.4 m/s². No paper prints a single m/s² line. "
    "Jeppesen et al., Epilepsia 2015: wearable RMSSD often falls during convulsive seizures. "
    "There is no published millisecond cutoff. Rest here is near 46–50 ms, and a seizure-like "
    "window is near 12–16 ms."
)


@dataclass(frozen=True)
class NightBars:
    motion_bar: float
    heart_rate_bar: float
    hrv_bar: float
    note: str
    source: str


_care: dict[tuple, str] = {}


def clear_cache() -> None:
    global _bars
    _cache.clear()
    _care.clear()
    _bars = None


def fallback_bars(baseline: float = BASELINE_HR) -> NightBars:
    return NightBars(
        motion_bar=MOTION_BAR,
        heart_rate_bar=round(baseline * (1 + HR_RISE), 2),
        hrv_bar=20.0,
        note=(
            "These lines are the service fallback. They are estimates, not a published cutoff. "
            "This is not a diagnosis."
        ),
        source="rules",
    )


def compile_bars(baseline: float = BASELINE_HR) -> NightBars:
    """Vultr compiles the study ranges into the lines the night uses. A bad reply keeps the fallback."""
    global _bars
    if _bars is not None and _bars.source == "vultr":
        return _bars
    fallback = fallback_bars(baseline)
    if not os.environ.get("VULTR_INFERENCE_API_KEY", "").strip():
        return fallback
    written = _complete_bars(baseline)
    if written is None:
        return fallback
    _bars = written
    return written


def _complete_bars(baseline: float) -> NightBars | None:
    system = (
        "Compile cutoff estimates for a night screen from the sources in the user message. "
        "The numbers are your estimates inside the stated ranges. They are not published cutoffs. "
        "Return JSON with keys motion_m_s2, heart_rate_rise, hrv_ms, note. "
        "motion_m_s2 is between a brief turn and sustained movement. "
        "heart_rate_rise is a fraction from 0.20 to 0.70. "
        "hrv_ms is an RMSSD below which variability looks reduced. "
        "note is one sentence with no digits. It must say these are estimates and include the exact words "
        '"This is not a diagnosis." Do not say seizure. seizure-like is allowed.'
    )
    prompt = f"Resting heart rate is {baseline:.0f} bpm. {_STUDY_NOTES}"
    for _ in range(2):
        content = _post_chat(prompt, system, 1000)
        if content is None:
            continue
        parsed = _parse_bars(content, baseline)
        if parsed is not None:
            return parsed
    return None


def _parse_bars(content: str, baseline: float) -> NightBars | None:
    data = _load_json(content)
    if not isinstance(data, dict):
        return None
    try:
        motion = float(data["motion_m_s2"])
        rise = float(data["heart_rate_rise"])
        hrv = float(data["hrv_ms"])
    except (KeyError, TypeError, ValueError):
        return None
    motion = min(4.8, max(2.8, motion))
    rise = min(0.45, max(0.20, rise))
    hrv = min(36.0, max(18.0, hrv))
    return NightBars(
        motion_bar=round(motion, 2),
        heart_rate_bar=round(baseline * (1 + rise), 2),
        hrv_bar=round(hrv, 1),
        note=_bar_note(str(data.get("note", ""))),
        source="vultr",
    )


def _bar_note(text: str) -> str:
    cleaned = " ".join(text.split())
    lowered = cleaned.lower()
    bare = lowered.replace("seizure-like", "")
    if (
        not cleaned
        or any(character.isdigit() for character in cleaned)
        or "seizure" in bare
        or "estimate" not in lowered
        or "not a diagnosis" not in lowered
    ):
        return (
            "Vultr compiled these lines from the study ranges. They are estimates, not a published cutoff. "
            "This is not a diagnosis."
        )
    return cleaned


def rule_lines(alarms: int, observations: int, has_week: bool) -> tuple[str, str]:
    if not has_week:
        return (
            "No anomaly has been saved yet.",
            "Run a test from Home. These counts update from the saved night.",
        )
    if alarms and observations:
        return (
            "Some anomalies combined stronger movement with a higher heart rate. Others were a heart-rate change without that movement.",
            "If you are safe, turn the alarm off. Note the usual hour and share that night with a clinician. This is not a diagnosis.",
        )
    if alarms:
        return (
            "The saved anomalies combined stronger movement with a higher heart rate than this patient’s usual night.",
            "If you are safe, turn the alarm off. A repeated hour like this is the detail worth reviewing with a clinician. This is not a diagnosis.",
        )
    return (
        "The saved anomalies were a higher heart rate without a strong movement pattern.",
        "That pattern is recorded as an observation, not an alarm. If it keeps showing up at the same hour, mention that hour to a clinician. This is not a diagnosis.",
    )


def phrase(
    *,
    alarms: int,
    observations: int,
    tonight: int,
    week: int,
    common_time: str | None,
    has_data: bool,
) -> tuple[str, str, str]:
    fallback = rule_lines(alarms, observations, has_data)
    key = os.environ.get("VULTR_INFERENCE_API_KEY", "").strip()
    if not has_data or not key:
        return (*fallback, "rules")
    cache_key = (tonight, week, common_time or "", alarms, observations)
    cached = _cache.get(cache_key)
    if cached is not None:
        return (*cached, "vultr")
    bars = compile_bars()
    written = _complete(
        "Tonight anomalies: {tonight}. Anomalies in the last 7 days: {week}. "
        "Most common hour: {hour}. Alarms with movement and a higher heart rate: {alarms}. "
        "Heart-rate observations without that movement: {observations}. "
        "These readings are synthetic demo data. Cutoff note, do not add numbers: {note}".format(
            tonight=tonight,
            week=week,
            hour=common_time or "unknown",
            alarms=alarms,
            observations=observations,
            note=bars.note,
        )
    )
    if written is None:
        return (*fallback, "rules")
    kept = _with_limit(written)
    _cache[cache_key] = kept
    return (*kept, "vultr")


def _with_limit(lines: tuple[str, str]) -> tuple[str, str]:
    cause, action = lines
    if "not a diagnosis" not in action.lower():
        action = action.rstrip()
        if action and not action.endswith("."):
            action += "."
        action = f"{action} This is not a diagnosis."
    return cause, action


def _complete(prompt: str) -> tuple[str, str] | None:
    system = (
        "Summarize only the counts in the user message for a prototype screen. "
        "The cutoff note was compiled from study ranges and is an estimate, not a published cutoff. "
        "Do not invent heart rates, times, medications, pain, anxiety, or care that was given. "
        "Do not say seizure. seizure-like is allowed. "
        'Return JSON with keys "cause" and "action". '
        "cause is one sentence about the pattern in those counts. "
        "action tells the person to turn the alarm off if they are safe, and must include the exact words "
        '"This is not a diagnosis."'
    )
    for _ in range(2):
        content = _post_chat(prompt, system, 1000)
        if content is None:
            continue
        parsed = _parse(content)
        if parsed is not None:
            return parsed
    return None


def _post_chat(prompt: str, system: str, max_tokens: int) -> str | None:
    key = os.environ.get("VULTR_INFERENCE_API_KEY", "").strip()
    if not key:
        return None
    model = os.environ.get("VULTR_INFERENCE_MODEL", "qwen3.8-flash-next")
    body = json.dumps(
        {
            "model": model,
            "temperature": 0.2,
            "max_tokens": max_tokens,
            "reasoning_effort": "minimal",
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt},
            ],
        }
    ).encode()
    request = urllib.request.Request(
        "https://api.vultrinference.com/v1/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.loads(response.read().decode())
        message = payload["choices"][0]["message"]
        content = str(message.get("content") or "").strip()
        if not content:
            reasoning = str(message.get("reasoning") or "")
            start, end = reasoning.find("{"), reasoning.rfind("}")
            content = reasoning[start : end + 1] if start >= 0 and end > start else ""
    except Exception as exc:
        status = getattr(exc, "code", "")
        print(f"vultr inference failed: {type(exc).__name__} {status}".rstrip())
        return None
    text = str(content).strip()
    return text or None


def _load_json(content: str) -> dict | None:
    text = content.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:].strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start < 0 or end <= start:
            return None
        try:
            data = json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            return None
    return data if isinstance(data, dict) else None


def _parse(content: str) -> tuple[str, str] | None:
    data = _load_json(content)
    if data is None:
        return None
    cause = str(data.get("cause", "")).strip()
    action = str(data.get("action", "")).strip()
    if not cause or not action or not _plain_summary(cause, action):
        return None
    return cause, action


LIKELY = {
    "seizure_like": "Likely a seizure-like pattern",
    "heart_rate": "Likely a heart-rate change",
    "turn": "Likely a turn in bed",
}
_KIND_ALIAS = {"alarm": "seizure_like", "observation": "heart_rate"}


def rule_log(kind: str) -> tuple[str, str]:
    kind = _KIND_ALIAS.get(kind, kind)
    if kind == "seizure_like":
        return (
            LIKELY["seizure_like"],
            "Heart rate rose and heart-rate variability fell while movement stayed strong. This is not a diagnosis.",
        )
    if kind == "turn":
        return (
            LIKELY["turn"],
            "Movement rose briefly. Heart rate and variability stayed near the resting pattern. This is not a diagnosis.",
        )
    return (
        LIKELY["heart_rate"],
        "Heart rate rose, variability dipped, and movement stayed quiet. This is not a diagnosis.",
    )


def describe_event(
    *,
    kind: str,
    score: float,
    heart_rate: float,
    motion_rms: float,
    hrv_rmssd: float = 0,
) -> tuple[str, str, str]:
    fallback = rule_log(kind)
    if not os.environ.get("VULTR_INFERENCE_API_KEY", "").strip():
        return (*fallback, "rules")
    written = _complete_log(
        f"Required likely label: {fallback[0]}. "
        f"Heart rate: {heart_rate:.0f} bpm. Heart-rate variability: {hrv_rmssd:.0f} ms RMSSD. "
        f"Motion: {motion_rms:.2f}. Peak anomaly score: {score:.2f}. Synthetic demo reading. "
        f"Cutoff note, do not add numbers: {compile_bars().note} "
        "The screen already shows those measurements. Do not include digits."
    )
    if written is None or written[0] != fallback[0]:
        return (*fallback, "rules")
    detail = written[1] if not any(character.isdigit() for character in written[1]) else fallback[1]
    return written[0], detail, "vultr"


def _complete_log(prompt: str) -> tuple[str, str] | None:
    allowed = ", ".join(LIKELY.values())
    system = (
        "Label one synthetic demo anomaly for a log. "
        f"The likely value must be exactly one of: {allowed}. "
        "Copy the required likely label with no extra period. "
        "detail is one sentence and must include the exact words "
        '"This is not a diagnosis." '
        "Do not name a disease, medicine, or dose. "
        "Do not say the pattern is a seizure. seizure-like is allowed only inside the required label. "
        "Put the JSON in the reply, not in private reasoning."
    )
    for _ in range(2):
        content = _post_chat(prompt, system, 1000)
        if content is None:
            continue
        parsed = _parse_log(content)
        if parsed is not None:
            return parsed
    return None


def _parse_log(content: str) -> tuple[str, str] | None:
    text = content.strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        start, end = text.find("{"), text.rfind("}")
        if start < 0 or end <= start:
            return None
        try:
            data = json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            return None
    likely = _canonical_likely(str(data.get("likely", "")))
    detail = str(data.get("detail", "")).strip()
    if likely is None or not detail:
        return None
    if "not a diagnosis" not in detail.lower():
        detail = detail.rstrip(".") + ". This is not a diagnosis."
    blob = detail.lower()
    if any(word in blob for word in ("diagnosed", "epilepsy", "medication", "prescribed", "dosage")):
        return None
    if "seizure" in blob and "seizure-like" not in blob:
        return None
    return likely, detail


def _canonical_likely(text: str) -> str | None:
    cleaned = text.strip().rstrip(".").strip()
    for label in LIKELY.values():
        if cleaned.casefold() == label.casefold():
            return label
    return None


def _plain_summary(cause: str, action: str) -> bool:
    blob = f"{cause} {action}".lower()
    banned = ("bpm", " mg", "pain", "administered", "medication", "anxiety", "tachycardia", "prescribed", "dosage")
    if any(word in blob for word in banned):
        return False
    return "seizure" not in blob.replace("seizure-like", "")


def caregiver_brief(
    *,
    waiting: bool,
    alarms: int,
    observations: int,
    common_time: str | None,
    likelies: tuple[str, ...],
) -> tuple[str, str]:
    """One sentence for the person nearby, compiled by Vultr from the saved night."""
    fallback = _caregiver_fallback(waiting, common_time)
    if not os.environ.get("VULTR_INFERENCE_API_KEY", "").strip():
        return fallback, "rules"
    cache_key = (waiting, alarms, observations, common_time or "", likelies)
    cached = _care.get(cache_key)
    if cached is not None:
        return cached, "vultr"
    written = _complete_sentence(
        "Waiting alarm: {waiting}. Alarms: {alarms}. Heart-rate observations: {observations}. "
        "Usual hour: {hour}. Log labels: {labels}. Cutoff note, do not add numbers: {note}".format(
            waiting="yes" if waiting else "no",
            alarms=alarms,
            observations=observations,
            hour=common_time or "unknown",
            labels=", ".join(likelies) if likelies else "none",
            note=compile_bars().note,
        ),
        (
            "Write one sentence a caregiver can read while watching a night of wearable readings. "
            "Use only the facts in the user message. "
            "If an alarm is waiting, tell them to check on the person and stay nearby. "
            "Do not invent care that was given, medications, or a time that was not provided. "
            "Do not say seizure. seizure-like is allowed. "
            'Return JSON with key "brief". '
            'brief must include the exact words "This is not a diagnosis."'
        ),
        "brief",
    )
    if written is None:
        return fallback, "rules"
    _care[cache_key] = written
    return written, "vultr"


def answer_caregiver(question: str, facts: str) -> tuple[str, str]:
    """Vultr answers one caregiver question from the saved night."""
    fallback = (
        "Use the plan on this screen: see whether an alarm is waiting, keep the usual hour, "
        "and stay with what the log already says. This is not a diagnosis."
    )
    if not os.environ.get("VULTR_INFERENCE_API_KEY", "").strip():
        return fallback, "rules"
    written = _complete_sentence(
        f"Night: {facts}\nQuestion: {question}",
        (
            "Answer one caregiver question using only the night in the user message. "
            "Two sentences at most. "
            "Do not invent medications, doses, care that was given, or measurements that were not provided. "
            "Do not say seizure. seizure-like is allowed. "
            'Return JSON with key "reply". '
            'reply must include the exact words "This is not a diagnosis."'
        ),
        "reply",
    )
    if written is None:
        return fallback, "rules"
    return written, "vultr"


def _caregiver_fallback(waiting: bool, common_time: str | None) -> str:
    hour = f" The usual hour is {common_time}." if common_time else ""
    if waiting:
        return (
            "An alarm is still waiting. Check on them and stay nearby until they say they are safe."
            f"{hour} This is not a diagnosis."
        )
    return f"No alarm is waiting. The saved night is here if you want to look back at it.{hour} This is not a diagnosis."


def _complete_sentence(prompt: str, system: str, key: str) -> str | None:
    for _ in range(2):
        content = _post_chat(prompt, system, 1000)
        if content is None:
            continue
        data = _load_json(content)
        if data is None:
            continue
        sentence = " ".join(str(data.get(key, "")).split())
        if not sentence or not _caregiver_sentence(sentence):
            continue
        if "not a diagnosis" not in sentence.lower():
            sentence = sentence.rstrip(".") + ". This is not a diagnosis."
        return sentence
    return None


def _caregiver_sentence(text: str) -> bool:
    blob = text.lower()
    banned = ("medication", "prescribed", "dosage", " mg", "pain", "administered", "diagnosed")
    if any(word in blob for word in banned):
        return False
    return "seizure" not in blob.replace("seizure-like", "")
