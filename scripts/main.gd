extends Node2D

const Mountain = preload("res://scripts/mountain_manager.gd")
const Boulder = preload("res://scripts/boulder_controller.gd")
const Art = preload("res://scripts/asset_visuals.gd")
var art: AssetVisuals = Art.new()
var impact_age: float = 10.0

const Audio = preload("res://scripts/soundscape.gd")
const INK: Color = Color("e8e1cc")
const MUTED: Color = Color("9ba8a4")
const GOLD: Color = Color("d8b678")
const RED: Color = Color("e7876c")
var mountain: MountainManager
var boulder: BoulderController
var sound: Soundscape
var path: Path2D
const KOREAN_FONT: Font = preload("res://assets/fonts/NotoSansKR.ttf")
var font: Font
var camera_position: Vector2 = Vector2.ZERO
var zoom: float = 1.0
var clock_time: float = 0.0
var screen: String = "title"
var paused: bool = false
var best: float = 0.0
var run_number: int = 1
var falls_seen: int = 0
var has_resume: bool = false
var save_path: String = "user://sisyphus-v1.json"
var buttons: Array[Dictionary] = []
var stone_shape: PackedVector2Array = PackedVector2Array()
var last_state: String = "climbing"
var summit_quiet: float = 0.0
var quitting: bool = false
var save_error: String = ""
var save_blocked: bool = false
var test_seed: int = -1
var test_weather: String = ""
var world_random: RandomNumberGenerator = RandomNumberGenerator.new()
var debug_course_enabled: bool = false
var debug_overlay: bool = false
var previous_best: float = 0.0
var record_crossed: bool = false
var record_flash: float = 0.0
var slip_alpha: float = 0.0
var feedback_time: float = 0.0
var feedback_text: String = ""
var camera_shake: Vector2 = Vector2.ZERO
var web_mode: bool = OS.has_feature("web")
var web_save_elapsed: float = 0.0
var web_notice: String = ""
var web_storage_error: String = ""
var web_page_callback: JavaScriptObject
var web_visibility_callback: JavaScriptObject

func _ready() -> void:
	get_tree().auto_accept_quit = false
	if web_mode:
		var web_font: FontVariation = FontVariation.new()
		web_font.base_font = KOREAN_FONT
		web_font.variation_opentype = {"wght": 400.0}
		font = web_font
	else:
		var system_font: SystemFont = SystemFont.new()
		system_font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Noto Sans", "Arial"])
		font = system_font
	path = Path2D.new()
	path.name = "MountainPath"
	add_child(path)
	sound = Audio.new()
	add_child(sound)
	for index: int in range(18):
		var angle: float = TAU * float(index) / 18.0
		var radius: float = 42.0 + sin(float(index) * 7.13) * 3.0
		stone_shape.append(Vector2(cos(angle), sin(angle)) * radius)
	# A test can supply an isolated save location via -- --save-path=...
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="):
			save_path = argument.trim_prefix("--save-path=")
		elif argument.begins_with("--seed="):
			test_seed = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--weather="):
			test_weather = argument.trim_prefix("--weather=")
		elif argument == "--debug-course" and OS.is_debug_build():
			debug_course_enabled = true
	if debug_course_enabled and ProjectSettings.globalize_path(save_path) == ProjectSettings.globalize_path("user://sisyphus-v1.json"):
		save_path = "user://sisyphus-debug-v02.json"
	world_random.randomize()
	_install_world(_fresh_world())
	_load_save()
	camera_position = mountain.sample(boulder.distance)
	if web_mode:
		_register_web_lifecycle()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_and_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "game":
		paused = true
		if web_mode:
			_save_for_web()

func _physics_process(delta: float) -> void:
	if screen != "game" or paused:
		return
	boulder.advance(delta, Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT), Input.is_physical_key_pressed(KEY_SHIFT), Input.is_physical_key_pressed(KEY_SPACE))
	if previous_best > 0.0 and not record_crossed and boulder.distance > previous_best:
		record_crossed = true
		record_flash = 0.5
	best = maxf(best, boulder.peak)
	if boulder.state == "result" and last_state != "result":
		falls_seen += 1
	if boulder.state == "summit" and last_state != "summit":
		summit_quiet = 0.0
	if web_mode and boulder.state != last_state:
		_save_for_web()
	last_state = boulder.state

func _process(delta: float) -> void:
	if not paused:
		impact_age += delta
	clock_time += delta
	if web_mode and screen == "game" and not paused:
		web_save_elapsed += delta
		if web_save_elapsed >= 5.0:
			_save_for_web()
	if not paused and screen == "game":
		record_flash = maxf(0.0, record_flash - delta)
		feedback_time = maxf(0.0, feedback_time - delta)
	slip_alpha = move_toward(slip_alpha, 1.0 if boulder.slip > 40.0 else 0.0, delta * 3.0)
	if boulder.state == "summit" and not paused and screen == "game":
		summit_quiet += delta
	var falling: bool = boulder.state == "runaway"
	var target: Vector2 = mountain.sample(boulder.distance)
	var lookahead: float = clampf(boulder.velocity * 35.0, -200.0, 90.0)
	camera_position = camera_position.lerp(target + Vector2(lookahead, 0.0), 1.0 - exp(-delta * 3.0))
	var fall_zoom: float = lerpf(0.94, 0.80, clampf(boulder.peak / mountain.total_length, 0.0, 1.0))
	zoom = lerpf(zoom, fall_zoom if falling else 1.0, 1.0 - exp(-delta * 2.0))
	var risk: float = clampf((boulder.slip - 70.0) / 30.0, 0.0, 1.0) if screen == "game" and not paused and not falling else 0.0
	camera_shake = Vector2(sin(boulder.elapsed * 43.0), cos(boulder.elapsed * 37.0)) * risk * 1.8
	sound.fill(boulder.velocity, falling, paused or screen != "game", boulder.state == "summit", str(mountain.surface_at(boulder.distance).id).to_lower(), mountain.wet_at(boulder.distance), boulder.stamina, boulder.slip, boulder.elapsed, boulder.action)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_M:
			sound.muted = not sound.muted
		elif event.keycode == KEY_F3 and OS.is_debug_build():
			debug_overlay = not debug_overlay
		elif event.keycode == KEY_ESCAPE and screen == "game":
			paused = not paused
			if web_mode and paused:
				_save_for_web()
		elif event.keycode == KEY_ENTER:
			if screen == "title":
				_begin()
			elif paused:
				paused = false
			elif boulder.state == "result" or (boulder.state == "summit" and summit_quiet >= 3.0):
				_new_run()
		elif event.keycode == KEY_E and screen == "game" and not paused and boulder.state == "runaway" and falls_seen > 0 and boulder.runaway_elapsed >= 1.5:
			boulder.finish_fall()
			falls_seen += 1
			last_state = "result"
			if web_mode:
				_save_for_web()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for button: Dictionary in buttons:
			if (button.rect as Rect2).has_point(get_global_mouse_position()):
				_button_action(str(button.action))
				break

func _button_action(action: String) -> void:
	match action:
		"begin": _begin()
		"resume": paused = false
		"new": _new_run()
		"quit": _save_and_quit()
		"mute": sound.muted = not sound.muted

func _begin() -> void:
	if save_blocked:
		return
	screen = "game"
	paused = false
	web_notice = ""
	if web_mode:
		_save_for_web()

func _fresh_world() -> MountainManager:
	if debug_course_enabled:
		return Mountain.debug_course()
	var seed_value: int = test_seed if test_seed >= 0 else world_random.randi_range(1, 2147483646)
	if mountain != null and test_seed < 0 and seed_value == mountain.seed_value:
		seed_value = (seed_value % 2147483646) + 1
	var world: MountainManager = Mountain.new(seed_value)
	if test_weather in ["clear", "rain"]:
		world.weather_id = test_weather
	return world

func _install_world(world: MountainManager) -> void:
	mountain = world
	path.curve = world.curve
	boulder = Boulder.new(mountain)
	boulder.recovered.connect(_recovery_feedback)
	if boulder.has_signal("ledge_crossed"):
		boulder.connect("ledge_crossed", _ledge_feedback)

func _recovery_feedback() -> void:
	impact_age = 0.0
	feedback_text = "돌을 다시 붙잡았다"
	feedback_time = 2.0
	sound.impact()

func _ledge_feedback(_distance: float) -> void:
	impact_age = 0.0
	feedback_text = "턱을 넘었다"
	feedback_time = 1.2
	sound.impact()

func _new_run() -> void:
	if save_blocked:
		return
	best = maxf(best, boulder.peak)
	previous_best = best
	record_crossed = false
	record_flash = 0.0
	feedback_time = 0.0
	run_number += 1
	_install_world(_fresh_world())
	last_state = "climbing"
	summit_quiet = 0.0
	camera_position = mountain.sample(0.0)
	screen = "game"
	paused = false
	if web_mode:
		_save_for_web()

func _load_save() -> void:
	var source: String = FileAccess.get_file_as_string(save_path) if FileAccess.file_exists(save_path) else ""
	if web_mode:
		var mirror: Dictionary = _read_web_mirror()
		var mirror_source: String = str(mirror.get("data", ""))
		if not mirror_source.is_empty():
			var mirrored: Variant = JSON.parse_string(mirror_source)
			var primary: Variant = JSON.parse_string(source) if not source.is_empty() else {}
			if not mirrored is Dictionary or not primary is Dictionary:
				save_blocked = true
				save_error = "브라우저 저장을 읽을 수 없습니다. 기존 기록을 보존했습니다."
				return
			if source.is_empty() or float(mirrored.get("saved_at_unix_msec", 0.0)) >= float(primary.get("saved_at_unix_msec", 0.0)):
				source = mirror_source
		if not bool(mirror.get("ok", false)) and not _web_userfs_persistent():
			web_notice = "이 브라우저는 저장을 허용하지 않습니다. 탭을 닫으면 진행이 사라질 수 있습니다."
	if source.is_empty():
		return
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		save_blocked = true
		save_error = "저장 파일을 읽을 수 없습니다. 기존 파일을 보존했습니다."
		return
	var saved: Dictionary = data as Dictionary
	var version: int = int(saved.get("version", 1))
	var restored_world: MountainManager = null
	if version == 1:
		restored_world = Mountain.new(1, true)
	elif version in [2, 3] and saved.get("world") is Dictionary:
		restored_world = Mountain.from_snapshot(saved.world as Dictionary)
	if restored_world == null or not saved.get("run") is Dictionary or restored_world.debug_mode != debug_course_enabled:
		save_blocked = true
		save_error = "저장된 산을 복원할 수 없습니다. 기존 파일을 보존했습니다."
		return
	_install_world(restored_world)
	best = maxf(0.0, float(saved.get("best", 0.0)))
	previous_best = maxf(0.0, float(saved.get("previous_best", best)))
	record_crossed = bool(saved.get("record_crossed", float(saved.run.get("peak", 0.0)) > previous_best))
	record_flash = clampf(float(saved.get("record_flash", 0.0)), 0.0, 0.5)
	run_number = maxi(1, int(saved.get("run_number", 1)))
	falls_seen = maxi(0, int(saved.get("falls_seen", 0)))
	if saved.get("run") is Dictionary:
		boulder.restore(saved.run as Dictionary)
		has_resume = true
		last_state = boulder.state

func _save_and_quit() -> void:
	if web_mode:
		paused = true
		if _save_for_web():
			screen = "title"
			paused = false
			has_resume = true
		return
	if quitting:
		return
	if save_blocked:
		quitting = true
		sound.shutdown()
		await get_tree().create_timer(0.1).timeout
		get_tree().quit()
		return
	quitting = true
	paused = true
	var failure: Error = _write_save_file(_save_payload())
	if failure != OK:
		save_error = "저장하지 못했습니다. 저장 위치를 확인한 뒤 다시 시도하세요."
		quitting = false
		push_warning("Could not save SISYPHUS run: " + error_string(failure))
		return
	save_error = ""
	sound.shutdown()
	# Give the audio mixer a cycle to release its generator playback reference.
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()

func _save_payload() -> Dictionary:
	return {"version": 3, "saved_at_unix_msec": Time.get_unix_time_from_system() * 1000.0, "best": best, "previous_best": previous_best, "record_crossed": record_crossed, "record_flash": record_flash, "run_number": run_number, "falls_seen": falls_seen, "world": mountain.snapshot(), "run": boulder.snapshot()}

func _write_save_file(payload: Dictionary) -> Error:
	var temporary_path: String = save_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	var failure: Error = OK
	if file != null:
		file.store_string(JSON.stringify(payload))
		file.flush()
		failure = file.get_error()
		file.close()
		if failure == OK:
			failure = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(save_path))
	else:
		failure = FileAccess.get_open_error()
	return failure

func _save_for_web() -> bool:
	if save_blocked or mountain == null or boulder == null:
		return false
	web_save_elapsed = 0.0
	var payload: Dictionary = _save_payload()
	var failure: Error = _write_save_file(payload)
	var mirrored: bool = _write_web_mirror(JSON.stringify(payload))
	if mirrored:
		save_error = ""
		web_notice = "이 브라우저에 저장했습니다. 처음 화면에서 이어갈 수 있습니다."
		return true
	if failure == OK and _web_userfs_persistent():
		# Godot queues IndexedDB synchronization after FileAccess.close(). The
		# localStorage fallback above is synchronous; this backend is asynchronous.
		save_error = ""
		web_notice = "브라우저 저장을 요청했습니다. 잠시 뒤 탭을 닫아 주세요."
		return true
	save_error = "브라우저 저장 공간을 사용할 수 없습니다. 탭을 닫으면 진행이 사라질 수 있습니다."
	return false

func _web_storage_key_expression() -> String:
	# Directory scoping treats /game/ and /game/index.html as the same game.
	return "'sisyphus:v02:' + new window.URL('.', window.location.href).pathname + ':' + " + JSON.stringify(save_path)

func _read_web_mirror() -> Dictionary:
	if not OS.has_feature("web"):
		return {"ok": false, "data": ""}
	var source: String = "(function(){try{return window.JSON.stringify({ok:true,data:window.localStorage.getItem(" + _web_storage_key_expression() + ")||''});}catch(e){return window.JSON.stringify({ok:false,data:'',error:e.name+': '+e.message});}})()"
	var result: Variant = JavaScriptBridge.eval(source, true)
	var decoded: Variant = JSON.parse_string(str(result))
	if decoded is Dictionary and not bool(decoded.get("ok", false)):
		_report_web_storage_failure(str(decoded.get("error", "Storage read unavailable")))
	return decoded as Dictionary if decoded is Dictionary else {"ok": false, "data": ""}

func _write_web_mirror(payload: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var source: String = "(function(){try{window.localStorage.setItem(" + _web_storage_key_expression() + "," + JSON.stringify(payload) + ");return window.JSON.stringify({ok:true});}catch(e){return window.JSON.stringify({ok:false,error:e.name+': '+e.message});}})()"
	var result: Variant = JavaScriptBridge.eval(source, true)
	var decoded: Variant = JSON.parse_string(str(result))
	if decoded is Dictionary and bool(decoded.get("ok", false)):
		web_storage_error = ""
		return true
	_report_web_storage_failure(str(decoded.get("error", "Storage write unavailable")) if decoded is Dictionary else "Storage result unavailable")
	return false

func _report_web_storage_failure(message: String) -> void:
	if message != web_storage_error:
		web_storage_error = message
		# Only the browser error is logged; never the saved game or its payload.
		push_warning("Browser save mirror unavailable: " + message)

func _web_userfs_persistent() -> bool:
	return OS.is_userfs_persistent()

func _register_web_lifecycle() -> void:
	if not OS.has_feature("web"):
		return
	web_page_callback = JavaScriptBridge.create_callback(_web_page_hidden)
	web_visibility_callback = JavaScriptBridge.create_callback(_web_visibility_changed)
	JavaScriptBridge.get_interface("window").addEventListener("pagehide", web_page_callback)
	JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", web_visibility_callback)

func _web_page_hidden(_arguments: Array) -> void:
	if screen == "game":
		paused = true
		_save_for_web()

func _web_visibility_changed(_arguments: Array) -> void:
	if JavaScriptBridge.eval("window.document.hidden", true) == true:
		_web_page_hidden([])

func _world(point: Vector2) -> Vector2:
	var size: Vector2 = get_viewport_rect().size
	return (point - camera_position) * zoom + Vector2(size.x * 0.36, size.y * 0.67) + camera_shake

func _text(text: String, point: Vector2, size: int = 16, color: Color = INK) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _ui_font_size(size), color)

func _ui_font_size(size: int) -> int:
	# Preserve readable type when the 1920 canvas is shown in a 1280 window.
	return maxi(20, roundi(float(size) * 1.25))

func _center(text: String, y: float, size: int, color: Color = INK) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _ui_font_size(size)).x
	_text(text, Vector2((get_viewport_rect().size.x - width) * 0.5, y), size, color)

func standard_hud_visible() -> bool:
	return screen == "game" and boulder.state not in ["summit", "runaway"]

func _draw() -> void:
	if mountain == null:
		return
	buttons.clear()
	var size: Vector2 = get_viewport_rect().size
	_draw_sky(size)
	_draw_terrain(size)
	_draw_character()
	_draw_stone()
	_draw_asset_effects()
	_draw_weather(size)
	_draw_foreground(size)
	if screen == "title":
		_draw_title(size)
	else:
		if standard_hud_visible():
			_draw_hud(size)
		elif boulder.state == "runaway" and falls_seen > 0 and boulder.runaway_elapsed >= 1.5:
			_center("E  추락 건너뛰기", size.y - 50.0, 16, MUTED)
		if boulder.state == "result":
			_draw_result(size)
		elif boulder.state == "summit" and summit_quiet >= 3.0:
			_draw_summit(size)
		if paused:
			_draw_pause(size)
	if debug_overlay and OS.is_debug_build():
		_draw_debug(size)
	if not save_error.is_empty():
		_center(save_error, size.y - 76.0, 16, RED)
	elif web_mode and not web_notice.is_empty() and (screen == "title" or paused):
		_center(web_notice, size.y - 76.0, 16, MUTED)

func _draw_sky(size: Vector2) -> void:
	var progress: float = boulder.distance / mountain.total_length
	var top: Color = Color("111e29").lerp(Color("273947"), progress)
	var bottom: Color = Color("7b8583").lerp(Color("d5bb93"), progress)
	if mountain.weather_id == "rain":
		top = top.lerp(Color("303d48"), 0.65)
		bottom = bottom.lerp(Color("657782"), 0.80)
	for stripe: int in range(48):
		var amount: float = float(stripe) / 47.0
		draw_rect(Rect2(0.0, size.y * amount, size.x, size.y / 47.0 + 1.0), top.lerp(bottom, amount))
	var sun: Vector2 = Vector2(size.x * 0.79, size.y * 0.27)
	draw_circle(sun, 72.0, Color(0.88, 0.79, 0.59, 0.025))
	draw_circle(sun, 50.0, Color(0.88, 0.79, 0.59, 0.035))
	draw_circle(sun, 32.0, Color(0.83, 0.77, 0.62, 0.12 if mountain.weather_id == "rain" else 0.4))
	for layer: int in range(3):
		var ridge: PackedVector2Array = PackedVector2Array()
		ridge.append(Vector2(-40.0, size.y))
		for index: int in range(40):
			var x: float = float(index) / 37.0 * size.x - 30.0
			var scroll: float = camera_position.x * (0.0009 + float(layer) * 0.0003)
			var wave: float = sin(float(index) * 0.47 + scroll) * 76.0 + sin(float(index) * 1.19 + float(layer) * 4.0) * 30.0
			ridge.append(Vector2(x, size.y * (0.43 + float(layer) * 0.09) + wave))
		ridge.append(Vector2(size.x + 40.0, size.y))
		draw_colored_polygon(ridge, [Color("52656a"), Color("3c5157"), Color("293e46")][layer])
	for index: int in range(16):
		var x: float = fposmod(float(index) * 149.0 - clock_time * (8.0 + float(index % 3) * 5.0), size.x + 100.0) - 50.0
		var y: float = 100.0 + fposmod(float(index) * 97.0, size.y * 0.55)
		draw_line(Vector2(x, y), Vector2(x + 18.0, y - 1.5), Color(0.85, 0.86, 0.76, 0.08), 1.0)

func _draw_terrain(size: Vector2) -> void:
	var polygon: PackedVector2Array = PackedVector2Array()
	var line: PackedVector2Array = PackedVector2Array()
	var from: float = maxf(0.0, boulder.distance - 120.0)
	var to: float = minf(mountain.total_length, boulder.distance + 180.0)
	if from == 0.0:
		line.append(_world(Vector2(-1800.0, 0.0)))
	var d: float = from
	while d < to:
		line.append(_world(mountain.sample(d)))
		d += 0.5
	line.append(_world(mountain.sample(to)))
	if to == mountain.total_length:
		line.append(_world(mountain.sample(mountain.total_length) + Vector2(1800.0, 0.0)))
	polygon.append_array(line)
	polygon.append(Vector2(line[-1].x, size.y + 2000.0))
	polygon.append(Vector2(line[0].x, size.y + 2000.0))
	draw_colored_polygon(polygon, Color("1b2a30"))
	draw_polyline(line, Color("aca184"), 3.0 * zoom, true)
	# A shallow material layer follows each slope and shelf. Transitions are
	# visible before the stone reaches them, matching the physics boundary.
	for segment: Dictionary in mountain.segments:
		var segment_start: float = maxf(from, float(segment.start))
		var segment_end: float = minf(to, float(segment.end))
		if segment_start >= segment_end:
			continue
		var edge: PackedVector2Array = PackedVector2Array()
		var cursor: float = segment_start
		while cursor < segment_end:
			edge.append(_world(mountain.sample(cursor)))
			cursor += 0.5
		edge.append(_world(mountain.sample(segment_end)))
		for sample_index: int in range(edge.size() - 1):
			var sample_distance: float = minf(segment_end, segment_start + float(sample_index) * 0.5 + 0.25)
			var local_color: Color = mountain.surface_at(sample_distance).color
			if mountain.wet_at(sample_distance):
				local_color = local_color.darkened(0.26)
			draw_colored_polygon(PackedVector2Array([edge[sample_index], edge[sample_index + 1], edge[sample_index + 1] + Vector2(0.0, 17.0 * zoom), edge[sample_index] + Vector2(0.0, 17.0 * zoom)]), local_color.darkened(0.35))
			draw_line(edge[sample_index], edge[sample_index + 1], local_color, 4.0 * zoom, true)
			if mountain.wet_at(sample_distance):
				draw_line(edge[sample_index], edge[sample_index + 1], Color(0.65, 0.78, 0.83, 0.58), 2.0 * zoom, true)
	_draw_asset_ground(from, to)
	for index: int in range(int(from), int(to), 3):
		var p: Vector2 = _world(mountain.sample(float(index)))
		var spread: float = 15.0 + fposmod(sin(float(index) * 78.13) * 998.0, 80.0)
		draw_line(p + Vector2(-8.0, 10.0) * zoom, p + Vector2(12.0, spread) * zoom, Color(0.47, 0.52, 0.48, 0.10), zoom)
		var material_id: String = str(mountain.surface_at(float(index)).id).to_lower()
		if material_id == "gravel":
			for pebble: int in range(4):
				var offset: Vector2 = Vector2(float(pebble) * 11.0 - 18.0, 4.0 + float((index + pebble) % 3) * 3.0)
				draw_circle(p + offset * zoom, (1.4 + float(pebble % 2)) * zoom, Color("a49b86"))
		elif material_id in ["soil", "mud"]:
			draw_line(p + Vector2(-14.0, 6.0) * zoom, p + Vector2(13.0, 10.0) * zoom, Color("79604a"), 2.0 * zoom)
	for segment: Dictionary in mountain.segments:
		if not bool(segment.shelf):
			continue
		var shelf_start: float = float(segment.start)
		if shelf_start >= from and shelf_start <= to:
			var p: Vector2 = _world(mountain.sample(shelf_start + minf(5.0, (float(segment.end) - shelf_start) * 0.5)))
			_draw_shelf_art(p, int(shelf_start))
			draw_line(p, p + Vector2(0.0, -42.0) * zoom, Color("726e56"), 2.0 * zoom)
			draw_line(p + Vector2(-10.0, -31.0) * zoom, p + Vector2(10.0, -31.0) * zoom, GOLD.darkened(0.2), 3.0 * zoom)
			if zoom > 0.8:
				_text("쉼터", p + Vector2(-17.0, -52.0), 12, MUTED)
	for rest_distance: float in mountain.rest_points:
		if rest_distance >= from and rest_distance <= to:
			var rest: Vector2 = _world(mountain.sample(rest_distance))
			Art.draw_at(self, art.texture("res://assets/terrain/foothold_rest_platform.png"), rest, Vector2(256, 106), 0.16 * zoom)
			Art.draw_at(self, art.texture("res://assets/ui/markers/rest_point_marker.png"), rest, Vector2(128, 232), 0.13 * zoom)
			draw_polyline(PackedVector2Array([rest + Vector2(-15, -5) * zoom, rest + Vector2(-6, 3) * zoom, rest + Vector2(7, 3) * zoom, rest + Vector2(15, -5) * zoom]), Color("8fa79a"), 3.0 * zoom, true)
	for ledge: Dictionary in mountain.ledges:
		var distance: float = float(ledge.distance)
		if distance >= from and distance <= to:
			var p: Vector2 = _world(mountain.sample(distance))
			Art.draw_at(self, art.texture("res://assets/terrain/small_stone_step.png"), p, Vector2(256, 99), 0.11 * zoom)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-13, 0) * zoom, p + Vector2(-3, -15) * zoom, p + Vector2(14, -9) * zoom, p + Vector2(20, 2) * zoom]), Color("a7aaa1"))
			draw_line(p + Vector2(-3, -15) * zoom, p + Vector2(14, -9) * zoom, INK, 2.0 * zoom)
	if previous_best > 0.0 and previous_best < mountain.total_length and previous_best >= from and previous_best <= to:
		var p: Vector2 = _world(mountain.sample(previous_best))
		var cairn_drawn: bool = Art.draw_at(self, art.texture("res://assets/props/cairn_checkpoint.png"), p, Vector2(192, 352), 0.20 * zoom)
		Art.draw_at(self, art.texture("res://assets/ui/markers/previous_record_marker.png"), p + Vector2(0, -65) * zoom, Vector2(128, 232), 0.16 * zoom)
		if not cairn_drawn:
			for rock: int in range(3):
				draw_circle(p + Vector2(0.0, -5.0 - float(rock) * 6.0) * zoom, (8.0 - float(rock) * 2.0) * zoom, GOLD.darkened(float(rock) * 0.1))
	for marker: int in range(0, int(mountain.total_length) + 1, 100):
		if float(marker) >= from and float(marker) <= to:
			var p: Vector2 = _world(mountain.sample(float(marker)))
			draw_rect(Rect2(p + Vector2(-13.0, -22.0) * zoom, Vector2(26.0, 22.0) * zoom), Color("48504a"))
			_text(str(marker), p + Vector2(-11.0, -6.0) * zoom, int(11.0 * zoom), INK)

func _draw_asset_ground(from: float, to: float) -> void:
	# Repeat flat artwork on the authored slope; rendering never changes its path.
	var wet_edges: Array[float] = []
	var chunk_origin: float = 0.0
	if mountain.weather_id == "rain":
		for chunk: Dictionary in mountain.chunks:
			for interval: Variant in chunk.get("wet_ranges", []):
				wet_edges.append(chunk_origin + float(interval[0]))
				wet_edges.append(chunk_origin + float(interval[1]))
			chunk_origin += float(chunk.length)
	if from == 0.0:
		var base_tex: Texture2D = art.terrain(str(mountain.surface_at(0.0).id), mountain.wet_at(0.0))
		for tile: int in range(1, 10):
			Art.draw_at(self, base_tex, _world(Vector2(-216.0 * tile, 0)), Vector2(0, 64), 216.0 / 512.0 * zoom)
	for segment: Dictionary in mountain.segments:
		var origin: float = float(segment.start)
		# Anchor tile phase to the mountain, so the texture never swims with the camera.
		var start: float = origin + maxf(0.0, floorf((from - origin) / 12.0)) * 12.0
		var end: float = minf(to, float(segment.end))
		var cursor: float = start
		while cursor < end:
			var phase: float = fposmod(cursor - origin, 12.0)
			var finish: float = minf(cursor + 12.0 - phase, end)
			for wet_edge: float in wet_edges:
				if wet_edge > cursor + 0.001 and wet_edge < finish:
					finish = wet_edge
			var tex: Texture2D = art.terrain(str(mountain.surface_at((cursor + finish) * 0.5).id), mountain.wet_at((cursor + finish) * 0.5))
			if tex != null:
				var a: Vector2 = _world(mountain.sample(cursor))
				var b: Vector2 = _world(mountain.sample(finish))
				var tangent: Vector2 = (b - a).normalized()
				var normal: Vector2 = Vector2(-tangent.y, tangent.x)
				var scale_value: float = 216.0 / 512.0 * zoom
				var top: Vector2 = normal * -64.0 * scale_value
				var bottom: Vector2 = normal * 192.0 * scale_value
				var uv_start: float = phase / 12.0
				var uv_end: float = uv_start + (finish - cursor) / 12.0
				draw_polygon(PackedVector2Array([a + top, b + top, b + bottom, a + bottom]), PackedColorArray([Color.WHITE]), PackedVector2Array([Vector2(uv_start, 0), Vector2(uv_end, 0), Vector2(uv_end, 1), Vector2(uv_start, 1)]), tex)
			cursor = finish

func _draw_shelf_art(position: Vector2, index: int) -> void:
	var names: Array[String] = ["broken_signpost", "dead_tree", "small_tree", "ruin_pillar", "shrine_fragment", "simple_arch_ruin"]
	var name: String = names[absi(index / 50) % names.size()]
	Art.draw_at(self, art.texture("res://assets/props/%s.png" % name), position + Vector2(45, 1) * zoom, Vector2(192, 352), 0.26 * zoom, 0.0, Color(0.80, 0.84, 0.83, 0.85))

func _draw_asset_effects() -> void:
	var ground: Vector2 = _world(mountain.sample(boulder.distance))
	var feet: Vector2 = _world(mountain.sample(maxf(0.0, boulder.distance - 3.7)))
	if boulder.state == "climbing" and boulder.action in ["push", "exert", "brace", "slip"]:
		var effect: String = "gravel" if str(mountain.surface_at(boulder.distance).id).to_lower() == "gravel" else "dust"
		Art.draw_at(self, art.frame("fx", effect, boulder.elapsed), feet, Vector2(128, 224), 0.25 * zoom, 0.0, Color(1, 1, 1, 0.7))
	if impact_age < 6.0 / 14.0:
		Art.draw_at(self, art.frame("fx", "impact", impact_age, false), ground, Vector2(128, 224), 0.38 * zoom)
	if boulder.stamina < 30.0 and boulder.state == "climbing":
		Art.draw_at(self, art.frame("fx", "breath", boulder.elapsed), feet + Vector2(14, -54) * zoom, Vector2(128, 128), 0.17 * zoom)
	Art.draw_at(self, art.frame("fx", "wind", clock_time), ground + Vector2(130, -125) * zoom, Vector2(128, 128), 0.65 * zoom, 0.0, Color(1, 1, 1, 0.16))

func _draw_weather(size: Vector2) -> void:
	if mountain.weather_id != "rain":
		return
	for index: int in range(110):
		var speed: float = 390.0 + float(index % 5) * 39.0
		var x: float = fposmod(float(index) * 137.31 - clock_time * 86.0, size.x + 90.0) - 45.0
		var y: float = fposmod(float(index) * 91.73 + clock_time * speed, size.y + 80.0) - 40.0
		draw_line(Vector2(x, y), Vector2(x - 4.5, y + 19.0), Color(0.72, 0.83, 0.88, 0.16), 1.0)

func _draw_stone() -> void:
	var angle: float = mountain.angle_at(boulder.distance)
	var center: Vector2 = _world(mountain.sample(boulder.distance) + Vector2(-sin(angle), -cos(angle)) * 43.0)
	var rotation: float = boulder.distance * MountainManager.PIXELS_PER_METER / 43.0
	var variant: String = "wet" if mountain.wet_at(boulder.distance) else ("rough" if str(mountain.surface_at(boulder.distance).id).to_lower() == "gravel" else "default")
	if Art.draw_at(self, art.texture("res://assets/boulder/boulder_%s.png" % variant), center, Vector2(192, 192), 43.0 / 176.0 * zoom, rotation):
		return
	var shape: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in stone_shape:
		shape.append(center + p.rotated(rotation) * zoom)
	draw_circle(center + Vector2(4.0, 32.0) * zoom, 39.0 * zoom, Color(0.02, 0.03, 0.04, 0.25))
	draw_colored_polygon(shape, Color("8d9287"))
	for index: int in range(18):
		var a: Vector2 = shape[index]
		var b: Vector2 = shape[(index + 1) % 18]
		var light: float = clampf((center.y - (a.y + b.y) * 0.5) / (90.0 * zoom) + 0.35, 0.1, 0.7)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-8.0, -6.0) * zoom, a, b]), Color("c3c2a9").lerp(Color("4e5b59"), 1.0 - light))
	for index: int in range(32):
		var local: Vector2 = Vector2(sin(float(index) * 8.11), cos(float(index) * 4.71)) * (10.0 + float(index % 5) * 5.0)
		var p: Vector2 = center + local.rotated(rotation) * zoom
		draw_circle(p, (0.8 + float(index % 3) * 0.5) * zoom, Color(0.15, 0.23, 0.24, 0.23))
	var crack: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in [Vector2(-18, -28), Vector2(-6, -12), Vector2(-12, 2), Vector2(5, 11), Vector2(11, 33)]:
		crack.append(center + p.rotated(rotation) * zoom)
	draw_polyline(crack, Color("4a5754"), 1.5 * zoom, true)

func _draw_character() -> void:
	if boulder.state == "runaway" or boulder.state == "result":
		return
	var d: float = boulder.distance - 3.7
	var ground: Vector2 = mountain.sample(d) if d >= 0.0 else mountain.sample(0.0) + Vector2(d * MountainManager.PIXELS_PER_METER, 0.0)
	var base: Vector2 = _world(ground)
	var animation: String = Art.character_animation(boulder.action, boulder.stamina)
	if Art.draw_at(self, art.frame("sisyphus", animation, boulder.elapsed), base, Vector2(256, 464), 0.18 * zoom):
		return
	if boulder.slip > 40.0 and not paused:
		for grain: int in range(7):
			var drift: float = fposmod(boulder.elapsed * 1.8 + float(grain) * 0.17, 1.0)
			var dust: Vector2 = Vector2(-drift * 30.0 - float(grain % 3) * 3.0, -sin(drift * PI) * 12.0)
			draw_circle(base + dust * zoom, 1.2 * zoom, Color(0.7, 0.65, 0.52, (1.0 - drift) * 0.35))
	var movement: float = sin(boulder.elapsed * (5.0 if boulder.stamina < 20.0 else 8.0)) * minf(absf(boulder.velocity), 1.0)
	var leaning: float = 11.0 if boulder.action in ["push", "exert", "brace"] else 2.0
	var hip: Vector2 = base + Vector2(-4.0, -25.0) * zoom
	var breath_phase: float = fmod(boulder.elapsed, 6.0)
	var breath_lift: float = breath_phase / 2.0 if breath_phase < 2.0 else (1.0 if breath_phase < 3.0 else (6.0 - breath_phase) / 3.0)
	var exhaustion: float = clampf((30.0 - boulder.stamina) / 30.0, 0.0, 1.0)
	var shoulder: Vector2 = base + Vector2(leaning + exhaustion * 5.0, -49.0 + exhaustion * 6.0 - breath_lift * (2.0 + exhaustion * 2.0)) * zoom
	var skin: Color = Color("c0a480")
	draw_line(base + Vector2(-12.0 - movement * 7.0, -1.0) * zoom, hip, Color("1b2023"), 7.0 * zoom, true)
	draw_line(base + Vector2(8.0 + movement * 7.0, -2.0) * zoom, hip, Color("1b2023"), 7.0 * zoom, true)
	draw_line(hip, shoulder, Color("b1a58a"), 13.0 * zoom, true)
	draw_circle(shoulder + Vector2(0.0, -11.0) * zoom, 7.0 * zoom, skin)
	var hand: Vector2 = shoulder + Vector2(22.0, 6.0) * zoom if leaning > 2.0 else hip + Vector2(12.0, -1.0) * zoom
	draw_line(shoulder, hand, skin, 5.0 * zoom, true)
	draw_colored_polygon(PackedVector2Array([hip + Vector2(-9.0, -9.0) * zoom, hip + Vector2(10.0, -8.0) * zoom, hip + Vector2(13.0, 10.0) * zoom, hip + Vector2(-12.0, 8.0) * zoom]), Color("675c4b"))
	var scarf_end: Vector2 = shoulder + Vector2(-35.0, 7.0 + sin(clock_time * 3.0) * 4.0) * zoom
	draw_line(shoulder + Vector2(-3.0, -2.0) * zoom, scarf_end, Color("b97e5d"), 4.0 * zoom, true)

func _draw_foreground(size: Vector2) -> void:
	# Soft film bands anchor the information without enclosing the world in panels.
	for stripe: int in range(12):
		var alpha: float = 0.25 * (1.0 - float(stripe) / 12.0)
		draw_rect(Rect2(0.0, float(stripe) * 12.0, size.x, 12.0), Color(0.03, 0.05, 0.07, alpha))
		draw_rect(Rect2(0.0, size.y - float(stripe + 1) * 9.0, size.x, 9.0), Color(0.03, 0.05, 0.07, alpha))

func _bar(point: Vector2, width: float, value: float, color: Color) -> void:
	draw_rect(Rect2(point, Vector2(width, 4.0)), Color(1.0, 1.0, 1.0, 0.12))
	draw_rect(Rect2(point, Vector2(width * clampf(value, 0.0, 1.0), 4.0)), color)

func _draw_hud(size: Vector2) -> void:
	Art.draw_at(self, art.texture("res://assets/ui/icons/height_marker_icon.png"), Vector2(30, 65), Vector2(64, 64), 0.22)
	_text("%d m" % int(boulder.distance), Vector2(54, 82), 44, GOLD if record_flash > 0.0 else INK)
	_text("시도 %02d  ·  %s" % [run_number, mountain.zone(boulder.distance)], Vector2(56, 113), 15, MUTED)
	var terrain: Dictionary = mountain.surface_at(boulder.distance)
	_text("%s  ·  %s" % [str(terrain.label), mountain.weather_label()], Vector2(56, 143), 15, INK)
	if mountain.wet_at(boulder.distance):
		_text("젖은 구간 · 접지력 감소", Vector2(56, 171), 14, GOLD)
	var y: float = size.y - 115.0
	Art.draw_at(self, art.texture("res://assets/ui/icons/stamina_icon.png"), Vector2(26, y - 6), Vector2(64, 64), 0.20)
	_text("STAMINA", Vector2(42, y), 15, MUTED)
	_bar(Vector2(42, y + 12.0), 248.0, boulder.stamina / 100.0, RED if boulder.stamina < 20.0 else GOLD)
	if slip_alpha > 0.01:
		var slip_color: Color = RED if boulder.slip > 70.0 else GOLD
		slip_color.a = slip_alpha
		Art.draw_at(self, art.texture("res://assets/ui/icons/slip_icon.png"), Vector2(316, y - 6), Vector2(64, 64), 0.20, 0.0, slip_color)
		_text("SLIP", Vector2(332, y), 15, slip_color)
		draw_rect(Rect2(332, y + 12.0, 200.0, 4.0), Color(1.0, 1.0, 1.0, 0.12 * slip_alpha))
		draw_rect(Rect2(332, y + 12.0, 200.0 * boulder.slip / 100.0, 4.0), slip_color)
	var sweet: bool = boulder.velocity >= 0.45 and boulder.velocity <= 1.2
	if boulder.action in ["brace", "exert"]:
		var action_icon: String = "brace" if boulder.action == "brace" else "push_burst"
		Art.draw_at(self, art.texture("res://assets/ui/icons/%s_icon.png" % action_icon), Vector2(size.x - 274, y - 6), Vector2(64, 64), 0.24)
	var pace: String = "좋은 흐름" if sweet else ("속도를 줄이세요" if boulder.velocity > 1.5 else ("뒤로 밀립니다" if boulder.velocity < -0.08 else "천천히, 한 걸음"))
	_text(pace, Vector2(size.x - 250.0, y), 17, GOLD if sweet else MUTED)
	var hint: String = "쉼터까지 %d m" % ceili(mountain.distance_to_shelf(boulder.distance))
	if mountain.distance_to_shelf(boulder.distance) > 0.0 and mountain.distance_to_shelf(boulder.distance) < 5.0:
		hint = "쉼터가 가깝습니다 · 미리 손을 놓고 속도를 줄이세요"
	if mountain.is_shelf(boulder.distance):
		hint = "쉼터 · 손을 놓고 호흡을 고르세요"
	if boulder.slip >= 75.0:
		hint = "발밑이 불안합니다 · 힘주기를 멈추고 균형을 되찾으세요"
	if boulder.slip_remaining > 0.0:
		hint = "발이 미끄러집니다 · 곧 Space로 버티세요"
	elif boulder.velocity < -0.08:
		hint = boulder.rollback_stage()
	if feedback_time > 0.0:
		hint = feedback_text
	_center(hint, size.y - 164.0, 19, RED if boulder.velocity < -1.0 else INK)
	_text("D / →  밀기     Shift + 밀기  힘주기     Space  버티기", Vector2(42, size.y - 36.0), 14, INK)
	_text("M  " + ("소리 꺼짐" if sound.muted else "소리 켜짐") + "     Esc  메뉴", Vector2(size.x - 265.0, size.y - 36.0), 13, MUTED)
	if boulder.state == "climbing" and boulder.distance < 12.0 and boulder.elapsed < 25.0:
		_center("돌을 밀어 보세요. 힘보다 중요한 것은, 멈출 때를 아는 일.", size.y * 0.30, 18, INK)

func _draw_debug(size: Vector2) -> void:
	var telemetry: Dictionary = boulder.telemetry()
	var names: Array[String] = ["distance", "velocity", "acceleration", "slope", "push_force", "gravity_force", "stamina", "slip", "surface", "run_state"]
	var origin: Vector2 = Vector2(size.x - 380.0, 40.0)
	draw_rect(Rect2(origin, Vector2(338.0, 346.0)), Color(0.02, 0.04, 0.06, 0.92))
	_text("F3 · DEBUG" + (" COURSE" if debug_course_enabled else ""), origin + Vector2(18, 28), 17, GOLD)
	for index: int in range(names.size()):
		var value: Variant = telemetry.get(names[index], "—")
		var label: String = "%.3f" % float(value) if value is float or value is int else str(value)
		_text(names[index].to_upper().replace("_", " ") + "  " + label, origin + Vector2(18.0, 58.0 + float(index) * 28.0), 15, INK)

func _button(label: String, rect: Rect2, action: String, primary: bool = false) -> void:
	var hovered: bool = rect.has_point(get_global_mouse_position())
	draw_rect(rect, Color(0.82, 0.73, 0.54, 0.18 if hovered else 0.08) if primary else Color(0.1, 0.15, 0.18, 0.65))
	draw_rect(rect, GOLD if primary else Color("56605d"), false, 1.0)
	var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _ui_font_size(17)).x
	_text(label, Vector2(rect.position.x + (rect.size.x - text_width) * 0.5, rect.position.y + 34.0), 17, INK)
	buttons.append({"rect": rect, "action": action})

func _draw_title(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.055, 0.075, 0.52))
	_center("A STONE. A MOUNTAIN. ANOTHER BEGINNING.", size.y * 0.25, 13, MUTED)
	_center("S I S Y P H U S", size.y * 0.37, 62, INK)
	_center("시 지 프 스", size.y * 0.43, 19, GOLD)
	_center("이번에는, 조금 더 올라갈 수 있을 것 같다.", size.y * 0.52, 19, INK)
	if not save_blocked:
		_button("이어 오르기  ↵" if has_resume else "돌 앞에 서기  ↵", Rect2(size.x * 0.5 - 145.0, size.y * 0.60, 290.0, 54.0), "begin", true)
	else:
		_center("저장 파일을 확인한 뒤 다시 실행해 주세요.", size.y * 0.65, 16, RED)
	_center("D / → 밀기   ·   Shift 힘주기   ·   Space 버티기", size.y * 0.76, 15, INK)
	_center("쉼터에서 손을 놓으면 호흡과 균형이 돌아옵니다.", size.y * 0.80, 14, MUTED)
	_text("MOUNTAIN & WEATHER / 0.2", Vector2(36, size.y - 30.0), 11, MUTED)
	_text("F11 전체 화면   ·   M 소리", Vector2(size.x - 230.0, size.y - 30.0), 12, MUTED)

func _draw_pause(size: Vector2) -> void:
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.06, 0.88))
	_center("잠시, 숨을 고르다", size.y * 0.27, 32, INK)
	_center("5초마다 현재 진행을 자동 저장합니다. 저장은 이 브라우저에만 남습니다." if web_mode else "종료할 때 현재 위치가 저장됩니다. 추락을 되돌리는 체크포인트는 없습니다.", size.y * 0.34, 15, MUTED)
	_button("계속 오르기  ·  Esc", Rect2(size.x * 0.5 - 170.0, size.y * 0.41, 340.0, 54.0), "resume", true)
	_button("소리 " + ("켜기" if sound.muted else "끄기"), Rect2(size.x * 0.5 - 170.0, size.y * 0.41 + 72.0, 340.0, 54.0), "mute")
	_button("저장하고 처음 화면으로" if web_mode else "저장 후 종료", Rect2(size.x * 0.5 - 170.0, size.y * 0.41 + 144.0, 340.0, 54.0), "quit")
	_center("일반 밀기 · 호흡 소모 적음     힘주기 · 미끄러짐 증가", size.y * 0.78, 14, MUTED)
	_center("뒤로 굴러갈 때 Space → 멈춘 뒤 다시 D", size.y * 0.82, 14, INK)

func _draw_result(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.06, 0.80))
	_center("돌은 다시, 산 아래에", size.y * 0.30, 35, INK)
	_center("이번에는 %d m까지 올랐습니다." % int(boulder.peak), size.y * 0.39, 22, GOLD)
	_center("%d분 %02d초   ·   미끄러짐 %d회   ·   최고 %d m" % [int(boulder.elapsed / 60.0), int(boulder.elapsed) % 60, boulder.slips, int(best)], size.y * 0.45, 16, MUTED)
	_center("다음 산길은 조금 다를 것이다. 오르는 사람도.", size.y * 0.53, 17, INK)
	_button("다시 돌 앞에 서기  ↵", Rect2(size.x * 0.5 - 160.0, size.y * 0.61, 320.0, 54.0), "new", true)

func _draw_summit(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.12, 0.14, 0.55))
	_center("정상", size.y * 0.29, 42, INK)
	_center("잠시, 아무것도 밀지 않아도 된다.", size.y * 0.45, 22, INK)
	_center("이 고요함을 기억한다.", size.y * 0.51, 16, MUTED)
	_button("새로운 등반  ↵", Rect2(size.x * 0.5 - 150.0, size.y * 0.64, 300.0, 54.0), "new", true)
