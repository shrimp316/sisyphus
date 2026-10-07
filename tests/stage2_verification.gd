extends SceneTree

var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func climb_world(world: MountainManager) -> BoulderController:
	var sim := BoulderController.new(world)
	var resting_chunk: int = -1
	for step in range(120 * 1500):
		var chunk_index: int = int(sim.distance / 50.0)
		var shelf: bool = world.is_shelf(sim.distance)
		var rest: bool = (shelf and resting_chunk != chunk_index) or (not shelf and world.distance_to_shelf(sim.distance) < 3.0 and sim.velocity > 0.8)
		if shelf and sim.stamina > 99.9:
			resting_chunk = chunk_index
			rest = false
		if sim.velocity < -0.1:
			sim.advance(1.0 / 120.0, false, false, true)
		else:
			sim.advance(1.0 / 120.0, not rest, not shelf, false)
		if sim.state != "climbing": break
	return sim

func run() -> void:
	var valid_layouts: bool = true
	var coverage: Dictionary = {}
	var weather_counts: Dictionary = {"clear": 0, "rain": 0}
	var signatures: Dictionary = {}
	for seed_value in range(1, 129):
		var world := MountainManager.new(seed_value, false, 2)
		weather_counts[world.weather_id] += 1
		valid_layouts = valid_layouts and world.chunks.size() == 20 and world.segments.size() == 40 and absf(world.curve.get_baked_length() - 18000.0) < 0.1
		var hard_streak: int = 0
		var own_ids: Dictionary = {}
		var signature: String = ""
		for index in range(world.chunks.size()):
			var chunk: Dictionary = world.chunks[index]
			coverage[chunk.id] = true
			own_ids[chunk.id] = true
			signature += str(chunk.id) + ","
			hard_streak = hard_streak + 1 if int(chunk.difficulty) == 5 else 0
			valid_layouts = valid_layouts and hard_streak < 3 and int(chunk.zone_index) == index / 4 and chunk.length == 50.0 and float(chunk.climb_length) < 40.0
		valid_layouts = valid_layouts and own_ids.size() == 15
		signatures[signature] = true
		var duplicate := MountainManager.new(seed_value, false, 2)
		valid_layouts = valid_layouts and world.snapshot() == duplicate.snapshot()
	check(valid_layouts, "128 seeds preserve zone pools, all15 authored chunks,1000m length, no3 difficulty5 and deterministic seeds")
	check(coverage.size() == 15 and signatures.size() > 100 and weather_counts.clear > 0 and weather_counts.rain > 0, "generation varies ordering and naturally selects both weather modes")
	print("SEED COVERAGE unique_layouts=%d clear=%d rain=%d" % [signatures.size(), weather_counts.clear, weather_counts.rain])
	for seed_value: int in [1, 2, 3, 7, 42, 1547, 2147483646]:
		for weather: String in ["clear", "rain"]:
			var world := MountainManager.new(seed_value, false, 2)
			world.weather_id = weather
			var sim := climb_world(world)
			check(sim.state == "summit", "base-stat summit seed%d %s (%.1fs, peak%.2f, slips%d)" % [seed_value, weather, sim.elapsed, sim.peak, sim.slips])
	var original := MountainManager.new(847, false, 2)
	original.weather_id = "rain"
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(original.snapshot()))
	snapshot.chunks[0].id = "removed_catalog_item"
	snapshot.chunks[0].start_angle = 10.25
	snapshot.chunks[0].end_angle = 10.25
	snapshot.surfaces.STONE.grip = 0.975
	var restored := MountainManager.from_snapshot(snapshot)
	check(restored != null and restored.chunks[0].id == "removed_catalog_item" and is_equal_approx(rad_to_deg(restored.angle_at(0.0)), 10.25) and restored.surfaces.STONE.grip == 0.975, "snapshot restore uses embedded obsolete/custom chunk and material definitions, not catalog regeneration")
	check(JSON.parse_string(JSON.stringify(restored.snapshot())) == snapshot, "world snapshot survives JSON serialization without data loss")
	var dry_speed: Array[float] = []
	var wet_speed: Array[float] = []
	var dry_slip: Array[float] = []
	var wet_slip: Array[float] = []
	var dry_brace: Array[float] = []
	var wet_brace: Array[float] = []
	for surface: String in ["STONE", "SOIL", "GRAVEL"]:
		for weather: String in ["clear", "rain"]:
			var fixture := MountainManager.new(1, false, 2)
			fixture.chunks[0].surface_type = surface
			fixture.chunks[0].start_angle = 10.0
			fixture.chunks[0].end_angle = 10.0
			fixture.chunks[0].climb_length = 30.0
			fixture._build_curve()
			fixture.weather_id = weather
			var sim := BoulderController.new(fixture)
			sim.distance = 10.0
			sim.advance(0.5, true, true, false)
			(dry_speed if weather == "clear" else wet_speed).append(sim.velocity)
			(dry_slip if weather == "clear" else wet_slip).append(sim.slip)
			var brake := BoulderController.new(fixture)
			brake.distance = 15.0
			brake.velocity = -2.0
			brake.advance(0.1, false, false, true)
			(dry_brace if weather == "clear" else wet_brace).append(brake.velocity)
			brake.advance(3.0, false, false, true)
			check(brake.stamina < 90.0 and brake.distance <= 15.0 and brake.velocity <= 0.0, "%s %s sustained brace spends stamina and never climbs" % [surface, weather])
	check(dry_speed[0] > dry_speed[1] and dry_speed[1] > dry_speed[2] and dry_slip[0] < dry_slip[1] and dry_slip[1] < dry_slip[2], "same-slope material changes affect propulsion and slip in expected order")
	var weather_effects: bool = true
	for index in range(3):
		weather_effects = weather_effects and wet_speed[index] < dry_speed[index] and wet_slip[index] > dry_slip[index] and wet_brace[index] < dry_brace[index]
	check(weather_effects, "rain reduces push/brace traction and increases slip on all3 surfaces")
	var coarse := BoulderController.new(restored)
	var fine := BoulderController.new(MountainManager.from_snapshot(restored.snapshot()))
	for i in range(300): coarse.advance(1.0 / 30.0, true, true, false)
	for i in range(1440): fine.advance(1.0 / 144.0, true, true, false)
	check(coarse.snapshot() == fine.snapshot(), "rain/material simulation remains frame independent at30/144FPS")
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.chunks[0].start_angle = INF
	check(MountainManager.from_snapshot(invalid) == null, "nonfinite saved slope is rejected")
	print("STAGE2 INDEPENDENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


