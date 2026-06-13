from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated"
MANIFEST = ROOT / "data" / "cg_manifest.json"
SIZE = (1920, 1080)


def load_image(path: str) -> Image.Image:
    image = Image.open(ROOT / path).convert("RGB")
    if image.size != SIZE:
        image = image.resize(SIZE, Image.Resampling.LANCZOS)
    return image


def vignette(image: Image.Image, strength: float) -> Image.Image:
    overlay = Image.new("L", SIZE, 0)
    draw = ImageDraw.Draw(overlay)
    limit = min(SIZE) // 2 - 8
    for i in range(0, limit, 8):
        value = int(255 * (i / max(1, limit)) ** 1.8 * strength)
        draw.rectangle((i, i, SIZE[0] - i, SIZE[1] - i), outline=value, width=8)
    mask = Image.eval(overlay.filter(ImageFilter.GaussianBlur(44)), lambda p: 255 - p)
    dark = Image.new("RGB", SIZE, (4, 6, 8))
    return Image.composite(dark, image, mask)


def color_grade(image: Image.Image, tint: tuple[int, int, int], alpha: int, contrast: float, brightness: float) -> Image.Image:
    graded = ImageEnhance.Contrast(image).enhance(contrast)
    graded = ImageEnhance.Brightness(graded).enhance(brightness)
    overlay = Image.new("RGB", SIZE, tint)
    return Image.blend(graded, overlay, alpha / 255.0)


def add_light(image: Image.Image, position: tuple[int, int], radius: int, color: tuple[int, int, int], alpha: int) -> Image.Image:
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x, y = position
    for r in range(radius, 0, -18):
        a = int(alpha * (r / radius) ** 2)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=(*color, a))
    return Image.alpha_composite(image.convert("RGBA"), layer.filter(ImageFilter.GaussianBlur(18))).convert("RGB")


def add_shadow_figure(image: Image.Image, x: int, y: int, scale: float, alpha: int) -> Image.Image:
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    w = int(120 * scale)
    h = int(360 * scale)
    draw.ellipse((x - w // 3, y - h, x + w // 3, y - h + int(92 * scale)), fill=(0, 0, 0, alpha))
    draw.rounded_rectangle((x - w // 2, y - h + int(70 * scale), x + w // 2, y), radius=int(42 * scale), fill=(0, 0, 0, alpha))
    draw.polygon([(x - w // 2, y - h + int(160 * scale)), (x - int(210 * scale), y - int(20 * scale)), (x - int(170 * scale), y + int(18 * scale)), (x - int(25 * scale), y - int(130 * scale))], fill=(0, 0, 0, int(alpha * 0.62)))
    draw.polygon([(x + w // 2, y - h + int(160 * scale)), (x + int(210 * scale), y - int(20 * scale)), (x + int(170 * scale), y + int(18 * scale)), (x + int(25 * scale), y - int(130 * scale))], fill=(0, 0, 0, int(alpha * 0.62)))
    return Image.alpha_composite(image.convert("RGBA"), layer.filter(ImageFilter.GaussianBlur(5))).convert("RGB")


def add_inspection_marks(image: Image.Image, kind: str) -> Image.Image:
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cyan = (125, 255, 230, 170)
    red = (255, 86, 86, 150)
    amber = (255, 196, 92, 145)
    if kind == "teeth":
        draw.rounded_rectangle((690, 390, 1230, 640), radius=52, outline=cyan, width=8)
        for x in range(745, 1190, 68):
            draw.line((x, 420, x + 22, 610), fill=red if x in (881, 1085) else amber, width=5)
    elif kind == "iris":
        draw.ellipse((720, 330, 1200, 810), outline=cyan, width=9)
        draw.ellipse((870, 480, 1050, 660), outline=red, width=8)
        draw.arc((655, 265, 1265, 875), 18, 342, fill=amber, width=5)
    elif kind == "finger":
        for offset in range(0, 280, 54):
            draw.arc((770 + offset, 430, 970 + offset, 690), 98, 274, fill=cyan, width=7)
        draw.line((710, 760, 1220, 650), fill=red, width=6)
    elif kind == "breath_shadow":
        for radius in range(120, 430, 70):
            draw.ellipse((960 - radius, 540 - radius // 2, 960 + radius, 540 + radius // 2), outline=cyan, width=5)
        draw.polygon([(1260, 220), (1490, 940), (1180, 940)], fill=(0, 0, 0, 118))
        draw.line((1260, 220, 1490, 940), fill=red, width=6)
    elif kind == "footprint":
        for x, y in [(720, 640), (910, 560), (1100, 680), (1280, 590)]:
            draw.ellipse((x - 45, y - 88, x + 45, y + 88), outline=cyan, width=7)
            draw.ellipse((x - 12, y - 132, x + 22, y - 102), fill=red)
    elif kind == "environment":
        points = [(520, 720), (760, 520), (1040, 610), (1330, 390), (1510, 560)]
        draw.line(points, fill=cyan, width=8)
        for x, y in points:
            draw.ellipse((x - 22, y - 22, x + 22, y + 22), fill=amber)
        draw.rectangle((650, 295, 1260, 770), outline=red, width=6)
    elif kind == "room_search":
        draw.rectangle((420, 330, 1500, 820), outline=cyan, width=8)
        draw.line((420, 330, 1500, 820), fill=red, width=5)
        draw.line((420, 820, 1500, 330), fill=red, width=5)
        for x, y in [(610, 450), (930, 610), (1230, 510), (1410, 730)]:
            draw.ellipse((x - 38, y - 38, x + 38, y + 38), outline=amber, width=6)
    return Image.alpha_composite(image.convert("RGBA"), layer.filter(ImageFilter.GaussianBlur(0.6))).convert("RGB")


def make_variant(source: Image.Image, spec: dict) -> Image.Image:
    image = source.copy()
    if spec.get("blur", 0):
        image = image.filter(ImageFilter.GaussianBlur(float(spec["blur"])))
    image = color_grade(image, tuple(spec["tint"]), int(spec["alpha"]), float(spec["contrast"]), float(spec["brightness"]))
    for light in spec.get("lights", []):
        image = add_light(image, tuple(light["position"]), int(light["radius"]), tuple(light["color"]), int(light["alpha"]))
    if spec.get("shadow"):
        shadow = spec["shadow"]
        image = add_shadow_figure(image, int(shadow["x"]), int(shadow["y"]), float(shadow["scale"]), int(shadow["alpha"]))
    if spec.get("inspection"):
        image = add_inspection_marks(image, str(spec["inspection"]))
    image = vignette(image, float(spec.get("vignette", 0.74)))
    return image


def write_sidecar(path: Path, source: str, spec: dict) -> None:
    path.with_suffix(".asset-plan.json").write_text(
        json.dumps(
            {
                "mode": "derived-16x9-cg-variant",
                "source": source,
                "output": str(path.relative_to(ROOT)),
                "size": list(SIZE),
                "loras": [],
                "vae": "checkpoint_default",
                "input_image": None,
                "mask_image": None,
                "comfyui_input_image": None,
                "comfyui_mask_image": None,
                "workflow_safety": {
                    "controlnet_preprocessor_nodes": [],
                    "lora_policy": "no final CG LoRA; derived from audited project assets",
                    "hires_fix": "not rerun here; this adapter color-grades and composites existing 16:9 assets",
                    "vae_policy": "checkpoint_default from source generation",
                },
                "variant": spec["id"],
                "role": spec["role"],
                "trigger": spec["trigger"],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


def main() -> None:
    sources = {
        "hallway": "assets/generated/bg_peephole_hallway_16x9.png",
        "room": "assets/generated/bg_safe_room_clueboard_16x9.png",
        "final": "assets/generated/cg_another_rikki_hui_16x9.png",
    }
    loaded = {key: load_image(path) for key, path in sources.items()}
    specs = [
        {"id": "cg_sleep_living_noise_16x9", "role": "sleep", "trigger": "sleep_living_noise", "source": "room", "tint": (24, 58, 62), "alpha": 54, "contrast": 1.2, "brightness": 0.72, "blur": 1.0, "shadow": {"x": 1340, "y": 900, "scale": 0.9, "alpha": 92}, "lights": [{"position": [520, 290], "radius": 360, "color": [90, 230, 210], "alpha": 58}]},
        {"id": "cg_sleep_kitchen_water_16x9", "role": "sleep", "trigger": "sleep_kitchen_water", "source": "room", "tint": (22, 76, 96), "alpha": 70, "contrast": 1.12, "brightness": 0.68, "blur": 1.4, "lights": [{"position": [1460, 330], "radius": 420, "color": [80, 170, 255], "alpha": 66}]},
        {"id": "cg_sleep_clueboard_16x9", "role": "sleep", "trigger": "sleep_clueboard", "source": "room", "tint": (82, 42, 88), "alpha": 52, "contrast": 1.35, "brightness": 0.78, "blur": 0.6, "lights": [{"position": [930, 410], "radius": 460, "color": [255, 100, 130], "alpha": 72}]},
        {"id": "cg_sleep_tv_on_16x9", "role": "sleep", "trigger": "sleep_tv_on", "source": "room", "tint": (20, 95, 82), "alpha": 80, "contrast": 1.42, "brightness": 0.72, "blur": 0.8, "lights": [{"position": [1120, 360], "radius": 540, "color": [120, 255, 225], "alpha": 100}]},
        {"id": "cg_sleep_door_unlock_16x9", "role": "sleep", "trigger": "sleep_door_unlock", "source": "hallway", "tint": (86, 28, 34), "alpha": 76, "contrast": 1.28, "brightness": 0.64, "blur": 0.7, "lights": [{"position": [960, 540], "radius": 360, "color": [255, 65, 60], "alpha": 78}]},
        {"id": "cg_sleep_crying_16x9", "role": "sleep", "trigger": "sleep_crying", "source": "room", "tint": (42, 42, 95), "alpha": 70, "contrast": 1.08, "brightness": 0.62, "blur": 1.8, "shadow": {"x": 520, "y": 930, "scale": 0.72, "alpha": 82}},
        {"id": "cg_sleep_bedside_16x9", "role": "sleep", "trigger": "sleep_bedside", "source": "room", "tint": (18, 18, 28), "alpha": 92, "contrast": 1.3, "brightness": 0.55, "blur": 0.9, "shadow": {"x": 1060, "y": 980, "scale": 1.1, "alpha": 150}, "lights": [{"position": [610, 260], "radius": 300, "color": [210, 230, 255], "alpha": 42}]},
        {"id": "cg_sleep_mirror_delay_16x9", "role": "sleep", "trigger": "sleep_mirror_delay", "source": "room", "tint": (78, 36, 98), "alpha": 78, "contrast": 1.22, "brightness": 0.7, "blur": 1.2, "lights": [{"position": [1250, 400], "radius": 520, "color": [175, 80, 255], "alpha": 86}]},
        {"id": "cg_sleep_window_tap_16x9", "role": "sleep", "trigger": "sleep_window_tap", "source": "hallway", "tint": (18, 54, 78), "alpha": 76, "contrast": 1.15, "brightness": 0.66, "blur": 1.0, "lights": [{"position": [1430, 230], "radius": 430, "color": [80, 180, 255], "alpha": 72}]},
        {"id": "cg_door_calm_16x9", "role": "door_event", "trigger": "visitor_calm", "source": "hallway", "tint": (46, 74, 68), "alpha": 46, "contrast": 1.08, "brightness": 0.82, "blur": 0.35, "lights": [{"position": [940, 430], "radius": 540, "color": [150, 255, 225], "alpha": 54}]},
        {"id": "cg_door_panic_16x9", "role": "door_event", "trigger": "visitor_panic", "source": "hallway", "tint": (94, 34, 42), "alpha": 72, "contrast": 1.46, "brightness": 0.62, "blur": 0.9, "shadow": {"x": 1010, "y": 910, "scale": 0.72, "alpha": 84}, "lights": [{"position": [760, 470], "radius": 410, "color": [255, 84, 72], "alpha": 86}]},
        {"id": "cg_door_chased_16x9", "role": "door_event", "trigger": "visitor_chased", "source": "hallway", "tint": (80, 25, 25), "alpha": 74, "contrast": 1.32, "brightness": 0.68, "blur": 0.5, "shadow": {"x": 1460, "y": 900, "scale": 0.88, "alpha": 110}},
        {"id": "cg_door_injured_16x9", "role": "door_event", "trigger": "visitor_injured", "source": "hallway", "tint": (95, 48, 42), "alpha": 62, "contrast": 1.26, "brightness": 0.68, "blur": 0.7, "shadow": {"x": 820, "y": 930, "scale": 0.64, "alpha": 78}, "lights": [{"position": [1020, 760], "radius": 310, "color": [255, 126, 100], "alpha": 70}]},
        {"id": "cg_door_duplicate_16x9", "role": "door_event", "trigger": "visitor_duplicate", "source": "hallway", "tint": (44, 82, 68), "alpha": 68, "contrast": 1.25, "brightness": 0.7, "blur": 0.8, "shadow": {"x": 760, "y": 900, "scale": 0.75, "alpha": 88}},
        {"id": "cg_door_supplies_16x9", "role": "door_event", "trigger": "visitor_supplies", "source": "hallway", "tint": (92, 76, 28), "alpha": 54, "contrast": 1.15, "brightness": 0.76, "blur": 0.6, "lights": [{"position": [1040, 720], "radius": 260, "color": [255, 220, 120], "alpha": 78}]},
        {"id": "cg_door_knows_inside_16x9", "role": "door_event", "trigger": "visitor_knows_inside", "source": "hallway", "tint": (38, 92, 86), "alpha": 76, "contrast": 1.34, "brightness": 0.66, "blur": 0.6, "shadow": {"x": 1160, "y": 910, "scale": 0.84, "alpha": 96}, "lights": [{"position": [610, 340], "radius": 360, "color": [80, 255, 220], "alpha": 74}]},
        {"id": "cg_door_wrong_code_16x9", "role": "door_event", "trigger": "visitor_wrong_code", "source": "hallway", "tint": (86, 70, 34), "alpha": 66, "contrast": 1.38, "brightness": 0.7, "blur": 0.55, "lights": [{"position": [980, 520], "radius": 380, "color": [255, 208, 82], "alpha": 82}, {"position": [1380, 260], "radius": 260, "color": [255, 70, 70], "alpha": 48}]},
        {"id": "cg_door_silent_16x9", "role": "door_event", "trigger": "visitor_silent", "source": "hallway", "tint": (26, 44, 48), "alpha": 84, "contrast": 1.18, "brightness": 0.56, "blur": 1.0, "shadow": {"x": 960, "y": 960, "scale": 0.78, "alpha": 138}},
        {"id": "cg_door_fake_radio_16x9", "role": "door_event", "trigger": "visitor_fake_radio", "source": "hallway", "tint": (40, 98, 86), "alpha": 80, "contrast": 1.54, "brightness": 0.7, "blur": 1.2, "lights": [{"position": [1080, 380], "radius": 520, "color": [95, 255, 210], "alpha": 114}, {"position": [620, 760], "radius": 260, "color": [255, 80, 90], "alpha": 54}]},
        {"id": "cg_door_asks_someone_16x9", "role": "door_event", "trigger": "visitor_asks_someone", "source": "hallway", "tint": (58, 36, 88), "alpha": 76, "contrast": 1.28, "brightness": 0.66, "blur": 0.7, "shadow": {"x": 1020, "y": 910, "scale": 0.82, "alpha": 104}, "lights": [{"position": [700, 360], "radius": 360, "color": [180, 90, 255], "alpha": 70}]},
        {"id": "cg_door_childlike_16x9", "role": "door_event", "trigger": "visitor_childlike", "source": "hallway", "tint": (96, 46, 82), "alpha": 72, "contrast": 1.22, "brightness": 0.7, "blur": 1.0, "lights": [{"position": [1120, 660], "radius": 320, "color": [255, 120, 190], "alpha": 76}]},
        {"id": "cg_door_mistaken_chased_16x9", "role": "door_event", "trigger": "mistaken_chased", "source": "hallway", "tint": (34, 70, 82), "alpha": 68, "contrast": 1.18, "brightness": 0.68, "blur": 1.1, "shadow": {"x": 1510, "y": 930, "scale": 0.58, "alpha": 68}, "lights": [{"position": [960, 420], "radius": 380, "color": [110, 210, 255], "alpha": 58}]},
        {"id": "cg_inspect_teeth_16x9", "role": "inspection", "trigger": "teeth", "source": "hallway", "tint": (34, 78, 76), "alpha": 64, "contrast": 1.36, "brightness": 0.68, "blur": 1.1, "inspection": "teeth", "lights": [{"position": [960, 520], "radius": 430, "color": [120, 255, 230], "alpha": 88}]},
        {"id": "cg_inspect_iris_16x9", "role": "inspection", "trigger": "iris", "source": "hallway", "tint": (72, 38, 88), "alpha": 72, "contrast": 1.42, "brightness": 0.66, "blur": 1.2, "inspection": "iris", "lights": [{"position": [950, 540], "radius": 390, "color": [210, 100, 255], "alpha": 90}]},
        {"id": "cg_inspect_finger_16x9", "role": "inspection", "trigger": "finger", "source": "hallway", "tint": (72, 60, 34), "alpha": 66, "contrast": 1.28, "brightness": 0.7, "blur": 0.9, "inspection": "finger", "lights": [{"position": [1030, 590], "radius": 380, "color": [255, 215, 115], "alpha": 76}]},
        {"id": "cg_inspect_breath_shadow_16x9", "role": "inspection", "trigger": "breath_shadow", "source": "hallway", "tint": (34, 62, 92), "alpha": 76, "contrast": 1.24, "brightness": 0.64, "blur": 1.3, "inspection": "breath_shadow", "shadow": {"x": 1320, "y": 940, "scale": 0.92, "alpha": 92}},
        {"id": "cg_inspect_footprint_16x9", "role": "inspection", "trigger": "footprint", "source": "hallway", "tint": (42, 78, 58), "alpha": 70, "contrast": 1.32, "brightness": 0.66, "blur": 0.8, "inspection": "footprint", "lights": [{"position": [1060, 720], "radius": 340, "color": [110, 255, 180], "alpha": 82}]},
        {"id": "cg_inspect_environment_16x9", "role": "inspection", "trigger": "environment", "source": "room", "tint": (48, 72, 78), "alpha": 62, "contrast": 1.24, "brightness": 0.72, "blur": 0.6, "inspection": "environment", "lights": [{"position": [980, 430], "radius": 520, "color": [110, 235, 225], "alpha": 72}]},
        {"id": "cg_inspect_room_search_16x9", "role": "inspection", "trigger": "room_search", "source": "room", "tint": (84, 46, 54), "alpha": 66, "contrast": 1.34, "brightness": 0.68, "blur": 0.7, "inspection": "room_search", "lights": [{"position": [960, 520], "radius": 520, "color": [255, 120, 110], "alpha": 74}]},
        {"id": "cg_ending_true_16x9", "role": "ending", "trigger": "true", "source": "hallway", "tint": (120, 170, 150), "alpha": 40, "contrast": 0.92, "brightness": 0.88, "blur": 0.4, "lights": [{"position": [960, 260], "radius": 720, "color": [215, 255, 235], "alpha": 88}]},
        {"id": "cg_ending_good_16x9", "role": "ending", "trigger": "good", "source": "room", "tint": (94, 82, 52), "alpha": 44, "contrast": 1.05, "brightness": 0.82, "blur": 0.5, "lights": [{"position": [700, 380], "radius": 480, "color": [255, 210, 150], "alpha": 72}]},
        {"id": "cg_ending_neutral_16x9", "role": "ending", "trigger": "neutral", "source": "room", "tint": (52, 66, 76), "alpha": 58, "contrast": 1.05, "brightness": 0.7, "blur": 0.8},
        {"id": "cg_ending_no_one_16x9", "role": "ending", "trigger": "no_one", "source": "hallway", "tint": (12, 18, 22), "alpha": 104, "contrast": 1.18, "brightness": 0.52, "blur": 1.2},
        {"id": "cg_ending_perfect_band_16x9", "role": "ending", "trigger": "perfect_band", "source": "room", "tint": (96, 48, 74), "alpha": 78, "contrast": 1.32, "brightness": 0.72, "blur": 0.7, "shadow": {"x": 960, "y": 940, "scale": 1.2, "alpha": 110}},
        {"id": "cg_ending_purple_16x9", "role": "ending", "trigger": "purple", "source": "final", "tint": (120, 55, 170), "alpha": 80, "contrast": 1.28, "brightness": 0.76, "blur": 0.5, "lights": [{"position": [1260, 420], "radius": 520, "color": [210, 90, 255], "alpha": 88}]},
        {"id": "cg_ending_identity_16x9", "role": "ending", "trigger": "identity", "source": "hallway", "tint": (38, 86, 72), "alpha": 80, "contrast": 1.34, "brightness": 0.66, "blur": 0.8, "shadow": {"x": 620, "y": 930, "scale": 0.8, "alpha": 86}},
        {"id": "cg_ending_door_16x9", "role": "ending", "trigger": "door", "source": "hallway", "tint": (115, 46, 28), "alpha": 84, "contrast": 1.36, "brightness": 0.62, "blur": 0.5, "lights": [{"position": [980, 520], "radius": 360, "color": [255, 90, 50], "alpha": 88}]},
        {"id": "cg_ending_distortion_16x9", "role": "ending", "trigger": "distortion", "source": "room", "tint": (40, 118, 96), "alpha": 92, "contrast": 1.52, "brightness": 0.68, "blur": 1.4, "lights": [{"position": [980, 340], "radius": 620, "color": [90, 255, 210], "alpha": 120}]},
    ]

    entries = [
        {
            "id": "cg_another_rikki_hui_16x9",
            "role": "ending",
            "trigger": "hidden",
            "asset": "assets/generated/cg_another_rikki_hui_16x9.png",
            "source": "assets/generated/another_rikki_final.png",
            "derived": True,
            "loras": [],
        }
    ]
    OUT.mkdir(parents=True, exist_ok=True)
    for spec in specs:
        filename = f"{spec['id']}.png"
        path = OUT / filename
        image = make_variant(loaded[spec["source"]], spec)
        image.save(path, optimize=True, compress_level=9)
        write_sidecar(path, sources[spec["source"]], spec)
        entries.append(
            {
                "id": spec["id"],
                "role": spec["role"],
                "trigger": spec["trigger"],
                "asset": f"assets/generated/{filename}",
                "source": sources[spec["source"]],
                "derived": True,
                "loras": [],
            }
        )

    MANIFEST.write_text(json.dumps({"version": 1, "size": list(SIZE), "entries": entries}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE_CG_VARIANTS {len(entries)} entries")


if __name__ == "__main__":
    main()
