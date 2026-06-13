extends SceneTree

func _initialize() -> void:
	var scene: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.seed_input.text = "smoke-test"
	scene._start_new_game()
	if !scene.state.has("character_trust") or !scene.state.has("character_stress"):
		push_error("Relationship maps were not initialized")
		quit(1)
		return
	scene._prep_assign_rooms()
	if !bool(scene.state.get("rooms_assigned", false)):
		push_error("Prep state did not persist after assigning rooms")
		quit(1)
		return
	scene._start_visitors()
	await process_frame
	if scene.question_input != null:
		scene.question_input.text = "你记得昨天的暗号吗？"
		scene._ask_free_question()
	for i in range(90):
		await process_frame
	scene._decide_visitor("reject")
	await process_frame
	print("SMOKE_OK phase=", scene.current_phase, " day=", scene.state.get("day", 0))
	quit()
