extends SceneTree

const Scene = preload("res://scenes/mvp/main_mvp.tscn")
const Contract = preload("res://scripts/mvp/save_contract.gd")
const DT: float = 1.0 / 120.0
var main
var checks: int = 0
var failures: Array = []
var isolated_path: String = ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i: int in range(a.size()):
			if not same(a[i], b[i]): return false
		return true
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 0.00000001
	return a == b

func spawn_main() -> void:
	main = Scene.instantiate()
	root.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	await process_frame
	check(main.save_path == isolated_path, "isolated save namespace")
	check(main.menu != null and main.board != null and main.boulder != null, "actual scene ready")

func reload_main() -> void:
	main.free()
	await process_frame
	await spawn_main()
	check(not main.save_blocked, "saved scene reload accepted")
	main._menu_action("continue")
	check(main.screen == "game", "continue menu resumes reloaded scene")
	if not main.prestige_phase.is_empty():
		check(main.ui_mode == "prestige" and main.paused, "continue menu restores prestige presentation")

func disk_payload() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(isolated_path))
	check(value is Dictionary and Contract.validate(value), "durable payload validates")
	return value if value is Dictionary else {}

func button_named(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child: Node in node.get_children():
		var found: Button = button_named(child, label)
		if found != null: return found
	return null

func press(label: String) -> void:
	var button: Button = button_named(main.overlay, label)
	check(button != null, "confirmation button " + label)
	if button != null: button.pressed.emit()

func make_summit() -> int:
	# A manual arrival fixture bypasses climbing, not the actual EXP or prestige APIs.
	main.boulder.distance = 1000.0
	main.boulder.peak = 1000.0
	main.boulder.velocity = 0.0
	main.boulder.state = "summit"
	main.boulder.ability.inertia_frontier = 1000.0
	var earned: int = main.mastery.award_distance(1000.0, main.mountain.total_length)
	main._start_prestige()
	return earned

func prestige_cycle(expected_count: int) -> void:
	for phase: String in main.PRESTIGE_PHASES:
		check(main.prestige_phase == phase, "phase reached " + phase)
		check(main._save_progression(), "phase saved " + phase)
		var before: Dictionary = disk_payload()
		await reload_main()
		check(main.prestige_phase == phase, "crash reload phase " + phase)
		check(same(main.boulder.snapshot(), before.run), "phase physical state restored " + phase)
		var snapshot: Dictionary = main.boulder.snapshot()
		main.advance_gameplay(1.0, [true, true, false])
		check(same(snapshot, main.boulder.snapshot()), "phase blocks gameplay " + phase)
		main._advance_prestige()
		if phase == "PRESTIGE_COMMIT":
			check(main.mastery.prestige_count == expected_count, "prestige commits once")
			check(main.mastery.threads_balance == expected_count, "one thread per summit")
			check(main.mastery.purchased_mastery_nodes.is_empty() and main.mastery.available_exp == 0, "committed growth cleared")
			check(main.boulder.max_stamina == 100.0 and main.boulder.push_multiplier == 1.0, "committed controller neutral")
			# Recreate the exact earlier journal phase after its durable commit. This
			# models interruption between the two writes in _advance_prestige.
			var committed: Dictionary = disk_payload()
			committed.prestige_phase = "PRESTIGE_COMMIT"
			check(Contract.validate(committed), "committed journal boundary valid")
			var file := FileAccess.open(isolated_path, FileAccess.WRITE)
			file.store_string(JSON.stringify(committed))
			file.close()
			await reload_main()
			main._advance_prestige()
			check(main.mastery.prestige_count == expected_count and main.mastery.threads_balance == expected_count, "committed journal replay idempotent")
			check(not main.mastery.commit_prestige(main.mastery.current_run_token), "duplicate token rejected")
	check(main.prestige_phase.is_empty() and main.boulder.distance == 0.0, "new cycle starts at bottom")
	check(main.mastery.exp_multiplier() == 5, "Malkuth remains exactly x5")
	check(main.mastery.permanent_mastery_unlocks.size() == 35, "all purchase qualifications retained")
	check(Contract.validate(main._save_payload()), "new cycle save valid")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="): isolated_path = argument.trim_prefix("--save-path=")
	if not isolated_path.begins_with("user://mvp-integration-") or "/" in isolated_path.trim_prefix("user://") or "\\" in isolated_path:
		printerr("Requires an isolated --save-path=user://mvp-integration-UNIQUE.json")
		quit(2)
		return
	if FileAccess.file_exists(isolated_path):
		printerr("Use a fresh integration namespace; refusing to overwrite an existing save")
		quit(2)
		return
	await spawn_main()
	main._menu_action("new_game")
	check(main.ui_mode == "confirm", "new game requires explicit confirmation")
	press("취소")
	check(not FileAccess.file_exists(isolated_path), "cancel new game preserves absent save")
	main._menu_action("new_game")
	press("확인")
	check(main.screen == "game" and main.has_resume, "confirmed new game starts")
	check("밀기 키를 놓고" in main._slip_recovery_hint(), "MVP Slip hint instructs releasing normal push too")
	check(main._ui_font_size(main._distance_hud_font_size()) == 28, "MVP distance HUD resolves to the shared 28px role")
	check(Contract.validate(main._save_payload()), "initial save contract")
	main.mastery.award_distance(249.999, 1000.0)
	main.boulder.distance = 249.999
	main.boulder.peak = 249.999
	main.boulder.velocity = 1.0
	main.boulder.stamina = 71.0
	main.boulder.slip = 42.0
	main.boulder.slip_remaining = 0.4
	main.advance_gameplay(DT, [true, false, false])
	check(main.paused and main.modal_milestone.get("distance") == 250, "fixed step crossing opens milestone pause")
	check(main.mastery.available_exp == 150, "250m awards exact first record EXP")
	var frozen: Dictionary = main.boulder.snapshot()
	main.advance_gameplay(4.0, [true, true, true])
	check(same(frozen, main.boulder.snapshot()), "position velocity stamina Slip timer and elapsed freeze")
	check(main.update_progression() == 0 and main.mastery.available_exp == 150, "paused milestone does not duplicate EXP")
	check(main.board.purchase_allowed, "milestone permits purchase while moving")
	main._confirm_purchase("STR01")
	check(main.ui_mode == "confirm_board", "purchase confirmation UI")
	press("확인")
	check(main.mastery.available_exp == 120 and "STR01" in main.mastery.purchased_mastery_nodes, "purchase spends once")
	check(absf(main.boulder.push_multiplier - 1.03) < 0.000001 and main.boulder.stamina == frozen.stamina, "purchase applies modifier without free refill")
	main._purchase("STR01")
	check(main.mastery.available_exp == 120, "duplicate purchase rejected")
	main._close_board()
	main.advance_gameplay(DT, [true, false, false])
	check(main.boulder.elapsed > frozen.elapsed and main.boulder.slip_remaining < frozen.slip_remaining, "closing milestone resumes one fixed step")
	main._open_board(false)
	check(not main.board.purchase_allowed, "moving slope disables board purchase")
	main._purchase("STR02")
	check(main.mastery.available_exp == 120 and "STR02" not in main.mastery.purchased_mastery_nodes, "unsafe direct purchase blocked")
	main._close_board()
	for segment: Dictionary in main.mountain.segments:
		if bool(segment.shelf) and float(segment.start) > main.boulder.distance:
			main.boulder.distance = float(segment.start) + 0.5
			main.boulder.peak = main.boulder.distance
			break
	main.boulder.velocity = 0.0
	main.update_progression()
	main._open_board(false)
	check(main.board.purchase_allowed, "stationary shelf purchase enabled")
	main._purchase("STR02")
	check("STR02" in main.mastery.purchased_mastery_nodes, "stationary shelf purchase accepted")
	main._close_board()
	# Valid serialization fixture; ability activation itself is covered by physics tests.
	main.boulder.ability.burst_cooldown = 1.25
	main.boulder.ability.inertia_frontier = main.boulder.peak
	main.boulder.ability.reserve_charge = 1
	main.boulder.ability.exhaustion_rescue_used = true
	check(main._save_progression(), "ability state persisted")
	var saved: Dictionary = disk_payload()
	await reload_main()
	check(same(saved.run, main.boulder.snapshot()), "all physics and ability state restored")
	check(same(saved.mastery.purchased_mastery_nodes, main.mastery.purchased_mastery_nodes) and main.mastery.available_exp == saved.mastery.available_exp, "profile restored")
	main._show_title()
	main._menu_action("new_game")
	check(same(main.mastery.purchased_mastery_nodes, saved.mastery.purchased_mastery_nodes), "existing profile unchanged before new-game confirmation")
	press("취소")
	check(same(disk_payload().mastery, saved.mastery), "cancel new game preserves durable profile")
	main._begin()
	var falls_before: int = main.falls_seen
	# Trigger the actual irreversible failure threshold, then integrate its fall.
	main.boulder.velocity = -4.1
	for step: int in range(120 * 60):
		main.advance_gameplay(DT, [false, false, false])
		if main.boulder.state == "result": break
	check(main.boulder.state == "result" and main.falls_seen == falls_before + 1, "actual Runaway reaches result and counts one fall")
	check(main.boulder.distance == 0.0, "actual fall returns to bottom")
	check(Contract.validate(main._save_payload()), "actual fall save valid")
	var old_token: String = main.mastery.current_run_token
	main._new_run()
	check(main.mastery.current_run_token != old_token and main.mastery.run_milestones == 0, "ordinary retry gets fresh run identity")
	check(main.mastery.available_exp == saved.mastery.available_exp and same(main.mastery.purchased_mastery_nodes, saved.mastery.purchased_mastery_nodes), "ordinary fall preserves wallet and purchased mastery")
	check(not main.boulder.ability.exhaustion_rescue_used and main.boulder.ability.reserve_charge == 0, "ordinary retry resets one shot abilities")
	check(main.boulder.stamina == main.boulder.max_stamina, "ordinary retry refills capacity")
	make_summit()
	await prestige_cycle(1)
	check(make_summit() == 2000, "second complete climb earns exactly 2000 EXP")
	check(main.mastery.award_distance(1000.0, 1000.0) == 0, "same summit EXP cannot duplicate")
	await prestige_cycle(2)
	check(make_summit() == 2000, "third complete climb still earns exactly 2000 EXP")
	check(main.mastery.exp_multiplier() == 5, "two prestiges never compound to x25")
	check(main.ahead_information().is_empty() and not main.slip_warning_active(), "special UI information absent without purchase")
	check(main.mastery.purchase_node("SPC01") and main.mastery.purchase_node("SPC03"), "verified UI special nodes purchasable after prestige")
	# A local display fixture covers an interior slope that endpoint-only sampling
	# would miss, two surface types, and ledges at the exact window boundaries.
	main.mountain.weather_id = "clear"
	var display_segments: Array[Dictionary] = [
		{"start":0.0,"end":110.0,"angle":deg_to_rad(10.0),"surface":"STONE","shelf":false},
		{"start":110.0,"end":140.0,"angle":deg_to_rad(40.0),"surface":"MUD","shelf":false},
		{"start":140.0,"end":1000.0,"angle":deg_to_rad(20.0),"surface":"STONE","shelf":false}]
	main.mountain.segments = display_segments
	var display_ledges: Array[Dictionary] = [{"distance":100.0},{"distance":125.0},{"distance":150.0},{"distance":150.01}]
	main.mountain.ledges = display_ledges
	main.boulder.distance = 100.0
	var ahead: Dictionary = main.ahead_information()
	check(absf(ahead.angle_min - 10.0) < 0.00001 and absf(ahead.angle_max - 40.0) < 0.00001, "SPC01 entire next 50m slope range")
	check("STONE" in ahead.surfaces and "MUD" in ahead.surfaces and ahead.surfaces.size() == 2, "SPC01 unique next surfaces")
	check(ahead.ledges == 2, "SPC01 ledge open-start closed-end range")
	main.boulder.slip = 59.999
	check(not main.slip_warning_active(), "SPC03 no early warning below threshold")
	main.boulder.slip = 60.0
	check(main.slip_warning_active(), "SPC03 warning at threshold")
	main.mastery.set_feature_enabled("SPC01", false)
	main.mastery.set_feature_enabled("SPC03", false)
	check(main.ahead_information().is_empty() and not main.slip_warning_active(), "disabled UI specials have no effect")
	main.free()
	await process_frame
	print(JSON.stringify({"suite":"mvp_integration","checks":checks,"failures":failures,"save_path":isolated_path,"manual_arrival_fixtures":true}))
	quit(0 if failures.is_empty() else 1)

