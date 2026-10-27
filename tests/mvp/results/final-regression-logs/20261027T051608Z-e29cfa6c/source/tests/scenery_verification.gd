extends SceneTree

const Mountain = preload("res://scripts/mountain_manager.gd")
const OUTPUT: String = "res://.tools/scenery-captures"
const ASSETS: Dictionary = {
	"res://assets/background/sky_mountains.png": [Vector2i(2048, 1024), false],
	"res://assets/background/sky_summit.png": [Vector2i(2048, 1024), false],
	"res://assets/background/midground_ridge.png": [Vector2i(2048, 1024), true],
	"res://assets/terrain/rock_subsurface.png": [Vector2i(1024, 1024), false],
}

var failures: int = 0
var capture: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func settle() -> void:
	for index: int in range(4):
		await process_frame

func render_case(game: Node2D, name: String, resolution: Vector2i) -> void:
	var world_before: Dictionary = game.mountain.snapshot().duplicate(true)
	var run_before: Dictionary = game.boulder.snapshot().duplicate(true)
	var random_before: int = game.world_random.state
	game.queue_redraw()
	await settle()
	if capture:
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		check(screenshot.get_size() == resolution, name + " viewport size")
		check(screenshot.save_png(OUTPUT.path_join(name + ".png")) == OK, "capture " + name)
	check(game.mountain.snapshot() == world_before and game.boulder.snapshot() == run_before and game.world_random.state == random_before, name + " rendering preserves world, simulation and run RNG")

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	if capture:
		DirAccess.make_dir_recursive_absolute(OUTPUT)
	for asset_path: String in ASSETS:
		var texture: Texture2D = load(asset_path) as Texture2D
		check(texture != null, asset_path + " imported texture loads")
		if texture == null:
			continue
		var image: Image = texture.get_image()
		check(image != null and image.get_size() == ASSETS[asset_path][0], asset_path + " dimensions")
		if image != null:
			var has_transparency: bool = image.detect_alpha() != Image.ALPHA_NONE
			check(has_transparency == bool(ASSETS[asset_path][1]), asset_path + " opacity contract")
	var game: Node2D = load("res://main.tscn").instantiate()
	# Isolate from participant progress even if no launch flags were supplied.
	game.save_path = "res://.tools/scenery-verification-unused.json"
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game._install_world(Mountain.new(42, false, 4))
	game.screen = "game"
	game.paused = false
	game.clock_time = 12.0
	game.zoom = 1.0
	game.camera_shake = Vector2.ZERO
	game.boulder.action = "push"
	game.boulder.stamina = 80.0
	game.boulder.elapsed = 12.15
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	for weather: String in ["clear", "rain"]:
		game.mountain.weather_id = weather
		for distance: float in [0.0, 175.0, 440.0, 800.0, 995.0]:
			game.boulder.distance = minf(distance, game.mountain.total_length)
			game.camera_position = game.mountain.sample(game.boulder.distance)
			await render_case(game, "%s-%04dm" % [weather, int(distance)], Vector2i(1280, 720))
	game.zoom = 0.8
	game.boulder.distance = 440.0
	game.camera_position = game.mountain.sample(game.boulder.distance)
	await render_case(game, "rain-0440m-zoom-out", Vector2i(1280, 720))
	game.zoom = 1.0
	root.content_scale_size = Vector2i(720, 1280)
	root.size = Vector2i(720, 1280)
	game.mountain.weather_id = "clear"
	game.boulder.distance = 440.0
	game.camera_position = game.mountain.sample(game.boulder.distance)
	await render_case(game, "portrait-clear-0440m", Vector2i(720, 1280))
	# Simulate absent optional art through the adapter cache, preserving source files.
	for asset_path: String in ASSETS:
		game.art.textures[asset_path] = null
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await render_case(game, "fallback-clear-0440m", Vector2i(1280, 720))
	game.sound.shutdown()
	game.queue_free()
	await settle()
	print("SCENERY VERIFICATION: %d failures" % failures)
	quit(1 if failures else 0)
