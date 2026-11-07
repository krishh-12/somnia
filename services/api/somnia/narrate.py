import json
import os
import urllib.request

_cache: dict[tuple, tuple[str, str]] = {}


def clear_cache() -> None:
    _cache.clear()


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
    written = _complete(
        "Tonight anomalies: {tonight}. Anomalies in the last 7 days: {week}. "
        "Most common hour: {hour}. Alarms with movement and a higher heart rate: {alarms}. "
        "Heart-rate observations without that movement: {observations}. "
        "These readings are synthetic demo data.".format(
            tonight=tonight,
            week=week,
            hour=common_time or "unknown",
            alarms=alarms,
            observations=observations,
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
    key = os.environ.get("VULTR_INFERENCE_API_KEY", "").strip()
    if not key:
        return None
    model = os.environ.get("VULTR_INFERENCE_MODEL", "qwen3.8-flash-next")
    body = json.dumps(
        {
            "model": model,
            "temperature": 0.2,
            "max_tokens": 700,
            "reasoning_effort": "minimal",
            "response_format": {"type": "json_object"},
            "messages": [
                {
                    "role": "system",
            "content": (
                "Summarize only the counts in the user message for a prototype screen. "
                "Do not invent heart rates, times, medications, pain, anxiety, or care that was given. "
                "Do not say seizure. "
                'Return JSON with keys "cause" and "action". '
                "cause is one sentence about the pattern in those counts. "
                "action tells the person to turn the alarm off if they are safe, and must include the exact words "
                '"This is not a diagnosis."'
            ),
                },
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
        content = payload["choices"][0]["message"]["content"]
    except Exception:
        return None
    return _parse(content)


def _parse(content: str) -> tuple[str, str] | None:
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
    cause = str(data.get("cause", "")).strip()
    action = str(data.get("action", "")).strip()
    if not cause or not action or not _plain_summary(cause, action):
        return None
    return cause, action


def _plain_summary(cause: str, action: str) -> bool:
    blob = f"{cause} {action}".lower()
    banned = ("bpm", " mg", "pain", "administered", "medication", "anxiety", "tachycardia", "prescribed", "dosage", "seizure")
    return not any(word in blob for word in banned)
