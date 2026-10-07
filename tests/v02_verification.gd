extends SceneTree

var failures: int = 0
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failures += 1

func approximately_matches(actual: Dictionary, expected: Dictionary) -> bool:
	for key: String in expected:
		if not actual.has(key): return false
		if expected[key] is float or expected[key] is int:
			if absf(float(actual[key]) - float(expected[key])) > 0.0000001: return false
		elif actual[key] != expected[key]:
			return false
	return true

func verify_legacy() -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/pre_v02_legacy.json"))
	var count: int = 0
	var exact: bool = true
	for fixture: Dictionary in fixtures:
		var terrain := MountainManager.from_snapshot(fixture.world)
		if terrain == null:
			exact = false
			continue
		var sim := BoulderController.new(terrain)
		sim.restore(fixture.initial)
		for step: Dictionary in fixture.steps:
			var input: Dictionary = step.command
			sim.advance(float(input.duration), bool(input.push), bool(input.exert), bool(input.brace))
			exact = exact and approximately_matches(sim.snapshot(), step.expected)
			count += 1
	check(exact and count == 30, "30 v1/v2 continuation states match actual pre-v0.2 golden recordings")

func fixture(speed: float, exert: bool = false, distance_value: float = 20.0) -> BoulderController:
	var sim := BoulderController.new(MountainManager.debug_course())
	sim.distance = distance_value
	sim.velocity = speed
	sim.stamina = 88.0
	sim.slip = 50.0
	sim.advance(BoulderController.FIXED_DT, true, exert, false)
	return sim

func verify_mechanics() -> void:
	var dt: float = BoulderController.FIXED_DT
	var sweet := fixture(0.8)
	var plain := fixture(1.3)
	check(is_equal_approx(sweet.push_force / plain.push_force, 1.1) and is_equal_approx((88.0 - sweet.stamina) / (88.0 - plain.stamina), 0.8), "sweet speed gives10percent force and20percent stamina efficiency")
	check(absf((sweet.slip - 50.0 + 4.0 * dt) / (plain.slip - 50.0 + 4.0 * dt) - 0.9) < 0.00001, "sweet speed reduces gross slip gain10percent")
	var fast := fixture(1.6)
	check(is_equal_approx(fast.push_force / plain.push_force, 0.9) and absf((fast.slip - 50.0 + 4.0 * dt) / (plain.slip - 50.0 + 4.0 * dt) - 1.4) < 0.00001, "highspeed reduces control and increases gross slip40percent")
	var stopped := fixture(0.0)
	check(absf((plain.push_force - stopped.acceleration) / (plain.push_force - plain.acceleration) - 1.25) < 0.00001, "starting fromrest needs25percent greater opposing-force threshold")
	var zero := BoulderController.new(MountainManager.debug_course())
	zero.stamina = 0.0
	zero.distance = 2.0
	zero.advance(0.1, true, false, false)
	check(zero.velocity > 0.0 and zero.stamina == 0.0 and zero.stamina_multiplier() == 0.45, "zero stamina still allows reduced pushing")
	var world := MountainManager.debug_course()
	world.chunks[1].surface_type = "MUD"
	world._build_curve()
	var slow := BoulderController.new(world)
	var moving := BoulderController.new(world)
	slow.distance = 20.0
	moving.distance = 20.0
	slow.velocity = 0.1
	moving.velocity = 0.8
	slow.advance(dt, true, false, false)
	moving.advance(dt, true, false, false)
	check(slow.surface_resistance > moving.surface_resistance, "mud resistance increases atlow speed")
	world = MountainManager.debug_course()
	var caught := BoulderController.new(world)
	caught.distance = world.rest_points[0] + 0.01
	caught.velocity = -2.0
	caught.advance(dt, false, false, false)
	check(caught.state == "climbing" and caught.velocity == 0.0 and caught.partial_falls == 1 and is_equal_approx(caught.distance, world.rest_points[0]), "groove catches partialfall without ending run")
	for initial_speed: float in [-4.0, -4.1]:
		var lost := BoulderController.new(world)
		lost.distance = world.rest_points[0] + 0.01
		lost.velocity = initial_speed
		lost.advance(dt, false, false, true)
		check(lost.state == "runaway" and lost.partial_falls == 0, "velocity%.1f cannot be rescued bybrace or groove" % initial_speed)
	world.rest_points = [20.0]
	var crossing := BoulderController.new(world)
	crossing.distance = 20.01
	crossing.velocity = -3.999
	crossing.advance(dt, false, false, false)
	check(crossing.state == "runaway" and crossing.partial_falls == 0, "within-step runaway boundary takes precedence over crossedgroove")
	world = MountainManager.debug_course()
	var ledge: Dictionary = world.ledges[0]
	var obstacle := BoulderController.new(world)
	obstacle.distance = float(ledge.distance) - 0.001
	obstacle.velocity = 0.8
	obstacle.advance(dt, true, false, false)
	check(obstacle.ledge_blocked and obstacle.distance < float(ledge.distance), "weak input fails ledge crossing")
	obstacle.distance = float(ledge.distance) - 0.001
	obstacle.velocity = 0.8
	obstacle.advance(dt, true, true, false)
	check(obstacle.cleared_ledges.has(ledge.id) and obstacle.distance > float(ledge.distance), "timed strongpush crosses ledge")
	obstacle.advance(0.003, true, false, false)
	var clone := BoulderController.new(MountainManager.from_snapshot(JSON.parse_string(JSON.stringify(world.snapshot()))))
	clone.restore(JSON.parse_string(JSON.stringify(obstacle.snapshot())))
	check(clone.cleared_ledges.has(ledge.id) and clone.mountain.rest_points == world.rest_points and clone.mountain.ledges == world.ledges, "v3 JSON roundtrip preserves ledgeclear and groove definitions")
	for i in range(100):
		obstacle.advance(0.013, true, false, false)
		clone.advance(0.013, true, false, false)
	check(approximately_matches(clone.snapshot(), obstacle.snapshot()), "v3 restored fractional-step state continues identically")
	clone.distance = float(ledge.distance) - 0.8
	clone.velocity = -0.1
	clone.advance(dt, false, false, false)
	check(not clone.cleared_ledges.has(ledge.id), "retreat rearms previously clearedledge")
	clone.distance = float(ledge.distance) - 0.001
	clone.velocity = 0.8
	clone.advance(dt, true, false, false)
	check(clone.ledge_blocked, "reapproaching ledge afterretreat requires strength again")

func verify_generation() -> void:
	var valid: bool = true
	for seed_value in range(1, 97):
		var world := MountainManager.new(seed_value)
		var previous_id: String = ""
		var previous_surface: String = ""
		var same_surface: int = 0
		var hard_streak: int = 0
		for chunk: Dictionary in world.chunks:
			valid = valid and str(chunk.id) != previous_id
			same_surface = same_surface + 1 if previous_surface == str(chunk.surface_type) else 1
			hard_streak = hard_streak + 1 if int(chunk.difficulty) >= 4 else 0
			valid = valid and same_surface < 4 and hard_streak < 3
			previous_id = str(chunk.id)
			previous_surface = str(chunk.surface_type)
		var previous_rest: float = 0.0
		for point: float in world.rest_points:
			valid = valid and point - previous_rest <= 150.0
			previous_rest = point
		valid = valid and world.total_length - previous_rest <= 150.0
	check(valid, "96v3seeds obey chunk/surface/difficulty/restgap constraints")
	var rain := MountainManager.new(42)
	rain.weather_id = "rain"
	var wet_count: int = 0
	for meter in range(int(rain.total_length)):
		if rain.wet_at(float(meter)): wet_count += 1
	check(wet_count > 0 and wet_count < int(rain.total_length), "rain wetness islocalized ratherthan mountainwide")

func traverse(world: MountainManager, strong_only: bool = false) -> Dictionary:
	var sim := BoulderController.new(world)
	var rested: Dictionary = {}
	var max_slip: float = 0.0
	var min_stamina: float = 100.0
	for frame in range(120 * (300 if strong_only else 1600)):
		var segment: Dictionary = world.segment_at(sim.distance)
		var shelf: bool = world.is_shelf(sim.distance)
		var rest_key: String = str(segment.start)
		if strong_only:
			sim.advance(1.0 / 120.0, true, true, false)
		else:
			var resting: bool = shelf and not rested.has(rest_key)
			if resting and sim.stamina >= 99.99:
				rested[rest_key] = true
				resting = false
			var push: bool = not resting and sim.velocity < 1.10
			var normal_force: float = BoulderController.BASE_PUSH * sim.stamina_multiplier() * world.grip_at(sim.distance) * (1.1 if sim.velocity >= 0.45 and sim.velocity <= 1.2 else 1.0)
			var opposition: float = BoulderController.GRAVITY * sin(world.angle_at(sim.distance)) + world.resistance_at(sim.distance)
			var exert: bool = normal_force < opposition + 0.12
			for ledge: Dictionary in world.ledges:
				if float(ledge.distance) >= sim.distance and float(ledge.distance) - sim.distance < 1.0 and not sim.cleared_ledges.has(ledge.id):
					exert = true
			if sim.velocity < -0.05:
				sim.advance(1.0 / 120.0, false, false, true)
			else:
				sim.advance(1.0 / 120.0, push, exert and push, false)
		max_slip = maxf(max_slip, sim.slip)
		min_stamina = minf(min_stamina, sim.stamina)
		if sim.state != "climbing": break
	return {"state":sim.state,"elapsed":sim.elapsed,"distance":sim.distance,"peak":sim.peak,"slips":sim.slips,"partial_falls":sim.partial_falls,"max_slip":max_slip,"min_stamina":min_stamina}

func verify_traversal() -> void:
	var controlled: Dictionary = traverse(MountainManager.debug_course())
	print("DEBUG CONTROLLED " + JSON.stringify(controlled))
	check(controlled.state == "summit", "base-stat controlled strategy can complete debugcourse")
	var held: Dictionary = traverse(MountainManager.debug_course(), true)
	print("DEBUG ALLSHIFT " + JSON.stringify(held))
	check(float(held.max_slip) > float(controlled.max_slip) + 20.0 or int(held.slips) > int(controlled.slips) or float(held.min_stamina) < float(controlled.min_stamina) - 20.0, "holdingShift has observable slip/stamina cost versus controlledpace")
	for seed_value: int in ([42] if "--quick" in OS.get_cmdline_user_args() else [1, 42, 1547]):
		for weather: String in ["clear", "rain"]:
			var world := MountainManager.new(seed_value)
			world.weather_id = weather
			var result: Dictionary = traverse(world)
			print("NORMAL%d %s %s" % [seed_value, weather, JSON.stringify(result)])
			check(result.state == "summit", "base-stat controlled climb reaches normal summit seed%d %s" % [seed_value, weather])

func verify_disk_continuation() -> void:
	var path: String = "res://.tools/v02-continuation.json"
	if "--continuation-write" in OS.get_cmdline_user_args():
		var world := MountainManager.debug_course()
		var sim := BoulderController.new(world)
		sim.distance = float(world.ledges[0].distance) - 0.001
		sim.velocity = 0.8
		sim.advance(BoulderController.FIXED_DT, true, true, false)
		sim.advance(0.003, true, false, false)
		sim.partial_falls = 2
		var input: Dictionary = sim.snapshot()
		for i in range(75): sim.advance(0.013, true, false, false)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"world":world.snapshot(),"run":input,"expected":sim.snapshot()}))
		file.close()
		check(not input.cleared_ledges.is_empty(), "crossprocess fixture records clearedledge and fractional accumulator")
	else:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var world := MountainManager.from_snapshot(data.world)
		var sim := BoulderController.new(world)
		sim.restore(data.run)
		check(not sim.cleared_ledges.is_empty() and sim.partial_falls == 2 and world.rest_points.size() == 5, "new process restores clearedledge, partialfall count andgrooves")
		for i in range(75): sim.advance(0.013, true, false, false)
		check(approximately_matches(sim.snapshot(), data.expected), "new process continues exact saved v3physics with same subsequentinputs")

func run() -> void:
	if "--continuation-write" in OS.get_cmdline_user_args() or "--continuation-read" in OS.get_cmdline_user_args():
		verify_disk_continuation()
		print("V0.2 DISK CONTINUATION: %d checks, %d failures" % [checks, failures])
		quit(1 if failures else 0)
		return
	verify_legacy()
	verify_mechanics()
	verify_generation()
	verify_traversal()
	print("V0.2 INDEPENDENT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

