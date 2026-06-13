extends SceneTree

var scene: Node


func _initialize() -> void:
	var truth_results := []
	var refuse_results := []
	var chaos_results := []
	for i in range(6):
		truth_results.append(await _run_strategy("balance-truth-" + str(i), "truth"))
		refuse_results.append(await _run_strategy("balance-refuse-" + str(i), "refuse"))
		chaos_results.append(await _run_strategy("balance-chaos-" + str(i), "chaos"))
	if !_assert_truth_route(truth_results):
		quit(1)
		return
	if !_assert_refuse_route(refuse_results):
		quit(1)
		return
	if !_assert_chaos_route(chaos_results):
		quit(1)
		return
	print("BALANCE_AUDIT_OK ", JSON.stringify({
		"truth": _summary(truth_results),
		"refuse": _summary(refuse_results),
		"chaos": _summary(chaos_results),
	}))
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
	while scene.current_phase != "ending" and guard < 1200:
		guard += 1
		match scene.current_phase:
			"prep":
				_play_prep_strategy(strategy)
			"door":
				_play_door_strategy(strategy)
			"investigation":
				_play_investigation_strategy(strategy)
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
		push_error("Balance audit did not reach ending for " + strategy + " seed=" + seed_text + " phase=" + str(scene.current_phase))
		return {"failed": true, "strategy": strategy, "seed": seed_text}
	return {
		"strategy": strategy,
		"seed": seed_text,
		"ending": scene.subtitle_label.text,
		"day": int(scene.state.get("day", 0)),
		"humans": int(scene.state.get("humans_inside", 0)),
		"fakes": int(scene.state.get("fakes_inside", 0)) + int(scene.state.get("mimics_inside", 0)),
		"missing": int(scene.state.get("missing", 0)),
		"stolen": int(scene.state.get("stolen", 0)),
		"contamination": int(scene.state.get("contamination", 0)),
		"abandonment": int(scene.state.get("abandonment", 0)),
		"final_judgment": int(scene.state.get("final_judgment", 0)),
	}


func _play_prep_strategy(strategy: String) -> void:
	match strategy:
		"truth":
			if int(scene.state.get("quarantine_capacity", 1)) < 2 and int(scene.state.get("supplies", 0)) >= 6:
				scene._prep_fortify_quarantine()
			elif !bool(scene.state.get("rooms_assigned", false)):
				scene._prep_assign_rooms()
			elif !bool(scene.state.get("supplies_distributed", false)) and int(scene.state.get("supplies", 0)) >= 10:
				scene._prep_distribute_supplies()
			elif str(scene.state.get("code_phrase", "")).is_empty():
				scene._prep_set_code()
			else:
				scene._start_visitors()
		"chaos":
			if int(scene.state.get("quarantine_capacity", 1)) < 2 and int(scene.state.get("supplies", 0)) >= 6:
				scene._prep_fortify_quarantine()
			elif int(scene.state.get("day", 1)) % 2 == 0 and int(scene.state.get("supplies", 0)) >= 8:
				scene._prep_set_guard()
			else:
				scene._start_visitors()
		_:
			scene._start_visitors()


func _play_door_strategy(strategy: String) -> void:
	if scene.current_visitor_index >= scene.current_visitors.size():
		scene._show_investigation()
		return
	var visitor: Dictionary = scene.current_visitors[scene.current_visitor_index]
	match strategy:
		"truth":
			if visitor["role"] == "human":
				if bool(visitor.get("event", {}).get("chased", false)) or visitor.get("event", {}).get("id", "") == "mistaken_chased":
					if _quarantine_available():
						scene._decide_visitor("quarantine")
					else:
						scene._decide_visitor("admit")
				else:
					scene._decide_visitor("admit")
			else:
				_reveal_all(visitor)
				scene._decide_visitor("reject")
		"refuse":
			scene._decide_visitor("reject")
		"chaos":
			if int(scene.current_visitor_index) % 3 == 0:
				scene._decide_visitor("admit")
			elif _quarantine_available():
				scene._decide_visitor("quarantine")
			else:
				scene._decide_visitor("reject")
		_:
			scene._decide_visitor("reject")


func _quarantine_available() -> bool:
	var capacity := mini(2, int(scene.state.get("quarantine_capacity", 1)))
	return int(scene.state.get("quarantine_used", 0)) < capacity and int(scene.state.get("quarantine", 0)) > 0


func _play_investigation_strategy(strategy: String) -> void:
	match strategy:
		"truth":
			if int(scene.state.get("fakes_inside", 0)) + int(scene.state.get("mimics_inside", 0)) > 0 and int(scene.state.get("room_searches_left", 0)) > 0:
				scene._investigate_room()
			else:
				scene._start_sleep()
		"chaos":
			if int(scene.state.get("cross_questions_left", 0)) > 0:
				scene._cross_question()
			else:
				scene._start_sleep()
		_:
			scene._start_sleep()


func _reveal_all(visitor: Dictionary) -> void:
	for clue in visitor["evidence"]:
		if !(clue in visitor["discovered"]):
			visitor["discovered"].append(clue)
			scene._add_evidence(visitor, clue)


func _assert_truth_route(results: Array) -> bool:
	for result in results:
		if bool(result.get("failed", false)):
			return false
		if int(result.get("day", 0)) < 9:
			push_error("Truth route ended before day 9: " + JSON.stringify(result))
			return false
		if int(result.get("humans", 0)) < 3:
			push_error("Truth route failed to preserve enough humans: " + JSON.stringify(result))
			return false
		if int(result.get("contamination", 0)) >= 90:
			push_error("Truth route contamination too high: " + JSON.stringify(result))
			return false
	return true


func _assert_refuse_route(results: Array) -> bool:
	for result in results:
		if bool(result.get("failed", false)):
			return false
		if int(result.get("missing", 0)) < 6 and int(result.get("abandonment", 0)) < 6:
			push_error("Refuse route did not punish blind refusal enough: " + JSON.stringify(result))
			return false
	return true


func _assert_chaos_route(results: Array) -> bool:
	var danger_count := 0
	for result in results:
		if bool(result.get("failed", false)):
			return false
		if int(result.get("contamination", 0)) >= 70 or int(result.get("fakes", 0)) >= 3 or int(result.get("missing", 0)) >= 2:
			danger_count += 1
	if danger_count < 3:
		push_error("Chaos route was too safe: " + JSON.stringify(results))
		return false
	return true


func _summary(results: Array) -> Dictionary:
	var total_humans := 0
	var total_fakes := 0
	var total_missing := 0
	var total_contamination := 0
	for result in results:
		total_humans += int(result.get("humans", 0))
		total_fakes += int(result.get("fakes", 0))
		total_missing += int(result.get("missing", 0))
		total_contamination += int(result.get("contamination", 0))
	return {
		"runs": results.size(),
		"avg_humans": float(total_humans) / maxf(1.0, results.size()),
		"avg_fakes": float(total_fakes) / maxf(1.0, results.size()),
		"avg_missing": float(total_missing) / maxf(1.0, results.size()),
		"avg_contamination": float(total_contamination) / maxf(1.0, results.size()),
	}
