class_name MountainChunk
extends Resource

@export var id: String = ""
@export_range(0, 4) var zone_index: int = 0
@export var length: float = 50.0
@export var climb_length: float = 30.0
@export var start_angle: float = 10.0
@export var end_angle: float = 10.0
@export_enum("STONE", "SOIL", "GRAVEL") var surface_type: String = "STONE"
@export_range(1, 5) var difficulty: int = 1
@export var tags: PackedStringArray = PackedStringArray()
@export var v02_surface_type: String = ""
@export_range(0, 5) var v02_difficulty: int = 0
@export var ledge_offsets: PackedFloat32Array = PackedFloat32Array()
@export var wet_ranges: Array[Vector2] = []

func definition() -> Dictionary:
	var ranges: Array = []
	for interval: Vector2 in wet_ranges:
		ranges.append([interval.x, interval.y])
	return {"id": id, "zone_index": zone_index, "length": length, "climb_length": climb_length, "start_angle": start_angle, "end_angle": end_angle, "surface_type": surface_type, "difficulty": difficulty, "tags": Array(tags), "v02_surface_type": v02_surface_type, "v02_difficulty": v02_difficulty, "ledge_offsets": Array(ledge_offsets), "wet_ranges": ranges}
