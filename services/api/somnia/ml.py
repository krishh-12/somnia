import numpy as np
from sklearn.ensemble import IsolationForest

FEATURE_VERSION = "demo-1"
BASELINE_HR = 62.0
MODEL_SEED = 7


def feature_row(heart_rate: float, motion_rms: float, motion_var: float) -> list[float]:
    return [heart_rate, heart_rate - BASELINE_HR, motion_rms, motion_var]


def train_model() -> tuple[IsolationForest, float]:
    rng = np.random.default_rng(MODEL_SEED)
    rows = []
    for _ in range(240):
        heart_rate = float(rng.normal(BASELINE_HR, 2.4))
        motion_rms = float(abs(rng.normal(0.045, 0.015)))
        motion_var = float(abs(rng.normal(0.002, 0.0008)))
        rows.append(feature_row(heart_rate, motion_rms, motion_var))
    samples = np.array(rows)
    model = IsolationForest(
        n_estimators=80,
        contamination=0.04,
        random_state=MODEL_SEED,
    )
    model.fit(samples)
    scores = -model.decision_function(samples)
    threshold = float(np.quantile(scores, 0.99))
    return model, threshold


def anomaly_score(model: IsolationForest, heart_rate: float, motion_rms: float, motion_var: float) -> float:
    row = np.array([feature_row(heart_rate, motion_rms, motion_var)])
    return float(-model.decision_function(row)[0])
