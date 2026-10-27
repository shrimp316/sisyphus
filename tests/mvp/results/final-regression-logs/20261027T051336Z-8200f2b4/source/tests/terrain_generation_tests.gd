extends SceneTree

var checks: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func equivalent(left: Variant, right: Variant) -> bool:
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left) - float(right)) < 0.0000001
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not equivalent(left[index], right[index]):
				return false
		return true
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not equivalent(left[key], right[key]):
				return false
		return true
	return left == right

func verify_new_courses() -> void:
	var dimensions: bool = true
	var angles: bool = true
	var geometry: bool = true
	var obstacles: bool = true
	var bags: bool = true
	var repeatable: bool = true
	var same_id_angles: Dictionary = {}
	for run_seed: int in range(1, 97):
		var world := MountainManager.new(run_seed, false, 5)
		var old_world := MountainManager.new(run_seed, false, 3)
		repeatable = repeatable and world.snapshot() == MountainManager.new(run_seed, false, 5).snapshot()
		dimensions = dimensions and world.generation_version == 5 and world.chunks.size() == 20 and is_equal_approx(world.total_length, 1000.0)
		bags = bags and world.weather_id == old_world.weather_id
		for index: int in range(world.chunks.size()):
			var chunk: Dictionary = world.chunks[index]
			var old: Dictionary = old_world.chunks[index]
			var begin: float = index * 50.0
			var degrees: float = float(chunk.start_angle)
			dimensions = dimensions and is_equal_approx(float(chunk.length) - float(chunk.climb_length), 8.0)
			dimensions = dimensions and not world.is_shelf(begin + 41.99) and world.is_shelf(begin + 42.01)
			angles = angles and degrees >= 4.0 and degrees <= 32.0 and is_equal_approx(degrees, float(chunk.end_angle))
			if str(chunk.surface_type) == "WET_STONE":
				angles = angles and degrees >= 16.0 and degrees <= 20.0
			else:
				angles = angles and absf(degrees - float(old.start_angle)) <= 4.0
			bags = bags and chunk.id == old.id and chunk.surface_type == old.surface_type and chunk.difficulty == old.difficulty
			var midpoint: float = begin + 21.0
			var drawn_direction: Vector2 = world.sample(midpoint + 1.0) - world.sample(midpoint - 1.0)
			geometry = geometry and absf(-drawn_direction.angle() - world.angle_at(midpoint)) < 0.001
			var flat_direction: Vector2 = world.sample(begin + 47.0) - world.sample(begin + 45.0)
			geometry = geometry and absf(flat_direction.angle()) < 0.001 and is_zero_approx(world.angle_at(begin + 46.0))
			obstacles = obstacles and chunk.wet_ranges == old.wet_ranges
			for offset: Variant in chunk.ledge_offsets:
				obstacles = obstacles and float(offset) > 42.0 and float(offset) < 50.0 and world.is_shelf(begin + float(offset))
			for interval: Variant in chunk.wet_ranges:
				obstacles = obstacles and float(interval[0]) >= 0.0 and float(interval[1]) <= 42.0
			var id: String = str(chunk.id)
			if not same_id_angles.has(id):
				same_id_angles[id] = [degrees, degrees]
			same_id_angles[id][0] = minf(float(same_id_angles[id][0]), degrees)
			same_id_angles[id][1] = maxf(float(same_id_angles[id][1]), degrees)
	var repeat_id_varies: bool = same_id_angles.size() == 15
	for bounds: Array in same_id_angles.values():
		repeat_id_varies = repeat_id_varies and float(bounds[1]) - float(bounds[0]) > 0.25
	check(dimensions, "96 seeds keep 1000m total with twenty 42m climbs and 8m shelves")
	check(angles, "random slopes stay within authored difficulty range and wet-climb safety ceiling")
	check(repeat_id_varies, "all fifteen authored variants, including wet stone, receive different inclines across draws")
	check(repeatable, "a run seed reproduces the entire geometry exactly")
	check(bags, "geometry randomization leaves authored bag order, materials and weather unchanged")
	check(geometry, "rendered curve inclines and flat shelves agree with physics angle queries")
	check(obstacles, "shelf ledges remain on the shortened shelf and localized wet patches remain in bounds")
	var first := MountainManager.new(1)
	var second := MountainManager.new(42)
	check(first.chunks != second.chunks, "different run seeds produce different courses")

func verify_history_and_saves() -> void:
	var unchanged: bool = true
	for run_seed: int in [1, 42, 1547]:
		var old := MountainManager.new(run_seed, false, 3)
		for chunk: Dictionary in old.chunks:
			var authored: MountainChunk = load("res://data/chunks/%s.tres" % str(chunk.id)) as MountainChunk
			unchanged = unchanged and is_equal_approx(float(chunk.start_angle), authored.start_angle) and is_equal_approx(float(chunk.climb_length), authored.climb_length)
	check(unchanged, "version 3 keeps original authored inclines and shelf lengths")
	for version: int in [1, 2, 3, 4, 5, 6]:
		var world := MountainManager.new(1547, version == 1, version)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(world.snapshot()))
		var restored := MountainManager.from_snapshot(saved)
		var roundtrip: bool = restored != null
		if roundtrip:
			roundtrip = equivalent(world.snapshot(), restored.snapshot()) and equivalent(world.rest_points, restored.rest_points) and equivalent(world.ledges, restored.ledges)
			for meter: int in range(1000):
				roundtrip = roundtrip and world.sample(float(meter)).is_equal_approx(restored.sample(float(meter)))
		check(roundtrip, "version %d JSON save/load preserves full course without rerolling" % version)
		if version >= 4 and restored != null:
			var sim := BoulderController.new(world)
			sim.distance = 460.0
			sim.advance(0.013, true, true, false)
			var clone := BoulderController.new(restored)
			clone.restore(JSON.parse_string(JSON.stringify(sim.snapshot())))
			for step: int in range(150):
				sim.advance(0.013, true, false, false)
				clone.advance(0.013, true, false, false)
			check(equivalent(sim.snapshot(), clone.snapshot()), "version %d resumes fractional-step physics exactly after save/load" % version)
	var debug := MountainManager.debug_course()
	var restored_debug := MountainManager.from_snapshot(JSON.parse_string(JSON.stringify(debug.snapshot())))
	check(debug.generation_version == 3 and debug.chunks.size() == 5 and is_equal_approx(debug.total_length, 98.0) and restored_debug != null and equivalent(debug.snapshot(), restored_debug.snapshot()), "authored debug course stays unchanged and reloadable")

func verify_shelf_recovery() -> void:
	for material: String in ["STONE", "WET_STONE"]:
		var world := MountainManager.new(42)
		world.chunks[0].surface_type = material
		world._build_curve()
		var sim := BoulderController.new(world)
		sim.distance = 42.01
		sim.velocity = 1.1
		sim.stamina = 50.0
		for step: int in range(1200):
			sim.advance(BoulderController.FIXED_DT, false, false, false)
		check(sim.distance < 50.0 and sim.velocity == 0.0 and sim.stamina == 100.0, material + " 8m shelf stops normal pace and allows full recovery")

func run() -> void:
	verify_new_courses()
	verify_history_and_saves()
	verify_shelf_recovery()
	print("TERRAIN GENERATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
