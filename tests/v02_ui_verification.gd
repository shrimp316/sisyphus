extends SceneTree

class InspectMain:
	extends "res://scripts/main.gd"
	var rendered_text: Array[String] = []
	func _draw() -> void:
		rendered_text.clear()
		super._draw()
	func _text(value: String, point: Vector2, font_size: int = 16, color: Color = INK) -> void:
		rendered_text.append(value)
		super._text(value, point, font_size, color)

var failures: int = 0
var checks: int = 0
var app: InspectMain
var capture: bool = false

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func frames(count: int = 4) -> void:
	for i in range(count): await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	app._unhandled_input(event)

func text_has(fragment: String) -> bool:
	for text: String in app.rendered_text:
		if fragment in text: return true
	return false

func snap(name: String) -> void:
	if not capture: return
	await frames()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.save_png("res://.tools/screenshots-v02/" + name + ".png") == OK, "GPU capture " + name)

func finish() -> void:
	print("V0.2 UI: %d checks, %d failures" % [checks, failures])
	if failures:
		app.sound.shutdown()
		await create_timer(0.1).timeout
		quit(1)
	else:
		app._save_and_quit()

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	app = InspectMain.new()
	root.add_child(app)
	await frames()
	app.set_physics_process(false)
	if "--guard-check" in OS.get_cmdline_user_args():
		var before := FileAccess.get_file_as_string(app.save_path)
		check(app.debug_course_enabled and app.save_blocked and not app.has_resume, "debug course refuses existing normal-world save")
		app._begin()
		check(app.screen == "title" and FileAccess.get_file_as_string(app.save_path) == before, "debug mismatch preserves normal save and best records")
		await finish()
		return
	if "--resume-check" in OS.get_cmdline_user_args():
		check(app.has_resume and app.boulder.state == "runaway" and is_equal_approx(app.boulder.runaway_elapsed, 1.2), "saved partial runaway timer is restored across processes")
		app._begin()
		key(KEY_E)
		check(app.boulder.state == "runaway", "resume cannot bypass remaining minimum fall presentation")
		app._physics_process(0.31)
		key(KEY_E)
		check(app.boulder.state == "result", "skip unlocks after resumed active fall time reaches1.5s")
		await finish()
		return
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1920 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1080, "reference viewport is1920x1080")
	if app.debug_course_enabled:
		check(app.mountain.debug_mode and app.best == 0.0 and not app.has_resume, "fresh debug course starts with isolated empty records")
		app._begin()
		key(KEY_F3)
		await frames()
		check(app.debug_overlay and text_has("DEBUG COURSE"), "F3 displays developer telemetry in debug course")
		await snap("07-debug-course")
		app.boulder.distance = app.mountain.total_length * 0.55
		app.camera_position = app.mountain.sample(app.boulder.distance)
		await snap("08-debug-course-middle")
		await finish()
		return
	await snap("01-title")
	key(KEY_ENTER)
	app.boulder.distance = 175.0
	app.boulder.peak = 175.0
	app.previous_best = 170.0
	app.best = 700.0
	app.boulder.velocity = 0.8
	app.camera_position = app.mountain.sample(175.0)
	app.boulder.slip = 40.0
	app._process(1.0)
	await frames()
	check(app.standard_hud_visible() and text_has("175 m") and not text_has("최고") and not text_has("1000") and not text_has("700"), "normal HUD exposes current distance only and hides total/best values")
	check(not text_has("SLIP") and app.slip_alpha == 0.0, "Slip40 remains hidden")
	await snap("02-normal-safe")
	app.boulder.slip = 41.0
	app._process(1.0)
	await frames()
	check(text_has("SLIP") and app.slip_alpha > 0.99, "Slip above40 fades in")
	await snap("03-slip-warning")
	app.record_crossed = false
	app._physics_process(1.0 / 120.0)
	check(app.record_crossed and app.record_flash > 0.0 and app.record_flash <= 0.5, "passing prior record highlights altitude briefly")
	key(KEY_F3)
	await frames()
	check(app.debug_overlay == OS.is_debug_build() and text_has("ACCELERATION") and text_has("PUSH FORCE") and text_has("RUN STATE"), "F3 telemetry available in normal developer build")
	await snap("04-debug-overlay-normal")
	key(KEY_F3)
	app.boulder.velocity = -2.5
	await snap("05-partial-fall")
	app.boulder.state = "runaway"
	app.boulder.runaway_elapsed = 0.0
	app.falls_seen = 0
	key(KEY_E)
	check(app.boulder.state == "runaway", "first runaway cannot be skipped")
	app.falls_seen = 2
	app.boulder.runaway_elapsed = 1.49
	key(KEY_E)
	check(app.boulder.state == "runaway", "later runaway cannot skip before1.5seconds")
	app.paused = true
	app._physics_process(2.0)
	check(is_equal_approx(app.boulder.runaway_elapsed, 1.49), "paused fall does not advance minimum skip timer")
	app.paused = false
	await frames()
	check(not app.standard_hud_visible() and not text_has("STAMINA") and not text_has("SLIP") and not text_has("175 m"), "runaway removes ordinary HUD")
	await snap("06-runaway")
	app.boulder.runaway_elapsed = 1.5
	key(KEY_E)
	check(app.boulder.state == "result", "later runaway skip unlocks at1.5seconds")
	app.boulder.state = "runaway"
	app.boulder.distance = 175.0
	app.boulder.velocity = -4.1
	app.boulder.runaway_elapsed = 1.2
	app.camera_position = app.mountain.sample(175.0)
	await finish()
