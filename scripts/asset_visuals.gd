class_name AssetVisuals
extends RefCounted
## Pure presentation adapter. Missing optional artwork retains the original renderer.

const CHARACTER_ANIMATIONS: Dictionary = {"idle": [6, 6.0], "push": [8, 8.0], "heavy_push": [6, 8.0], "brace": [6, 8.0], "exhausted": [6, 6.0]}
const FX_ANIMATIONS: Dictionary = {"dust": [6, 10.0], "gravel": [6, 12.0], "impact": [6, 14.0], "wind": [6, 6.0], "breath": [6, 6.0], "snow": [6, 8.0]}
var textures: Dictionary = {}
var animations: Dictionary = {}

func texture(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return textures[path] as Texture2D

func frames(kind: String) -> SpriteFrames:
	if not animations.has(kind):
		var path: String = "res://godot/resources/spriteframes/%s.tres" % kind
		animations[kind] = load(path) as SpriteFrames if ResourceLoader.exists(path) else null
	return animations[kind] as SpriteFrames

func frame(kind: String, animation: String, elapsed: float, loop: bool = true) -> Texture2D:
	var resource: SpriteFrames = frames(kind)
	if resource == null or not resource.has_animation(animation):
		return null
	var count: int = resource.get_frame_count(animation)
	if count == 0:
		return null
	var index: int = int(maxf(0.0, elapsed) * resource.get_animation_speed(animation))
	index = index % count if loop else mini(index, count - 1)
	return resource.get_frame_texture(animation, index)

static func character_animation(action: String, stamina: float) -> String:
	match action:
		"brace", "slip": return "brace"
		"exert": return "heavy_push"
		"push": return "push"
	return "exhausted" if stamina < 30.0 else "idle"

func terrain(surface_id: String, wet: bool) -> Texture2D:
	var name: String = "rock_ground"
	match surface_id.to_lower():
		"gravel": name = "gravel_ground"
		"soil", "mud": name = "mud_ground"
		"wet_stone": name = "wet_rock"
	if wet and name == "rock_ground":
		name = "wet_rock"
	return texture("res://assets/terrain/%s.png" % name)

static func draw_at(canvas: CanvasItem, tex: Texture2D, position: Vector2, pivot: Vector2, scale_value: float, rotation: float = 0.0, tint: Color = Color.WHITE) -> bool:
	if tex == null:
		return false
	canvas.draw_set_transform(position, rotation, Vector2.ONE * scale_value)
	canvas.draw_texture(tex, -pivot, tint)
	canvas.draw_set_transform(Vector2.ZERO)
	return true
