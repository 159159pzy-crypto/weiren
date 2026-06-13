from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated"
SIZE = (1920, 1080)

SOURCES = {
    "hallway": "assets/generated/bg_peephole_hallway_16x9.png",
    "room": "assets/generated/bg_safe_room_clueboard_16x9.png",
}

SPECS = [
    {"id": "bg_title_night_16x9", "source": "hallway", "tint": (20, 52, 60), "alpha": 66, "contrast": 1.18, "brightness": 0.62, "blur": 0.7, "lines": "peephole"},
    {"id": "bg_prep_clueboard_16x9", "source": "room", "tint": (58, 72, 54), "alpha": 48, "contrast": 1.12, "brightness": 0.76, "blur": 0.35, "lines": "grid"},
    {"id": "bg_investigation_room_16x9", "source": "room", "tint": (40, 84, 76), "alpha": 56, "contrast": 1.22, "brightness": 0.70, "blur": 0.45, "lines": "search"},
    {"id": "bg_quarantine_glass_16x9", "source": "room", "tint": (38, 96, 92), "alpha": 72, "contrast": 1.32, "brightness": 0.64, "blur": 0.8, "lines": "bars"},
    {"id": "bg_sleep_locked_room_16x9", "source": "room", "tint": (18, 22, 42), "alpha": 86, "contrast": 1.10, "brightness": 0.46, "blur": 1.2, "lines": "sleep"},
    {"id": "bg_dawn_settlement_16x9", "source": "hallway", "tint": (126, 152, 128), "alpha": 38, "contrast": 0.96, "brightness": 0.90, "blur": 0.55, "lines": "dawn"},
    {"id": "bg_contamination_room_16x9", "source": "room", "tint": (64, 128, 92), "alpha": 88, "contrast": 1.45, "brightness": 0.58, "blur": 1.1, "lines": "contam"},
    {"id": "bg_final_judgment_16x9", "source": "hallway", "tint": (94, 28, 72), "alpha": 84, "contrast": 1.38, "brightness": 0.60, "blur": 0.8, "lines": "final"},
]


def load_image(path: str) -> Image.Image:
    image = Image.open(ROOT / path).convert("RGB")
    if image.size != SIZE:
        image = image.resize(SIZE, Image.Resampling.LANCZOS)
    return image


def draw_lines(image: Image.Image, mode: str) -> Image.Image:
    layer = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cyan = (120, 255, 226, 92)
    red = (255, 72, 86, 96)
    amber = (255, 210, 118, 82)
    if mode == "peephole":
        draw.ellipse((-120, -160, 2040, 1240), outline=(8, 12, 14, 210), width=86)
        draw.ellipse((380, 160, 1540, 920), outline=cyan, width=4)
    elif mode == "grid":
        for x in range(360, 1600, 210):
            draw.line((x, 180, x + 60, 900), fill=amber, width=3)
        for y in range(260, 860, 145):
            draw.line((300, y, 1600, y - 40), fill=cyan, width=3)
    elif mode == "search":
        for box in [(420, 260, 820, 520), (940, 310, 1450, 700), (620, 650, 1280, 860)]:
            draw.rectangle(box, outline=cyan, width=5)
        draw.line((430, 880, 1510, 260), fill=red, width=4)
    elif mode == "bars":
        for x in range(460, 1480, 170):
            draw.rounded_rectangle((x, 130, x + 32, 960), radius=14, fill=(160, 255, 240, 72))
        draw.rectangle((350, 220, 1570, 840), outline=cyan, width=7)
    elif mode == "sleep":
        draw.rectangle((0, 0, SIZE[0], SIZE[1]), fill=(0, 0, 0, 55))
        for i in range(6):
            draw.arc((520 - i * 40, 220 - i * 20, 1400 + i * 40, 860 + i * 20), 20, 160, fill=(180, 210, 255, 34), width=4)
    elif mode == "dawn":
        for y in range(0, 520, 35):
            draw.line((0, y, SIZE[0], y + 180), fill=(255, 238, 190, 36), width=12)
    elif mode == "contam":
        for x in range(220, 1720, 180):
            draw.ellipse((x - 90, 250, x + 90, 760), outline=(90, 255, 150, 58), width=7)
        draw.line((260, 260, 1640, 820), fill=red, width=6)
    elif mode == "final":
        draw.rectangle((330, 180, 1590, 900), outline=red, width=8)
        draw.line((960, 120, 960, 960), fill=cyan, width=5)
        draw.line((380, 540, 1540, 540), fill=cyan, width=5)
    return Image.alpha_composite(image.convert("RGBA"), layer.filter(ImageFilter.GaussianBlur(0.4))).convert("RGB")


def make_variant(source: Image.Image, spec: dict) -> Image.Image:
    image = source.copy()
    if spec.get("blur", 0):
        image = image.filter(ImageFilter.GaussianBlur(float(spec["blur"])))
    image = ImageEnhance.Contrast(image).enhance(float(spec["contrast"]))
    image = ImageEnhance.Brightness(image).enhance(float(spec["brightness"]))
    overlay = Image.new("RGB", SIZE, tuple(spec["tint"]))
    image = Image.blend(image, overlay, int(spec["alpha"]) / 255.0)
    return draw_lines(image, str(spec["lines"]))


def write_sidecar(path: Path, source: str, spec: dict) -> None:
    sidecar = {
        "mode": "derived-16x9-environment-background",
        "source": source,
        "output": str(path.relative_to(ROOT)),
        "size": list(SIZE),
        "role": "environment_background",
        "variant": spec["id"],
        "loras": [],
        "vae": "checkpoint_default",
        "input_image": None,
        "mask_image": None,
        "comfyui_input_image": None,
        "comfyui_mask_image": None,
        "workflow_safety": {
            "active_loras": [],
            "controlnet_preprocessor_nodes": [],
            "suspicious_preprocessor_nodes": [],
            "lora_policy": "no final environment LoRA; derived from audited background",
            "hires_fix": "not rerun here; color-grade and overlay variant from audited 16:9 background",
            "vae_policy": "checkpoint_default from source generation",
        },
    }
    path.with_suffix(".asset-plan.json").write_text(json.dumps(sidecar, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    loaded = {key: load_image(path) for key, path in SOURCES.items()}
    for spec in SPECS:
        filename = f"{spec['id']}.png"
        path = OUT / filename
        make_variant(loaded[spec["source"]], spec).save(path, optimize=True, compress_level=9)
        write_sidecar(path, SOURCES[spec["source"]], spec)
    print(f"WROTE_ENVIRONMENT_VARIANTS {len(SPECS)} variants")


if __name__ == "__main__":
    main()
