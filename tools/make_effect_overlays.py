from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated"
SIZE = (1920, 1080)

SPECS = [
    {"id": "fx_contamination_overlay", "kind": "veins", "color": (72, 255, 150, 78), "accent": (255, 68, 92, 56)},
    {"id": "fx_door_damage_overlay", "kind": "cracks", "color": (255, 198, 92, 86), "accent": (255, 72, 58, 62)},
    {"id": "fx_outside_danger_overlay", "kind": "peephole", "color": (255, 80, 94, 76), "accent": (8, 10, 12, 150)},
    {"id": "fx_trust_break_overlay", "kind": "fracture", "color": (122, 160, 255, 70), "accent": (255, 255, 255, 38)},
    {"id": "fx_evidence_noise_overlay", "kind": "scanlines", "color": (120, 255, 230, 44), "accent": (255, 216, 128, 50)},
    {"id": "fx_mimic_learning_overlay", "kind": "echo", "color": (190, 90, 255, 70), "accent": (90, 255, 220, 46)},
]


def draw_overlay(spec: dict) -> Image.Image:
    image = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    color = tuple(spec["color"])
    accent = tuple(spec["accent"])
    kind = spec["kind"]
    if kind == "veins":
        for x in range(120, 1900, 180):
            points = [(x, 0), (x - 60, 210), (x + 40, 420), (x - 90, 690), (x + 20, 1080)]
            draw.line(points, fill=color, width=7)
            draw.line([(px + 45, py + 20) for px, py in points[1:4]], fill=accent, width=3)
    elif kind == "cracks":
        for x in [280, 620, 980, 1340, 1620]:
            points = [(x, 70), (x + 80, 260), (x - 35, 470), (x + 130, 760), (x + 10, 1040)]
            draw.line(points, fill=color, width=6)
            draw.line((points[2][0], points[2][1], points[2][0] - 180, points[2][1] + 90), fill=accent, width=4)
    elif kind == "peephole":
        draw.ellipse((-160, -210, 2080, 1290), outline=accent, width=110)
        for radius in range(320, 980, 140):
            draw.ellipse((960 - radius, 540 - radius // 2, 960 + radius, 540 + radius // 2), outline=color, width=5)
    elif kind == "fracture":
        for y in range(120, 980, 160):
            draw.line((0, y, 420, y + 40, 820, y - 30, 1320, y + 80, 1920, y - 10), fill=color, width=5)
        draw.rectangle((120, 120, 1800, 960), outline=accent, width=4)
    elif kind == "scanlines":
        for y in range(0, SIZE[1], 34):
            draw.line((0, y, SIZE[0], y), fill=color, width=3)
        for x in range(160, 1840, 260):
            draw.rectangle((x, 180, x + 120, 900), outline=accent, width=3)
    elif kind == "echo":
        for offset in range(0, 420, 70):
            draw.ellipse((540 - offset, 160, 1380 + offset, 920), outline=color, width=5)
            draw.line((960 - offset, 140, 960 + offset, 940), fill=accent, width=4)
    return image.filter(ImageFilter.GaussianBlur(1.2))


def write_sidecar(path: Path, spec: dict) -> None:
    sidecar = {
        "mode": "generated-effect-overlay",
        "output": str(path.relative_to(ROOT)),
        "size": list(SIZE),
        "role": "effect_overlay",
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
            "lora_policy": "no effect overlay LoRA; procedural transparent PNG",
            "hires_fix": "not applicable; procedural 16:9 transparent overlay",
            "vae_policy": "checkpoint_default",
        },
    }
    path.with_suffix(".asset-plan.json").write_text(json.dumps(sidecar, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        path = OUT / f"{spec['id']}.png"
        draw_overlay(spec).save(path, optimize=True, compress_level=9)
        write_sidecar(path, spec)
    print(f"WROTE_EFFECT_OVERLAYS {len(SPECS)} overlays")


if __name__ == "__main__":
    main()
