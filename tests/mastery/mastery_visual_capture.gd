extends SceneTree
## Requires native rendering. Input is sent through a SubViewport, not direct signals.
const Screen = preload("res://godot/scenes/mastery/mastery_tablet_screen.tscn")
const Adapter = preload("res://scripts/mastery/mastery_progress_adapter.gd")
const Report = preload("res://tests/mastery/test_report.gd")
var report = Report.new()
var viewport: SubViewport
var screen
var captures: Array = []
var output := "res://tests/mastery/results/v12/verification/captures"

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 2) -> void:
	for i in count: await process_frame

func click_at(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	viewport.push_input(move, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame

func click_control(control: Control) -> void:
	await click_at(control.get_global_transform() * (control.size * 0.5))

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame

func capture(name: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var path: String = output.path_join(name + ".png")
	report.check(image.save_png(path) == OK, "screenshot saved " + name)
	report.check(image.get_size() == viewport.size, "screenshot exact resolution " + name)
	captures.append({"path":path,"width":image.get_width(),"height":image.get_height(),"sha256":FileAccess.get_sha256(path)})

func inspect_decorations(node: Node) -> void:
	if node is TextureRect:
		report.check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "decorative texture ignores input " + str(node.get_path()))
	for child: Node in node.get_children(): inspect_decorations(child)

func check_detail(size_name: String) -> void:
	for id: String in screen.node_views:
		screen.select_node(id)
		await frames(1)
		for label: Label in [screen.detail_name,screen.detail_effect,screen.detail_requirement,screen.detail_cost,screen.detail_state]:
			var height: float = label.get_line_count() * label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
			report.check(height <= label.size.y + 1, "text line height fits %s %s %s" % [size_name,id,label.name])
			var box: Rect2 = label.get_global_rect()
			report.check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(box), "detail within viewport %s %s %s" % [size_name,id,label.name])
		if screen.node_views[id].data.track == "special":
			report.check(screen.detail_effect.text.contains("미정") and screen.detail_cost.text.contains("미정") and screen.purchase_button.disabled, "special unknown and unpurchasable " + size_name + id)
		else:
			report.check(screen.detail_cost.text.contains("강화점 1") and screen.detail_cost.text.contains("EXP 직접 차감 없음"), "normal node truthful pending-point cost " + size_name + id)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Native renderer required; this is not a headless PASS.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = true
	root.add_child(viewport)
	screen = Screen.instantiate()
	viewport.add_child(screen)
	await frames()
	report.check(screen.node_views.size() == 35, "35 common node instances")
	report.check(screen.track_views.size() == 4, "three regular paths plus one special track")
	inspect_decorations(screen)
	for id: String in screen.node_views:
		var view = screen.node_views[id]
		report.check(view.scene_file_path == "res://godot/scenes/mastery/mastery_node.tscn", "common scene reused " + id)
		report.check(view.position + view.size * 0.5 == Vector2(view.data.x,view.data.y), "CSV center maintained " + id)
		report.check(view.hit_target.focus_mode == Control.FOCUS_ALL, "keyboard focusable " + id)
	for resolution: Vector2i in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(960,600)]:
		viewport.size = resolution
		await frames()
		var name: String = "%dx%d" % [resolution.x,resolution.y]
		var bounds := Rect2(Vector2.ZERO,Vector2(resolution))
		var node_rects: Array[Rect2] = []
		for view in screen.node_views.values():
			var rect: Rect2 = view.hit_target.get_global_rect()
			report.check(bounds.encloses(rect), "node hit target onscreen " + name + str(view.data.node_id))
			report.check(not rect.intersects(screen.purchase_button.get_parent().get_global_rect()), "node does not overlap detail " + name + str(view.data.node_id))
			for previous: Rect2 in node_rects: report.check(not rect.intersects(previous), "separate node hit areas " + name)
			node_rects.append(rect)
		await check_detail(name)
		for fixture: String in ["zero","250","500","750","first_summit","next_run"]:
			screen.apply_fixture(fixture,false)
			screen.select_node("act1_special_01" if fixture in ["first_summit","next_run"] else "act1_strength_01")
			await capture(fixture + "-" + name)
		# Actual mouse targets are tested after letterboxing, not only at design resolution.
		screen.apply_fixture("zero",false)
		await click_control(screen.node_views.act1_breath_10.hit_target)
		report.check(screen.selected_id == "act1_breath_10" and screen.node_views.act1_breath_10.selection_overlay.visible, "mouse selects locked node " + name)
		report.check(screen.node_views.act1_breath_10.state.base_state == "STORY_LOCKED", "locked selection keeps base state " + name)
	viewport.size = Vector2i(1920,1080)
	screen.apply_fixture("250",false)
	await frames()
	await click_control(screen.node_views.act1_strength_01.hit_target)
	report.check(not screen.purchase_button.disabled, "mouse selection enables valid purchase")
	var xp: int = int(screen.adapter.snapshot().total_xp)
	await click_control(screen.purchase_button)
	report.check(screen.adapter.snapshot().ranks.strength == 1 and screen.adapter.snapshot().total_xp == xp, "actual mouse purchase changes one rank without XP subtraction")
	await click_control(screen.purchase_button)
	report.check(screen.adapter.snapshot().ranks.strength == 1, "double click cannot repurchase selected node")
	report.check(screen.node_views.act1_strength_01.glyph.texture.resource_path.ends_with("active/0392.png"), "purchased glyph actual active PNG")
	screen.node_views.act1_strength_02.hit_target.grab_focus()
	await key(KEY_ENTER)
	report.check(screen.selected_id == "act1_strength_02", "keyboard Enter selects focused successor")
	var owner_before: Control = viewport.gui_get_focus_owner()
	await key(KEY_TAB)
	report.check(viewport.gui_get_focus_owner() != owner_before and viewport.gui_get_focus_owner() != null, "Tab advances real GUI focus")
	await click_control(screen.node_views.act1_strength_02.hit_target)
	await click_control(screen.purchase_button)
	await click_control(screen.node_views.act1_endurance_01.hit_target)
	report.check(screen.node_views.act1_endurance_01.state.base_state == "INSUFFICIENT_EXP" and screen.node_views.act1_endurance_01.selection_overlay.visible and screen.purchase_button.disabled, "mouse selects unfunded node independently")
	await capture("mixed-states-1920x1080")
	screen.apply_fixture("750",false)
	screen.adapter.fund_preview()
	for view in screen.node_views.values():
		if view.data.track != "special": screen.adapter.purchase(view.data)
	screen.skip_animations()
	report.check(screen.adapter.snapshot().ranks == {"strength":10,"endurance":10,"recovery":10}, "all 30 real rank nodes displayed purchased")
	var track_colors: Dictionary = {"strength":Color("f6af4d"),"endurance":Color("38a7ff"),"breath":Color("37e7e4")}
	for view in screen.node_views.values():
		if view.data.track != "special": report.check(view.glyph.modulate == track_colors[view.data.track], "active glyph track color " + str(view.data.node_id))
	await capture("all-normal-purchased-1920x1080")
	screen.apply_fixture("250",true)
	report.check(screen.progress_label.text.contains("10 / 35"), "gate state committed before animation")
	report.check(screen.gate_views[0].playing and screen.gate_views[0].wall.texture.resource_path.ends_with("stone_wall_closed.png"), "gate plays provided rectangular stone wall")
	await create_timer(0.32).timeout
	await capture("gate-push-1920x1080")
	var before_skip: Dictionary = screen.adapter.snapshot()
	screen.skip_animations()
	report.check(screen.adapter.snapshot() == before_skip, "skipping visual gate cannot change progression")
	for gate in screen.gate_views: report.check(not gate.playing and not gate.blocker.visible, "skip releases gate-only blocker")
	screen.apply_fixture("500",true)
	await key(KEY_ESCAPE)
	report.check(not screen.visible, "Escape actually closes screen")
	for gate in screen.gate_views: report.check(not gate.playing and not gate.blocker.visible, "close releases in-flight gate")
	screen.show()
	screen.refresh()
	await click_control(screen.node_views.act1_breath_01.hit_target)
	report.check(screen.selected_id == "act1_breath_01", "reopen remains interactive after cancelled animation")
	screen.apply_fixture("first_summit",true)
	await create_timer(1.8).timeout
	for gate in screen.gate_views: report.check(not gate.playing and not gate.blocker.visible, "natural animation completion releases input")
	screen.queue_free()
	await frames()
	var preview = load("res://godot/scenes/mastery/mastery_preview.tscn").instantiate()
	viewport.add_child(preview)
	await frames()
	screen = preview.screen
	report.check(preview.has_node("PreviewControls") and not screen.has_node("PreviewControls"), "developer controls isolated to preview wrapper")
	var fixture_definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/mastery/mastery_preview_fixtures.json"))
	for fixture: Dictionary in fixture_definitions:
		var button: Button
		for child: Node in preview.controls.get_children():
			if child is Button and child.text == fixture.label: button = child
		report.check(button != null, "preview fixture button exists " + str(fixture.id))
		if button != null:
			await click_control(button)
			report.check(screen.adapter.snapshot().fixture_id == fixture.id and screen.visible, "actual preview fixture button " + str(fixture.id))
		screen.skip_animations()
	await capture("preview-controls-next-run-1920x1080")
	viewport.size = Vector2i(1280,720)
	await frames()
	await capture("preview-controls-next-run-1280x720")
	viewport.queue_free()
	await frames()
	quit(report.finish("visual_capture", {"scope":"Windows native OpenGL-rendered SubViewport screenshots; real mouse and key InputEvents dispatched through viewport; not an OS-window automation or Linux/Web validation", "captures":captures, "resolutions":[[1920,1080],[1280,720],[960,600]]}))
