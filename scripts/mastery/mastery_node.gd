extends Control
signal selected(node_id: String)
const Art = preload("res://scripts/mastery/mastery_art.gd")
const COLORS := {"strength": Color("f6af4d"), "endurance": Color("38a7ff"), "breath": Color("37e7e4"), "special": Color("f0c781")}
var data: Dictionary
var state: Dictionary = {}
var hit_target: Button
var glyph: TextureRect
var selection_overlay: TextureRect
var state_overlay: TextureRect
var lock_overlay: TextureRect
var glow_overlay: TextureRect
var special_icon: TextureRect
var fx: Tween

func configure(row: Dictionary) -> void:
	data = row
	name = data.node_id
	var side := 110.0 if data.track == "special" else 88.0
	size = Vector2(side, side)
	position = Vector2(data.x, data.y) - size * 0.5
	mouse_filter = MOUSE_FILTER_IGNORE
	var bounds := Rect2(Vector2.ZERO, size)
	Art.image(self, "NodeBase", data.base_asset, bounds)
	Art.image(self, "NodeRing", data.frame_asset, bounds)
	if data.track != "special":
		Art.image(self, "RuneFace", data.rune_face_png, bounds)
		glyph = Art.image(self, "Glyph", data.glyph_engraved_png, bounds)
	else:
		special_icon = Art.image(self, "SpecialIcon", "special/special_placeholder_%02d.png" % int(data.index), bounds)
	state_overlay = Art.image(self, "StateOverlay", "nodes/state_story_locked.png", bounds)
	lock_overlay = Art.image(self, "LockOverlay", "special/special_seal.png" if data.track == "special" else "nodes/state_padlock_symbol.png", bounds)
	glow_overlay = Art.image(self, "GlowOverlay", "effects/fx_engrave.png", bounds.grow(10))
	glow_overlay.modulate = COLORS[data.track]
	glow_overlay.modulate.a = 0.0
	selection_overlay = Art.image(self, "SelectionOverlay", "nodes/state_selected.png", bounds.grow(3))
	selection_overlay.visible = false
	hit_target = Button.new()
	hit_target.name = "HitTarget"
	hit_target.size = size
	hit_target.flat = true
	hit_target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed", "disabled", "focus"]: hit_target.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	hit_target.pressed.connect(func(): selected.emit(str(data.node_id)))
	hit_target.focus_entered.connect(func(): selected.emit(str(data.node_id)))
	add_child(hit_target)
	var number := Art.label(self, "Index", "%02d" % int(data.index), Rect2(0, side - 3, side, 24), "SisyphusTooltipLabel")
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 16)

func apply_state(next_state: Dictionary) -> void:
	selection_overlay.visible = bool(next_state.selected)
	var base_changed: bool = state.get("base_state", "") != next_state.base_state
	state = next_state.duplicate()
	if not base_changed: return
	var base: String = state.base_state
	var locked: bool = base in ["STORY_LOCKED", "LOCKED"]
	lock_overlay.visible = locked
	var overlay := "nodes/state_%s.png" % base.to_lower()
	if base == "LOCKED": overlay = "nodes/state_story_locked.png"
	state_overlay.texture = Art.texture(overlay)
	state_overlay.modulate.a = 0.45 if locked else 0.7
	if glyph != null:
		var glyph_role := "active" if base == "PURCHASED" else ("ready" if base == "AVAILABLE" else "engraved")
		glyph.texture = Art.texture(data["glyph_%s_png" % glyph_role])
		glyph.modulate = COLORS[data.track] if base == "PURCHASED" else Color.WHITE
		glyph.visible = not locked
	if data.track == "special":
		state_overlay.visible = false
		special_icon.modulate.a = 0.5 if locked else 1.0
	hit_target.tooltip_text = "%s %02d · %s\n%s" % [str(data.track), int(data.index), base, "효과·비용 미정 / 개발 데이터" if data.track == "special" else "선택하여 조건과 강화점을 확인하세요"]

func flash(delay: float = 0.0) -> void:
	if fx != null: fx.kill()
	glow_overlay.modulate.a = 0.0
	fx = create_tween()
	fx.tween_interval(delay)
	fx.tween_property(glow_overlay, "modulate:a", 0.85, 0.15)
	fx.tween_property(glow_overlay, "modulate:a", 0.0, 0.55)

func stop_animation() -> void:
	if fx != null: fx.kill()
	glow_overlay.modulate.a = 0.0
