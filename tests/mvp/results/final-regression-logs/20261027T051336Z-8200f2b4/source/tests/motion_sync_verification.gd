extends SceneTree

const Main = preload("res://scripts/main.gd")
const Art = preload("res://scripts/asset_visuals.gd")
var checks: int = 0
var failures: int = 0
var capture: bool = false
var fixture: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func move(app: Node2D, distance_delta: float) -> void:
	var previous_distance: float = app.boulder.distance
	var previous_state: String = app.boulder.state
	var previous_falls: int = app.boulder.partial_falls
	app.boulder.distance += distance_delta
	app.advance_character_motion(previous_distance, previous_state, previous_falls)

func verify_distance_clock(app: Node2D) -> void:
	for speed: float in [0.0, 0.3, 1.0, 1.8]:
		app.gait_phase = 0.0
		app.boulder.distance = 20.0
		for tick: int in range(120):
			move(app, speed / 120.0)
		check(is_equal_approx(app.gait_phase, speed / Main.GAIT_STRIDE_METERS), "one second at %.1f m/s advances proportionally to actual travel" % speed)
	app.gait_phase = 0.0
	move(app, 0.1)
	move(app, 0.3)
	move(app, 0.05)
	check(is_equal_approx(app.gait_phase, 0.45 / Main.GAIT_STRIDE_METERS), "changing speed accumulates travel without resetting or jumping phase")
	var before: float = app.gait_phase
	app.boulder.action = "push"
	app.boulder.velocity = 1.8
	app.boulder.ledge_blocked = true
	move(app, 0.0)
	check(app.gait_phase == before, "blocked pushing holds its frame even if velocity telemetry is nonzero")
	app.boulder.ledge_blocked = false
	move(app, -0.2)
	check(is_equal_approx(app.gait_phase, before + 0.2 / Main.GAIT_STRIDE_METERS), "controlled backward movement uses actual travel for the brace cycle")
	app.gait_phase = 0.0
	move(app, Main.GAIT_STRIDE_METERS)
	check(is_zero_approx(app.gait_phase), "one stride wraps cleanly to the first phase")

func verify_frames(app: Node2D) -> void:
	var frames: SpriteFrames = app.art.frames("sisyphus")
	check(frames != null, "authored character frames load")
	if frames == null:
		return
	app.boulder.stamina = 80.0
	for phase: float in [0.0625, 0.3, 0.51, 0.92]:
		app.gait_phase = phase
		var matching: bool = true
		for action: String in ["push", "exert", "brace"]:
			app.boulder.action = action
			var animation: String = Art.character_animation(action, 80.0)
			var expected: int = int(phase * frames.get_frame_count(animation))
			matching = matching and app.character_frame() == frames.get_frame_texture(animation, expected)
		check(matching and app.gait_phase == phase, "action changes preserve normalized phase %.4f across 8- and 6-frame cycles" % phase)
	app.boulder.action = "push"
	var held: Texture2D = app.character_frame()
	app.boulder.elapsed += 10.0
	check(app.character_frame() == held, "simulation elapsed time alone cannot animate stationary pushing")
	for stamina: float in [80.0, 10.0]:
		app.boulder.action = "rest"
		app.boulder.stamina = stamina
		app.boulder.elapsed = 0.0
		var first: Texture2D = app.character_frame()
		app.boulder.elapsed = 0.2
		check(app.character_frame() != first, "stationary %s remains time animated" % ("idle" if stamina == 80.0 else "exhausted breathing"))

func verify_lifecycle(app: Node2D) -> void:
	app._install_world(MountainManager.new(42, false, 4))
	app.screen = "game"
	app.paused = false
	app.boulder.distance = 20.0
	app.boulder.peak = 20.0
	app.boulder.velocity = 0.5
	var reference := BoulderController.new(app.mountain)
	reference.restore(app.boulder.snapshot())
	reference.advance(1.0 / 120.0, false, false, false)
	app._physics_process(1.0 / 120.0)
	check(app.boulder.snapshot() == reference.snapshot(), "main physics remains identical to the standalone boulder simulation")
	check(is_equal_approx(app.gait_phase, absf(app.boulder.distance - 20.0) / Main.GAIT_STRIDE_METERS) and app.gait_phase > 0.0, "real physics tick feeds the actual displacement into the gait clock")
	app.gait_phase = 0.37
	app.screen = "game"
	app.paused = true
	var before: Dictionary = app.boulder.snapshot()
	app._physics_process(1.0)
	check(app.gait_phase == 0.37 and app.boulder.snapshot() == before, "pause freezes both simulation and motion phase")
	app.paused = false
	app.screen = "title"
	app._physics_process(1.0)
	check(app.gait_phase == 0.37 and app.boulder.snapshot() == before, "title screen cannot advance motion")
	app.screen = "game"
	app.progression.award_distance(100.0, 1000.0)
	app.boulder.distance = 46.0
	app.boulder.velocity = 0.0
	app.boulder.state = "climbing"
	before = app.boulder.snapshot()
	app._physics_process(1.0)
	check(app.upgrade_open and app.gait_phase == 0.37 and app.boulder.snapshot() == before, "shelter upgrade modal freezes simulation and gait")
	app.boulder.state = "runaway"
	app.boulder.distance = 0.0
	app.advance_character_motion(46.0, "climbing", 0)
	check(is_zero_approx(app.gait_phase), "runaway transition clears phase without counting fall travel")
	app.gait_phase = 0.4
	app.boulder.state = "result"
	app.advance_character_motion(300.0, "runaway", 0)
	check(is_zero_approx(app.gait_phase), "finish-fall teleport cannot become a walking stride")
	app.gait_phase = 0.4
	app.boulder.state = "climbing"
	app.boulder.partial_falls = 1
	app.advance_character_motion(300.0, "climbing", 0)
	check(is_zero_approx(app.gait_phase), "partial-fall recovery resets phase without counting repositioning")
	app.gait_phase = 0.4
	app.boulder.state = "summit"
	app.advance_character_motion(app.boulder.distance, "summit", app.boulder.partial_falls)
	check(app.gait_phase == 0.4, "stationary summit preserves the final foot pose")
	app._new_run()
	check(is_zero_approx(app.gait_phase) and app.boulder.distance == 0.0, "new run resets presentation phase")
	app.boulder.distance = 20.0
	app.boulder.peak = 20.0
	app.gait_phase = 0.6
	app._save_progression()
	app.boulder.distance = 0.0
	app._load_save()
	check(not app.save_blocked and app.boulder.distance == 20.0 and is_zero_approx(app.gait_phase), "loading a run resets gait without counting restored distance")
	move(app, 0.2)
	check(is_equal_approx(app.gait_phase, 0.2 / Main.GAIT_STRIDE_METERS), "first movement after load counts only new travel")
	before = app.boulder.snapshot()
	app.advance_character_motion(app.boulder.distance - 0.1, app.boulder.state, app.boulder.partial_falls)
	check(app.boulder.snapshot() == before, "presentation motion cannot mutate boulder physics or save state")

func snap(app: Node2D, name: String) -> void:
	app.queue_redraw()
	for tick: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(fixture.path_join(name + ".png")) == OK, "capture " + name)

func verify_captures(app: Node2D) -> void:
	app.screen = "game"
	app.paused = false
	app.upgrade_open = false
	app.boulder.state = "climbing"
	app.boulder.action = "push"
	app.boulder.stamina = 80.0
	app.zoom = 1.0
	app.clock_time = 12.0
	for speed: float in [0.0, 0.3, 1.0, 1.8]:
		app.gait_phase = 0.0
		app.boulder.distance = 20.0
		app.boulder.velocity = speed
		app.camera_position = app.mountain.sample(app.boulder.distance)
		await snap(app, "speed-%.1f-start" % speed)
		move(app, speed)
		await snap(app, "speed-%.1f-after-one-second" % speed)

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	fixture = "res://.tools/motion-sync-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(fixture)
	var app: Node2D = Main.new()
	app.save_path = fixture.path_join("save.json")
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app._install_world(MountainManager.new(42, false, 4))
	verify_distance_clock(app)
	verify_frames(app)
	verify_lifecycle(app)
	if capture:
		await verify_captures(app)
	app.sound.shutdown()
	app.free()
	print("MOTION SYNC: %d checks, %d failures; fixture %s" % [checks, failures, fixture])
	quit(1 if failures else 0)
