extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _run() -> void:
	var rain_count: int = 0
	for seed_index: int in range(1, 101):
		var terrain: MountainManager = MountainManager.new(seed_index, false, 2)
		var repeated: MountainManager = MountainManager.new(seed_index, false, 2)
		check(terrain.snapshot() == repeated.snapshot(), "Repeated seed reproduces exact route and weather")
		check(terrain.chunks.size() == 20 and terrain.segments.size() == 40, "Route contains twenty climb/shelf chunks")
		var seen: Dictionary = {}
		var streak: int = 0
		for index: int in range(20):
			var chunk: Dictionary = terrain.chunks[index]
			seen[str(chunk.id)] = true
			streak = streak + 1 if int(chunk.difficulty) == 5 else 0
			check(streak < 3 and int(chunk.zone_index) == index / 4, "Zone pools and hard-climb streak constraints hold")
		check(seen.size() == 15, "Every route visits all fifteen authored variants")
		check(absf(terrain.curve.get_baked_length() - 18000.0) < 1.0, "Visual curve and meter simulation use the same authored length")
		rain_count += 1 if terrain.weather_id == "rain" else 0
	print("WEATHER SAMPLE: %d rainy routes /100 seeds" % rain_count)
	check(rain_count >= 8 and rain_count <= 35, "Seeded weather distribution is consistent with20percent rain")
	var terrain: MountainManager = MountainManager.new(12, false, 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(terrain.snapshot())) as Dictionary
	saved.chunks[0].id = "retired_catalog_entry"
	var restored: MountainManager = MountainManager.from_snapshot(saved)
	check(restored != null and restored.chunks[0].id == "retired_catalog_entry", "Snapshot restores authored definitions without catalog lookup")
	for index: int in range(0, 1001, 10):
		check(terrain.sample(float(index)).distance_to(restored.sample(float(index))) < 0.01, "Serialized path roundtrip preserves world coordinates")
	saved.chunks[0].climb_length = 99.0
	check(MountainManager.from_snapshot(saved) == null, "Malformed route cannot silently replace a saved mountain")
	for surface_id: String in MountainManager.SURFACE_IDS:
		var position: float = 0.0
		for segment: Dictionary in terrain.segments:
			if str(segment.surface) == surface_id and not bool(segment.shelf):
				position = float(segment.start) + 2.0
				break
		terrain.weather_id = "clear"
		var dry: BoulderController = BoulderController.new(terrain)
		dry.distance = position
		dry.advance(1.0 / 120.0, true, true, false)
		var dry_acceleration: float = dry.acceleration
		var dry_slip: float = dry.slip
		terrain.weather_id = "rain"
		var wet: BoulderController = BoulderController.new(terrain)
		wet.distance = position
		wet.advance(1.0 / 120.0, true, true, false)
		check(wet.acceleration < dry_acceleration and wet.slip > dry_slip, "%s rain reduces pushing traction and increases deterministic slip" % surface_id)
		wet.velocity = -0.2
		wet.advance(0.5, false, false, true)
		check(wet.velocity <= 0.0 and wet.velocity > -0.1, "%s rain brace arrests rollback without pushing uphill" % surface_id)
		var shelf: float = float(terrain.segment_at(position).end) + 3.0
		for direction: float in [-1.0, 1.0]:
			var rolling: BoulderController = BoulderController.new(terrain)
			rolling.distance = shelf
			rolling.velocity = direction * 0.5
			rolling.advance(1.0, false, false, false)
			check(absf(rolling.velocity) < 0.5 and rolling.velocity * direction >= 0.0, "%s resistance opposes either rolling direction" % surface_id)
			rolling.advance(5.0, false, false, false)
			var stopped_at: float = rolling.distance
			rolling.advance(12.0, false, false, false)
			check(rolling.velocity == 0.0 and rolling.distance == stopped_at, "%s rolling friction settles exactly without indefinite shelf drift" % surface_id)
	for seed_index: int in [1, 7, 42, 91]:
		for weather: String in ["clear", "rain"]:
			_check_summit(seed_index, weather)
	print("ENVIRONMENT TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check_summit(run_seed: int, weather: String) -> void:
	var terrain: MountainManager = MountainManager.new(run_seed, false, 2)
	terrain.weather_id = weather
	var climb: BoulderController = BoulderController.new(terrain)
	var rested_chunk: int = -1
	for tick: int in range(120 * 1800):
		var index: int = int(climb.distance / 50.0)
		var shelf: bool = terrain.is_shelf(climb.distance)
		var rest: bool = shelf and rested_chunk != index
		if shelf and climb.stamina > 99.9 and climb.slip < 0.1:
			rested_chunk = index
			rest = false
		if not shelf and terrain.distance_to_shelf(climb.distance) < 3.0 and climb.velocity > 0.8:
			rest = true
		var gravity: float = 4.0 * sin(terrain.angle_at(climb.distance))
		var normal_margin: float = 2.0 * climb.stamina_multiplier() * terrain.grip_at(climb.distance) - gravity - terrain.resistance_at(climb.distance)
		if climb.velocity < -0.1:
			climb.advance(1.0 / 120.0, false, false, true)
		else:
			climb.advance(1.0 / 120.0, not rest, normal_margin < 0.15, false)
		if climb.state != "climbing":
			break
	print("ROUTE %d %s: %s %.1fm %.1fs stamina%.1f slip%d" % [run_seed, weather, climb.state, climb.distance, climb.elapsed, climb.stamina, climb.slips])
	check(climb.state == "summit", "Base stats complete seed%d %s without meta upgrades" % [run_seed, weather])
