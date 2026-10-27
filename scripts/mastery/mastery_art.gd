extends RefCounted
const Loader = preload("res://scripts/mastery/mastery_layout_loader.gd")
static var cache: Dictionary = {}

static func texture(path: String) -> Texture2D:
	var resolved := Loader.asset_path(path)
	if resolved.is_empty(): return null
	if not cache.has(resolved): cache[resolved] = load(resolved) as Texture2D
	return cache[resolved]

static func image(parent: Node, name: String, path: String, rect: Rect2) -> TextureRect:
	var view := TextureRect.new()
	view.name = name
	view.texture = texture(path)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.position = rect.position
	view.size = rect.size
	parent.add_child(view)
	return view

static func label(parent: Node, name: String, value: String, rect: Rect2, role: String = "SisyphusBodyLabel") -> Label:
	var view := Label.new()
	view.name = name
	view.text = value
	view.theme_type_variation = role
	view.position = rect.position
	view.size = rect.size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)
	return view
