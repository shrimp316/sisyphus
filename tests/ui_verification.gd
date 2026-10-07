extends SceneTree

var failures: int = 0
var app: Node2D
var capture: bool = false

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	app._unhandled_input(event)

func frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func snap(name: String) -> void:
	if not capture: return
	await frames(4)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var destination := "res://.tools/screenshots/" + name + ".png"
	check(image.save_png(destination) == OK, "render capture " + name)

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await frames()
	app.set_physics_process(false)
	if "--resume-check" in OS.get_cmdline_user_args():
		check(app.has_resume and app.run_number == 7 and app.falls_seen == 2, "persisted run metadata loads")
		check(app.boulder.distance == 432.125 and app.boulder.velocity == -1.5 and app.boulder.stamina == 31.25, "exit save restores position, momentum, stamina")
		check(app.boulder.slip == 67.0 and app.boulder.slip_remaining == 0.4 and app.boulder.elapsed == 123.5 and app.boulder.slips == 3, "exit save restores slip and run timer")
		print("UI RESUME VERIFICATION: %d failures" % failures)
		quit(1 if failures else 0)
		return
	check(app.screen == "title", "main scene starts on title")
	await snap("01-title")
	key(KEY_ENTER)
	check(app.screen == "game", "Enter starts play")
	app.boulder.distance = 175.0
	app.boulder.peak = 175.0
	app.best = 175.0
	app.boulder.stamina = 78.0
	app.camera_position = app.mountain.sample(175.0)
	await snap("02-game")
	key(KEY_ESCAPE)
	var start_distance: float = app.boulder.distance
	app._physics_process(1.0)
	check(app.paused and app.boulder.distance == start_distance, "Escape pauses physical progress")
	await snap("03-pause")
	key(KEY_ESCAPE)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(app.paused, "focus loss pauses the run")
	key(KEY_ENTER)
	check(not app.paused, "Enter resumes from pause")
	app.boulder.state = "runaway"
	app.falls_seen = 0
	key(KEY_E)
	check(app.boulder.state == "runaway", "first fall cannot be skipped")
	app.boulder.distance = 1.0
	app.boulder.velocity = -64.0
	app._physics_process(1.0)
	check(app.boulder.state == "result" and app.falls_seen == 1, "first completed fall unlocks later skip")
	await snap("04-result")
	key(KEY_ESCAPE)
	await frames()
	var pause_actions: Array = []
	for button: Dictionary in app.buttons: pause_actions.append(button.action)
	check("new" not in pause_actions, "pause overlay removes underlying result click targets")
	key(KEY_ENTER)
	key(KEY_ENTER)
	check(app.boulder.state == "climbing" and app.boulder.distance == 0.0 and app.boulder.stamina == 100.0, "result restart resets run")
	app.boulder.state = "runaway"
	app.boulder.distance = 50.0
	app.boulder.runaway_elapsed = 0.0
	key(KEY_E)
	check(app.boulder.state == "runaway", "later fall still shows minimum 1.5 seconds")
	app.boulder.runaway_elapsed = 1.5
	key(KEY_E)
	check(app.boulder.state == "result" and app.falls_seen == 2, "later fall can be skipped")
	app.boulder.state = "summit"
	app.boulder.distance = app.mountain.total_length
	app.boulder.peak = app.mountain.total_length
	app.camera_position = app.mountain.sample(app.mountain.total_length)
	app.summit_quiet = 0.0
	key(KEY_ENTER)
	check(app.boulder.state == "summit", "summit preserves first three seconds of quiet")
	await snap("05-summit-quiet")
	app.summit_quiet = 3.1
	app.paused = false
	await snap("06-summit")
	key(KEY_ENTER)
	check(app.boulder.state == "climbing" and app.boulder.distance == 0.0, "summit restart works")
	if capture:
		var original_weather: String = app.mountain.weather_id
		for material_id: String in ["stone", "mud", "gravel", "wet_stone"]:
			for segment: Dictionary in app.mountain.segments:
				if not bool(segment.shelf) and str(app.mountain.surface_at(float(segment.start) + 1.0).id).to_lower() == material_id:
					app.boulder.distance = float(segment.start) + 10.0
					app.camera_position = app.mountain.sample(app.boulder.distance)
					app.mountain.weather_id = "clear"
					await snap("07-clear-" + material_id)
					app.mountain.weather_id = "rain"
					app.boulder.slip = 82.0
					await snap("08-rain-" + material_id)
					break
		app.mountain.weather_id = original_weather
	app.run_number = 7
	app.best = 500.0
	app.boulder.distance = 432.125
	app.boulder.peak = 470.0
	app.boulder.velocity = -1.5
	app.boulder.stamina = 31.25
	app.boulder.slip = 67.0
	app.boulder.slip_remaining = 0.4
	app.boulder.elapsed = 123.5
	app.boulder.slips = 3
	app.camera_position = app.mountain.sample(app.boulder.distance)
	print("UI VERIFICATION: %d failures" % failures)
	if failures:
		quit(1)
	else:
		app._save_and_quit()

