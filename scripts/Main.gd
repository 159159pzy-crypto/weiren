extends Control

const CHARACTERS_PATH := "res://data/characters.json"
const DAY_RULES_PATH := "res://data/day_rules.json"
const EVENTS_PATH := "res://data/events.json"

const BG_PEEPHOLE := "res://assets/generated/bg_peephole_hallway_16x9.png"
const BG_ROOM := "res://assets/generated/bg_safe_room_clueboard_16x9.png"
const BG_FINAL := "res://assets/generated/cg_another_rikki_hui_16x9.png"
const CHAR_HUMAN := "res://assets/generated/char_human_base.png"
const CHAR_FAKE := "res://assets/generated/char_fake_base.png"
const CHAR_MIMIC := "res://assets/generated/char_mimic_base.png"
const CHAR_RIKKI := "res://assets/generated/char_rikki_base.png"
const BACKEND_DIALOGUE_URL := "http://127.0.0.1:8787/v1/dialogue"

var rng := RandomNumberGenerator.new()

var characters: Array = []
var day_rules: Array = []
var door_events: Array = []
var sleep_events: Array = []

var state := {}
var current_visitors: Array = []
var current_visitor_index := 0
var current_phase := "title"
var current_seed := 0
var session_id := ""
var final_mimic_identified := false
var final_mimic_mishandled := false
var backend_enabled := true
var pending_backend_context := {}

var background: TextureRect
var veil: ColorRect
var title_label: Label
var subtitle_label: Label
var stats_label: RichTextLabel
var narrative: RichTextLabel
var character_portrait: TextureRect
var actions_box: VBoxContainer
var board_label: RichTextLabel
var event_label: RichTextLabel
var seed_input: LineEdit
var question_input: LineEdit
var dialogue_http: HTTPRequest

func _ready() -> void:
	rng.randomize()
	_load_data()
	_build_ui()
	_setup_http()
	_show_title()


func _load_data() -> void:
	characters = _read_json_array(CHARACTERS_PATH)
	day_rules = _read_json_array(DAY_RULES_PATH)
	var events := _read_json_dict(EVENTS_PATH)
	door_events = events.get("door_events", [])
	sleep_events = events.get("sleep_events", [])


func _read_json_array(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Array:
		return parsed
	push_error("JSON array load failed: " + path)
	return []


func _read_json_dict(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("JSON dictionary load failed: " + path)
	return {}


func _build_ui() -> void:
	_set_background(BG_PEEPHOLE)
	veil = ColorRect.new()
	veil.color = Color(0.02, 0.025, 0.028, 0.48)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 28)
	root.add_theme_constant_override("margin_right", 28)
	root.add_theme_constant_override("margin_top", 22)
	root.add_theme_constant_override("margin_bottom", 22)
	add_child(root)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)

	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 74)
	top.add_theme_constant_override("separation", 18)
	main.add_child(top)

	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_stack)

	title_label = Label.new()
	title_label.text = "猫眼之后"
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", Color(0.86, 0.95, 0.92))
	title_stack.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "九夜随机猫眼伪人辨识"
	subtitle_label.add_theme_font_size_override("font_size", 15)
	subtitle_label.add_theme_color_override("font_color", Color(0.58, 0.78, 0.76))
	title_stack.add_child(subtitle_label)

	event_label = RichTextLabel.new()
	event_label.bbcode_enabled = true
	event_label.fit_content = true
	event_label.scroll_active = false
	event_label.custom_minimum_size = Vector2(420, 68)
	event_label.add_theme_font_size_override("normal_font_size", 14)
	top.add_child(_panel_wrap(event_label, Color(0.04, 0.06, 0.065, 0.76)))

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	main.add_child(content)

	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = false
	stats_label.scroll_active = false
	stats_label.add_theme_font_size_override("normal_font_size", 15)
	var stats_panel := _titled_panel("状态", stats_label, Vector2(255, 0), Color(0.025, 0.04, 0.045, 0.82))
	content.add_child(stats_panel)

	var center_panel := PanelContainer.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_panel.add_theme_stylebox_override("panel", _stylebox(Color(0.03, 0.035, 0.038, 0.80), Color(0.30, 0.48, 0.46, 0.45)))
	content.add_child(center_panel)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 12)
	center_panel.add_child(center)

	var story_row := HBoxContainer.new()
	story_row.add_theme_constant_override("separation", 12)
	story_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(story_row)

	character_portrait = TextureRect.new()
	character_portrait.custom_minimum_size = Vector2(220, 320)
	character_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	character_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	character_portrait.visible = false
	story_row.add_child(character_portrait)

	narrative = RichTextLabel.new()
	narrative.bbcode_enabled = true
	narrative.size_flags_vertical = Control.SIZE_EXPAND_FILL
	narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrative.add_theme_font_size_override("normal_font_size", 20)
	narrative.add_theme_color_override("default_color", Color(0.90, 0.93, 0.89))
	story_row.add_child(narrative)

	var action_scroll := ScrollContainer.new()
	action_scroll.custom_minimum_size = Vector2(0, 188)
	center.add_child(action_scroll)

	actions_box = VBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 8)
	actions_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.add_child(actions_box)

	board_label = RichTextLabel.new()
	board_label.bbcode_enabled = true
	board_label.fit_content = false
	board_label.add_theme_font_size_override("normal_font_size", 14)
	var board_panel := _titled_panel("线索板", board_label, Vector2(330, 0), Color(0.035, 0.032, 0.04, 0.84))
	content.add_child(board_panel)


func _panel_wrap(child: Control, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _stylebox(color, Color(0.30, 0.42, 0.45, 0.45)))
	panel.add_child(child)
	return panel


func _titled_panel(title: String, child: Control, min_size: Vector2, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", _stylebox(color, Color(0.34, 0.46, 0.42, 0.55)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.72, 0.94, 0.88))
	box.add_child(label)
	child.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(child)
	return panel


func _stylebox(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _set_background(path: String) -> void:
	if background == null:
		background = TextureRect.new()
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(background)
	var tex := _load_texture(path)
	if tex != null:
		background.texture = tex


func _load_texture(path: String) -> Texture2D:
	var tex: Texture2D
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image != null:
		tex = ImageTexture.create_from_image(image)
	else:
		tex = ResourceLoader.load(path) as Texture2D
	return tex


func _set_character_portrait(path: String) -> void:
	if character_portrait == null:
		return
	var tex := _load_texture(path)
	if tex != null:
		character_portrait.texture = tex
		character_portrait.visible = true


func _hide_character_portrait() -> void:
	if character_portrait != null:
		character_portrait.visible = false


func _setup_http() -> void:
	dialogue_http = HTTPRequest.new()
	dialogue_http.timeout = 8.0
	dialogue_http.request_completed.connect(_on_dialogue_http_completed)
	add_child(dialogue_http)


func _show_title() -> void:
	current_phase = "title"
	_set_background(BG_PEEPHOLE)
	_hide_character_portrait()
	title_label.text = "猫眼之后"
	subtitle_label.text = "你不能相信所有人。但如果你谁都不信，你也会失去所有人。"
	event_label.text = "[color=#8de8d0]本地最终版[/color]\n九夜随机、证据链、隔离区、变身怪、睡眠事件与多结局。"
	stats_label.text = "[color=#9ef0dc]等待开始[/color]\n\n输入种子可复现同一局。留空则随机。"
	board_label.text = "[color=#ffc878]规则[/color]\n每晚门外会有 3-5 名来访者。真人、伪人和变身怪都会说谎，区别是他们为什么说谎。"
	narrative.text = "[font_size=28][color=#effff7]凌晨 0:43。[/color][/font_size]\n\n电视雪花里断续重复一句话：不要立刻开门。\n门外的走廊被雨水涂亮，猫眼之后，所有熟悉的脸都要重新证明自己。\n\n你是椎名立希。安全屋的门锁还完好，物资只够九夜。"
	_clear_actions()
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "随机种子，例如 20260613"
	seed_input.custom_minimum_size = Vector2(0, 42)
	actions_box.add_child(seed_input)
	_add_action("开始九夜", _start_new_game, "使用当前种子生成一局完整随机流程。")
	_add_action("后端表演：" + ("开" if backend_enabled else "关"), _toggle_backend, "本地 FastAPI 后端只负责角色表演，不决定真相。")
	_add_action("查看玩法摘要", _show_help, "打开规则和判定说明。")


func _show_help() -> void:
	narrative.text = "[color=#9ef0dc]玩法摘要[/color]\n\n- 盘问和检查会消耗体力，过度盘问会提高伪人学习。\n- 伪人至少有三条可发现证据，但后期会适应单一规则。\n- 真人也可能表现可疑，拒绝真人会提高见死不救和身份被盗风险。\n- 隔离区是折中方案，但容量和耐久有限。\n- 第九夜会出现最终审判；保留至少三名可信人类、低污染并识别最终变身怪可达成真结局。"
	_clear_actions()
	_add_action("返回标题", _show_title)


func _start_new_game() -> void:
	var seed_text := seed_input.text.strip_edges() if seed_input != null else ""
	if seed_text.is_empty():
		current_seed = int(Time.get_unix_time_from_system()) ^ rng.randi()
	else:
		current_seed = hash(seed_text)
	session_id = str(current_seed)
	rng.seed = current_seed
	state = {
		"day": 1,
		"stamina": 100,
		"stamina_max": 100,
		"contamination": 0,
		"abandonment": 0,
		"supplies": 72,
		"door": 100,
		"quarantine": 100,
		"quarantine_used": 0,
		"trust": 62,
		"outside_danger": 16,
		"evidence_integrity": 100,
		"mimic_learning": 0,
		"humans_inside": 0,
		"fakes_inside": 0,
		"mimics_inside": 0,
		"missing": 0,
		"stolen": 0,
		"refusal_streak": 0,
		"guarded": false,
		"code_phrase": "",
		"detector_focus": "none",
		"rooms_assigned": false,
		"supplies_distributed": false,
		"room_search_bonus": 0,
		"log": [],
		"evidence": []
	}
	final_mimic_identified = false
	final_mimic_mishandled = false
	_log("随机种子：" + str(current_seed))
	_begin_day()


func _begin_day() -> void:
	current_phase = "prep"
	_hide_character_portrait()
	state["quarantine_used"] = 0
	state["guarded"] = false
	state["detector_focus"] = "none"
	state["rooms_assigned"] = false
	state["supplies_distributed"] = false
	state["room_search_bonus"] = 0
	_generate_visitors()
	_set_background(BG_ROOM)
	var rule := _rule_for_day(state["day"])
	title_label.text = "第 " + str(state["day"]) + " 夜"
	subtitle_label.text = rule.get("rule", "")
	event_label.text = "[color=#ffc878]" + rule.get("focus", "") + "[/color]\n今晚预计来访：" + str(current_visitors.size()) + " 人"
	narrative.text = "[color=#effff7]黄昏准备[/color]\n\n今天的新规则是：[color=#9ef0dc]" + rule.get("rule", "") + "[/color]\n" + rule.get("focus", "") + "\n\n你还有一点时间决定今晚把体力花在哪里。"
	_update_panels()
	_clear_actions()
	_add_action("修理门锁（体力 12，零件 8）", _prep_repair_door)
	_add_action("加固隔离区（体力 15，物资 6）", _prep_fortify_quarantine)
	_add_action("分配房间（体力 5）", _prep_assign_rooms)
	_add_action("设定今日暗号（体力 4）", _prep_set_code)
	_add_action("选择重点检测设备（体力 5）", _prep_select_detector)
	_add_action("分配物资（物资 10）", _prep_distribute_supplies)
	_add_action("整理线索板（体力 6）", _prep_sort_evidence)
	_add_action("安排守夜（物资 8，信任 -2）", _prep_set_guard)
	_add_action("短休并进门口（体力 +10）", _prep_rest)
	_add_action("开始门外来访", _start_visitors, "结束准备阶段。")


func _prep_repair_door() -> void:
	if !_spend_stamina(12):
		return
	if state["supplies"] < 8:
		_notice("物资不足，门锁零件不够。")
		return
	state["supplies"] -= 8
	state["door"] = mini(100, state["door"] + 22)
	_log("修理门锁，门锁耐久上升。")
	_begin_day()


func _prep_fortify_quarantine() -> void:
	if !_spend_stamina(15):
		return
	if state["supplies"] < 6:
		_notice("物资不足，隔离门无法加固。")
		return
	state["supplies"] -= 6
	state["quarantine"] = mini(100, state["quarantine"] + 24)
	_log("加固隔离区，玻璃后的第二道锁重新咬合。")
	_begin_day()


func _prep_assign_rooms() -> void:
	if !_spend_stamina(5):
		return
	state["rooms_assigned"] = true
	state["trust"] = mini(100, state["trust"] + 3)
	state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 5)
	_log("重新分配房间：每个人的睡位、门缝和逃生路线都被写到线索板上。")
	_begin_day()


func _prep_set_code() -> void:
	if !_spend_stamina(4):
		return
	var codes := ["蓝色不是紫色", "猫不敲三下", "鼓槌在左手", "不要说完整名字", "天亮前不唱副歌"]
	state["code_phrase"] = codes[(int(state["day"]) + int(current_seed)) % codes.size()]
	state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 4)
	_log("设定今日暗号：" + str(state["code_phrase"]) + "。答错半句的人更容易被记录。")
	_begin_day()


func _prep_select_detector() -> void:
	if !_spend_stamina(5):
		return
	var sequence := ["teeth", "iris", "finger", "breath_shadow", "footprint", "environment"]
	state["detector_focus"] = sequence[(int(state["day"]) - 1) % sequence.size()]
	_log("今晚重点检测设备：" + _detector_label(str(state["detector_focus"])) + "。对应检查更省体力，成功率更高。")
	_begin_day()


func _prep_distribute_supplies() -> void:
	if state["supplies"] < 10:
		_notice("物资不足，无法提前分配。")
		return
	state["supplies"] -= 10
	state["supplies_distributed"] = true
	state["trust"] = mini(100, state["trust"] + 8)
	state["stamina"] = mini(state["stamina_max"], state["stamina"] + 6)
	_log("提前分配物资。有人终于愿意相信今晚不是只靠怀疑活下去。")
	_begin_day()


func _prep_sort_evidence() -> void:
	if !_spend_stamina(6):
		return
	state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 14)
	state["trust"] = mini(100, state["trust"] + 2)
	_log("整理线索板，篡改痕迹更容易被发现。")
	_begin_day()


func _prep_set_guard() -> void:
	if state["supplies"] < 8:
		_notice("没有足够物资说服别人守夜。")
		return
	state["supplies"] -= 8
	state["trust"] = maxi(0, state["trust"] - 2)
	state["guarded"] = true
	_log("安排守夜。你会睡得更稳，但屋内压力上升。")
	_begin_day()


func _prep_rest() -> void:
	state["stamina"] = mini(state["stamina_max"], state["stamina"] + 10)
	_log("短休十分钟。你把耳朵从门板上挪开。")
	_start_visitors()


func _start_visitors() -> void:
	current_phase = "door"
	current_visitor_index = 0
	_set_background(BG_PEEPHOLE)
	_show_current_visitor()


func _generate_visitors() -> void:
	current_visitors.clear()
	var day := int(state["day"])
	var rule := _rule_for_day(day)
	var count := rng.randi_range(int(rule["visitors_min"]), int(rule["visitors_max"]))
	if day == 9:
		count = maxi(count, 4)
	var fake_count := rng.randi_range(int(rule["fakes_min"]), int(rule["fakes_max"]))
	var mimic_count := 0
	if rng.randi_range(1, 100) <= int(rule["mimic_chance"]):
		mimic_count = 1
	if day >= 7 and rng.randi_range(1, 100) <= 35:
		mimic_count += 1
	if day == 9:
		mimic_count = maxi(1, mimic_count)
	var roles: Array = []
	for i in range(mimic_count):
		roles.append("mimic")
	for i in range(fake_count):
		roles.append("fake")
	while roles.size() < count:
		roles.append("human")
	roles.shuffle()

	var pool := []
	for c in characters:
		if c.get("id", "") != "taki_fake":
			pool.append(c)
	pool.shuffle()
	for i in range(count):
		var character: Dictionary
		if day == 9 and i == count - 1:
			character = _character_by_id("taki_fake")
			roles[i] = "mimic"
		else:
			character = pool[i % pool.size()]
		var event: Dictionary = door_events[rng.randi_range(0, door_events.size() - 1)]
		if day >= 4 and roles[i] == "human" and rng.randf() < 0.30:
			event = _door_event_by_id("visitor_chased")
		if day >= 5 and roles[i] != "human" and rng.randf() < 0.24:
			event = _door_event_by_id("visitor_duplicate")
		var visitor: Dictionary = {
			"character": character,
			"role": roles[i],
			"event": event,
			"evidence": _make_evidence(character, roles[i], event, day),
			"discovered": [],
			"asked": 0,
			"stress": rng.randi_range(35, 85),
			"decided": false
		}
		current_visitors.append(visitor)


func _make_evidence(character: Dictionary, role: String, event: Dictionary, day: int) -> Array:
	var evidence := []
	var mislead: Array = character.get("mislead", [])
	if role == "human":
		evidence.append(_clue("行为可疑", _pick(mislead), "behavior", false, 1))
		evidence.append(_clue("真实记忆", character.get("memory", ""), "memory", false, -1))
		if event.get("id", "") == "visitor_wrong_code":
			evidence.append(_clue("暗号解释", "她说收到的是旧暗号；今日暗号是“" + str(state.get("code_phrase", "未设定")) + "”，时间线能勉强对上。", "memory", false, -1))
		elif event.get("id", "") == "visitor_knows_inside":
			evidence.append(_clue("屋内细节", "她知道房间分配，但说法和线索板上的睡位一致。", "environment", false, -1))
		elif event.get("id", "") == "visitor_supplies":
			evidence.append(_clue("物资来源", "包装有雨水和便利店收据，来源大致可信。", "environment", false, -1))
		else:
			evidence.append(_clue("生理反应", "呼吸紊乱但有热雾，恐惧不像循环录音。", "breath", false, -1))
		return evidence

	if role == "mimic":
		var anchors := [
			_clue("影子延迟", "灯下的影子慢了半拍。", "shadow", true, 3),
			_clue("无呼吸", "她说完整句话，冷凝片几乎没有雾。", "breath", true, 3),
			_clue("称呼停顿", "她叫你名字前停顿，像在搜索称呼。", "memory", true, 2),
			_clue("情绪被压平", "她知道事实，却说不出那件事为什么痛。", "memory", true, 2),
			_clue("黑泥锚点", "指尖有和昨日门把上一样的黑泥。", "finger", true, 2)
		]
		anchors.shuffle()
		evidence.append(anchors[0])
		evidence.append(anchors[1])
		evidence.append(_clue("历史形态", "她提到一段只有失踪者才可能听见的脚步声。", "environment", true, 3))
		evidence.append(_clue("当前破绽", "她的" + character.get("short", "某人") + "式反应只有轮廓，没有重量。", "behavior", true, 2))
		return evidence

	var physical := []
	physical.append(_clue("完美牙齿", "牙齿整齐得像同一套白瓷，没有磨损。", "teeth", true, 2))
	if event.get("id", "") == "visitor_wrong_code" and !str(state.get("code_phrase", "")).is_empty():
		physical.append(_clue("暗号错位", "她复述暗号时把“" + str(state["code_phrase"]) + "”说成了上一夜的版本。", "memory", true, 3))
	elif event.get("id", "") == "visitor_knows_inside":
		physical.append(_clue("知道屋内", "她说出房间细节，却把今晚分配的睡位说反了。", "environment", true, 3))
	elif event.get("id", "") == "visitor_fake_radio":
		physical.append(_clue("假情报", "广播里的规则停顿太整齐，像从线索板反向拼出来。", "environment", true, 2))
	if day >= 2:
		physical.append(_clue("红虹膜", "虹膜边缘有不自然的红偏。", "iris", true, 2))
		physical.append(_clue("指尖黑泥", "指甲缝里有不属于走廊的黑泥。", "finger", true, 2))
	if day >= 3:
		physical.append(_clue("呼吸节拍错误", "她的喘息和说话没有同步。", "breath", true, 2))
		physical.append(_clue("影子错位", "门缝灯光下，影子比身体更早移动。", "shadow", true, 3))
	if day >= 4:
		physical.append(_clue("足迹灼痕", "足迹检测板边缘留下细小灼痕。", "footprint", true, 3))
	physical.shuffle()
	evidence.append(physical[0])
	evidence.append(_clue("记忆漏洞", "共同记忆里的顺序错了，她把结果说在原因前面。", "memory", true, 2))
	evidence.append(_clue("证词矛盾", "她的路线和门禁记录差了十二分钟。", "environment", true, 2))
	if day >= 6:
		evidence.append(_clue("诱导怀疑", "她不断把你的注意力推向另一个屋内的人。", "behavior", true, 2))
	return evidence


func _clue(title: String, text: String, category: String, incriminating: bool, weight: int) -> Dictionary:
	return {
		"title": title,
		"text": text,
		"category": category,
		"incriminating": incriminating,
		"weight": weight
	}


func _show_current_visitor() -> void:
	if current_visitor_index >= current_visitors.size():
		_show_investigation()
		return
	var visitor: Dictionary = current_visitors[current_visitor_index]
	var character: Dictionary = visitor["character"]
	var event: Dictionary = visitor["event"]
	_set_character_portrait(_portrait_for_visitor(visitor))
	title_label.text = "第 " + str(state["day"]) + " 夜 / 门外来访 " + str(current_visitor_index + 1) + "-" + str(current_visitors.size())
	subtitle_label.text = character.get("name", "") + " / " + event.get("name", "")
	event_label.text = "[color=#ffc878]" + event.get("name", "") + "[/color]\n" + event.get("hint", "")
	var intro := _visitor_intro(visitor)
	narrative.text = intro + "\n\n[color=#9ef0dc]已发现线索：" + str(visitor["discovered"].size()) + "/" + str(visitor["evidence"].size()) + "[/color]\n" + _visitor_clue_text(visitor)
	_update_panels()
	_clear_actions()
	question_input = LineEdit.new()
	question_input.placeholder_text = "自由盘问：输入你要问她的问题"
	question_input.custom_minimum_size = Vector2(0, 42)
	actions_box.add_child(question_input)
	_add_action("提交自由盘问（体力 2）", _ask_free_question)
	_add_action("普通盘问（体力 1）", _ask_basic)
	_add_action("深度盘问（体力 3，学习 +）", _ask_deep)
	_add_action(_inspect_action_label("牙齿检查", "teeth", 4), func(): _inspect_category("teeth", 4, "牙齿检查"))
	if state["day"] >= 2:
		_add_action(_inspect_action_label("虹膜检查", "iris", 4), func(): _inspect_category("iris", 4, "虹膜检查"))
		_add_action(_inspect_action_label("手指污垢检查", "finger", 3), func(): _inspect_category("finger", 3, "手指检查"))
	if state["day"] >= 3:
		_add_action(_inspect_action_label("呼吸/影子检测", "breath_shadow", 4), _inspect_breath_shadow)
	if state["day"] >= 4:
		_add_action(_inspect_action_label("足迹检测板", "footprint", 5), func(): _inspect_category("footprint", 5, "足迹检测"))
	_add_action(_inspect_action_label("查证路线与线索板", "environment", 4), func(): _inspect_category("environment", 4, "路线查证"))
	_add_action("开门放入屋内", func(): _decide_visitor("admit"))
	_add_action("放入隔离区", func(): _decide_visitor("quarantine"))
	_add_action("驱逐/拒绝开门", func(): _decide_visitor("reject"))
	if state["day"] >= 7:
		_add_action("使用驱逐装置（体力 15）", func(): _decide_visitor("gun"))


func _visitor_intro(visitor: Dictionary) -> String:
	var character: Dictionary = visitor["character"]
	var event: Dictionary = visitor["event"]
	var line: String = _dialogue_for(visitor, "intro")
	var text: String = "[color=#effff7]" + character.get("name", "") + "[/color] 站在猫眼后。\n"
	text += event.get("hint", "") + "\n\n"
	text += "[color=#ffc878]" + character.get("short", "") + "：[/color]“" + line + "”"
	return text


func _portrait_for_visitor(visitor: Dictionary) -> String:
	var character: Dictionary = visitor["character"]
	if character.get("id", "") == "taki_fake":
		return CHAR_RIKKI
	if visitor.get("role", "") == "human":
		return CHAR_HUMAN
	if visitor.get("role", "") == "fake":
		return CHAR_FAKE
	return CHAR_MIMIC


func _dialogue_for(visitor: Dictionary, mode: String) -> String:
	var character: Dictionary = visitor["character"]
	var role: String = visitor["role"]
	var event: Dictionary = visitor["event"]
	var short: String = character.get("short", "她")
	if character.get("id", "") == "taki_fake":
		if mode == "deep":
			return "你知道我会怎么选。问题是，你能证明你不是我吗？"
		return "开门。她们需要的是立希，不是一个躲在门后的记录员。"
	if role == "human":
		if event.get("id", "") == "visitor_chased":
			return "后面有声音，我不确定是不是人。你可以怀疑我，但先让我进隔离区。"
		if event.get("id", "") == "visitor_supplies":
			return "我带了吃的和药。你可以先检查袋子，别直接碰我的手。"
		if mode == "deep":
			return character.get("memory", "我记得那天的事。") + " 这种细节，伪装不出来吧？"
		return "我知道你必须怀疑。那就问，问到你觉得够为止。"
	if role == "mimic":
		if mode == "deep":
			return "证明……证明你要的证明。我可以学会你想听的每一种回答。"
		return "我是" + short + "。你一直都认识我。现在开门，别让外面继续看着我们。"
	if mode == "deep":
		return "你刚才问的是暗号，暗号就是……等一下，你最后说的那个词是什么？"
	return "别浪费时间。你越问，门外的东西越近。"


func _visitor_clue_text(visitor: Dictionary) -> String:
	var lines := []
	for clue in visitor["discovered"]:
		var color := "#ff8f8f" if clue.get("incriminating", false) else "#9ef0dc"
		lines.append("[color=" + color + "]" + clue["title"] + "[/color]：" + clue["text"])
	if lines.is_empty():
		return "\n尚未确认任何线索。"
	return "\n" + "\n".join(lines)


func _ask_free_question() -> void:
	if question_input == null:
		return
	var question := question_input.text.strip_edges()
	if question.is_empty():
		_notice("先输入一个问题。")
		return
	if !_spend_stamina(2):
		return
	var visitor: Dictionary = current_visitors[current_visitor_index]
	visitor["asked"] += 1
	if visitor["role"] == "mimic":
		state["mimic_learning"] = mini(100, state["mimic_learning"] + 3)
	elif visitor["role"] == "fake":
		state["mimic_learning"] = mini(100, state["mimic_learning"] + 1)
	var categories := _categories_for_question(question)
	var clue := _reveal_next_clue(visitor, categories, 72)
	var response := _free_dialogue_for(visitor, question, clue)
	if clue.is_empty():
		_log("自由盘问：" + question + " / 未得到新线索。")
	else:
		_log("自由盘问发现：" + clue["title"])
	_show_current_visitor_with_response(response)
	_request_backend_dialogue(visitor, question, clue)


func _toggle_backend() -> void:
	backend_enabled = !backend_enabled
	_show_title()


func _request_backend_dialogue(visitor: Dictionary, question: String, clue: Dictionary) -> void:
	if !backend_enabled or dialogue_http == null:
		return
	if dialogue_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var character: Dictionary = visitor["character"]
	var event: Dictionary = visitor["event"]
	var payload := {
		"session_id": session_id,
		"character_id": character.get("id", ""),
		"character_name": character.get("name", ""),
		"current_form": character.get("id", ""),
		"true_role": visitor.get("role", "human"),
		"location": "door",
		"day": int(state.get("day", 1)),
		"event_type": event.get("id", ""),
		"known_facts": visitor["discovered"].map(func(item): return item.get("title", "")),
		"forbidden_facts": ["不要改变身份真相", "不要决定生死", "不要创造新证据"],
		"personality": [character.get("tone", ""), character.get("normal", "")],
		"speech_style": character.get("tone", ""),
		"stress": int(visitor.get("stress", 50)),
		"trust": int(state.get("trust", 50)),
		"is_being_chased": bool(event.get("chased", false)),
		"player_message": question,
		"candidate_clue": clue if !clue.is_empty() else null
	}
	pending_backend_context = {
		"character": character.get("short", character.get("name", "")),
		"question": question
	}
	var err := dialogue_http.request(
		BACKEND_DIALOGUE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		_log("后端未连接，使用本地兜底对白。")


func _on_dialogue_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_log("后端表演请求失败，已保留本地对白。")
		_update_panels()
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if !(parsed is Dictionary):
		return
	var dialogue := str(parsed.get("dialogue", ""))
	if dialogue.is_empty():
		return
	var action := str(parsed.get("action", ""))
	var source := str(parsed.get("source", "backend"))
	narrative.text += "\n\n[color=#8ab4ff]后端表演 / " + source + "：[/color]“" + dialogue + "”"
	if !action.is_empty():
		narrative.text += "\n[color=#8ab4ff]" + action + "[/color]"
	_log("后端表演完成：" + source)
	_update_panels()


func _categories_for_question(question: String) -> Array:
	var q := question.to_lower()
	var categories := []
	if q.contains("牙") or q.contains("teeth"):
		categories.append("teeth")
	if q.contains("眼") or q.contains("虹膜") or q.contains("iris"):
		categories.append("iris")
	if q.contains("手") or q.contains("指") or q.contains("泥") or q.contains("finger"):
		categories.append("finger")
	if q.contains("脚") or q.contains("足") or q.contains("foot"):
		categories.append("footprint")
	if q.contains("呼吸") or q.contains("喘") or q.contains("breath"):
		categories.append("breath")
	if q.contains("影") or q.contains("灯") or q.contains("shadow"):
		categories.append("shadow")
	if q.contains("暗号") or q.contains("昨天") or q.contains("记得") or q.contains("memory"):
		categories.append("memory")
	if q.contains("哪里") or q.contains("路线") or q.contains("谁") or q.contains("证据"):
		categories.append("environment")
	if categories.is_empty():
		categories.append("behavior")
		categories.append("memory")
	return categories


func _free_dialogue_for(visitor: Dictionary, question: String, clue: Dictionary) -> String:
	var character: Dictionary = visitor["character"]
	var role: String = visitor["role"]
	var short: String = character.get("short", "她")
	if role == "human":
		if clue.is_empty():
			return "你问“" + question + "”？我知道这听起来不够，但我现在只能把我记得的都说出来。"
		return "你问得太细了……可是对，" + clue.get("text", "这件事是真的。")
	if role == "mimic":
		if clue.is_empty():
			return "“" + question + "”。她重复了一遍问题，像在确认你的期待。"
		return "它停了一下。" + clue.get("text", "") + " 然后才用" + short + "的声音继续回答。"
	if clue.is_empty():
		return "这重要吗？你一直问，外面就一直有时间靠近。"
	return "她的回答很快，快到像提前背过。" + clue.get("text", "")


func _ask_basic() -> void:
	if !_spend_stamina(1):
		return
	var visitor: Dictionary = current_visitors[current_visitor_index]
	visitor["asked"] += 1
	var clue := _reveal_next_clue(visitor, ["memory", "behavior"], 55)
	var response := _dialogue_for(visitor, "basic")
	if clue.is_empty():
		_log(visitor["character"].get("short", "") + "回答了问题，但没有新线索。")
	else:
		_log("盘问发现：" + clue["title"])
	_show_current_visitor_with_response(response)


func _ask_deep() -> void:
	if !_spend_stamina(3):
		return
	var visitor: Dictionary = current_visitors[current_visitor_index]
	visitor["asked"] += 2
	state["mimic_learning"] = mini(100, state["mimic_learning"] + (4 if visitor["role"] == "mimic" else 1))
	var clue := _reveal_next_clue(visitor, ["memory", "behavior", "environment", "breath", "shadow", "finger", "teeth", "iris", "footprint"], 85)
	var response := _dialogue_for(visitor, "deep")
	if clue.is_empty():
		_log("深度盘问没有新增证据，伪人学习仍在上升。")
	else:
		_log("深度盘问发现：" + clue["title"])
	_show_current_visitor_with_response(response)


func _detector_label(focus: String) -> String:
	match focus:
		"teeth":
			return "牙齿检查"
		"iris":
			return "虹膜检查"
		"finger":
			return "指泥检查"
		"breath_shadow":
			return "呼吸/影子检测"
		"footprint":
			return "足迹检测板"
		"environment":
			return "路线与线索板"
		_:
			return "未指定"


func _detector_matches(category: String) -> bool:
	var focus := str(state.get("detector_focus", "none"))
	if focus == category:
		return true
	return focus == "breath_shadow" and (category == "breath" or category == "shadow")


func _inspection_cost(category: String, base_cost: int) -> int:
	return maxi(1, base_cost - (2 if _detector_matches(category) else 0))


func _inspection_chance(category: String, base_chance: int) -> int:
	return mini(98, base_chance + (6 if _detector_matches(category) else 0))


func _inspect_action_label(label: String, category: String, base_cost: int) -> String:
	var cost := _inspection_cost(category, base_cost)
	var suffix := " / 重点" if _detector_matches(category) else ""
	return label + "（体力 " + str(cost) + suffix + "）"


func _inspect_breath_shadow() -> void:
	var cost := _inspection_cost("breath_shadow", 4)
	if !_spend_stamina(cost):
		return
	var visitor: Dictionary = current_visitors[current_visitor_index]
	var clue := _reveal_next_clue(visitor, ["breath", "shadow"], _inspection_chance("breath_shadow", 90))
	if clue.is_empty():
		_log("呼吸/影子检测未发现明确异常。")
	else:
		_log("检测发现：" + clue["title"])
	_show_current_visitor()


func _inspect_category(category: String, cost: int, label: String) -> void:
	var actual_cost := _inspection_cost(category, cost)
	if !_spend_stamina(actual_cost):
		return
	var visitor: Dictionary = current_visitors[current_visitor_index]
	var clue := _reveal_next_clue(visitor, [category], _inspection_chance(category, 92))
	if clue.is_empty():
		_log(label + "没有发现明确异常。")
	else:
		_log(label + "发现：" + clue["title"])
	_show_current_visitor()


func _show_current_visitor_with_response(response: String) -> void:
	_show_current_visitor()
	var visitor: Dictionary = current_visitors[current_visitor_index]
	var character: Dictionary = visitor["character"]
	narrative.text += "\n\n[color=#ffc878]" + character.get("short", "") + "：[/color]“" + response + "”"


func _reveal_next_clue(visitor: Dictionary, categories: Array, chance: int) -> Dictionary:
	if rng.randi_range(1, 100) > chance:
		return {}
	for clue in visitor["evidence"]:
		if clue in visitor["discovered"]:
			continue
		if categories.has(clue.get("category", "")):
			visitor["discovered"].append(clue)
			_add_evidence(visitor, clue)
			return clue
	for clue in visitor["evidence"]:
		if !(clue in visitor["discovered"]):
			visitor["discovered"].append(clue)
			_add_evidence(visitor, clue)
			return clue
	return {}


func _add_evidence(visitor: Dictionary, clue: Dictionary) -> void:
	var character: Dictionary = visitor["character"]
	var entry: String = character.get("short", "") + " / " + clue["title"] + "：" + clue["text"]
	state["evidence"].append(entry)
	if state["evidence"].size() > 24:
		state["evidence"].pop_front()


func _decide_visitor(decision: String) -> void:
	var visitor: Dictionary = current_visitors[current_visitor_index]
	var character: Dictionary = visitor["character"]
	var role: String = visitor["role"]
	var clue_score := _clue_score(visitor)
	if decision == "gun":
		if !_spend_stamina(15):
			return
		if state["day"] < 7:
			_notice("驱逐装置还不可用。")
			return
	if decision == "quarantine":
		if state["quarantine_used"] >= 2:
			_notice("今晚隔离区已经使用到极限。")
			return
		if state["quarantine"] <= 0:
			_notice("隔离区已经损坏。")
			return
		state["quarantine_used"] += 1
		_apply_quarantine(visitor, clue_score)
	elif decision == "admit":
		_apply_admit(visitor, clue_score)
	elif decision == "reject":
		_apply_reject(visitor, clue_score)
	elif decision == "gun":
		_apply_gun(visitor, clue_score)
	visitor["decided"] = true
	current_visitor_index += 1
	_check_immediate_failure()
	if current_phase == "ending":
		return
	_show_current_visitor()


func _clue_score(visitor: Dictionary) -> int:
	var score := 0
	for clue in visitor["discovered"]:
		score += int(clue.get("weight", 0))
	return score


func _apply_admit(visitor: Dictionary, clue_score: int) -> void:
	var character: Dictionary = visitor["character"]
	var role: String = visitor["role"]
	state["refusal_streak"] = 0
	if role == "human":
		state["humans_inside"] += 1
		state["trust"] = mini(100, state["trust"] + 4)
		if visitor["event"].get("id", "") == "visitor_supplies":
			state["supplies"] = mini(100, state["supplies"] + 18)
		_log(character.get("short", "") + "被放入屋内。她是真的，但屋内也因此更拥挤。")
	elif role == "fake":
		state["fakes_inside"] += 1
		state["contamination"] = mini(100, state["contamination"] + 12)
		state["trust"] = maxi(0, state["trust"] - 9)
		_log("你放入了伪装成" + character.get("short", "") + "的伪人。屋内空气变冷。")
	else:
		state["mimics_inside"] += 1
		state["contamination"] = mini(100, state["contamination"] + 20)
		state["mimic_learning"] = mini(100, state["mimic_learning"] + 12)
		if character.get("id", "") == "taki_fake":
			final_mimic_mishandled = true
		_log("变身怪被放入屋内。它开始学习每个人的站姿。")


func _apply_quarantine(visitor: Dictionary, clue_score: int) -> void:
	var character: Dictionary = visitor["character"]
	var role: String = visitor["role"]
	state["refusal_streak"] = 0
	if role == "human":
		state["humans_inside"] += 1
		state["trust"] = mini(100, state["trust"] + 1)
		state["quarantine"] = maxi(0, state["quarantine"] - rng.randi_range(4, 10))
		_log(character.get("short", "") + "进入隔离区。她活下来了，但被玻璃隔开。")
	elif role == "fake":
		state["quarantine"] = maxi(0, state["quarantine"] - rng.randi_range(16, 34))
		if clue_score >= 3:
			_log("伪人被关进隔离区，冲击后暴露形态。")
		else:
			state["fakes_inside"] += 1
			state["contamination"] = mini(100, int(state["contamination"]) + 6)
			_log("隔离区收容了可疑目标，但证据不足，它留下了污染。")
	else:
		state["quarantine"] = maxi(0, state["quarantine"] - rng.randi_range(32, 58))
		state["mimic_learning"] = mini(100, state["mimic_learning"] + 6)
		if character.get("id", "") == "taki_fake" and clue_score >= 4:
			final_mimic_identified = true
		_log("变身怪撞上隔离玻璃，灯光里影子慢了半拍。")


func _apply_reject(visitor: Dictionary, clue_score: int) -> void:
	var character: Dictionary = visitor["character"]
	var role: String = visitor["role"]
	state["refusal_streak"] += 1
	if role == "human":
		state["missing"] += 1
		state["abandonment"] = mini(10, state["abandonment"] + (2 if visitor["event"].get("chased", false) else 1))
		state["trust"] = maxi(0, state["trust"] - 8)
		if rng.randi_range(1, 100) <= 45 + int(state["outside_danger"]):
			state["stolen"] += 1
			_log("你拒绝了真正的" + character.get("short", "") + "。走廊安静后，她的身份进入可盗用池。")
		else:
			_log("你拒绝了真正的" + character.get("short", "") + "。屋内没人说话。")
	elif role == "fake":
		state["outside_danger"] = mini(100, state["outside_danger"] + 2)
		state["trust"] = mini(100, state["trust"] + 2)
		_log("伪人被留在门外。门板另一侧传来很轻的笑声。")
	else:
		state["outside_danger"] = mini(100, state["outside_danger"] + 5)
		state["mimic_learning"] = mini(100, state["mimic_learning"] + 3)
		if character.get("id", "") == "taki_fake":
			if clue_score >= 4:
				final_mimic_identified = true
			else:
				final_mimic_mishandled = true
		_log("你没有开门。那张脸在猫眼后退了一步，却没有离开。")


func _apply_gun(visitor: Dictionary, clue_score: int) -> void:
	var character: Dictionary = visitor["character"]
	var role: String = visitor["role"]
	state["refusal_streak"] = 0
	if role == "human" and clue_score < 3:
		state["missing"] += 1
		state["abandonment"] = mini(10, state["abandonment"] + 3)
		state["trust"] = maxi(0, state["trust"] - 18)
		_log("驱逐装置误伤了真正的" + character.get("short", "") + "。海铃什么也没说。")
	elif role == "human":
		state["trust"] = maxi(0, state["trust"] - 10)
		_log(character.get("short", "") + "被强制驱离。她也许是真的，但你没有留下余地。")
	else:
		state["contamination"] = maxi(0, state["contamination"] - 4)
		if role == "mimic" and character.get("id", "") == "taki_fake" and clue_score >= 4:
			final_mimic_identified = true
		_log("驱逐装置启动，门外的轮廓像湿纸一样塌陷。")


func _show_investigation() -> void:
	current_phase = "investigation"
	_set_background(BG_ROOM)
	_hide_character_portrait()
	title_label.text = "第 " + str(state["day"]) + " 夜 / 室内排查"
	subtitle_label.text = "门外来访结束，真正危险可能已经进屋。"
	event_label.text = "[color=#ffc878]室内排查[/color]\n在睡前，你还能处理一次屋内风险。"
	narrative.text = "[color=#effff7]门锁暂时安静。[/color]\n\n屋内的人不全可信，线索板也未必可信。你可以用最后的体力清理一个风险点。"
	_update_panels()
	_clear_actions()
	_add_action("搜查房间（体力 6）", _investigate_room)
	_add_action("交叉质问屋内成员（体力 4）", _cross_question)
	_add_action("让乐奈凭直觉指出危险（体力 3）", _rana_hint)
	_add_action("请爽世照顾伤员（物资 6）", _soyo_care)
	_add_action("熬夜守到天亮（体力 35）", _guard_until_dawn)
	_add_action("睡觉", _start_sleep)


func _investigate_room() -> void:
	if !_spend_stamina(6):
		return
	state["room_search_bonus"] = 1
	if state["fakes_inside"] > 0 and rng.randi_range(1, 100) <= 60 + int(state["evidence_integrity"]) / 4:
		state["fakes_inside"] -= 1
		state["contamination"] = maxi(0, state["contamination"] - 6)
		_log("房间搜查发现伪人的藏身痕迹，并把它逼回门外。")
	else:
		state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 6)
		_log("你重新标记了房间和线索，但没有抓到人。")
	_show_investigation()


func _cross_question() -> void:
	if !_spend_stamina(4):
		return
	if state["mimics_inside"] > 0 and rng.randi_range(1, 100) <= 45:
		state["mimics_inside"] -= 1
		state["quarantine"] = maxi(0, state["quarantine"] - 18)
		_log("交叉质问逼出一个变身怪。它撞碎隔离门内侧玻璃。")
	else:
		state["mimic_learning"] = mini(100, state["mimic_learning"] + 5)
		state["trust"] = maxi(0, state["trust"] - 3)
		_log("交叉质问让大家更紧张，伪人也学到更多回答。")
	_show_investigation()


func _rana_hint() -> void:
	if !_spend_stamina(3):
		return
	if state["fakes_inside"] + state["mimics_inside"] > 0:
		state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 8)
		_log("乐奈盯着走廊说：'那个，不有趣。' 线索板上一个名字被圈出。")
	else:
		state["trust"] = mini(100, state["trust"] + 2)
		_log("乐奈在沙发上睡着了。今晚屋内暂时没有她讨厌的味道。")
	_show_investigation()


func _soyo_care() -> void:
	if state["supplies"] < 6:
		_notice("物资不足，无法安排照顾。")
		return
	state["supplies"] -= 6
	state["trust"] = mini(100, state["trust"] + 6)
	state["stamina"] = mini(state["stamina_max"], state["stamina"] + 8)
	_log("爽世把水和药分好。温柔本身也可能是一种秩序。")
	_show_investigation()


func _guard_until_dawn() -> void:
	if !_spend_stamina(35):
		return
	state["guarded"] = true
	state["contamination"] = mini(100, state["contamination"] + 3)
	_log("你熬夜守到天亮。猫眼里的黑点像眼睛一样睁着。")
	_dawn_settlement([])


func _start_sleep() -> void:
	current_phase = "sleep"
	var rule := _rule_for_day(state["day"])
	var count := rng.randi_range(int(rule["sleep_min"]), int(rule["sleep_max"]))
	if state["guarded"]:
		count = maxi(0, count - 1)
	var picked := []
	var pool := sleep_events.duplicate()
	pool.shuffle()
	for i in range(count):
		picked.append(pool[i % pool.size()])
	if picked.is_empty():
		_log("这一觉没有被打断。")
		_dawn_settlement([])
	else:
		_show_sleep_event(picked, 0)


func _show_sleep_event(events: Array, index: int) -> void:
	if index >= events.size():
		_dawn_settlement(events)
		return
	_hide_character_portrait()
	var ev: Dictionary = events[index]
	title_label.text = "第 " + str(state["day"]) + " 夜 / 睡眠事件"
	subtitle_label.text = ev.get("name", "")
	event_label.text = "[color=#ff8f8f]" + ev.get("name", "") + "[/color]\n醒来会损失体力，不醒来会丢线索。"
	narrative.text = "[color=#effff7]" + ev.get("text", "") + "[/color]\n\n你能听见自己的呼吸。门外，或屋内，有什么东西也在听。"
	_update_panels()
	_clear_actions()
	_add_action("起床查看（体力 8）", func(): _resolve_sleep_event(events, index, "check"))
	_add_action("从门缝观察（体力 4）", func(): _resolve_sleep_event(events, index, "peek"))
	_add_action("拿手电筒查看（体力 6，物资 1）", func(): _resolve_sleep_event(events, index, "flashlight"))
	_add_action("锁门继续睡（门锁 -3）", func(): _resolve_sleep_event(events, index, "lock_sleep"))
	_add_action("装睡", func(): _resolve_sleep_event(events, index, "ignore"))
	_add_action("叫醒可信的人（信任 -3）", func(): _resolve_sleep_event(events, index, "call"))


func _resolve_sleep_event(events: Array, index: int, choice: String) -> void:
	var ev: Dictionary = events[index]
	if choice == "check":
		if !_spend_stamina(8):
			return
		state["contamination"] = mini(100, state["contamination"] + 2)
		if ev.get("id", "") == "sleep_clueboard":
			state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 10)
			_log("你抓到线索板被挪动的痕迹。证据可信度上升。")
		elif ev.get("id", "") == "sleep_door_unlock":
			state["door"] = maxi(0, state["door"] - 4)
			_log("你及时按住门锁，但金属已经变形。")
		elif ev.get("id", "") == "sleep_mirror_delay":
			state["contamination"] = mini(100, state["contamination"] + 8)
			_log("镜中的延迟变成新的污染证据。")
		else:
			state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 4)
			_log("你查看了" + ev.get("name", "") + "，得到一条模糊线索。")
	elif choice == "peek":
		if !_spend_stamina(4):
			return
		state["contamination"] = mini(100, state["contamination"] + 4)
		if ev.get("id", "") == "sleep_bedside":
			state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 8)
			_log("你从门缝看见床边人影的脚尖没有影子。")
		elif ev.get("id", "") == "sleep_window_tap":
			state["outside_danger"] = mini(100, state["outside_danger"] + 4)
			_log("你从门缝看见窗外有东西学着暗号敲击。")
		else:
			state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 5)
			_log("你从门缝观察，没有暴露位置，但污染像冷雾一样贴近。")
	elif choice == "flashlight":
		if state["supplies"] < 1:
			_notice("手电没有备用电池。")
			return
		if !_spend_stamina(6):
			return
		state["supplies"] -= 1
		state["evidence_integrity"] = mini(100, state["evidence_integrity"] + 12)
		if ev.get("id", "") == "sleep_door_unlock":
			state["door"] = maxi(0, state["door"] - 2)
			_log("手电光照到门锁上的新划痕，你及时压住锁舌。")
		elif ev.get("id", "") == "sleep_clueboard":
			_log("手电光下，线索卡边缘露出新折痕。篡改顺序被记录。")
		else:
			state["mimic_learning"] = mini(100, state["mimic_learning"] + 2)
			_log("手电照亮了异常，也暴露了你会优先看哪里。")
	elif choice == "lock_sleep":
		state["door"] = maxi(0, state["door"] - 3)
		if ev.get("id", "") == "sleep_door_unlock":
			state["door"] = maxi(0, state["door"] - 8)
			_log("你反锁卧室继续睡。玄关锁撑住了，但金属疲劳更严重。")
		elif ev.get("id", "") == "sleep_crying":
			state["trust"] = maxi(0, state["trust"] - 5)
			state["abandonment"] = mini(10, state["abandonment"] + 1)
			_log("你锁门继续睡。哭声停了，屋内信任也少了一截。")
		else:
			state["stamina"] = mini(state["stamina_max"], state["stamina"] + 8)
			_log("你锁门继续睡，换来一点体力，也放弃了一条夜间线索。")
	elif choice == "call":
		var trust_cost := 1 if bool(state.get("supplies_distributed", false)) else 3
		state["trust"] = maxi(0, state["trust"] - trust_cost)
		if state["humans_inside"] > 0:
			state["contamination"] = maxi(0, state["contamination"] - 1)
			_log("有人陪你查看，恐惧被分摊了一点。" + ("提前分配的物资让大家少了些怨气。" if trust_cost == 1 else ""))
		else:
			state["mimic_learning"] = mini(100, state["mimic_learning"] + 5)
			_log("你叫来的声音不太像你记得的那个人。")
	else:
		if ev.get("id", "") == "sleep_door_unlock":
			state["door"] = maxi(0, state["door"] - rng.randi_range(10, 22))
		elif ev.get("id", "") == "sleep_clueboard":
			state["evidence_integrity"] = maxi(0, state["evidence_integrity"] - rng.randi_range(10, 24))
		else:
			state["contamination"] = mini(100, state["contamination"] + 3)
		_log("你选择装睡。早上醒来时，屋里有东西变了。")
	_show_sleep_event(events, index + 1)


func _dawn_settlement(_events: Array) -> void:
	current_phase = "dawn"
	_set_background(BG_ROOM)
	_hide_character_portrait()
	var fake_pressure := int(state["fakes_inside"]) * rng.randi_range(7, 14) + int(state["mimics_inside"]) * rng.randi_range(12, 22)
	if bool(state.get("rooms_assigned", false)):
		fake_pressure = int(round(float(fake_pressure) * 0.75))
		if fake_pressure > 0:
			_log("房间分配延缓了屋内污染扩散。")
	if fake_pressure > 0:
		state["contamination"] = mini(100, state["contamination"] + fake_pressure / 2)
		state["door"] = maxi(0, state["door"] - fake_pressure / 3)
		state["trust"] = maxi(0, state["trust"] - fake_pressure / 4)
		if rng.randi_range(1, 100) <= fake_pressure:
			state["missing"] += 1
			state["stolen"] += 1
			_log("黎明前有人失踪，身份被盗用池扩大。")
	var food_cost := 8 + int(state["humans_inside"]) * 2
	state["supplies"] = maxi(0, state["supplies"] - food_cost)
	if state["supplies"] < 25:
		state["stamina_max"] = maxi(70, 100 - (25 - int(state["supplies"])))
	else:
		state["stamina_max"] = 100
	var recovery := 45
	if state["guarded"]:
		recovery += 15
	if state["contamination"] > 60:
		recovery -= 10
	state["stamina"] = mini(state["stamina_max"], maxi(0, state["stamina"]) + recovery)
	state["outside_danger"] = mini(100, state["outside_danger"] + int(state["abandonment"]) * 2 + int(state["stolen"]) * 2)
	_log("黎明结算：消耗物资 " + str(food_cost) + "，恢复体力 " + str(recovery) + "。")
	title_label.text = "第 " + str(state["day"]) + " 夜 / 黎明"
	subtitle_label.text = "天亮并不代表安全，只代表你还能记录。"
	event_label.text = "[color=#9ef0dc]黎明结算[/color]\n下一夜危险度：" + str(state["outside_danger"])
	narrative.text = _dawn_text()
	_update_panels()
	_clear_actions()
	_check_immediate_failure()
	if current_phase == "ending":
		return
	if state["day"] >= 9:
		_show_ending(_judge_final_ending())
	else:
		_add_action("进入下一夜", func():
			state["day"] = int(state["day"]) + 1
			_begin_day()
		)


func _dawn_text() -> String:
	var text := "[color=#effff7]天亮了。[/color]\n\n"
	text += "门锁：" + str(state["door"]) + " / 隔离区：" + str(state["quarantine"]) + "\n"
	text += "屋内可信人类：" + str(state["humans_inside"]) + " / 入侵伪人：" + str(state["fakes_inside"] + state["mimics_inside"]) + "\n"
	text += "失踪：" + str(state["missing"]) + " / 身份被盗：" + str(state["stolen"]) + "\n\n"
	if state["evidence_integrity"] < 45:
		text += "[color=#ff8f8f]线索板上有几张卡片的位置不对。[/color]\n"
	if state["trust"] < 35:
		text += "[color=#ff8f8f]屋内的人开始怀疑你不是唯一的立希。[/color]\n"
	if state["supplies"] < 20:
		text += "[color=#ffc878]物资不足，明天体力上限会继续下降。[/color]\n"
	return text


func _judge_final_ending() -> String:
	var trusted_humans := int(state["humans_inside"]) - int(state["missing"])
	if final_mimic_mishandled:
		return "hidden"
	if final_mimic_identified and trusted_humans >= 3 and int(state["contamination"]) < 70:
		return "true"
	if int(state["abandonment"]) >= 8:
		return "no_one"
	if int(state["contamination"]) >= 90:
		return "purple"
	if int(state["stolen"]) >= 5:
		return "identity"
	if int(state["fakes_inside"]) + int(state["mimics_inside"]) >= maxi(3, trusted_humans):
		return "perfect_band"
	if trusted_humans >= 2:
		return "good"
	return "neutral"


func _check_immediate_failure() -> void:
	if int(state["door"]) <= 0:
		_show_ending("door")
	elif int(state["contamination"]) >= 100:
		_show_ending("purple")
	elif int(state["abandonment"]) >= 10:
		_show_ending("no_one")


func _show_ending(kind: String) -> void:
	current_phase = "ending"
	_hide_character_portrait()
	if kind == "hidden":
		_set_background(BG_FINAL)
	else:
		_set_background(BG_ROOM)
	var title := ""
	var body := ""
	match kind:
		"true":
			title = "True End：《猫眼之后》"
			body = "第九夜的变身怪被识别。天亮后，猫眼外空无一人。\n你留下了至少三个还能互相证明的人，也留下了怀疑本身。"
		"good":
			title = "Good End：《天亮了》"
			body = "你活过九夜。门还在，屋内仍有人会回答你的名字。\n只是线索板上仍有几个问题没有结案。"
		"neutral":
			title = "Neutral End：《只剩安全》"
			body = "你活了下来，但大多数名字停在失踪栏里。\n安全屋没有被攻破，只是里面越来越空。"
		"no_one":
			title = "Bad End：《无人入内》"
			body = "你守住了门，也拒绝了所有还在敲门的人。\n群聊头像一个接一个变灰，最后连通知声也消失。"
		"perfect_band":
			title = "Bad End：《完美乐队》"
			body = "每个人都开始用同样的节奏呼吸，同样的角度微笑。\n这支乐队终于没有任何分歧。"
		"purple":
			title = "Bad End：《紫色是偏红的蓝色》"
			body = "污染值越过阈值。海铃举起驱逐装置，问你最后一个问题：\n'你怎么证明你还站在门内？'"
		"identity":
			title = "Bad End：《身份被盗》"
			body = "失踪者陆续回来了。她们知道暗号，知道房间，知道你的语气。\n只有真正的她们不再需要开门。"
		"door":
			title = "Bad End：《门锁之后》"
			body = "门锁耐久归零。玄关门没有被撞开，只是自己慢慢松开。\n你听见屋内所有人同时转头。"
		"hidden":
			title = "Hidden End：《另一个立希》"
			body = "第九夜，猫眼外站着另一个立希。\n她知道你的每个决定，却不知道你为什么仍然想救人。"
		_:
			title = "End：《规则失真》"
			body = "电视显示 Human / Alternate 的乱码。你无法再证明任何单条规则。"
	title_label.text = "结局"
	subtitle_label.text = title
	event_label.text = "[color=#ff8f8f]" + title + "[/color]\nSeed " + str(current_seed)
	narrative.text = "[font_size=28][color=#effff7]" + title + "[/color][/font_size]\n\n" + body + "\n\n[color=#9ef0dc]最终记录[/color]\n" + _final_stats()
	_update_panels()
	_clear_actions()
	_add_action("重新开始", _show_title)


func _final_stats() -> String:
	return "可信人类：" + str(state.get("humans_inside", 0)) + "\n伪人入侵：" + str(int(state.get("fakes_inside", 0)) + int(state.get("mimics_inside", 0))) + "\n失踪：" + str(state.get("missing", 0)) + "\n身份被盗：" + str(state.get("stolen", 0)) + "\n污染：" + str(state.get("contamination", 0)) + "\n见死不救：" + str(state.get("abandonment", 0))


func _update_panels() -> void:
	if state.is_empty():
		return
	var status := ""
	status += "[color=#9ef0dc]Day[/color] " + str(state["day"]) + " / 9\n"
	status += _bar("体力", state["stamina"], state["stamina_max"], "#9ef0dc")
	status += _bar("污染", state["contamination"], 100, "#ff6d7a")
	status += _bar("门锁", state["door"], 100, "#ffc878")
	status += _bar("隔离", state["quarantine"], 100, "#8ab4ff")
	status += _bar("物资", state["supplies"], 100, "#d5e878")
	status += "\n信任：" + str(state["trust"]) + "\n见死不救：" + str(state["abandonment"]) + "/10\n外部危险：" + str(state["outside_danger"]) + "\n线索可信：" + str(state["evidence_integrity"]) + "\n伪人学习：" + str(state["mimic_learning"]) + "\n"
	status += "暗号：" + (str(state.get("code_phrase", "")) if !str(state.get("code_phrase", "")).is_empty() else "未设定") + "\n"
	status += "重点检测：" + _detector_label(str(state.get("detector_focus", "none"))) + "\n"
	status += "房间分配：" + ("已完成" if bool(state.get("rooms_assigned", false)) else "未完成") + "\n"
	status += "物资分配：" + ("已完成" if bool(state.get("supplies_distributed", false)) else "未完成") + "\n"
	stats_label.text = status
	var board := "[color=#ffc878]最近记录[/color]\n" + _recent_lines(state["log"], 10)
	board += "\n\n[color=#9ef0dc]证据[/color]\n" + _recent_lines(state["evidence"], 12)
	board_label.text = board


func _bar(label: String, value, max_value, color: String) -> String:
	var max_v := maxf(1.0, float(max_value))
	var ratio := clampf(float(value) / max_v, 0.0, 1.0)
	var filled := int(round(ratio * 10.0))
	var text := "[color=" + color + "]" + label + "[/color] "
	for i in range(10):
		text += "█" if i < filled else "░"
	text += " " + str(int(value)) + "/" + str(int(max_value)) + "\n"
	return text


func _recent_lines(items: Array, count: int) -> String:
	if items.is_empty():
		return "无"
	var start := maxi(0, items.size() - count)
	var lines := []
	for i in range(start, items.size()):
		lines.append("- " + str(items[i]))
	return "\n".join(lines)


func _clear_actions() -> void:
	for child in actions_box.get_children():
		child.queue_free()


func _add_action(text: String, callable: Callable, tooltip := "") -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0, 42)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callable)
	actions_box.add_child(button)


func _spend_stamina(cost: int) -> bool:
	if int(state["stamina"]) < cost:
		_notice("体力不足。你不能靠意志无限盘问。")
		return false
	state["stamina"] = maxi(0, int(state["stamina"]) - cost)
	if int(state["stamina"]) == 0:
		state["contamination"] = mini(100, int(state["contamination"]) + 8)
		_log("体力耗尽，视野边缘出现猫眼一样的黑圈。")
	_update_panels()
	return true


func _notice(text: String) -> void:
	event_label.text = "[color=#ff8f8f]无法执行[/color]\n" + text


func _log(text: String) -> void:
	state["log"].append("D" + str(state.get("day", "?")) + " " + text)
	if state["log"].size() > 40:
		state["log"].pop_front()


func _rule_for_day(day: int) -> Dictionary:
	for rule in day_rules:
		if int(rule.get("day", 0)) == day:
			return rule
	return day_rules.back() if !day_rules.is_empty() else {}


func _character_by_id(id: String) -> Dictionary:
	for c in characters:
		if c.get("id", "") == id:
			return c
	return characters[0] if !characters.is_empty() else {}


func _door_event_by_id(id: String) -> Dictionary:
	for ev in door_events:
		if ev.get("id", "") == id:
			return ev
	return door_events[0] if !door_events.is_empty() else {}


func _pick(items: Array) -> String:
	if items.is_empty():
		return ""
	return str(items[rng.randi_range(0, items.size() - 1)])
