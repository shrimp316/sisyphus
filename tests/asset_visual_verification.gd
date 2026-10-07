extends SceneTree
const Art = preload("res://scripts/asset_visuals.gd")
var failures: int = 0
var capture: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + label)
	if not condition: failures += 1

func settle() -> void:
	for index: int in range(4): await process_frame

func snap(name: String) -> void:
	if not capture: return
	await settle()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.tools/art-captures/%s.png" % name) == OK, "capture " + name)

func key(node: Node, code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	node._unhandled_key_input(event)

func run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute("res://.tools/art-captures")
	var art: AssetVisuals = Art.new()
	for kind: String in ["sisyphus", "fx"]:
		var frames: SpriteFrames = art.frames(kind)
		check(frames != null, kind + " native SpriteFrames exists")
		if frames == null: continue
		var definitions: Dictionary = Art.CHARACTER_ANIMATIONS if kind == "sisyphus" else Art.FX_ANIMATIONS
		for animation: String in definitions:
			check(frames.has_animation(animation) and frames.get_frame_count(animation) == int(definitions[animation][0]) and frames.get_animation_speed(animation) == float(definitions[animation][1]), kind + "/" + animation + " count and fps")
			check(art.frame(kind, animation, 0.0) != art.frame(kind, animation, 1.0 / float(definitions[animation][1]) + 0.001), animation + " advances to distinct frame")
	check(Art.character_animation("push", 0) == "push" and Art.character_animation("exert", 1) == "heavy_push" and Art.character_animation("brace", 1) == "brace" and Art.character_animation("rest", 10) == "exhausted" and Art.character_animation("rest", 100) == "idle", "animation follows existing simulation action")
	for mode: String in ["character", "fx", "ui", "environment"]:
		var preview: Node2D = load("res://godot/scenes/preview/%s_preview.tscn" % mode).instantiate()
		root.add_child(preview)
		await settle()
		if mode in ["character", "fx"]:
			check(preview.sprite is AnimatedSprite2D and not preview.names.is_empty(), mode + " uses native animated sprite")
			if not preview.names.is_empty():
				key(preview, KEY_SPACE)
				check(not preview.sprite.is_playing(), mode + " pause")
				var before_scale: float = preview.sprite.scale.x
				key(preview, KEY_F)
				check(preview.sprite.scale.x == -before_scale, mode + " pivot-preserving flip")
				key(preview, KEY_F)
				for index: int in range(preview.names.size()):
					preview._select(index)
					check(preview.sprite.animation == preview.names[index], mode + " switches " + str(preview.names[index]))
					await snap(mode + "-" + str(preview.names[index]))
		else:
			await snap(mode)
		preview.queue_free()
		await settle()
	var game: Node2D = load("res://main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_physics_process(false)
	game.screen = "game"
	game.paused = false
	for action: String in ["rest", "push", "exert", "brace"]:
		game.boulder.action = action
		game.boulder.elapsed = 12.15
		game.boulder.stamina = 80
		await snap("game-" + action)
	if capture:
		for distance: float in [175.0, 440.0, 800.0]:
			game.boulder.distance = minf(distance, game.mountain.total_length)
			game.boulder.action = "push"
			game.boulder.stamina = 24.0 if distance == 440.0 else 80.0
			game.boulder.slip = 60.0
			game.camera_position = game.mountain.sample(game.boulder.distance)
			game.previous_best = game.boulder.distance + 7.0
			await snap("game-distance-%d" % int(distance))
	check(game.art.frames("sisyphus") != null and game.art.texture("res://assets/boulder/boulder_default.png") != null, "main loads authored character and stone")
	game.sound.shutdown()
	game.queue_free()
	await settle()
	print("ART VERIFICATION: %d failures" % failures)
	quit(1 if failures else 0)
