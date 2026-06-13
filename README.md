# 猫眼之后

Godot 4 单机版九夜随机猫眼伪人辨识游戏。玩家在门内判断访客、盘问线索、管理体力和污染，并在第九夜面对“另一个立希”。

## 运行

```powershell
godot --path D:\game
```

可选：启动本地对白后端。后端不决定真相，只负责角色表演和日志记录；不启动时游戏会自动使用内置兜底文本。

```powershell
cd D:\game
python -m uvicorn backend.main:app --reload --host 127.0.0.1 --port 8787
```

可选 LLM/API Key 配置见 `.env.example`。至少设置 `LLM_API_KEY` 后，后端会调用 OpenAI-compatible chat completions；未配置、后端未启动或请求失败时会使用本地兜底对白。

游戏标题页的“正式版说明”会显示同人免责声明、LLM 配置路径和发布前检查命令。对应配置文件为 `data/release_config.json`。

## 当前内容

- 九夜流程：黄昏准备、门外来访、自由盘问、证据检查、隔离区处理、室内排查、睡眠事件、黎明结算。
- JSON 数据驱动：角色池、每日规则、门外事件、睡眠事件。
- 访客身份：真人、普通伪人、拟态体、最终夜 duplicate。
- 自由盘问输入框会按关键词触发记忆、路线、牙齿、虹膜、手指、呼吸、影子、足迹等证据。
- 本地 FastAPI/SQLite 后端可接管角色对白表演，并记录盘问日志。
- LLM API 为可选 OpenAI-compatible 配置；未配置时后端使用本地兜底表演。
- 多结局：True、Good、Neutral、多个 Bad End、Hidden End。
- M8 打磨项：标题页内置正式版说明、同人免责声明、API Key 配置说明和发布检查清单。

## 资产规范

- 背景使用 SDXL/txt2img 路线，游戏内最终图必须是 16:9。
- 角色与背景分开生成、分开审计。
- 角色 LoRA 当前统一禁用；最终角色图 sidecar 的 `loras` 必须为空。
- 旧的角色 LoRA 临时图已移除，Godot 不再引用旧 Hui 角色图。
- CG 可由 Hui 锁定工作流生成竖图后再适配为 16:9 游戏图。
- ControlNet / Canny / Depth / OpenPose 等预处理图不得进入 `assets/generated` 最终资产目录。
- Hui 锁定工作流中的风格 LoRA 已降到保守权重，并且新 sidecar 会记录实际 LoRA、Sampler、VAE 和可疑预处理节点摘要。

## 关键资产

- `assets/generated/bg_peephole_hallway_16x9.png`
- `assets/generated/bg_safe_room_clueboard_16x9.png`
- `tools/make_environment_variants.py` derives 8 audited 16:9 environment backgrounds for title, prep, investigation, quarantine, sleep, dawn, contamination, and final judgment scenes.
- `tools/make_effect_overlays.py` derives 6 audited 16:9 transparent status overlays for contamination, door damage, outside danger, trust collapse, evidence noise, and mimic learning.
- `tools/make_ui_icons.py` derives 8 audited transparent status icons for stamina, contamination, door, quarantine, supplies, trust, danger, and evidence.
- `assets/generated/char_human_base.png`
- `assets/generated/char_fake_base.png`
- `assets/generated/char_mimic_base.png`
- `assets/generated/char_rikki_base.png`
- `tools/make_character_variants.py` derives calm/stress/doubt portraits from the four audited bases; the release audit now expects 16 no-LoRA character portraits.
- `assets/generated/cg_another_rikki_hui_16x9.png`
- `data/cg_manifest.json` lists the current 39 audited 16:9 CG entries used by sleep events, all door events, inspections, and endings.
- `data/broadcasts.json` drives day 1-9 TV/radio rule updates during dusk prep, with one-time state effects for evidence integrity, quarantine pressure, identity theft warnings, gun charges, self-check pressure, and final judgment distortion.

## 验证

```powershell
python tools/audit_project.py
godot --headless --path D:\game --quit-after 1
godot --headless --path D:\game --script res://scripts/SmokeTest.gd
godot --headless --path D:\game --script res://scripts/FullRunAudit.gd
godot --headless --path D:\game --script res://scripts/BalanceAudit.gd
python -m backend.smoke_test
```

完整后端链路验证：

```powershell
$p = Start-Process -FilePath "python" -ArgumentList @("-m","uvicorn","backend.main:app","--host","127.0.0.1","--port","8787") -WorkingDirectory "D:\game" -PassThru -WindowStyle Hidden
godot --headless --path D:\game --script res://scripts/SmokeTest.gd
Stop-Process -Id $p.Id
```

发布前总检查：

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_release.ps1 -SkipExport
```

导出 Windows 版：

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_release.ps1
```

如果导出失败但检查通过，通常是当前机器没有安装 Godot 4.6.3 export templates。打开 Godot Editor -> Editor -> Manage Export Templates 安装后重跑。
