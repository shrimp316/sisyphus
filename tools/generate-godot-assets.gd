extends SceneTree
## Run after PNG import: godot --headless --path . --script res://tools/generate-godot-assets.gd
const Art = preload("res://scripts/asset_visuals.gd")

func _initialize() -> void:
	var missing: Array[String] = []
	var groups: Array[String] = ["sisyphus"]
	if not "--characters-only" in OS.get_cmdline_user_args():
		groups.append("fx")
	for group: String in groups:
		var definitions: Dictionary = Art.CHARACTER_ANIMATIONS if group == "sisyphus" else Art.FX_ANIMATIONS
		for animation: String in definitions:
			for index: int in range(1, int(definitions[animation][0]) + 1):
				var path: String = _path(group, animation, index)
				if not ResourceLoader.exists(path):
					missing.append(path)
	if not missing.is_empty():
		push_error("Import all artwork before generating resources. Missing: " + ", ".join(missing))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://godot/resources/spriteframes")
	for group: String in groups:
		var definitions: Dictionary = Art.CHARACTER_ANIMATIONS if group == "sisyphus" else Art.FX_ANIMATIONS
		var combined: SpriteFrames = SpriteFrames.new()
		combined.remove_animation("default")
		for animation: String in definitions:
			var individual: SpriteFrames = SpriteFrames.new()
			individual.remove_animation("default")
			for frames: SpriteFrames in [combined, individual]:
				frames.add_animation(animation)
				frames.set_animation_speed(animation, float(definitions[animation][1]))
				frames.set_animation_loop(animation, animation != "impact")
				for index: int in range(1, int(definitions[animation][0]) + 1):
					frames.add_frame(animation, load(_path(group, animation, index)) as Texture2D)
			var error: Error = ResourceSaver.save(individual, "res://godot/resources/spriteframes/%s_%s.tres" % [group, animation])
			if error != OK:
				push_error("Resource write failed: " + str(error))
				quit(1)
				return
		if ResourceSaver.save(combined, "res://godot/resources/spriteframes/%s.tres" % group) != OK:
			quit(1)
			return
	print("Generated SpriteFrames resources for: " + ", ".join(groups))
	quit(0)

func _path(group: String, animation: String, index: int) -> String:
	var root: String = "res://assets/character/sisyphus" if group == "sisyphus" else "res://assets/fx"
	return "%s/%s/%s_%02d.png" % [root, animation, animation, index]
