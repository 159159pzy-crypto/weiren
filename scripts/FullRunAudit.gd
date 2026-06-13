extends SceneTree

var scene: Node

func _initialize() -> void:
	var results := []
	for spec in [["audit-true", "truth"], ["audit-refuse", "refuse"], ["audit-chaos", "chaos"]]:
		var result: Dictionary = await _run_strategy(spec[0], spec[1])
		if bool(result.get("failed", false)):
			quit(1)
			return
		results.append(result)
	print("FULL_RUN_AUDIT_OK ", JSON.stringify(results))
	quit()


func _run_strategy(seed_text: String, strategy: String) -> Dictionary:
	if scene != null:
		scene.queue_free()
		scene = null
		await process_frame
	scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._show_title()
	scene.seed_input.text = seed_text
	scene._start_new_game()
	await process_frame
	var guard := 0
	while scene.current_phase != "ending" and guard < 1000:
		guard += 1
		match scene.current_phase:
			"prep":
				_play_prep_strategy(strategy)
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
	if scene.current_phase != "ending":
		push_error("Full run audit did not reach ending for " + strategy + ": phase=" + str(scene.current_phase) + " day=" + str(scene.state.get("day", "?")))
		return {"failed": true, "strategy": strategy}
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
			elif !_quarantine_available():
				scene._decide_visitor("reject")
			else:
				scene._decide_visitor("quarantine")
		_:
			scene._decide_visitor("reject")


func _play_prep_strategy(strategy: String) -> void:
	if strategy in ["truth", "chaos"] and int(scene.state.get("quarantine_capacity", 1)) < 2 and int(scene.state.get("supplies", 0)) >= 6:
		scene._prep_fortify_quarantine()
	else:
		scene._start_visitors()


func _quarantine_available() -> bool:
	var capacity := mini(2, int(scene.state.get("quarantine_capacity", 1)))
	return int(scene.state.get("quarantine_used", 0)) < capacity and int(scene.state.get("quarantine", 0)) > 0


func _reveal_all(visitor: Dictionary) -> void:
	for clue in visitor["evidence"]:
		if !(clue in visitor["discovered"]):
			visitor["discovered"].append(clue)
			scene._add_evidence(visitor, clue)
