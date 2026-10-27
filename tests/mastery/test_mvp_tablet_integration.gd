extends SceneTree
## Real MVP host and real viewport input, using a fresh test-only save namespace.
const Scene = preload("res://scenes/mvp/main_mvp.tscn")
const Profile = preload("res://scripts/mastery_progression.gd")
const Contract = preload("res://scripts/mvp/save_contract.gd")
const OUTPUT := "res://tests/mastery/results/unlock-150-400-700/live"
var checks := 0
var failures: Array[String] = []
var captures: Array = []
var viewport: SubViewport
var main
var fixture: String

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: " + label)

func frames(count := 3) -> void:
	for i in count: await process_frame

func button_named(node: Node, text: String) -> Button:
	if node == null: return null
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := button_named(child, text)
		if found != null: return found
	return null

func click(control: Control) -> void:
	check(control != null, "click target exists")
	if control == null: return
	var point: Vector2 = control.get_global_transform() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	await frames()

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	await frames()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var path := OUTPUT.path_join("captures/" + name + ".png")
	check(image.save_png(path) == OK, "capture " + name)
	captures.append({"path":path,"size":[image.get_width(),image.get_height()],"sha256":FileAccess.get_sha256(path)})

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT + "/captures"))
	fixture = "res://.tools/mastery-live-test-%d.json" % Time.get_ticks_usec()
	check(not FileAccess.file_exists(fixture), "fresh isolated save")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = true
	root.add_child(viewport)
	main = Scene.instantiate()
	main.save_path = fixture
	viewport.add_child(main)
	main.set_process(false)
	main.set_physics_process(false)
	await frames()
	check(main.save_path == fixture, "real user save never used")
	check(not FileAccess.file_exists(fixture) and not main.has_resume, "no save before first title browse")
	check(main.board.scene_file_path == "res://godot/scenes/mastery/mastery_mvp_board.tscn", "actual MVP uses new tablet")
	await capture("mvp-main-menu-1920")
	check(not button_named(main.menu, "숙련의 석판").disabled, "zero-distance readonly browse enabled")
	await click(button_named(main.menu, "숙련의 석판"))
	check(main.ui_mode == "board" and main.board.visible and main.paused, "real menu opens live tablet")
	check(main.board.node_views.size() == 35 and main.board.slots.size() == 35, "35 real mapped nodes")
	check(main.board.profile == main.mastery, "live model identity, not mock")
	check(main.mastery.available_exp == 0 and not main.board.purchase_allowed, "title readonly actual empty wallet")
	check(main.board.detail_requirement.text.contains("150 m"), "first live requirement shows150m")
	check(not main.board.exp_label.text.contains("강화점"), "MVP wallet never mislabeled rank points")
	check(button_named(main.board, "30점 시연") == null, "no developer funding control in game")
	check(button_named(main.board, "구매 초기화") == null, "no developer reset control in game")
	await capture("mvp-title-tablet-1920")
	await key(KEY_ESCAPE)
	check(main.screen == "title" and main.menu.visible and not main.board.visible, "Escape returns to title")
	check(not FileAccess.file_exists(fixture) and not main.has_resume, "readonly title browse does not create a save")
	await click(button_named(main.menu, "숙련의 석판"))
	await click(main.board.close_button)
	check(main.menu.visible and not main.board.visible and not FileAccess.file_exists(fixture), "pointer return button preserves empty save")
	main._reset_game()
	await frames()
	check(main.screen == "game" and Contract.validate(main._save_payload()), "real fresh run save contract")
	main.mastery.award_distance(150,1000)
	main.boulder.distance = 150
	main.boulder.peak = 150
	main.boulder.velocity = 1.0
	main.update_progression()
	await frames()
	check(main.modal_milestone.get("distance") == 150 and main.board.visible, "real milestone opens new board")
	check(main.mastery.available_exp == 90 and main.board.purchase_allowed, "existing milestone permission and EXP90")
	main.board.select_node("STR01")
	await frames()
	var definition: Dictionary = main.mastery.get_node_definition("STR01")
	check(main.board.detail_effect.text.contains(str(definition.description)), "actual MVP effect text, not mock2percent")
	check(main.board.detail_cost.text.contains(str(definition.exp_cost)) and main.board.detail_cost.text.contains("EXP"), "actual existing EXP cost")
	var frozen: Dictionary = main.boulder.snapshot()
	main.advance_gameplay(1.0,[true,true,true])
	check(main.boulder.snapshot() == frozen, "open tablet freezes entire climbing state")
	await click(main.board.purchase_button)
	check(main.ui_mode == "confirm_board" and main.mastery.available_exp == 90, "purchase request opens confirmation without spending")
	await click(button_named(main.overlay, "취소"))
	check(main.mastery.available_exp == 90 and "STR01" not in main.mastery.purchased_mastery_nodes, "cancel never buys")
	await click(main.board.purchase_button)
	await key(KEY_ESCAPE)
	check(main.ui_mode == "board" and main.board.visible and main.mastery.available_exp == 90, "Escape dismisses confirmation before board")
	await click(main.board.purchase_button)
	await click(button_named(main.overlay, "확인"))
	check(main.mastery.available_exp == 90-int(definition.exp_cost) and "STR01" in main.mastery.purchased_mastery_nodes, "confirmed real purchase spends existing cost once")
	check(is_equal_approx(main.boulder.push_multiplier,1.03), "existing modifier applied unchanged")
	check(main.board.purchase_button.disabled, "purchased node button disabled")
	var spent: int = main.mastery.available_exp
	main._purchase("STR01")
	check(main.mastery.available_exp == spent, "duplicate host purchase rejected")
	check(Contract.validate(main._save_payload()), "purchase preserves original save schema")
	await capture("mvp-purchase-1920")
	await key(KEY_ESCAPE)
	check(not main.board.visible and not main.paused and main.screen == "game", "Escape resumes live climb")
	main.boulder.distance = 160
	main.boulder.peak = 160
	main.boulder.velocity = 1.0
	main.mastery.award_distance(160,1000)
	main.modal_milestone = {}
	await key(KEY_TAB)
	check(main.board.visible and not main.board.purchase_allowed, "Tab opens readonly on moving slope")
	main._confirm_purchase("STR02")
	main._purchase("STR02")
	check(main.ui_mode == "board" and main.mastery.available_exp == spent and "STR02" not in main.mastery.purchased_mastery_nodes, "unsafe confirmation and direct purchase rejected")
	await key(KEY_ESCAPE)
	for segment: Dictionary in main.mountain.segments:
		if bool(segment.shelf) and float(segment.start) > main.boulder.distance:
			main.boulder.distance = float(segment.start) + 0.5
			main.boulder.peak = main.boulder.distance
			break
	main.boulder.velocity = 0
	main.update_progression()
	main._open_board(false)
	await frames()
	check(main.board.purchase_allowed, "stationary shelf retains existing permission")
	main.board.select_node("STR02")
	await frames()
	check(not main.board.purchase_button.disabled, "next normal purchase on shelf enabled")
	# A fresh in-memory profile uses actual old award/prestige/purchase methods;
	# this is a test fixture, never injected into a user's save.
	var saved_special = Profile.new()
	saved_special.begin_run("special-fixture")
	saved_special.award_distance(1000,1000)
	check(saved_special.commit_prestige("special-fixture"), "existing prestige fixture")
	saved_special.begin_run("after-first")
	saved_special.award_distance(1000,1000)
	check(saved_special.purchase_node("SPC01"), "existing model special purchase fixture")
	var original_snapshot: Dictionary = saved_special.snapshot()
	var original_effects: Dictionary = saved_special.get_mastery_modifiers()
	main.mastery = saved_special
	main.run_number = 2
	main.modal_milestone = {}
	main._open_board(false)
	await frames()
	for index in range(1,6):
		var id := "SPC%02d" % index
		main.board.select_node(id)
		await frames()
		check(main.board.purchase_button.disabled, "special placeholder cannot buy " + id)
		check(main.board.detail_effect.text.contains("미정") and main.board.detail_cost.text.contains("미정"), "special unknown text " + id)
		main._confirm_purchase(id)
		main._purchase(id)
		check(main.ui_mode == "board", "special cannot open purchase confirmation " + id)
	check(saved_special.snapshot() == original_snapshot and saved_special.get_mastery_modifiers() == original_effects, "existing purchased special model/effects untouched")
	check(main.board.node_views.act1_special_01.state.purchased, "existing saved special still marked purchased")
	for dimensions in [Vector2i(1920,1080),Vector2i(1280,720)]:
		viewport.size = dimensions
		await frames()
		var rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		for view in main.board.node_views.values():
			check(rect.encloses(view.hit_target.get_global_rect()), "node hitbox fits " + str(dimensions) + str(view.name))
		for label in [main.board.detail_name,main.board.detail_effect,main.board.detail_requirement,main.board.detail_cost,main.board.detail_state]:
			check(rect.encloses(label.get_global_rect()), "detail fits " + str(dimensions) + str(label.name))
		for id: String in main.board.slots:
			main.board.select_node(id)
			await frames(1)
			if not id.begins_with("SPC"):
				var threshold: int = int(main.mastery.get_node_definition(id).unlock_milestone)
				check(threshold in [150,400,700] and main.board.detail_requirement.text.contains("%d m" % threshold), "new unlock requirement matches model " + id)
			for label: Label in [main.board.detail_name,main.board.detail_effect,main.board.detail_requirement,main.board.detail_cost,main.board.detail_state]:
				var height: float = label.get_line_count() * label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
				check(height <= label.size.y + 1, "all live descriptions fit " + str(dimensions) + id + str(label.name))
			var fields: Array = [main.board.detail_name,main.board.detail_effect,main.board.detail_requirement,main.board.detail_cost,main.board.detail_state,main.board.purchase_button]
			for i in range(fields.size()-1):
				check(fields[i].get_global_rect().end.y <= fields[i+1].get_global_rect().position.y + 1, "detail fields never overlap " + str(dimensions) + id + str(i))
			check(main.board.purchase_button.size.x <= 317, "button text stays inside original316width " + str(dimensions) + id)
		main.board.select_node("SPC01")
		await capture("mvp-special-preserved-%d" % dimensions.x)
	# Allowlist patch assets rendered directly; no generated replacement artwork.
	main.board.gate_views[0].play()
	await frames(5)
	await capture("mvp-patched-push-1280")
	main.board.skip_animations()
	check(not main.board.gate_views[0].playing, "patched gate can be skipped")
	main.sound.shutdown()
	viewport.free()
	await frames()
	var result := {"checks":checks,"failures":failures,"passed":failures.is_empty(),"captures":captures,"save_fixture":fixture,"display":DisplayServer.get_name(),"scope":"Actual MVP host and original model; isolated save; actual mouse/key InputEvents via SubViewport. Screenshots only with native GL renderer."}
	var file := FileAccess.open(OUTPUT.path_join("live_integration.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
