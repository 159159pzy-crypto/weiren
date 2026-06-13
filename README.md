# 猫眼之后

Godot 4 单机版九夜随机猫眼伪人辨识游戏。

## 运行

```powershell
godot --path D:\game
```

可选：启动本地对白后端。后端不决定真相，只负责角色表演；不启动时游戏会自动使用内置兜底文本。

```powershell
cd D:\game
python -m uvicorn backend.main:app --reload --host 127.0.0.1 --port 8787
```

## 当前版本内容

- 九夜随机流程：黄昏准备、门外来访、室内排查、睡眠事件、黎明结算。
- 角色池、每日规则、门外事件、睡眠事件使用 JSON 数据驱动。
- 真人、普通伪人、变身怪三类身份生成。
- 自由盘问输入框会按关键词触发记忆、路线、牙齿、虹膜、手指、呼吸、影子、足迹等证据。
- 本地 FastAPI/SQLite 后端可接管角色对白表演，并记录盘问日志。
- LLM API 为可选 OpenAI-compatible 配置；未配置时后端使用本地兜底表演。
- 体力、污染、见死不救、物资、门锁、隔离区、信任、伪人学习等状态变量。
- 多结局：真结局、Good、Neutral、多个 Bad End、Hidden End。

## 资产规范

- 背景使用 SDXL txt2img 工作流，并输出 16:9。
- 人物使用 `hui` 锁定工作流。
- CG 使用 `hui` 锁定工作流生成原图，再适配为 16:9 游戏成品；适配步骤不会修改 `hui` 工作流参数。

## 关键资产

- `assets/generated/bg_peephole_hallway_16x9.png`
- `assets/generated/bg_safe_room_clueboard_16x9.png`
- `assets/generated/char_human_visitor_hui.png`
- `assets/generated/char_mimic_visitor_hui.png`
- `assets/generated/char_another_rikki_hui.png`
- `assets/generated/cg_another_rikki_hui_16x9.png`

## 验证

```powershell
godot --headless --path D:\game --quit-after 1
godot --headless --path D:\game --script res://scripts/SmokeTest.gd
python -m backend.smoke_test
```

完整链路验证：

```powershell
$p = Start-Process -FilePath "python" -ArgumentList @("-m","uvicorn","backend.main:app","--host","127.0.0.1","--port","8787") -WorkingDirectory "D:\game" -PassThru -WindowStyle Hidden
godot --headless --path D:\game --script res://scripts/SmokeTest.gd
Stop-Process -Id $p.Id
```
