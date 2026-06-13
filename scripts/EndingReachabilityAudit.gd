extends SceneTree

var scene: Node


func _initialize() -> void:
	scene = load("res://scenes/Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._show_title()
	scene.seed_input.text = "ending-reachability-audit"
	scene._start_new_game()
	await process_frame

	var expected := {
		"true": _state({"humans_inside": 4, "missing": 0, "contamination": 20, "final_judgment": 40}, true, false),
		"hidden": _state({"humans_inside": 4, "missing": 0, "contamination": 20, "final_judgment": 40}, false, true),
		"no_one": _state({"humans_inside": 1, "missing": 0, "abandonment": 8}),
		"purple": _state({"humans_inside": 4, "missing": 0, "contamination": 95}),
		"identity": _state({"humans_inside": 4, "missing": 0, "stolen": 5}),
		"distortion": _state({"humans_inside": 4, "missing": 0, "rule_distortion": 80, "final_judgment": 10}),
		"perfect_band": _state({"humans_inside": 2, "missing": 0, "fakes_inside": 3, "mimics_inside": 0}),
		"good": _state({"humans_inside": 3, "missing": 0, "fakes_inside": 0, "mimics_inside": 0, "contamination": 30}),
		"neutral": _state({"humans_inside": 1, "missing": 0, "fakes_inside": 0, "mimics_inside": 0, "contamination": 30}),
	}
	for kind in expected.keys():
		_apply_state(expected[kind])
		var got: String = scene._judge_final_ending()
		if got != kind:
			push_error("Ending reachability mismatch for " + kind + ": got " + got)
			quit(1)
			return

	_apply_state(_state({"door": 0, "humans_inside": 3, "missing": 0}))
	scene._check_immediate_failure()
	if scene.current_phase != "ending" or !("门锁之后" in scene.subtitle_label.text):
		push_error("Immediate door ending was not reachable")
		quit(1)
		return

	print("ENDING_REACHABILITY_OK ", JSON.stringify(expected.keys() + ["door"]))
	quit()


func _state(overrides: Dictionary, final_identified := false, final_mishandled := false) -> Dictionary:
	var base := {
		"day": 9,
		"stamina": 80,
		"stamina_max": 100,
		"contamination": 0,
		"self_suspicion": 0,
		"rule_distortion": 0,
		"final_judgment": 0,
		"abandonment": 0,
		"supplies": 40,
		"door": 80,
		"quarantine": 80,
		"trust": 60,
		"outside_danger": 20,
		"evidence_integrity": 80,
		"mimic_learning": 20,
		"humans_inside": 0,
		"missing": 0,
		"fakes_inside": 0,
		"mimics_inside": 0,
		"stolen": 0,
	}
	for key in overrides.keys():
		base[key] = overrides[key]
	base["final_mimic_identified"] = final_identified
	base["final_mimic_mishandled"] = final_mishandled
	return base


func _apply_state(spec: Dictionary) -> void:
	for key in spec.keys():
		if key == "final_mimic_identified":
			scene.final_mimic_identified = bool(spec[key])
		elif key == "final_mimic_mishandled":
			scene.final_mimic_mishandled = bool(spec[key])
		else:
			scene.state[key] = spec[key]
	scene.current_phase = "dawn"
