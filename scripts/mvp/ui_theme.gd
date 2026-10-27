extends RefCounted

const GOLD = Color("f0c781")
const TEXT = Color("dfd0af")
const MUTED = Color("81796d")
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

static func label(parent: Node, value: String, rect: Rect2, font_size: int = 28, color: Color = TEXT, variation: StringName = &"") -> Label:
	var node := Label.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	# Existing overlay calls retain their explicit sizes and colors; role-based
	# calls inherit the shared Theme's font, size, color, and engraving effects.
	node.theme_type_variation = variation if variation != &"" else &"SisyphusBodyLabel"
	if variation == &"":
		node.add_theme_font_size_override("font_size", font_size)
		node.add_theme_color_override("font_color", color)
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

static func button(parent: Node, text: String, rect: Rect2, callback: Callable, primary: bool = false, variation: StringName = &"") -> Button:
	var node := Button.new()
	node.text = text
	node.position = rect.position
	node.size = rect.size
	node.theme_type_variation = variation if variation != &"" else (&"SisyphusPrimaryButton" if primary else &"SisyphusSecondaryButton")
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
