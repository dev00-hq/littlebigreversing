from __future__ import annotations

from typing import Final


FULL_TURN_BETA: Final[int] = 4096
HALF_TURN_BETA: Final[int] = FULL_TURN_BETA // 2

# Repo-local debug compass over classic beta.
# Axis convention:
#   0°   = +Z
#   90°  = +X
#   180° = -Z
#   270° = -X
HEADING_BETAS: Final[dict[str, int]] = {
    "N": 0,
    "NE": 512,
    "E": 1024,
    "SE": 1536,
    "S": 2048,
    "SW": 2560,
    "W": 3072,
    "NW": 3584,
}


def normalize_beta(beta: int) -> int:
    return int(beta) % FULL_TURN_BETA


def beta_to_degrees(beta: int) -> float:
    return normalize_beta(beta) * 360.0 / FULL_TURN_BETA


def degrees_to_beta(degrees: float) -> int:
    return int(round((float(degrees) % 360.0) * FULL_TURN_BETA / 360.0)) % FULL_TURN_BETA


def shortest_beta_delta(current_beta: int, target_beta: int) -> int:
    delta = (normalize_beta(target_beta) - normalize_beta(current_beta)) % FULL_TURN_BETA
    if delta > HALF_TURN_BETA:
        delta -= FULL_TURN_BETA
    return delta


def heading_to_beta(name: str) -> int:
    key = str(name).upper()
    if key not in HEADING_BETAS:
        raise KeyError(f"Unsupported heading name: {name}")
    return HEADING_BETAS[key]


def beta_to_heading(beta: int, headings: int = 8) -> str:
    normalized = normalize_beta(beta)
    if headings != 8:
        raise ValueError("Only 8-way heading labels are currently supported")
    best_name = "N"
    best_abs_delta = FULL_TURN_BETA + 1
    for name, target_beta in HEADING_BETAS.items():
        abs_delta = abs(shortest_beta_delta(normalized, target_beta))
        if abs_delta < best_abs_delta:
            best_name = name
            best_abs_delta = abs_delta
    return best_name


def describe_beta(beta: int, headings: int = 8) -> dict[str, object]:
    normalized = normalize_beta(beta)
    return {
        "beta": normalized,
        "degrees": beta_to_degrees(normalized),
        "heading": beta_to_heading(normalized, headings=headings),
    }
