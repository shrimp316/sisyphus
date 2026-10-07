class_name MountainManager
extends RefCounted

const LENGTH: float = 1000.0
const PIXELS_PER_METER: float = 18.0
const ZONES: Array[String] = ["황량한 산기슭", "오래된 돌길", "바람의 능선", "침묵의 고지", "마지막 오르막"]
const SURFACE_IDS: Array[String] = ["STONE", "SOIL", "GRAVEL"]
var curve: Curve2D = Curve2D.new()
var segments: Array[Dictionary] = []
var chunks: Array[Dictionary] = []
var seed_value: int = 1
var generation_version: int = 2
var total_length: float = LENGTH
var debug_mode: bool = false
var rest_points: Array[float] = []
var ledges: Array[Dictionary] = []
var legacy: bool = false
var weather_id: String = "clear"
var surfaces: Dictionary = {
	"STONE": {"id": "STONE", "label": "돌", "grip": 1.0, "resistance": 1.0, "slipperiness": 0.6, "color": Color("9ba5a3")},
	"SOIL": {"id": "SOIL", "label": "흙", "grip": 0.85, "resistance": 1.15, "slipperiness": 0.8, "color": Color("ae805d")},
	"GRAVEL": {"id": "GRAVEL", "label": "자갈", "grip": 0.75, "resistance": 1.3, "slipperiness": 1.2, "color": Color("a1adb1")}
}

func _init(run_seed: int = 1, legacy_mode: bool = false, generation: int = 3) -> void:
	seed_value = run_seed
	legacy = legacy_mode
	generation_version = 1 if legacy else generation
	if generation_version >= 3:
		_set_v02_surfaces()
	if legacy:
		generation_version = 1
		_legacy_chunks()
	else:
		_generate_chunks()
	_build_curve()

func _set_v02_surfaces() -> void:
	surfaces.STONE.slipperiness = 1.0
	surfaces.GRAVEL.resistance = 1.15
	surfaces.GRAVEL.slipperiness = 1.3
	surfaces["MUD"] = {"id": "MUD", "label": "진흙", "grip": 0.9, "resistance": 1.5, "slipperiness": 1.1, "color": Color("89694f")}
	surfaces["WET_STONE"] = {"id": "WET_STONE", "label": "젖은 바위", "grip": 0.55, "resistance": 0.85, "slipperiness": 1.5, "color": Color("7ca6aa")}

func _legacy_chunks() -> void:
	var angles: Array[float] = [9, 13, 17, 20, 16, 24, 27, 21, 28, 30, 23, 32, 26, 33, 29, 35, 28, 36, 32, 38]
	for index: int in range(20):
		chunks.append({"id": "legacy_%02d" % index, "zone_index": index / 4, "length": 50.0, "climb_length": 36.0 if index < 12 else 32.0, "start_angle": angles[index], "end_angle": angles[index], "surface_type": "STONE", "difficulty": mini(5, index / 4 + 1), "tags": ["legacy"]})

func _generate_chunks() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	weather_id = "rain" if random.randf() < 0.20 else "clear"
	var hard_streak: int = 0
	var hard_threshold: int = 4 if generation_version >= 3 else 5
	for zone_index: int in range(5):
		var pool: Array[Dictionary] = []
		for surface_id: String in SURFACE_IDS:
			var chunk: MountainChunk = load("res://data/chunks/zone_%d_%s.tres" % [zone_index + 1, surface_id.to_lower()]) as MountainChunk
			var definition: Dictionary = chunk.definition()
			if generation_version >= 3 and int(definition.get("v02_difficulty", 0)) > 0:
				definition.difficulty = int(definition.v02_difficulty)
			pool.append(definition)
		# A shuffled bag visits each authored variant before a fourth draw.
		var bag: Array[Dictionary] = pool.duplicate(true)
		for index: int in range(4):
			if bag.is_empty():
				bag = pool.duplicate(true)
			var candidates: Array[Dictionary] = []
			for candidate: Dictionary in bag:
				if (hard_streak < 2 or int(candidate.difficulty) < hard_threshold) and (generation_version < 3 or chunks.is_empty() or str(candidate.id) != str(chunks.back().id)):
					candidates.append(candidate)
			if candidates.is_empty():
				for candidate: Dictionary in pool:
					if int(candidate.difficulty) < hard_threshold and (generation_version < 3 or chunks.is_empty() or str(candidate.id) != str(chunks.back().id)):
						candidates.append(candidate)
			var selected: Dictionary = candidates[random.randi_range(0, candidates.size() - 1)].duplicate(true)
			bag.erase(selected)
			if generation_version >= 3:
				var override_surface: String = str(selected.get("v02_surface_type", ""))
				if not override_surface.is_empty():
					selected.surface_type = override_surface
			chunks.append(selected)
			hard_streak = hard_streak + 1 if int(selected.difficulty) >= hard_threshold else 0

func _build_curve() -> void:
	curve.clear_points()
	segments.clear()
	rest_points.clear()
	ledges.clear()
	curve.bake_interval = 2.0
	var point: Vector2 = Vector2.ZERO
	var start: float = 0.0
	curve.add_point(point)
	for chunk: Dictionary in chunks:
		var climb: float = float(chunk.climb_length)
		# Phase 2 resources author a constant slope (equal start/end angles).
		var angle: float = deg_to_rad(float(chunk.start_angle))
		var common: Dictionary = {"surface": str(chunk.surface_type), "chunk_id": str(chunk.id), "difficulty": int(chunk.difficulty), "zone_index": int(chunk.zone_index)}
		var uphill: Dictionary = common.duplicate()
		uphill.merge({"start": start, "end": start + climb, "angle": angle, "shelf": false})
		if climb > 0.0:
			segments.append(uphill)
			point += Vector2(cos(angle), -sin(angle)) * climb * PIXELS_PER_METER
			curve.add_point(point)
		var shelf: Dictionary = common.duplicate()
		shelf.merge({"start": start + climb, "end": start + float(chunk.length), "angle": 0.0, "shelf": true})
		segments.append(shelf)
		point += Vector2.RIGHT * (float(chunk.length) - climb) * PIXELS_PER_METER
		curve.add_point(point)
		if generation_version >= 3:
			rest_points.append(start + float(chunk.length) - 0.25)
			for offset: Variant in chunk.get("ledge_offsets", []):
				ledges.append({"id": "%s@%d" % [str(chunk.id), int(start)], "distance": start + float(offset), "required_push": 1.6})
		start += float(chunk.length)
	total_length = start

func sample(distance: float) -> Vector2:
	return curve.sample_baked(clampf(distance, 0.0, total_length) * PIXELS_PER_METER)

func segment_at(distance: float) -> Dictionary:
	var d: float = clampf(distance, 0.0, total_length - 0.001)
	for segment: Dictionary in segments:
		if d < float(segment.end):
			return segment
	return segments.back()

func angle_at(distance: float) -> float:
	return float(segment_at(distance).angle)

func is_shelf(distance: float) -> bool:
	return bool(segment_at(distance).shelf)

func distance_to_shelf(distance: float) -> float:
	var segment: Dictionary = segment_at(distance)
	return 0.0 if bool(segment.shelf) else float(segment.end) - distance

func zone(distance: float) -> String:
	return ZONES[clampi(int(distance / 200.0), 0, 4)]

func surface_at(distance: float) -> Dictionary:
	var surface_id: String = str(segment_at(distance).surface)
	if generation_version >= 3 and surface_id == "STONE" and wet_at(distance):
		surface_id = "WET_STONE"
	return surfaces[surface_id] as Dictionary

func wet_at(distance: float) -> bool:
	if generation_version < 3:
		return weather_id == "rain" and not legacy
	if str(segment_at(distance).surface) == "WET_STONE":
		return true
	if weather_id != "rain":
		return false
	var start: float = 0.0
	for chunk: Dictionary in chunks:
		if distance >= start and distance < start + float(chunk.length):
			for interval: Variant in chunk.get("wet_ranges", []):
				if distance >= start + float(interval[0]) and distance <= start + float(interval[1]):
					return true
			return false
		start += float(chunk.length)
	return false

func grip_at(distance: float) -> float:
	if legacy:
		return 1.0
	if generation_version >= 3:
		return float(surface_at(distance).grip) * (0.85 if weather_id == "rain" and wet_at(distance) else 1.0)
	return float(surface_at(distance).grip) * (0.8 if weather_id == "rain" else 1.0)

func slip_multiplier_at(distance: float) -> float:
	if legacy:
		return 1.0
	if generation_version >= 3:
		return float(surface_at(distance).slipperiness)
	return float(surface_at(distance).slipperiness) / 0.6 * (1.4 if weather_id == "rain" else 1.0)

func resistance_at(distance: float) -> float:
	return 0.20 if legacy else 0.20 * float(surface_at(distance).resistance)

func weather_label() -> String:
	return "비" if weather_id == "rain" else "맑음"

func snapshot() -> Dictionary:
	var saved_surfaces: Dictionary = surfaces.duplicate(true)
	for key: String in saved_surfaces:
		saved_surfaces[key].color = (saved_surfaces[key].color as Color).to_html()
	return {"generation_version": generation_version, "seed": seed_value, "legacy": legacy, "weather": weather_id, "chunks": chunks.duplicate(true), "surfaces": saved_surfaces, "total_length": total_length, "debug_mode": debug_mode}

static func from_snapshot(data: Dictionary) -> MountainManager:
	if int(data.get("generation_version", 0)) not in [1, 2, 3] or not data.get("chunks") is Array or not data.get("surfaces") is Dictionary:
		return null
	var ordered: Array = data.chunks as Array
	var debug: bool = bool(data.get("debug_mode", false)) and int(data.generation_version) == 3
	if (ordered.size() != 20 and not debug) or ordered.is_empty() or ordered.size() > 40 or str(data.get("weather", "")) not in ["clear", "rain"]:
		return null
	var terrain: MountainManager = MountainManager.new(1, true)
	terrain.chunks.clear()
	for index: int in range(ordered.size()):
		if not ordered[index] is Dictionary:
			return null
		var chunk: Dictionary = ordered[index] as Dictionary
		if not _valid_chunk(chunk, index / 4, debug):
			return null
		terrain.chunks.append(chunk.duplicate(true))
	var surface_data: Dictionary = data.surfaces as Dictionary
	var surface_keys: Array[String] = SURFACE_IDS.duplicate()
	if int(data.generation_version) >= 3:
		surface_keys.append_array(["MUD", "WET_STONE"])
	for key: String in surface_keys:
		if not surface_data.get(key) is Dictionary:
			return null
		var material: Dictionary = (surface_data[key] as Dictionary).duplicate(true)
		for number_key: String in ["grip", "resistance", "slipperiness"]:
			var value: float = float(material.get(number_key, -1.0))
			if not is_finite(value) or value <= 0.0 or value > 5.0:
				return null
		material.id = key
		material.label = str(material.get("label", key))
		material.color = Color.from_string(str(material.get("color", "aca184")), Color("aca184"))
		terrain.surfaces[key] = material
	terrain.generation_version = int(data.generation_version)
	terrain.debug_mode = debug
	terrain.legacy = terrain.generation_version == 1
	terrain.seed_value = int(data.get("seed", 1))
	terrain.weather_id = "clear" if terrain.legacy else str(data.weather)
	terrain._build_curve()
	return terrain

static func _valid_chunk(chunk: Dictionary, expected_zone: int, debug: bool = false) -> bool:
	if str(chunk.get("surface_type", "")) not in ["STONE", "SOIL", "GRAVEL", "MUD", "WET_STONE"] or (not debug and int(chunk.get("zone_index", -1)) != expected_zone):
		return false
	if str(chunk.get("id", "")).is_empty() or int(chunk.get("difficulty", 0)) not in [1, 2, 3, 4, 5]:
		return false
	var length: float = float(chunk.get("length", -1.0))
	var climb: float = float(chunk.get("climb_length", -1.0))
	var start_angle: float = float(chunk.get("start_angle", -1.0))
	var end_angle: float = float(chunk.get("end_angle", -1.0))
	if not ((is_equal_approx(length, 50.0) or (debug and length > 0.0 and length <= 60.0)) and is_finite(climb) and climb >= 0.0 and climb < length and is_finite(start_angle) and start_angle >= 0.0 and start_angle <= 45.0 and is_equal_approx(start_angle, end_angle)):
		return false
	for offset: Variant in chunk.get("ledge_offsets", []):
		if not is_finite(float(offset)) or float(offset) < 0.0 or float(offset) >= length:
			return false
	for interval: Variant in chunk.get("wet_ranges", []):
		if not interval is Array or interval.size() != 2 or float(interval[0]) < 0.0 or float(interval[1]) > length or float(interval[1]) <= float(interval[0]):
			return false
	return true

static func debug_course() -> MountainManager:
	var terrain: MountainManager = MountainManager.new(1, true)
	terrain.legacy = false
	terrain.generation_version = 3
	terrain.debug_mode = true
	terrain.weather_id = "clear"
	terrain._set_v02_surfaces()
	terrain.chunks.clear()
	var definitions: Array = [["flat", 14.0, 0.0, 0.0, "STONE"], ["slope20", 28.0, 16.0, 20.0, "STONE"], ["gravel30", 22.0, 12.0, 30.0, "GRAVEL"], ["slope35", 14.0, 10.0, 35.0, "STONE"], ["wet30", 20.0, 12.0, 30.0, "WET_STONE"]]
	for index: int in range(definitions.size()):
		var d: Array = definitions[index]
		terrain.chunks.append({"id": "debug_" + str(d[0]), "zone_index": 0, "length": float(d[1]), "climb_length": float(d[2]), "start_angle": float(d[3]), "end_angle": float(d[3]), "surface_type": str(d[4]), "difficulty": mini(index + 1, 5), "tags": ["debug", "narrow" if index == 3 else "safe"], "ledge_offsets": [15.0] if index == 2 else [], "wet_ranges": []})
	terrain._build_curve()
	return terrain
