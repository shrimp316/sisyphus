extends Control
## The provided five poses push a rectangular wall. This is not skeletal animation.
signal finished
const Art = preload("res://scripts/mastery/mastery_art.gd")
var wall: TextureRect
var actor: TextureRect
var dust: TextureRect
var flash_view: TextureRect
var blocker: Control
var animation: Tween
var playing := false

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = Vector2(1065, 115)
	clip_contents = true
	wall = Art.image(self, "RectangularWall", "gates/stone_wall_closed.png", Rect2(115, 8, 933, 101))
	actor = Art.image(self, "Sisyphus", "character/sisyphus_idle.png", Rect2(0, 3, 136, 110))
	dust = Art.image(self, "Dust", "effects/fx_dust.png", Rect2(85, 40, 130, 75))
	flash_view = Art.image(self, "OpeningLight", "effects/fx_unlock_flash.png", Rect2(110, 0, 100, 110))
	blocker = Control.new()
	blocker.name = "GateInputOnly"
	blocker.position = Vector2(115, 8)
	blocker.size = Vector2(933, 101)
	blocker.mouse_filter = MOUSE_FILTER_STOP
	add_child(blocker)
	visible = false

func play(special: bool = false) -> void:
	skip(false)
	visible = true
	playing = true
	blocker.visible = true
	wall.position.x = 115
	wall.modulate.a = 1
	dust.modulate.a = 0
	flash_view.modulate.a = 0
	flash_view.texture = Art.texture("effects/fx_special_open.png" if special else "effects/fx_unlock_flash.png")
	animation = create_tween()
	for frame in range(1, 6):
		animation.tween_callback(_pose.bind(frame))
		animation.tween_interval(0.10)
	animation.set_parallel(true)
	animation.tween_property(wall, "position:x", 1065.0, 0.65)
	animation.tween_property(wall, "modulate:a", 0.0, 0.65)
	animation.tween_property(dust, "modulate:a", 0.7, 0.2)
	animation.tween_property(flash_view, "modulate:a", 0.8, 0.2)
	animation.chain().tween_callback(func(): actor.texture = Art.texture("character/sisyphus_idle.png"))
	animation.tween_property(dust, "modulate:a", 0.0, 0.25)
	animation.tween_property(flash_view, "modulate:a", 0.0, 0.25)
	animation.chain().tween_callback(skip)

func _pose(frame: int) -> void:
	actor.texture = Art.texture("character/sisyphus_push_%02d.png" % frame)

func skip(emit_finished: bool = true) -> void:
	if animation != null: animation.kill()
	playing = false
	visible = false
	if actor != null: actor.texture = Art.texture("character/sisyphus_idle.png")
	if blocker != null: blocker.visible = false
	if emit_finished: finished.emit()

func _exit_tree() -> void:
	if animation != null: animation.kill()
