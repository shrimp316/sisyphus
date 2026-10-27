extends RefCounted

const FONT = preload("res://assets/fonts/NotoSansKR.ttf")
const GOLD = Color("d6b777")
const TEXT = Color("ede5d5")
const MUTED = Color("b5b4a6")
static var textures: Dictionary = {}
static var catalog: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/mvp_assets.json"))
		if parsed is Dictionary: catalog = parsed
	if not textures.has(id):
		var path: String = str(catalog.get(id, ""))
		textures[id] = load(path) if ResourceLoader.exists(path) else null
	return textures[id]

static func image(parent: Node, id: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture(id)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.position = rect.position
	node.size = rect.size
	parent.add_child(node)
	return node

static func label(parent: Node, value: String, rect: Rect2, font_size: int = 28, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.add_theme_color_override("font_outline_color", Color(0.0,0.0,0.0,0.85))
	node.add_theme_constant_override("outline_size", 1)
	node.add_theme_color_override("font_shadow_color", Color(0.0,0.0,0.0,0.65))
	node.add_theme_constant_override("shadow_offset_x", 1)
	node.add_theme_constant_override("shadow_offset_y", 1)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func style(id: String) -> StyleBox:
	var tex: Texture2D = texture(id)
	if tex != null:
		var box := StyleBoxTexture.new()
		box.texture = tex
		box.set_texture_margin_all(24)
		box.content_margin_left = 18
		box.content_margin_right = 18
		return box
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color("182120")
	flat.border_color = GOLD
	flat.set_border_width_all(2)
	flat.set_corner_radius_all(8)
	return flat

static func button(parent: Node, text: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", 28)
	node.add_theme_color_override("font_color", TEXT)
	for state: String in ["hover", "focus", "pressed"]:
		node.add_theme_color_override("font_"+state+"_color", GOLD)
	node.add_theme_color_override("font_disabled_color", MUTED)
	var prefix: String = "primary" if primary else "secondary"
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var suffix: String = "base" if state == "normal" else ("hover" if state == "focus" else state)
		node.add_theme_stylebox_override(state, style(prefix + "_" + suffix))
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

static func backdrop(parent: Node, rect: Rect2, color: Color = Color(0.03, 0.05, 0.05, 0.94)) -> ColorRect:
	var node := ColorRect.new()
	node.color = color
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node
