from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated"
SIZE = (128, 128)

ICONS = [
    {"id": "ui_icon_stamina", "kind": "bolt", "color": (120, 255, 226, 255)},
    {"id": "ui_icon_contamination", "kind": "hazard", "color": (255, 90, 112, 255)},
    {"id": "ui_icon_door", "kind": "lock", "color": (255, 202, 112, 255)},
    {"id": "ui_icon_quarantine", "kind": "shield", "color": (138, 180, 255, 255)},
    {"id": "ui_icon_supplies", "kind": "crate", "color": (216, 234, 124, 255)},
    {"id": "ui_icon_trust", "kind": "heart", "color": (255, 150, 194, 255)},
    {"id": "ui_icon_danger", "kind": "eye", "color": (255, 104, 82, 255)},
    {"id": "ui_icon_evidence", "kind": "pin", "color": (120, 235, 210, 255)},
]


def base_canvas(color: tuple[int, int, int, int]) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    glow = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((18, 18, 110, 110), fill=(*color[:3], 44))
    image = Image.alpha_composite(image, glow.filter(ImageFilter.GaussianBlur(10)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((18, 18, 110, 110), radius=24, outline=(*color[:3], 180), width=4, fill=(5, 9, 12, 150))
    return image, draw


def draw_icon(spec: dict) -> Image.Image:
    color = tuple(spec["color"])
    image, draw = base_canvas(color)
    c = color
    kind = spec["kind"]
    if kind == "bolt":
        draw.polygon([(68, 26), (42, 72), (62, 72), (52, 104), (86, 56), (64, 58)], fill=c)
    elif kind == "hazard":
        draw.ellipse((42, 34, 86, 78), outline=c, width=7)
        draw.rectangle((58, 72, 70, 100), fill=c)
        draw.line((34, 96, 94, 96), fill=c, width=6)
    elif kind == "lock":
        draw.rounded_rectangle((38, 58, 90, 98), radius=9, outline=c, width=6)
        draw.arc((46, 30, 82, 72), 180, 360, fill=c, width=7)
        draw.ellipse((59, 73, 69, 83), fill=c)
    elif kind == "shield":
        draw.polygon([(64, 28), (94, 42), (88, 82), (64, 104), (40, 82), (34, 42)], outline=c, fill=(*c[:3], 80))
        draw.line((64, 38, 64, 94), fill=c, width=5)
    elif kind == "crate":
        draw.rectangle((34, 46, 94, 94), outline=c, width=6)
        draw.line((34, 62, 94, 62), fill=c, width=5)
        draw.line((64, 46, 64, 94), fill=c, width=5)
    elif kind == "heart":
        points = []
        for i in range(96):
            t = math.pi * 2 * i / 96
            x = 16 * math.sin(t) ** 3
            y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
            points.append((64 + x * 2.3, 72 - y * 2.3))
        draw.polygon(points, fill=c)
    elif kind == "eye":
        draw.ellipse((34, 48, 94, 84), outline=c, width=6)
        draw.ellipse((55, 52, 73, 80), fill=c)
        draw.line((64, 26, 64, 42), fill=c, width=5)
    elif kind == "pin":
        draw.rounded_rectangle((38, 32, 90, 92), radius=8, outline=c, width=6)
        draw.line((50, 50, 78, 50), fill=c, width=5)
        draw.line((50, 66, 84, 66), fill=c, width=5)
        draw.line((50, 82, 70, 82), fill=c, width=5)
    return image


def write_sidecar(path: Path, spec: dict) -> None:
    sidecar = {
        "mode": "procedural-ui-icon",
        "output": str(path.relative_to(ROOT)),
        "size": list(SIZE),
        "role": "ui_icon",
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
            "lora_policy": "no UI icon LoRA; procedural transparent PNG",
            "hires_fix": "not applicable; procedural UI icon",
            "vae_policy": "checkpoint_default",
        },
    }
    path.with_suffix(".asset-plan.json").write_text(json.dumps(sidecar, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for spec in ICONS:
        path = OUT / f"{spec['id']}.png"
        draw_icon(spec).save(path, optimize=True, compress_level=9)
        write_sidecar(path, spec)
    print(f"WROTE_UI_ICONS {len(ICONS)} icons")


if __name__ == "__main__":
    main()
