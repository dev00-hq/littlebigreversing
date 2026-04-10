from __future__ import annotations

from scenes.base import StructuredSceneSpec
from scenes.scene11 import SCENE_SPEC as SCENE11_PAIR_SCENE_SPEC
from scenes.tavern import SCENE_SPEC as TAVERN_SCENE_SPEC


STRUCTURED_SCENE_SPECS: dict[str, StructuredSceneSpec] = {
    TAVERN_SCENE_SPEC.preset.name: TAVERN_SCENE_SPEC,
    SCENE11_PAIR_SCENE_SPEC.preset.name: SCENE11_PAIR_SCENE_SPEC,
}


def get_structured_scene_spec(mode: str) -> StructuredSceneSpec:
    try:
        return STRUCTURED_SCENE_SPECS[mode]
    except KeyError as exc:
        known = ", ".join(sorted(STRUCTURED_SCENE_SPECS))
        raise RuntimeError(f"unknown structured scene mode: {mode} (expected one of: {known})") from exc


def structured_scene_modes() -> tuple[str, ...]:
    return tuple(STRUCTURED_SCENE_SPECS)
