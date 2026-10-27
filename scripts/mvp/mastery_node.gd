extends Button

const UI = preload("res://scripts/mvp/ui_theme.gd")
var node_id: String
var state_name: String
var _pulse: Tween

func configure(definition: Dictionary, state: String) -> void:
	var previous_state: String = state_name
	node_id = str(definition.id)
	state_name = state
	text = "%s  %d\n%s" % ["특별" if definition.category == "SPC" else {"STR":"근력","END":"지구력","BRE":"호흡"}.get(definition.category, definition.category), definition.sequence, {"purchased":"각인 완료", "available":"%d EXP" % definition.exp_cost, "locked":"미개방", "disabled":"준비 중", "prerequisite":"선행 필요", "insufficient_exp":"EXP 부족"}.get(state, state)]
	tooltip_text = "%s · %s" % [definition.name, definition.description]
	theme_type_variation = &"SisyphusNodeButton"
	var text_color: Color = Color("f5d79c") if state == "purchased" else (Color("e8bd78") if state == "available" else Color("81796d"))
	add_theme_color_override("font_color", text_color)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("29372c") if state == "purchased" else (Color("343022") if state == "available" else Color("1a2222"))
	box.border_color = UI.GOLD if state in ["purchased", "available"] else Color("4e5551")
	box.set_border_width_all(2)
	box.set_corner_radius_all(12 if definition.category == "SPC" else 5)
	add_theme_stylebox_override("normal", box)
	var focus: StyleBoxFlat = box.duplicate()
	focus.border_color = Color("ffe0a0")
	focus.set_border_width_all(4)
	add_theme_stylebox_override("hover", focus)
	add_theme_stylebox_override("focus", focus)
	add_theme_stylebox_override("pressed", focus)
	if get_child_count() == 0:
		var tex: TextureRect = UI.image(self, "node_core" if definition.category == "SPC" else "node_branch", Rect2(8, 8, 34, 34))
		tex.modulate.a = 0.75
	if previous_state != state:
		if _pulse != null and _pulse.is_valid(): _pulse.kill()
		modulate = Color.WHITE
		if not previous_state.is_empty() and state in ["available", "purchased"]:
			modulate = Color(1.25,1.15,0.85,1.0)
			_pulse = create_tween()
			_pulse.tween_property(self,"modulate",Color.WHITE,0.3)
