# Asset Pipeline

The game keeps character, CG, and background generation separate so visual problems can be audited and fixed without changing gameplay code.

## Current Safety Decisions

- Character LoRAs are disabled for final in-game character portraits.
- The four in-game character portraits are prompt-only outputs with empty `loras` arrays in their sidecars.
- Temporary character-LoRA test files must not be committed or referenced by Godot.
- Backgrounds and CG used by the game must be 16:9.
- ControlNet/preprocessor outputs are not part of the final asset set. Files named like `controlnet`, `preprocess`, `canny`, `depth`, `openpose`, `lineart`, `scribble`, or `softedge` fail the project audit.

## Character Route

- Role: `character`
- Checkpoint: `wai-illustrious-sdxl-v170`
- Size: vertical portrait, currently 1248x1824 final output
- LoRA rule: `--max-loras 0`
- Negative focus: no readable text, no logo, no cropped face, no duplicate character, no extra limbs, and no unintended second figure.

Final in-game portraits:

| Visitor role | Output | LoRA policy |
|---|---|---|
| Human visitor | `char_human_base.png` | none |
| Fake visitor | `char_fake_base.png` | none |
| Mimic visitor | `char_mimic_base.png` | none |
| Final duplicate | `char_rikki_base.png` | none |

## Background Route

- Role: `background`
- Checkpoint: `wai-illustrious-sdxl-v170`
- Size: 1920x1080 final, 16:9
- Prompt rule: no people, no readable text, clear gameplay surface, strong negative space for UI panels.

Final in-game backgrounds:

| Scene | Output |
|---|---|
| Peephole hallway | `bg_peephole_hallway_16x9.png` |
| Safe-room clue board | `bg_safe_room_clueboard_16x9.png` |
| Final CG | `cg_another_rikki_hui_16x9.png` |

## Hui Workflow Notes

- The Hui locked workflow is still available for character/CG direction, but its style LoRA strengths were reduced to conservative values.
- New Hui sidecars include a `workflow_safety` summary listing active LoRA, sampler, VAE, and suspicious preprocessor nodes.
- The current final character portraits use the prompt-only no-LoRA route because the user reported character LoRA instability.

## Verification

Run the project audit after any asset change:

```powershell
python tools/audit_project.py
```

The audit checks referenced assets, sidecars, Hires parameters, 16:9 backgrounds/CG, stale Godot references, and preprocessor-looking leaks.
