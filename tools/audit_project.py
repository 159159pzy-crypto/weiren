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


def sidecar_json_for_asset(path: str) -> dict:
    sidecar = ROOT / path.replace(".png", ".asset-plan.json")
    require(sidecar.exists(), f"Missing sidecar {sidecar.relative_to(ROOT)}")
    return json.loads(sidecar.read_text(encoding="utf-8"))


def assert_no_loras(path: str) -> None:
    sidecar = sidecar_json_for_asset(path)
    loras = sidecar.get("loras", [])
    require(isinstance(loras, list), f"{path} sidecar loras must be a list")
    require(not loras, f"{path} must not use LoRA after character-LoRA rollback")


def assert_lora_weights_sane(path: str, max_weight: float = 0.55) -> None:
    sidecar = sidecar_json_for_asset(path)
    loras = sidecar.get("loras", [])
    require(isinstance(loras, list), f"{path} sidecar loras must be a list")
    for lora in loras:
        require(isinstance(lora, dict), f"{path} has malformed LoRA metadata")
        model_weight = abs(float(lora.get("weight", lora.get("strength_model", 0.0))))
        clip_weight = abs(float(lora.get("clip_weight", lora.get("strength_clip", model_weight))))
        require(model_weight <= max_weight, f"{path} LoRA model weight is too high: {model_weight}")
        require(clip_weight <= max_weight, f"{path} LoRA clip weight is too high: {clip_weight}")


def assert_hires_sane(path: str) -> None:
    sidecar = sidecar_json_for_asset(path)
    scale = float(sidecar.get("hires_scale", 1.0))
    hires_denoise = float(sidecar.get("hires_denoise", 0.0))
    steps = int(sidecar.get("hires_steps", 0))
    require(1.0 <= scale <= 1.75, f"{path} hires_scale is unsafe: {scale}")
    require(0.15 <= hires_denoise <= 0.45, f"{path} hires_denoise is unsafe: {hires_denoise}")
    require(1 <= steps <= 24, f"{path} hires_steps is unsafe: {steps}")


def assert_vae_sane(path: str) -> None:
    sidecar = sidecar_json_for_asset(path)
    vae = str(sidecar.get("vae", "checkpoint_default"))
    require(vae in {"", "checkpoint_default", "embedded", "model_default"}, f"{path} uses unexpected VAE: {vae}")
    text = json.dumps(sidecar, ensure_ascii=False).lower()
    for token in ["sd15_vae", "vae-ft-mse", "kl-f8", "external_vae", "vae_name"]:
        require(token not in text, f"{path} may reference a mismatched external VAE: {token}")


def assert_workflow_safety_sane(path: str) -> None:
    sidecar = sidecar_json_for_asset(path)
    workflow_safety = sidecar.get("workflow_safety", {})
    require(isinstance(workflow_safety, dict), f"{path} workflow_safety must be an object when present")
    active_loras = workflow_safety.get("active_loras", [])
    require(active_loras in (None, []), f"{path} workflow_safety reports active LoRA: {active_loras}")
    preprocessor_nodes = workflow_safety.get("controlnet_preprocessor_nodes", [])
    suspicious_nodes = workflow_safety.get("suspicious_preprocessor_nodes", [])
    require(preprocessor_nodes in (None, []), f"{path} workflow_safety reports ControlNet/preprocessor nodes: {preprocessor_nodes}")
    require(suspicious_nodes in (None, []), f"{path} workflow_safety reports suspicious preprocessor nodes: {suspicious_nodes}")
    vae_policy = str(workflow_safety.get("vae_policy", sidecar.get("vae", "checkpoint_default"))).lower()
    require(vae_policy in {"", "checkpoint_default", "embedded", "model_default", "checkpoint_default from source generation"}, f"{path} workflow_safety has unexpected VAE policy: {vae_policy}")

    # Derived CGs do not rerun Hires Fix; source txt2img assets must keep direct numeric params sane.
    hires_note = str(workflow_safety.get("hires_fix", "")).lower()
    if "not rerun" in hires_note:
        return
    if any(key in sidecar for key in ["hires_scale", "hires_denoise", "hires_steps"]):
        assert_hires_sane(path)


def assert_no_preprocessor_leaks() -> None:
    banned = ["controlnet", "preprocess", "preprocessor", "canny", "depth", "openpose", "lineart", "scribble", "softedge"]
    for path in (ROOT / "assets/generated").iterdir():
        lower_name = path.name.lower()
        require(not any(token in lower_name for token in banned), f"Preprocessor-looking generated file leaked: {path.name}")
        if path.suffix == ".json":
            text = path.read_text(encoding="utf-8").lower()
            require(not any(token in text for token in ["controlnetpreprocessor", "cannyedgepreprocessor", "dwpreprocessor", "openposepreprocessor"]), f"Preprocessor node leaked in {path.name}")


def assert_no_generated_orphans(allowed_stems: set[str]) -> None:
    for path in (ROOT / "assets/generated").iterdir():
        if path.suffix == ".txt":
            continue
        stem = path.name.replace(".asset-plan.json", "").replace(".png", "")
        require(stem in allowed_stems, f"Obsolete generated asset remains in final directory: {path.name}")


def assert_no_input_image_leaks(path: str) -> None:
    sidecar = sidecar_json_for_asset(path)
    for key in ["input_image", "mask_image", "comfyui_input_image", "comfyui_mask_image"]:
        value = sidecar.get(key)
        require(value in (None, ""), f"{path} sidecar still references {key}: {value}")


def audit_data() -> list[str]:
    characters = read_json("data/characters.json")
    day_rules = read_json("data/day_rules.json")
    events = read_json("data/events.json")
    release_config = read_json("data/release_config.json")

    ids = {row["id"] for row in characters}
    require(len(characters) == 10, "Expected 10 characters including final-night duplicate")
    require("taki_fake" in ids, "Missing final-night taki_fake character")
    require(sorted(row["day"] for row in day_rules) == list(range(1, 10)), "Day rules must cover days 1-9")
    door_event_ids = {event.get("id", "") for event in events.get("door_events", [])}
    require(len(events.get("door_events", [])) >= 13, "Expected at least 13 door events")
    for event_id in ["visitor_asks_someone", "visitor_childlike", "mistaken_chased"]:
        require(event_id in door_event_ids, f"Missing expanded door event {event_id}")
    require(len(events.get("sleep_events", [])) >= 9, "Expected at least 9 sleep events")
    require("同人" in release_config.get("disclaimer", ""), "Release config must include fan disclaimer")
    require("LLM_API_KEY" in release_config.get("llm", {}).get("required_when_enabled", []), "Release config must document LLM_API_KEY")
    require(len(release_config.get("release_checks", [])) >= 6, "Release config must list release checks")
    require(any("BalanceAudit.gd" in check for check in release_config.get("release_checks", [])), "Release config must include balance audit")
    return [
        f"characters={len(characters)}",
        "day_rules=1-9",
        f"door_events={len(events['door_events'])}",
        f"sleep_events={len(events['sleep_events'])}",
        "release_config=yes",
    ]


def audit_assets() -> list[str]:
    cg_manifest = read_json("data/cg_manifest.json")
    cg_entries = cg_manifest.get("entries", [])
    require(len(cg_entries) >= 39, "Expected at least 39 CG manifest entries")
    cg_assets = [entry["asset"] for entry in cg_entries]
    roles = {entry.get("role", "") for entry in cg_entries}
    triggers = {entry.get("trigger", "") for entry in cg_entries}
    require("sleep" in roles and "ending" in roles and "door_event" in roles and "inspection" in roles, "CG manifest must cover sleep, endings, door events, and inspections")
    for trigger in ["sleep_living_noise", "sleep_kitchen_water", "sleep_clueboard", "sleep_tv_on", "sleep_door_unlock", "sleep_crying", "sleep_bedside", "sleep_mirror_delay", "sleep_window_tap"]:
        require(trigger in triggers, f"CG manifest missing sleep trigger {trigger}")
    for trigger in ["true", "good", "neutral", "no_one", "perfect_band", "purple", "identity", "door", "hidden", "distortion"]:
        require(trigger in triggers, f"CG manifest missing ending trigger {trigger}")
    for trigger in ["visitor_calm", "visitor_panic", "visitor_chased", "visitor_injured", "visitor_supplies", "visitor_knows_inside", "visitor_wrong_code", "visitor_duplicate", "visitor_silent", "visitor_fake_radio", "visitor_asks_someone", "visitor_childlike", "mistaken_chased"]:
        require(trigger in triggers, f"CG manifest missing door event trigger {trigger}")
    for trigger in ["teeth", "iris", "finger", "breath_shadow", "footprint", "environment", "room_search"]:
        require(trigger in triggers, f"CG manifest missing inspection trigger {trigger}")
    backgrounds = [
        "assets/generated/bg_peephole_hallway_16x9.png",
        "assets/generated/bg_safe_room_clueboard_16x9.png",
    ]
    environment_backgrounds = [
        "assets/generated/bg_title_night_16x9.png",
        "assets/generated/bg_prep_clueboard_16x9.png",
        "assets/generated/bg_investigation_room_16x9.png",
        "assets/generated/bg_quarantine_glass_16x9.png",
        "assets/generated/bg_sleep_locked_room_16x9.png",
        "assets/generated/bg_dawn_settlement_16x9.png",
        "assets/generated/bg_contamination_room_16x9.png",
        "assets/generated/bg_final_judgment_16x9.png",
    ]
    effect_overlays = [
        "assets/generated/fx_contamination_overlay.png",
        "assets/generated/fx_door_damage_overlay.png",
        "assets/generated/fx_outside_danger_overlay.png",
        "assets/generated/fx_trust_break_overlay.png",
        "assets/generated/fx_evidence_noise_overlay.png",
        "assets/generated/fx_mimic_learning_overlay.png",
    ]
    ui_icons = [
        "assets/generated/ui_icon_stamina.png",
        "assets/generated/ui_icon_contamination.png",
        "assets/generated/ui_icon_door.png",
        "assets/generated/ui_icon_quarantine.png",
        "assets/generated/ui_icon_supplies.png",
        "assets/generated/ui_icon_trust.png",
        "assets/generated/ui_icon_danger.png",
        "assets/generated/ui_icon_evidence.png",
    ]
    cgs = cg_assets
    character_roles = ["human", "fake", "mimic", "rikki"]
    character_variants = ["base", "calm", "stress", "doubt"]
    characters = [
        f"assets/generated/char_{role}_{variant}.png"
        for role in character_roles
        for variant in character_variants
    ]
    source_assets = ["assets/generated/another_rikki_final.png"]
    allowed_stems = {
        "another_rikki_final",
        "bg_peephole_hallway_16x9",
        "bg_safe_room_clueboard_16x9",
        "char_human_base",
        "char_fake_base",
        "char_mimic_base",
        "char_rikki_base",
    }
    allowed_stems.update(Path(path).stem for path in characters)
    allowed_stems.update(Path(path).stem for path in environment_backgrounds)
    allowed_stems.update(Path(path).stem for path in effect_overlays)
    allowed_stems.update(Path(path).stem for path in ui_icons)
    allowed_stems.update(Path(path).stem for path in cgs)
    assert_no_preprocessor_leaks()
    assert_no_generated_orphans(allowed_stems)
    for path in backgrounds + environment_backgrounds + effect_overlays + ui_icons + cgs + characters + source_assets:
        require((ROOT / path).exists(), f"Missing asset {path}")
    for path in backgrounds + environment_backgrounds + effect_overlays + cgs:
        assert_16x9(path)
    for path in backgrounds:
        assert_sidecar_contains(path.replace(".png", ".asset-plan.json"), "txt2img")
    for path in backgrounds + environment_backgrounds + effect_overlays + ui_icons + cgs + characters + source_assets:
        assert_no_loras(path)
        assert_lora_weights_sane(path)
        assert_vae_sane(path)
        assert_workflow_safety_sane(path)
        assert_no_input_image_leaks(path)
    for path in characters + backgrounds + source_assets:
        assert_hires_sane(path)
    assert_sidecar_contains("assets/generated/cg_another_rikki_hui_16x9.asset-plan.json", "hui-derived-16x9-adapter")
    variant_script = ROOT / "tools/make_character_variants.py"
    require(variant_script.exists(), "Missing tools/make_character_variants.py")
    environment_script = ROOT / "tools/make_environment_variants.py"
    require(environment_script.exists(), "Missing tools/make_environment_variants.py")
    effect_script = ROOT / "tools/make_effect_overlays.py"
    require(effect_script.exists(), "Missing tools/make_effect_overlays.py")
    icon_script = ROOT / "tools/make_ui_icons.py"
    require(icon_script.exists(), "Missing tools/make_ui_icons.py")
    for path in ui_icons:
        require(image_size(path) == (128, 128), f"{path} must be 128x128")
    return ["backgrounds=2@16:9", f"environment_bg={len(environment_backgrounds)}@16:9", f"effects={len(effect_overlays)}@16:9", f"ui_icons={len(ui_icons)}", f"characters={len(characters)}@no-lora", f"cg={len(cgs)}@no-lora-16:9", "door_event_cg=13", "inspection_cg=7", "preprocessor_leaks=none", "vae=checkpoint_default"]


def audit_godot() -> list[str]:
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    main = (ROOT / "scripts/Main.gd").read_text(encoding="utf-8")
    scene = (ROOT / "scenes/Main.tscn").read_text(encoding="utf-8")
    balance = ROOT / "scripts/BalanceAudit.gd"
    require(balance.exists(), "Missing scripts/BalanceAudit.gd")
    balance_text = balance.read_text(encoding="utf-8")
    for token in ["BALANCE_AUDIT_OK", "balance-truth", "balance-refuse", "balance-chaos", "_assert_truth_route", "_assert_refuse_route", "_assert_chaos_route"]:
        require(token in balance_text, f"BalanceAudit.gd missing {token}")
    require('run/main_scene="res://scenes/Main.tscn"' in project, "Main scene is not configured")
    for token in [
        "BG_PEEPHOLE",
        "BG_ROOM",
        "BG_FINAL",
        "CHAR_HUMAN",
        "CHAR_FAKE",
        "CHAR_MIMIC",
        "CHAR_RIKKI",
        "RELEASE_CONFIG_PATH",
        "_show_release_notes",
        "SLEEP_CG",
        "DOOR_EVENT_CG",
        "ENDING_CG",
        "BACKEND_DIALOGUE_URL",
        "_prep_assign_rooms",
        "_prep_set_code",
        "_prep_select_detector",
        "_prep_distribute_supplies",
        "entering_new_day",
        "_prep_accept_self_check",
        "_prep_refuse_self_check",
        "_apply_self_suspicion_pressure",
        "_refresh_gun_charges",
        "_prep_calibrate_gun",
        "_apply_rule_distortion_pressure",
        "_record_missing_identity",
        "_pick_stolen_identity",
        "_steal_random_inside_identity",
        "_initialize_relationships",
        "_adjust_character_relation",
        "_apply_relationship_pressure",
        "_relationship_summary",
        "_indoor_free_talk",
        "_indoor_memory_check",
        "_indoor_face_check",
        "_indoor_trace_check",
        "_indoor_breath_shadow_check",
        "_investigate_room",
        "_cross_question",
        "_advance_chase",
        "_resolve_chase_timeout",
        "_ask_free_question",
        "_judge_final_ending",
        "_request_backend_dialogue",
    ]:
        require(token in main, f"Main.gd missing {token}")
    for token in ["bg_title_night_16x9.png", "bg_prep_clueboard_16x9.png", "bg_quarantine_glass_16x9.png", "bg_dawn_settlement_16x9.png", "fx_contamination_overlay.png", "fx_door_damage_overlay.png", "fx_outside_danger_overlay.png", "fx_trust_break_overlay.png", "fx_evidence_noise_overlay.png", "fx_mimic_learning_overlay.png", "ui_icon_stamina.png", "ui_icon_contamination.png", "ui_icon_door.png", "ui_icon_quarantine.png", "ui_icon_supplies.png", "ui_icon_trust.png", "ui_icon_danger.png", "ui_icon_evidence.png", "char_human_stress.png", "char_fake_doubt.png", "char_mimic_doubt.png", "char_rikki_stress.png", "cg_sleep_living_noise_16x9.png", "cg_sleep_mirror_delay_16x9.png", "cg_door_calm_16x9.png", "cg_door_panic_16x9.png", "cg_door_injured_16x9.png", "cg_door_knows_inside_16x9.png", "cg_door_wrong_code_16x9.png", "cg_door_silent_16x9.png", "cg_door_fake_radio_16x9.png", "cg_door_chased_16x9.png", "cg_door_duplicate_16x9.png", "cg_door_asks_someone_16x9.png", "cg_door_childlike_16x9.png", "cg_door_mistaken_chased_16x9.png", "cg_inspect_teeth_16x9.png", "cg_inspect_room_search_16x9.png", "cg_ending_true_16x9.png", "cg_ending_distortion_16x9.png"]:
        require(token in main, f"Main.gd missing CG mapping {token}")
    for stale in ["char_human_visitor_hui.png", "char_mimic_visitor_hui.png", "char_another_rikki_hui.png"]:
        require(stale not in main, f"Main.gd still references old character asset {stale}")
    for label in ["分配房间", "设定今日暗号", "选择重点检测设备", "分配物资"]:
        require(label in main, f"Main.gd missing prep action {label}")
    for label in ["接受屋内自检", "拒绝自检并继续指挥"]:
        require(label in main, f"Main.gd missing self suspicion action {label}")
    for token in ["gun_charges", "校准驱逐装置", "驱逐充能", "清除权"]:
        require(token in main, f"Main.gd missing gun faction token {token}")
    for token in ["rule_distortion", "final_judgment", "规则失真", "最终审判"]:
        require(token in main, f"Main.gd missing final-night distortion token {token}")
    for label in ["从门缝观察", "拿手电筒查看", "锁门继续睡"]:
        require(label in main, f"Main.gd missing sleep action {label}")
    for label in ["室内自由对话", "共同记忆盘问", "屋内牙齿/虹膜检查", "屋内指泥/足迹检测", "屋内呼吸/影子观察", "搜查房间", "交叉质问屋内成员"]:
        require(label in main, f"Main.gd missing indoor investigation action {label}")
    for token in ["room_searches_left", "cross_questions_left", "交叉证词", "线索污染"]:
        require(token in main, f"Main.gd missing expanded indoor investigation token {token}")
    for token in ["character_trust", "character_stress", "guarded_id", "屋内关系", "黎明关系结算"]:
        require(token in main, f"Main.gd missing relationship system token {token}")
    for token in ["visitor_asks_someone", "visitor_childlike", "mistaken_chased", "关系矛盾", "误判追赶", "反常依赖"]:
        require(token in main, f"Main.gd missing expanded door event token {token}")
    for token in ["正式版说明", "同人免责声明", "LLM / API Key", "发布前检查"]:
        require(token in main, f"Main.gd missing release note token {token}")
    for token in ["chase_timer", "chase_resolved", "追赶余裕", "追赶超时"]:
        require(token in main, f"Main.gd missing chase event token {token}")
    for token in ["missing_ids", "stolen_ids", "inside_human_ids", "身份被盗回归预警", "可盗用外形"]:
        require(token in main, f"Main.gd missing identity theft token {token}")
    for state_key in ["code_phrase", "detector_focus", "rooms_assigned", "supplies_distributed", "self_suspicion"]:
        require(state_key in main, f"Main.gd missing prep state {state_key}")
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
    env_example = ROOT / ".env.example"
    require(env_example.exists(), "Missing .env.example")
    env_text = env_example.read_text(encoding="utf-8")
    for token in ["LLM_API_KEY", "LLM_BASE_URL", "LLM_MODEL"]:
        require(token in env_text, f".env.example missing {token}")
    return ["fastapi=yes", "sqlite=yes", "llm_fallback=yes", "env_example=yes"]


def audit_release() -> list[str]:
    preset = ROOT / "export_presets.cfg"
    build = ROOT / "tools/build_release.ps1"
    require(preset.exists(), "Missing export_presets.cfg")
    require(build.exists(), "Missing tools/build_release.ps1")
    text = preset.read_text(encoding="utf-8")
    build_text = build.read_text(encoding="utf-8")
    require('platform="Windows Desktop"' in text, "Missing Windows Desktop export preset")
    require("build/windows/猫眼之后.exe" in text, "Export path not configured")
    require("BalanceAudit.gd" in build_text, "Release script must run BalanceAudit.gd")
    return ["windows_export_preset=yes", "release_script=yes", "balance_audit=yes"]


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
