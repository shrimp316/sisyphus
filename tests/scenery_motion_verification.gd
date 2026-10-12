extends SceneTree
## GPU regression: camera motion must not relight a fixed point in the rock.

const Art = preload("res://scripts/asset_visuals.gd")
const Mountain = preload("res://scripts/mountain_manager.gd")
const SIZE: Vector2i = Vector2i(1280, 720)
const ANCHOR: Vector2 = Vector2(460.8, 482.4)
const TOLERANCE: float = 3.0 / 255.0
var failures: int = 0
var report: Array[Dictionary] = []
var save_captures: bool = false
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition:
		failures += 1

func distance_at_x(world: MountainManager, x: float) -> float:
	var low: float = 0.0
	var high: float = world.total_length
	for index: int in range(32):
		var middle: float = (low + high) * 0.5
		if world.sample(middle).x < x:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5

func capture_view(scenery: Node2D, art: AssetVisuals, world: MountainManager, camera: Vector2, scale_value: float, rainy: bool, name: String) -> Image:
	var from: float = distance_at_x(world, camera.x + (-300.0 - ANCHOR.x) / scale_value)
	var to: float = distance_at_x(world, camera.x + (float(SIZE.x) + 300.0 - ANCHOR.x) / scale_value)
	var outline: PackedVector2Array = PackedVector2Array()
	var cursor: float = from
	while cursor < to:
		outline.append((world.sample(cursor) - camera) * scale_value + ANCHOR)
		cursor += 0.5
	outline.append((world.sample(to) - camera) * scale_value + ANCHOR)
	scenery.configure_view(art, Vector2(SIZE), camera, scale_value, Vector2.ZERO, 0.44, rainy, 0.0)
	scenery.set_ground(outline)
	for index: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if save_captures:
		check(image.save_png(output.path_join(name + ".png")) == OK, "capture " + name)
	return image

func samples(image: Image, points: PackedVector2Array, camera: Vector2, scale_value: float) -> Array[Color]:
	var colors: Array[Color] = []
	for point: Vector2 in points:
		var pixel: Vector2i = Vector2i(((point - camera) * scale_value + ANCHOR).round())
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= image.get_width() or pixel.y >= image.get_height():
			check(false, "world sample remains inside viewport")
			colors.append(Color.MAGENTA)
		else:
			colors.append(image.get_pixelv(pixel))
	return colors

func run() -> void:
	var baseline: bool = "--baseline" in OS.get_cmdline_user_args()
	save_captures = "--capture" in OS.get_cmdline_user_args()
	output = "res://.tools/scenery-motion-" + ("baseline" if baseline else "fixed")
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = SIZE
	root.size = SIZE
	var renderer_path: String = "res://.tools/scenery_visuals-motion-baseline.gd" if baseline else "res://scripts/scenery_visuals.gd"
	var renderer: Script = load(renderer_path) as Script
	if renderer == null:
		check(false, "scenery renderer available: " + renderer_path)
		quit(1)
		return
	var scenery: Node2D = renderer.new()
	root.add_child(scenery)
	var art: AssetVisuals = Art.new()
	# A solid opaque texture removes rock grain and UV filtering from the measurement.
	var white: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	art.textures["res://assets/terrain/rock_subsurface.png"] = ImageTexture.create_from_image(white)
	var world: MountainManager = Mountain.new(42, false, 4)
	var world_before: Dictionary = world.snapshot().duplicate(true)
	var movements: Array[Dictionary] = [
		{"name": "left", "offset": Vector2(-80, 0), "zoom": 1.0},
		{"name": "right", "offset": Vector2(80, 0), "zoom": 1.0},
		{"name": "up", "offset": Vector2(0, -80), "zoom": 1.0},
		{"name": "down", "offset": Vector2(0, 80), "zoom": 1.0},
		{"name": "zoom-out", "offset": Vector2.ZERO, "zoom": 0.8},
	]
	for distance: float in [175.0, 440.0]:
		var camera: Vector2 = world.sample(distance)
		var points: PackedVector2Array = PackedVector2Array()
		for offset: float in [-3.0, 0.0, 3.0]:
			for depth: float in [60.0, 90.0]:
				points.append(world.sample(distance + offset) + Vector2(0, depth))
		for rainy: bool in [false, true]:
			var prefix: String = "%03dm-%s" % [int(distance), "rain" if rainy else "clear"]
			var reference: Image = await capture_view(scenery, art, world, camera, 1.0, rainy, prefix + "-reference")
			var expected: Array[Color] = samples(reference, points, camera, 1.0)
			for movement: Dictionary in movements:
				var moved_camera: Vector2 = camera + movement.offset
				var scale_value: float = float(movement.zoom)
				var name: String = prefix + "-" + str(movement.name)
				var image: Image = await capture_view(scenery, art, world, moved_camera, scale_value, rainy, name)
				var actual: Array[Color] = samples(image, points, moved_camera, scale_value)
				var maximum_delta: float = 0.0
				for index: int in range(expected.size()):
					for channel: int in range(3):
						maximum_delta = maxf(maximum_delta, absf(actual[index][channel] - expected[index][channel]))
				report.append({"case": name, "maximum_channel_delta": maximum_delta, "tolerance": TOLERANCE})
				check(maximum_delta <= TOLERANCE, "%s fixed-world shading delta %.5f <= %.5f" % [name, maximum_delta, TOLERANCE])
	check(world.snapshot() == world_before, "presentation leaves seeded mountain unchanged")
	var report_file: FileAccess = FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t") + "\n")
	scenery.queue_free()
	print("SCENERY MOTION VERIFICATION: %d failures" % failures)
	quit(1 if failures else 0)
