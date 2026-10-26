extends SceneTree

const Main = preload("res://scripts/main.gd")
const OUTPUT: String = "res://.tools/boulder-growth"
var checks: int = 0
var failures: int = 0
var capture: bool = false
var app: Node2D
var isolated_save: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func uniform_world(degrees: float) -> MountainManager:
	var world := MountainManager.new(42, false, 4)
	world.weather_id = "clear"
	for chunk: Dictionary in world.chunks:
		chunk.start_angle = degrees
		chunk.end_angle = degrees
	world._build_curve()
	return world

func verify_scale() -> void:
	app._install_world(uniform_world(20.0))
	for item: Array in [[-100.0, 1.0], [0.0, 1.0], [500.0, 1.075], [1000.0, 1.15], [1500.0, 1.15]]:
		app.boulder.peak = float(item[0])
		check(is_equal_approx(app.boulder_visual_scale(), float(item[1])), "peak %.0fm yields bounded scale %.3f on uniform terrain" % [float(item[0]), float(item[1])])
		check(is_equal_approx(app.boulder_visual_radius(), 43.0 * float(item[1])), "visual radius follows the bounded growth scale")
	app._install_world(MountainManager.new(42))
	var bottom: Vector2 = app.mountain.sample(0.0)
	var summit: Vector2 = app.mountain.sample(app.mountain.total_length)
	for progress: float in [0.1, 0.35, 0.7, 1.0]:
		app.boulder.peak = app.mountain.total_length * progress
		var point: Vector2 = app.mountain.sample(app.boulder.peak)
		var expected: float = 1.0 + 0.15 * (bottom.y - point.y) / (bottom.y - summit.y)
		check(is_equal_approx(app.boulder_visual_scale(), expected), "generated terrain growth follows peak elevation at %.0f%% course distance" % (progress * 100.0))
	var shelf: Dictionary = {}
	for segment: Dictionary in app.mountain.segments:
		if bool(segment.shelf) and float(segment.start) > 100.0:
			shelf = segment
			break
	app.boulder.peak = float(shelf.start) + 0.2
	var before: float = app.boulder_visual_scale()
	app.boulder.peak = float(shelf.end) - 0.2
	check(is_equal_approx(app.boulder_visual_scale(), before), "horizontal shelf travel does not inflate height-based growth")
	app._install_world(uniform_world(0.0))
	app.boulder.peak = 1000.0
	check(is_equal_approx(app.boulder_visual_scale(), 1.0), "a zero-height course safely keeps the base size")

func verify_lifecycle() -> void:
	app._install_world(MountainManager.new(42))
	app.boulder.peak = 700.0
	app.boulder.distance = 700.0
	var grown: float = app.boulder_visual_scale()
	for distance_value: float in [500.0, 100.0, 500.0, 700.0, 500.0]:
		app.boulder.distance = distance_value
		check(is_equal_approx(app.boulder_visual_scale(), grown), "retreat and repeated traversal to %.0fm retain exactly the attained size" % distance_value)
	app.boulder.state = "runaway"
	check(is_equal_approx(app.boulder_visual_scale(), grown), "runaway retains attained visual size")
	app.boulder.finish_fall()
	check(is_equal_approx(app.boulder_visual_scale(), grown), "fall result retains this run's peak size")
	app.boulder.state = "climbing"
	app.boulder.distance = 200.0
	var payload: Dictionary = app._save_payload()
	var run_keys: Array = payload.run.keys()
	run_keys.sort()
	var expected_keys: Array = ["distance", "velocity", "stamina", "slip", "slip_remaining", "peak", "elapsed", "state", "slips", "accumulator", "runaway_elapsed", "partial_falls", "cleared_ledges", "falling_active"]
	expected_keys.sort()
	check(int(payload.version) == 4 and run_keys == expected_keys, "existing version-4 save and controller schema need no visual-growth fields")
	var file := FileAccess.open(isolated_save, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	app.boulder.peak = 0.0
	app._load_save()
	check(not app.save_blocked and app.has_resume and is_equal_approx(app.boulder_visual_scale(), grown), "ordinary save reload reconstructs exactly the same size from peak")
	app.best = 1000.0
	app._new_run()
	check(app.boulder.peak == 0.0 and app.boulder_visual_scale() == 1.0 and app.best == 1000.0, "new run resets size while preserving a higher lifetime record")
	check(app.save_path == isolated_save, "all lifecycle saves remain inside the isolated test fixture")

func verify_geometry() -> void:
	for degrees: float in [0.0, 20.0, 32.0, 45.0]:
		app._install_world(uniform_world(degrees))
		for distance_value: float in [0.0, 20.0, 47.0]:
			app.boulder.distance = distance_value
			app.boulder.peak = 1000.0
			var ground: Vector2 = app.mountain.sample(distance_value)
			var angle: float = app.mountain.angle_at(distance_value)
			var up := Vector2(-sin(angle), -cos(angle))
			var tangent := Vector2(cos(angle), -sin(angle))
			var center: Vector2 = app.boulder_visual_center()
			var radius: float = app.boulder_visual_radius()
			check(center.distance_to(ground + up * radius) < 0.0001 and absf((center - ground).dot(tangent)) < 0.0001, "%.0f-degree course at %.0fm keeps the enlarged stone tangent to its local ground normal" % [degrees, distance_value])
			var feet: Vector2 = app.character_ground_position()
			check(feet.x <= ground.x and is_finite(feet.x) and is_finite(feet.y), "character and foot-FX anchor stays finite and behind the stone")
			if degrees <= 32.0 or distance_value > 0.0:
				check((feet + Vector2(6.0, -44.0)).distance_to(center) >= radius, "the character torso reference point stays outside the stone silhouette")
			if distance_value == 0.0:
				check(is_equal_approx(feet.y, ground.y) and feet.x < ground.x, "start extension anchors feet and foot effects on the same flat ground")
			elif distance_value == 20.0:
				check(absf((feet - ground).dot(up)) < 0.01, "character and foot-effect anchor lies on the slope rather than stretching the sprite")
				check(absf((feet + Vector2(23.6, -43.0)).distance_to(center) - radius) < 0.01, "the authored hand reference touches the circle on a uniform slope")
			elif distance_value == 47.0:
				check(is_equal_approx(feet.y, ground.y), "enlarged-stone character feet remain on the shelf")
	app._install_world(uniform_world(20.0))
	app.boulder.distance = 20.0
	app.boulder.peak = 0.0
	var original_feet: Vector2 = app.character_ground_position()
	app.boulder.peak = 1000.0
	var grown_feet: Vector2 = app.character_ground_position()
	check(grown_feet.x < original_feet.x and grown_feet.distance_to(original_feet) < 15.0, "growth shifts the terrain-anchored character backward without changing sprite size")
	var center_before: Vector2 = app.boulder_visual_center()
	var feet_before: Vector2 = app.character_ground_position()
	app.zoom = 0.8
	app.camera_position += Vector2(100.0, -80.0)
	app.camera_shake = Vector2(2.0, -2.0)
	check(app.boulder_visual_center() == center_before and app.character_ground_position() == feet_before, "camera zoom and shake cannot change world-space stone or foot anchors")
	app._install_world(uniform_world(32.0))
	app.boulder.peak = 1000.0
	for boundary: float in [41.9, 42.1, 49.9, 50.1]:
		app.boulder.distance = boundary
		var feet: Vector2 = app.character_ground_position()
		var center: Vector2 = app.boulder_visual_center()
		var radius: float = app.boulder_visual_radius()
		check(absf((feet + Vector2(23.6, -43.0)).distance_to(center) - radius) <= 0.2, "actual-path hand contact stays within0.2px across the %.1fm terrain boundary" % boundary)
		check((feet + Vector2(6.0, -44.0)).distance_to(center) >= radius, "character torso remains outside the stone at the %.1fm terrain boundary" % boundary)

func verify_physics_unchanged() -> void:
	app._install_world(MountainManager.new(42))
	app.boulder.distance = 175.0
	app.boulder.peak = 700.0
	app.boulder.velocity = 0.5
	var before: Dictionary = app.boulder.snapshot().duplicate(true)
	var terrain: Dictionary = app.mountain.snapshot().duplicate(true)
	var random_state: int = app.world_random.state
	var reference := BoulderController.new(app.mountain)
	reference.restore(before)
	for tick: int in range(120):
		app.boulder_visual_scale()
		app.boulder_visual_radius()
		app.boulder_visual_center()
		app.character_ground_position()
	check(app.boulder.snapshot() == before and app.mountain.snapshot() == terrain and app.world_random.state == random_state, "presentation helpers do not mutate physics, terrain or run RNG")
	for tick: int in range(120):
		app.boulder_visual_radius()
		app.boulder.advance(1.0 / 120.0, true, false, tick > 60)
		reference.advance(1.0 / 120.0, true, false, tick > 60)
	check(app.boulder.snapshot() == reference.snapshot(), "visual-growth queries do not change active pushing or braking outcomes")

func capture_case(name: String) -> void:
	app.camera_position = app.mountain.sample(app.boulder.distance)
	app.queue_redraw()
	var before: Dictionary = app.boulder.snapshot().duplicate(true)
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT.path_join(name + ".png")) == OK, "GPU capture " + name)
	check(app.boulder.snapshot() == before, "GPU drawing preserves simulation: " + name)

func capture_views() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	app._install_world(uniform_world(32.0))
	app.screen = "game"
	app.paused = false
	app.zoom = 1.3
	app.camera_shake = Vector2.ZERO
	app.clock_time = 12.0
	app.boulder.elapsed = 12.15
	app.boulder.action = "push"
	app.character_travel = 0.01
	app.gait_phase = 0.3
	# Deliberately inconsistent peak<distance fixtures isolate only visual size.
	app.boulder.distance = 20.0
	app.boulder.peak = 0.0
	await capture_case("01-base-steep-same-position")
	app.boulder.peak = 1000.0
	await capture_case("02-grown-steep-same-position")
	app.boulder.distance = 47.0
	app.boulder.peak = 0.0
	await capture_case("03-base-shelf-same-position")
	app.boulder.peak = 1000.0
	await capture_case("04-grown-shelf-same-position")
	for boundary: float in [41.9, 42.1, 50.1]:
		app.boulder.distance = boundary
		await capture_case("boundary-%.1fm-grown" % boundary)
	app.boulder.distance = 47.0
	for variant: String in ["default", "rough", "wet"]:
		app.art.textures["res://assets/boulder/boulder_%s.png" % variant] = null
	await capture_case("05-grown-fallback")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	isolated_save = OUTPUT.path_join("save-%d.json" % Time.get_ticks_usec())
	app = Main.new()
	app.save_path = isolated_save
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	verify_scale()
	verify_lifecycle()
	verify_geometry()
	verify_physics_unchanged()
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture and DisplayServer.get_name() != "headless":
		await capture_views()
	app.sound.shutdown()
	app.queue_free()
	for frame: int in range(4):
		await process_frame
	print("BOULDER GROWTH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
