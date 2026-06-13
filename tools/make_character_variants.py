from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated"

SOURCES = {
    "human": "assets/generated/char_human_base.png",
    "fake": "assets/generated/char_fake_base.png",
    "mimic": "assets/generated/char_mimic_base.png",
    "rikki": "assets/generated/char_rikki_base.png",
}

VARIANTS = {
    "calm": {"tint": (80, 145, 128), "alpha": 0.10, "contrast": 0.98, "brightness": 1.04, "blur": 0.0},
    "stress": {"tint": (155, 54, 62), "alpha": 0.16, "contrast": 1.18, "brightness": 0.92, "blur": 0.35},
    "doubt": {"tint": (74, 55, 130), "alpha": 0.18, "contrast": 1.08, "brightness": 0.88, "blur": 0.55},
}


def make_variant(image: Image.Image, spec: dict) -> Image.Image:
    result = image.convert("RGB")
    if spec["blur"]:
        result = result.filter(ImageFilter.GaussianBlur(float(spec["blur"])))
    result = ImageEnhance.Contrast(result).enhance(float(spec["contrast"]))
    result = ImageEnhance.Brightness(result).enhance(float(spec["brightness"]))
    overlay = Image.new("RGB", result.size, tuple(spec["tint"]))
    result = Image.blend(result, overlay, float(spec["alpha"]))
    if spec is VARIANTS["doubt"]:
        edges = ImageOps.grayscale(image).filter(ImageFilter.FIND_EDGES).convert("RGB")
        result = Image.blend(result, edges, 0.08)
    return result


def write_sidecar(path: Path, source: str, role: str, variant: str) -> None:
    sidecar = {
        "mode": "derived-character-variant",
        "source": source,
        "output": str(path.relative_to(ROOT)),
        "role": "character",
        "character_base": role,
        "variant": variant,
        "loras": [],
        "vae": "checkpoint_default",
        "input_image": None,
        "mask_image": None,
        "comfyui_input_image": None,
        "comfyui_mask_image": None,
        "hires_scale": 1.0,
        "hires_steps": 1,
        "hires_denoise": 0.15,
        "workflow_safety": {
            "active_loras": [],
            "controlnet_preprocessor_nodes": [],
            "suspicious_preprocessor_nodes": [],
            "lora_policy": "no final character LoRA; derived from audited base portrait",
            "hires_fix": "not rerun here; color-grade variant from audited character portrait",
            "vae_policy": "checkpoint_default from source generation",
        },
    }
    path.with_suffix(".asset-plan.json").write_text(json.dumps(sidecar, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    count = 0
    for role, source in SOURCES.items():
        image = Image.open(ROOT / source).convert("RGB")
        for variant, spec in VARIANTS.items():
            path = OUT / f"char_{role}_{variant}.png"
            make_variant(image, spec).save(path, optimize=True, compress_level=9)
            write_sidecar(path, source, role, variant)
            count += 1
    print(f"WROTE_CHARACTER_VARIANTS {count} variants")


if __name__ == "__main__":
    main()
