class_name SceneryVisuals
extends Node2D
## A separate canvas keeps world texture repetition away from character and UI art.

const SUBSURFACE_FADE_DEPTH: float = 720.0

var art: AssetVisuals
var view_size: Vector2 = Vector2.ZERO
var camera_position: Vector2 = Vector2.ZERO
var view_zoom: float = 1.0
var camera_shake: Vector2 = Vector2.ZERO
var progress: float = 0.0
var rainy: bool = false
var clock_time: float = 0.0
var ground_outline: PackedVector2Array = PackedVector2Array()

func _init() -> void:
	show_behind_parent = true
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

func configure_view(adapter: AssetVisuals, size: Vector2, camera: Vector2, scale_value: float, shake: Vector2, climb_progress: float, rain: bool, elapsed: float) -> void:
	art = adapter
	view_size = size
	camera_position = camera
	view_zoom = scale_value
	camera_shake = shake
	progress = clampf(climb_progress, 0.0, 1.0)
	rainy = rain
	clock_time = elapsed

func set_ground(outline: PackedVector2Array) -> void:
	ground_outline = outline
	queue_redraw()

func _draw() -> void:
	if art == null or view_size.x <= 0.0 or view_size.y <= 0.0:
		return
	_draw_background()
	_draw_subsurface()

func _draw_background() -> void:
	var lowland: Texture2D = art.texture("res://assets/background/sky_mountains.png")
	var summit: Texture2D = art.texture("res://assets/background/sky_summit.png")
	if lowland == null and summit == null:
		_draw_fallback_sky()
	else:
		var base: Texture2D = lowland if lowland != null else summit
		_draw_far_layer(base, 1.0)
		if lowland != null and summit != null:
			_draw_far_layer(summit, smoothstep(0.28, 0.94, progress))
		var ridge: Texture2D = art.texture("res://assets/background/midground_ridge.png")
		if ridge != null:
			_draw_ridge(ridge)
		# A neutral veil lowers the contrast and saturation of distant rain scenery.
		if rainy:
			draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.27, 0.32, 0.36, 0.22))
	for index: int in range(16):
		var x: float = fposmod(float(index) * 149.0 - clock_time * (8.0 + float(index % 3) * 5.0), view_size.x + 100.0) - 50.0
		var y: float = 100.0 + fposmod(float(index) * 97.0, view_size.y * 0.55)
		draw_line(Vector2(x, y), Vector2(x + 18.0, y - 1.5), Color(0.85, 0.86, 0.76, 0.06), 1.0)

func _draw_far_layer(tex: Texture2D, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var cover: float = maxf(view_size.x / float(tex.get_width()), view_size.y / float(tex.get_height())) * 1.16
	var extent: Vector2 = tex.get_size() * cover
	var margin: Vector2 = (extent - view_size) * 0.5
	var pan: Vector2 = Vector2(clampf(camera_position.x * 0.006, -margin.x * 0.8, margin.x * 0.8), clampf(camera_position.y * 0.002, -margin.y * 0.8, margin.y * 0.8))
	var tint: Color = Color(0.65, 0.69, 0.72, alpha) if rainy else Color(0.85, 0.87, 0.87, alpha)
	draw_texture_rect(tex, Rect2(-margin - pan, extent), false, tint)

func _draw_ridge(tex: Texture2D) -> void:
	var height: float = view_size.y * 0.86
	var width: float = height * float(tex.get_width()) / float(tex.get_height())
	var scroll: float = camera_position.x * 0.085
	var first_tile: int = floori(scroll / width) - 1
	var count: int = ceili(view_size.x / width) + 3
	var tint: Color = Color(0.55, 0.63, 0.67, lerpf(0.84, 0.38, progress)) if rainy else Color(0.76, 0.82, 0.82, lerpf(0.86, 0.43, progress))
	for index: int in range(first_tile, first_tile + count):
		var x: float = float(index) * width - scroll
		var mirrored: bool = posmod(index, 2) == 1
		draw_set_transform(Vector2(x + (width if mirrored else 0.0), view_size.y * 0.15), 0.0, Vector2(-1.0 if mirrored else 1.0, 1.0))
		draw_texture_rect(tex, Rect2(0.0, 0.0, width + 0.5, height), false, tint)
	draw_set_transform(Vector2.ZERO)

func _draw_subsurface() -> void:
	if ground_outline.size() < 2:
		return
	var bottom: float = maxf(view_size.y + 320.0 * view_zoom, maxf(ground_outline[0].y + 1.0, ground_outline[-1].y + 1.0))
	var rock: Texture2D = art.texture("res://assets/terrain/rock_subsurface.png")
	if rock == null:
		var polygon: PackedVector2Array = ground_outline.duplicate()
		polygon.append(Vector2(ground_outline[-1].x, bottom))
		polygon.append(Vector2(ground_outline[0].x, bottom))
		draw_colored_polygon(polygon, Color("1b2a30"))
		return
	var points: PackedVector2Array = PackedVector2Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var camera_anchor: Vector2 = Vector2(view_size.x * 0.36, view_size.y * 0.67) + camera_shake
	var surface_color: Color = Color(0.63, 0.65, 0.65) if rainy else Color(0.77, 0.74, 0.68)
	var deep_color: Color = Color(0.13, 0.17, 0.20)
	for index: int in range(ground_outline.size()):
		var surface: Vector2 = ground_outline[index]
		var fade_end: Vector2 = surface + Vector2(0.0, SUBSURFACE_FADE_DEPTH * view_zoom)
		points.append(surface)
		points.append(fade_end)
		points.append(Vector2(surface.x, maxf(bottom, fade_end.y)))
		colors.append(surface_color)
		colors.append(deep_color)
		colors.append(deep_color)
		if index > 0:
			var left: int = (index - 1) * 3
			var right: int = index * 3
			# Fixed adjacent columns avoid re-triangulating the entire visible mountain.
			# Each fade spans the same world depth; extending coverage cannot change it.
			indices.append_array(PackedInt32Array([left, right, right + 1, left, right + 1, left + 1,
				left + 1, right + 1, right + 2, left + 1, right + 2, left + 2]))
	for point: Vector2 in points:
		# Invert the game's camera transform: texture grains stay attached to rock.
		var world_point: Vector2 = (point - camera_anchor) / view_zoom + camera_position
		uvs.append(world_point / 600.0)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors, uvs, PackedInt32Array(), PackedFloat32Array(), rock.get_rid())

func _draw_fallback_sky() -> void:
	var top: Color = Color("111e29").lerp(Color("273947"), progress)
	var bottom: Color = Color("7b8583").lerp(Color("d5bb93"), progress)
	if rainy:
		top = top.lerp(Color("303d48"), 0.65)
		bottom = bottom.lerp(Color("657782"), 0.80)
	for stripe: int in range(48):
		var amount: float = float(stripe) / 47.0
		draw_rect(Rect2(0.0, view_size.y * amount, view_size.x, view_size.y / 47.0 + 1.0), top.lerp(bottom, amount))
	var sun: Vector2 = Vector2(view_size.x * 0.79, view_size.y * 0.27)
	draw_circle(sun, 72.0, Color(0.88, 0.79, 0.59, 0.025))
	draw_circle(sun, 50.0, Color(0.88, 0.79, 0.59, 0.035))
	draw_circle(sun, 32.0, Color(0.83, 0.77, 0.62, 0.12 if rainy else 0.4))
	for layer: int in range(3):
		var ridge: PackedVector2Array = PackedVector2Array([Vector2(-40.0, view_size.y)])
		for index: int in range(40):
			var x: float = float(index) / 37.0 * view_size.x - 30.0
			var scroll: float = camera_position.x * (0.0009 + float(layer) * 0.0003)
			var wave: float = sin(float(index) * 0.47 + scroll) * 76.0 + sin(float(index) * 1.19 + float(layer) * 4.0) * 30.0
			ridge.append(Vector2(x, view_size.y * (0.43 + float(layer) * 0.09) + wave))
		ridge.append(Vector2(view_size.x + 40.0, view_size.y))
		draw_colored_polygon(ridge, [Color("52656a"), Color("3c5157"), Color("293e46")][layer])
