from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


class AuditFailure(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditFailure(message)


def read_json(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def image_size(path: str) -> tuple[int, int]:
    with Image.open(ROOT / path) as image:
        return image.size


def assert_16x9(path: str) -> None:
    width, height = image_size(path)
    require(width > 0 and height > 0, f"{path} has invalid image size")
    require(abs((width / height) - (16 / 9)) < 0.001, f"{path} is not 16:9: {width}x{height}")


def assert_sidecar_contains(path: str, expected: str) -> None:
    sidecar = ROOT / path
    require(sidecar.exists(), f"Missing sidecar {path}")
    text = sidecar.read_text(encoding="utf-8")
    require(expected in text, f"{path} does not mention {expected!r}")


def audit_data() -> list[str]:
    characters = read_json("data/characters.json")
    day_rules = read_json("data/day_rules.json")
    events = read_json("data/events.json")

    ids = {row["id"] for row in characters}
    require(len(characters) == 10, "Expected 10 characters including final-night duplicate")
    require("taki_fake" in ids, "Missing final-night taki_fake character")
    require(sorted(row["day"] for row in day_rules) == list(range(1, 10)), "Day rules must cover days 1-9")
    require(len(events.get("door_events", [])) >= 10, "Expected at least 10 door events")
    require(len(events.get("sleep_events", [])) >= 9, "Expected at least 9 sleep events")
    return [
        f"characters={len(characters)}",
        "day_rules=1-9",
        f"door_events={len(events['door_events'])}",
        f"sleep_events={len(events['sleep_events'])}",
    ]


def audit_assets() -> list[str]:
    backgrounds = [
        "assets/generated/bg_peephole_hallway_16x9.png",
        "assets/generated/bg_safe_room_clueboard_16x9.png",
    ]
    cgs = ["assets/generated/cg_another_rikki_hui_16x9.png"]
    characters = [
        "assets/generated/char_human_visitor_hui.png",
        "assets/generated/char_mimic_visitor_hui.png",
        "assets/generated/char_another_rikki_hui.png",
    ]
    for path in backgrounds + cgs + characters:
        require((ROOT / path).exists(), f"Missing asset {path}")
    for path in backgrounds + cgs:
        assert_16x9(path)
    for path in backgrounds:
        assert_sidecar_contains(path.replace(".png", ".asset-plan.json"), "txt2img")
    for path in characters:
        assert_sidecar_contains(path.replace(".png", ".asset-plan.json"), "hui-prompt-only-locked")
    assert_sidecar_contains("assets/generated/cg_another_rikki_hui_16x9.asset-plan.json", "hui-derived-16x9-adapter")
    return ["backgrounds=2@16:9", "characters=3@hui", "cg=1@hui-derived-16:9"]


def audit_godot() -> list[str]:
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    main = (ROOT / "scripts/Main.gd").read_text(encoding="utf-8")
    scene = (ROOT / "scenes/Main.tscn").read_text(encoding="utf-8")
    require('run/main_scene="res://scenes/Main.tscn"' in project, "Main scene is not configured")
    for token in [
        "BG_PEEPHOLE",
        "BG_ROOM",
        "BG_FINAL",
        "CHAR_HUMAN",
        "CHAR_MIMIC",
        "CHAR_RIKKI",
        "BACKEND_DIALOGUE_URL",
        "_ask_free_question",
        "_judge_final_ending",
        "_request_backend_dialogue",
    ]:
        require(token in main, f"Main.gd missing {token}")
    require('script = ExtResource("1_main")' in scene, "Main scene does not attach Main.gd")
    endings = re.findall(r'title = "([^"]*End[^"]*)"', main)
    require(len(endings) >= 7, "Expected multiple ending branches in Main.gd")
    return [f"ending_branches={len(endings)}", "backend_hook=yes"]


def audit_backend() -> list[str]:
    backend = (ROOT / "backend/main.py").read_text(encoding="utf-8")
    for token in ["FastAPI", "sqlite3", "DialogueRequest", "DialogueResponse", "/v1/dialogue", "LLM_API_KEY"]:
        require(token in backend, f"backend/main.py missing {token}")
    smoke = ROOT / "backend/smoke_test.py"
    require(smoke.exists(), "Missing backend smoke test")
    return ["fastapi=yes", "sqlite=yes", "llm_fallback=yes"]


def audit_release() -> list[str]:
    preset = ROOT / "export_presets.cfg"
    build = ROOT / "tools/build_release.ps1"
    require(preset.exists(), "Missing export_presets.cfg")
    require(build.exists(), "Missing tools/build_release.ps1")
    text = preset.read_text(encoding="utf-8")
    require('platform="Windows Desktop"' in text, "Missing Windows Desktop export preset")
    require("build/windows/猫眼之后.exe" in text, "Export path not configured")
    return ["windows_export_preset=yes", "release_script=yes"]


def main() -> int:
    checks = {
        "data": audit_data,
        "assets": audit_assets,
        "godot": audit_godot,
        "backend": audit_backend,
        "release": audit_release,
    }
    passed: list[str] = []
    try:
        for name, fn in checks.items():
            details = ", ".join(fn())
            passed.append(f"{name}: {details}")
    except AuditFailure as exc:
        print(f"AUDIT_FAIL {exc}", file=sys.stderr)
        return 1
    print("AUDIT_OK")
    for line in passed:
        print(f"- {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
