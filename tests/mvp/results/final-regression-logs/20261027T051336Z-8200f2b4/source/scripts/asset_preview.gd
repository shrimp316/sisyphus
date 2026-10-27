extends Node2D
## Standalone native AnimatedSprite2D preview; deliberately independent of game saves.
const Art = preload("res://scripts/asset_visuals.gd")
@export_enum("character", "fx", "ui", "environment") var preview_kind: String = "character"
var art: AssetVisuals = Art.new()
var sprite: AnimatedSprite2D
var font: Font = ThemeDB.fallback_font
var names: PackedStringArray = PackedStringArray()
var selected: int = 0
var frozen: bool = false

func _ready() -> void:
	if preview_kind in ["character", "fx"]:
		sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = art.frames("sisyphus" if preview_kind == "character" else "fx")
		sprite.centered = false
		add_child(sprite)
		if sprite.sprite_frames != null:
			names = sprite.sprite_frames.get_animation_names()
			_select(names.find("idle" if preview_kind == "character" else "dust"))
	queue_redraw()

func _select(index: int) -> void:
	if names.is_empty(): return
	selected = posmod(index, names.size())
	sprite.play(names[selected])
	if frozen: sprite.pause()
	_update_pivot()

func _update_pivot() -> void:
	var pivot: Vector2 = Vector2(256, 464) if preview_kind == "character" else Vector2(128, 128 if names[selected] in ["wind", "breath"] else 224)
	# Flip around the foot/FX pivot, not the top-left of the source canvas.
	sprite.offset = -pivot
	sprite.flip_h = false
	sprite.position = get_viewport_rect().size * Vector2(0.5, 0.72)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if sprite == null: return
	match event.keycode:
		KEY_RIGHT: _select(selected + 1)
		KEY_LEFT: _select(selected - 1)
		KEY_F: sprite.scale.x *= -1.0
		KEY_SPACE:
			frozen = not frozen
			if frozen: sprite.pause()
			else: sprite.play()
		KEY_EQUAL, KEY_KP_ADD: sprite.speed_scale = minf(3.0, sprite.speed_scale + 0.25)
		KEY_MINUS, KEY_KP_SUBTRACT: sprite.speed_scale = maxf(0.25, sprite.speed_scale - 0.25)
		_:
			if event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_select(event.keycode - KEY_1)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var size: Vector2 = get_viewport_rect().size
	for y: int in range(0, int(size.y), 32):
		for x: int in range(0, int(size.x), 32):
			draw_rect(Rect2(x, y, 32, 32), Color("29343b") if (x / 32 + y / 32) % 2 == 0 else Color("34424a"))
	draw_string(font, Vector2(32, 42), "SISYPHUS / " + preview_kind.to_upper() + " / ART PREVIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8e1cc"))
	if sprite != null:
		var anchor: Vector2 = size * Vector2(0.5, 0.72)
		draw_line(Vector2(0, anchor.y), Vector2(size.x, anchor.y), Color("caad72"), 1.0)
		draw_line(anchor - Vector2(10, 0), anchor + Vector2(10, 0), Color.CYAN, 2.0)
		draw_line(anchor - Vector2(0, 10), anchor + Vector2(0, 10), Color.CYAN, 2.0)
		if names.is_empty():
			draw_string(font, Vector2(32, 92), "Missing resources. Run tools/generate-godot-assets.gd after PNG import.", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		else:
			var anim: String = names[selected]
			draw_string(font, Vector2(32, 90), "%s | frame %d/%d | %.1f fps | scale 1:1 | foot/FX pivot at cross" % [anim, sprite.frame + 1, sprite.sprite_frames.get_frame_count(anim), sprite.sprite_frames.get_animation_speed(anim) * sprite.speed_scale], HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			draw_string(font, Vector2(32, 125), "1-9 / Left / Right: animation    F: flip    Space: pause    +/-: playback speed", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	else:
		_draw_gallery(size)

func _draw_gallery(size: Vector2) -> void:
	var paths: Array[String] = []
	if preview_kind == "ui":
		for name: String in ["stamina", "slip", "brace", "push_burst", "checkpoint", "height_marker", "warning_wind", "warning_rockfall"]:
			paths.append("res://assets/ui/icons/%s_icon.png" % name)
		for name: String in ["previous_record", "event", "rest_point"]:
			paths.append("res://assets/ui/markers/%s_marker.png" % name)
	else:
		for name: String in ["default", "rough", "wet", "snow"]:
			paths.append("res://assets/boulder/boulder_%s.png" % name)
		for name: String in ["rock_ground", "gravel_ground", "mud_ground", "wet_rock", "snow_ground", "steep_slope_up", "convex_slope_up", "concave_slope_down", "ledge", "foothold_rest_platform", "small_stone_step"]:
			paths.append("res://assets/terrain/%s.png" % name)
		for name: String in ["cairn_checkpoint", "broken_signpost", "dead_tree", "small_tree", "ruin_pillar", "shrine_fragment", "simple_arch_ruin"]:
			paths.append("res://assets/props/%s.png" % name)
	var columns: int = 6 if preview_kind == "environment" else 4
	var cell: Vector2 = Vector2(size.x / columns, (size.y - 120.0) / ceilf(float(paths.size()) / columns))
	for index: int in range(paths.size()):
		var position: Vector2 = Vector2(index % columns, index / columns) * cell + Vector2(cell.x * 0.5, 140)
		var tex: Texture2D = art.texture(paths[index])
		if tex != null:
			var display_scale: float = minf((cell.x - 32.0) / tex.get_width(), (cell.y - 50.0) / tex.get_height())
			Art.draw_at(self, tex, position, Vector2(tex.get_width() * 0.5, 0), display_scale)
		draw_string(font, position + Vector2(-cell.x * 0.46, cell.y - 44), paths[index].get_file().get_basename(), HORIZONTAL_ALIGNMENT_LEFT, cell.x - 10, 15)
