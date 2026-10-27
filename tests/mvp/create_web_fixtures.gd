extends SceneTree

const Scene = preload("res://scenes/mvp/main_mvp.tscn")
const Contract = preload("res://scripts/mvp/save_contract.gd")
const OUTPUT: String = "res://tests/mvp/fixtures/web-unlock-150-400-700/"
var failures: Array = []

func _initialize() -> void:
	call_deferred("run")

func export_fixture(main, name: String) -> void:
	var payload: Dictionary = main._save_payload()
	if not Contract.validate(payload):
		failures.append(name + ": invalid save")
		return
	var file := FileAccess.open(OUTPUT + name + ".json", FileAccess.WRITE)
	if file == null:
		failures.append(name + ": cannot write fixture")
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + name + ".json"))
	if not parsed is Dictionary or not Contract.validate(parsed): failures.append(name + ": roundtrip invalid")

func run() -> void:
	var path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="): path = argument.trim_prefix("--save-path=")
	if not path.begins_with("user://mvp-web-fixture-builder-") or "/" in path.trim_prefix("user://") or "\\" in path or FileAccess.file_exists(path):
		printerr("Requires a fresh isolated --save-path=user://mvp-web-fixture-builder-UNIQUE.json")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var main = Scene.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	await process_frame
	main._reset_game()
	# Artificial browser-QA arrival fixture; no claim of a played climb.
	main.boulder.distance = 150.0
	main.boulder.peak = 150.0
	main.boulder.velocity = 0.9
	main.boulder.stamina = 71.0
	main.boulder.ability.inertia_frontier = 150.0
	main.update_progression()
	if main.mastery.available_exp != 90 or main.modal_milestone.get("distance") != 150:
		failures.append("milestone setup")
	export_fixture(main, "milestone150")
	main._close_board()
	main.boulder.distance = 1000.0
	main.boulder.peak = 1000.0
	main.boulder.velocity = 0.0
	main.boulder.state = "summit"
	main.boulder.ability.inertia_frontier = 1000.0
	main.mastery.award_distance(1000.0, 1000.0)
	for id: String in ["STR01", "END01", "BRE01"]:
		if not main.mastery.purchase_node(id): failures.append("fixture purchase " + id)
	main.boulder.apply_mastery_effects(main.mastery.get_mastery_modifiers())
	main._start_prestige()
	for index: int in range(3): main._advance_prestige()
	if main.prestige_phase != "PRESTIGE_COMMIT" or main.mastery.prestige_count != 0:
		failures.append("precommit setup")
	export_fixture(main, "prestige-commit")
	for index: int in range(4): main._advance_prestige()
	if not main.prestige_phase.is_empty() or main.mastery.available_exp != 0 or main.mastery.prestige_count != 1 or main.mastery.permanent_mastery_unlocks.size() != 35:
		failures.append("after prestige setup")
	export_fixture(main, "after-prestige")
	main.free()
	await process_frame
	print(JSON.stringify({"suite":"web_fixture_creation","fixtures":3,"failures":failures,"artificial_arrival_states":true,"output":OUTPUT}))
	quit(0 if failures.is_empty() else 1)
