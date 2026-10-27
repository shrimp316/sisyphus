extends "res://scripts/mountain_manager.gd"

var late_grip_scale: float = 1.0
var late_grip_start_m: float = 500.0
var ledge_relocations: Array = []
var rest_point_relocations: Array = []

func grip_at(position: float) -> float:
	return super.grip_at(position) * (late_grip_scale if position >= late_grip_start_m else 1.0)

func configure_experiment(candidate: Dictionary) -> void:
	late_grip_scale = float(candidate.get("late_grip_scale", 1.0))
	late_grip_start_m = float(candidate.get("late_grip_start_m", 500.0))
	var original_ledges: Array = ledges.duplicate(true)
	var original_rest_points: Array = rest_points.duplicate()
	var mode: String = str(candidate.get("geometry_mode", "B0"))
	var pair_indices: Array = []
	if mode == "B1":
		pair_indices = [10, 12, 14, 16, 18]
	elif mode == "B3":
		pair_indices = [15, 17]
	for index: int in pair_indices:
		chunks[index].climb_length = 50.0
		chunks[index + 1].climb_length = 34.0
		if mode == "B3":
			chunks[index].surface_type = "MUD"
			chunks[index + 1].surface_type = "MUD"
	if mode == "B2":
		for index: int in range(10, 20):
			chunks[index].climb_length = 46.0
	for override: Dictionary in candidate.get("geometry_overrides", []):
		var index: int = int(override.chunk_index)
		if override.has("climb_length"):
			chunks[index].climb_length = float(override.climb_length)
		if override.has("angle"):
			chunks[index].start_angle = float(override.angle)
			chunks[index].end_angle = float(override.angle)
		if override.has("surface"):
			chunks[index].surface_type = str(override.surface)
		if override.has("wet_ranges"):
			chunks[index].wet_ranges = override.wet_ranges.duplicate(true)
	_build_curve()
	# Zero-length shelves must not remain phantom safe segments or supports.
	for index: int in range(segments.size() - 1, -1, -1):
		if float(segments[index].end) <= float(segments[index].start):
			segments.remove_at(index)
	rest_points.clear()
	rest_point_relocations.clear()
	for original_point: float in original_rest_points:
		var point: float = original_point
		if not is_shelf(point):
			for segment: Dictionary in segments:
				if bool(segment.shelf) and float(segment.end) > original_point:
					point = float(segment.end) - 0.25
					break
		if is_shelf(point) and point not in rest_points:
			rest_points.append(point)
		if not is_equal_approx(point, original_point):
			rest_point_relocations.append({"old_m": original_point, "new_m": point})
	ledges.clear()
	ledge_relocations.clear()
	for original: Dictionary in original_ledges:
		var ledge: Dictionary = original.duplicate(true)
		var old_position: float = float(ledge.distance)
		if old_position >= 250.0 and not is_shelf(old_position):
			var relocated: bool = false
			for segment: Dictionary in segments:
				if bool(segment.shelf) and float(segment.end) > old_position:
					ledge.distance = float(segment.start) + minf(2.0, (float(segment.end) - float(segment.start)) * 0.25)
					relocated = true
					break
			if not relocated:
				for index: int in range(segments.size() - 1, -1, -1):
					if bool(segments[index].shelf):
						ledge.distance = float(segments[index].end) - 2.0
						break
		# Separate obstacles moved into the same shelf by at least 1m.
		for placed: Dictionary in ledges:
			if absf(float(placed.distance) - float(ledge.distance)) < 1.0:
				ledge.distance = float(placed.distance) + 1.0
		ledges.append(ledge)
		if not is_equal_approx(old_position, float(ledge.distance)):
			ledge_relocations.append({"id": ledge.id, "old_m": old_position, "new_m": ledge.distance})

func experiment_layout() -> Array:
	var layout: Array = []
	for index: int in range(chunks.size()):
		var chunk: Dictionary = chunks[index]
		layout.append({"chunk_index": index, "start_m": index * 50.0, "end_m": (index + 1) * 50.0, "climb_end_m": index * 50.0 + float(chunk.climb_length), "shelf_length": 50.0 - float(chunk.climb_length), "surface": chunk.surface_type, "angle_degrees": chunk.start_angle, "wet_ranges": chunk.get("wet_ranges", [])})
	return layout
