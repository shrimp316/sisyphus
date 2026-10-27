extends SceneTree

const Main = preload("res://scripts/main.gd")
var checks: int = 0
var failures: int = 0
var output: String
var app: Node2D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func verify_layout() -> void:
	var placement: bool = true
	var geometry: bool = true
	for seed_value: int in range(1, 97):
		var world := MountainManager.new(seed_value, false, 5)
		var previous := MountainManager.new(seed_value, false, 4)
		placement = placement and world.rest_points.size() == 10
		geometry = geometry and world.chunks == previous.chunks and world.segments == previous.segments and world.weather_id == previous.weather_id
		for index: int in range(20):
			placement = placement and world.rest_points.has(49.75 + index * 50.0) == (index % 2 == 0)
			geometry = geometry and world.is_shelf(42.0 + index * 50.0) and world.is_shelf(49.99 + index * 50.0)
	check(placement, "96 seeds place exactly ten grooves at 49.75, 149.75 ... 949.75m")
	check(geometry, "all twenty 8m shelves, slopes, ledges, materials and weather retain generation 4 geometry")

func verify_physics() -> void:
	for weather: String in ["clear", "rain"]:
		for rank: int in [0, 10]:
			var world := MountainManager.new(42)
			world.weather_id = weather
			var catches: bool = true
			var unblocked: bool = true
			var runaway: bool = true
			var recovery: bool = true
			for index: int in range(20):
				var boundary: float = 49.75 + index * 50.0
				var sim := BoulderController.new(world)
				sim.apply_progression({"strength": rank, "endurance": rank, "recovery": rank})
				sim.distance = boundary + 0.01
				sim.velocity = -2.0
				sim.peak = boundary + 0.01
				sim.stamina = 30.0
				sim.advance(BoulderController.FIXED_DT, false, false, false)
				if index % 2 == 0:
					catches = catches and is_equal_approx(sim.distance, boundary) and sim.velocity == 0.0 and sim.partial_falls == 1 and sim.state == "climbing"
				else:
					unblocked = unblocked and sim.distance < boundary and sim.velocity < -1.9 and sim.partial_falls == 0
				var lost := BoulderController.new(world)
				lost.distance = boundary + 0.01
				lost.velocity = -4.0
				lost.advance(2.0 * BoulderController.FIXED_DT, false, false, true)
				runaway = runaway and lost.state == "runaway" and lost.distance < boundary and lost.partial_falls == 0
				# A low-speed retreat should still stop naturally on either kind of flat.
				sim.distance = boundary - 1.0
				sim.velocity = -0.1
				sim.stamina = 30.0
				sim.advance(1.0, false, false, false)
				recovery = recovery and sim.velocity == 0.0 and sim.stamina > 39.9 and world.is_shelf(sim.distance)
			var label: String = "%s rank %d: " % [weather, rank]
			check(catches, label + "every selected groove catches partial falls")
			check(unblocked, label + "all ten ordinary shelves have no invisible rollback stop")
			check(runaway, label + "runaway takes priority on all twenty shelves")
			check(recovery, label + "both shelf kinds retain natural friction and stamina recovery")

func verify_integration() -> void:
	app.screen = "game"
	app.progression.award_distance(100.0, 1000.0)
	var choices: bool = true
	for index: int in range(20):
		app.boulder.distance = 45.0 + index * 50.0
		app.boulder.velocity = 0.0
		app._refresh_upgrade_choice()
		choices = choices and app.upgrade_open
	check(choices, "pending upgrade opens on every shelf, including all ten without grooves")
	app.boulder.distance = 95.0
	check(app.choose_upgrade("strength") and app.progression.ranks.strength == 1, "ordinary shelf can spend and save a permanent upgrade")
	for generation: int in [3, 4, 5, 6]:
		app._install_world(MountainManager.new(42, false, generation))
		app.boulder.distance = 95.0
		app.boulder.peak = 725.0
		app.boulder.velocity = -0.2
		var old_world: Dictionary = app.mountain.snapshot()
		var old_growth: float = app.boulder_visual_scale()
		check(app._save_progression(), "generation %d writes isolated save" % generation)
		app._load_save()
		check(app.has_resume and not app.save_blocked and JSON.parse_string(JSON.stringify(app.mountain.snapshot())) == JSON.parse_string(JSON.stringify(old_world)) and app.mountain.rest_points.size() == (10 if generation >= 5 else 20), "generation %d resume preserves exact terrain and original groove layout" % generation)
		check(app.boulder.peak == 725.0 and is_equal_approx(app.boulder_visual_scale(), old_growth), "generation %d resume retains attained boulder growth after retreat" % generation)
		app._new_run()
		check(app.mountain.generation_version == 6 and app.mountain.rest_points.size() == 10 and app.boulder_visual_scale() == 1.0, "next run adopts steeper terrain with selective grooves and resets only this run's boulder size")
	app.boulder.peak = 1000.0
	check(is_equal_approx(app.boulder_visual_scale(), 1.15), "new selective-groove course retains the 15 percent visual growth cap")

func capture_view(name: String) -> void:
	app.camera_position = app.mountain.sample(app.boulder.distance)
	app.queue_redraw()
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "GPU capture " + name)

func run() -> void:
	output = "res://.tools/shelters-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	verify_layout()
	verify_physics()
	app = Main.new()
	app.save_path = output.path_join("save.json")
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._install_world(MountainManager.new(42))
	verify_integration()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		root.content_scale_size = Vector2i(1280, 720)
		root.size = Vector2i(1280, 720)
		app._install_world(MountainManager.new(42))
		app.zoom = 1.3
		for distance_value: float in [47.0, 97.0]:
			app.boulder.distance = distance_value
			for peak_value: float in [distance_value, 1000.0]:
				app.boulder.peak = peak_value
				await capture_view("shelf-%.0f-peak-%.0f" % [distance_value, peak_value])
	app.sound.shutdown()
	app.queue_free()
	for frame: int in range(4):
		await process_frame
	print("SHELTER VERIFICATION: %d checks, %d failures; captures: %s" % [checks, failures, output])
	quit(1 if failures else 0)
