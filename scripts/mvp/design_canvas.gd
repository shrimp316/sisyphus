extends Control

const Typography = preload("res://scripts/mvp/typography.gd")
var canvas: Control

func _ready() -> void:
	theme = Typography.load_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = Control.new()
	canvas.size = Vector2(1920, 1080)
	add_child(canvas)
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	if canvas == null: return
	var factor: float = minf(size.x / 1920.0, size.y / 1080.0)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - Vector2(1920, 1080) * factor) * 0.5
