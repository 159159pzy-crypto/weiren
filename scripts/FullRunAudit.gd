extends SceneTree

var scene: Node

func _initialize() -> void:
	scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var results := []
	results.append(await _run_strategy("audit-true", "truth"))
	results.append(await _run_strategy("audit-refuse", "refuse"))
	results.append(await _run_strategy("audit-chaos", "chaos"))
	print("FULL_RUN_AUDIT_OK ", JSON.stringify(results))
	quit()


func _run_strategy(seed_text: String, strategy: String) -> Dictionary:
	scene._show_title()
	scene.seed_input.text = seed_text
	scene._start_new_game()
	await process_frame
	var guard := 0
	while scene.current_phase != "ending" and guard < 400:
		guard += 1
		match scene.current_phase:
			"prep":
				scene._start_visitors()
			"door":
				_play_door_strategy(strategy)
			"investigation":
				scene._start_sleep()
			"sleep":
				scene._dawn_settlement([])
			"dawn":
				if int(scene.state.get("day", 1)) >= 9:
					scene._show_ending(scene._judge_final_ending())
				else:
					scene.state["day"] = int(scene.state.get("day", 1)) + 1
					scene._begin_day()
			_:
				break
		await process_frame
	assert(scene.current_phase == "ending")
	return {
		"strategy": strategy,
		"seed": seed_text,
		"day": scene.state.get("day", 0),
		"humans": scene.state.get("humans_inside", 0),
		"fakes": int(scene.state.get("fakes_inside", 0)) + int(scene.state.get("mimics_inside", 0)),
		"missing": scene.state.get("missing", 0),
		"contamination": scene.state.get("contamination", 0),
	}


func _play_door_strategy(strategy: String) -> void:
	if scene.current_visitor_index >= scene.current_visitors.size():
		scene._show_investigation()
		return
	var visitor: Dictionary = scene.current_visitors[scene.current_visitor_index]
	match strategy:
		"truth":
			if visitor["role"] == "human":
				scene._decide_visitor("admit")
			else:
				_reveal_all(visitor)
				scene._decide_visitor("reject")
		"refuse":
			scene._decide_visitor("reject")
		"chaos":
			if int(scene.current_visitor_index) % 2 == 0:
				scene._decide_visitor("admit")
			else:
				scene._decide_visitor("quarantine")
		_:
			scene._decide_visitor("reject")


func _reveal_all(visitor: Dictionary) -> void:
	for clue in visitor["evidence"]:
		if !(clue in visitor["discovered"]):
			visitor["discovered"].append(clue)
			scene._add_evidence(visitor, clue)
