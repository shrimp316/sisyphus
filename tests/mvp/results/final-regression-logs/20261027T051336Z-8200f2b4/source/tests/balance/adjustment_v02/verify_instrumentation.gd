extends SceneTree

const Factory = preload("res://tests/balance/adjustment_v02/controller_factory.gd")
const Terrain = preload("res://tests/balance/adjustment_v02/terrain.gd")
var checks: int = 0
var failures: int = 0
var factory = Factory.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func equal(left: Dictionary, right: Dictionary) -> bool:
	for key: String in left:
		if typeof(left[key]) == TYPE_FLOAT:
			if absf(float(left[key]) - float(right[key])) > 0.000001:
				return false
		elif left[key] != right[key]:
			return false
	return left.size() == right.size()

func parity() -> void:
	for generation: int in [1,2,3,4,5,6]:
		for weather: String in ["clear", "rain"]:
			var good: bool = true
			for position: float in [25.0, 525.0, 742.0, 775.0]:
				var world := MountainManager.new(101, false, generation, weather)
				var original := BoulderController.new(world)
				var altered: BoulderController = factory.create(world, {})
				for sim: BoulderController in [original, altered]:
					sim.distance = position
					sim.velocity = 0.8
					sim.stamina = 19.99
					sim.slip = 99.999
				for command: Array in [[true,true,false],[true,true,true],[false,false,false],[true,false,false]]:
					for frame: int in range(24):
						original.advance(0.013, command[0], command[1], command[2])
						altered.advance(0.013, command[0], command[1], command[2])
						good = good and equal(original.snapshot(), altered.snapshot())
			check(good, "neutral generated controller matches production every observed step: generation%d %s" % [generation, weather])
	for candidate: Dictionary in [{}, {"moving_shelf_recovery_scale":0.4,"slip_gain_after500_scale":1.3,"slip_decay_after750_scale":0.75}]:
		var world := MountainManager.new(101, false, 6, "rain")
		var slow: BoulderController = factory.create(world, candidate)
		var fast: BoulderController = factory.create(world, candidate)
		for sim: BoulderController in [slow, fast]:
			sim.distance = 775.0
			sim.velocity = 0.8
			sim.slip = 99.999
		for command: Array in [[true,true,false],[false,false,true],[true,false,false],[false,false,false]]:
			for frame: int in range(30):
				slow.advance(1.0/30.0, command[0], command[1], command[2])
			for frame: int in range(144):
				fast.advance(1.0/144.0, command[0], command[1], command[2])
		check(equal(slow.snapshot(), fast.snapshot()), "30/144 FPS equivalent recorded commands, candidate " + str(candidate))

func geometry() -> void:
	for mode: String in ["B0","B1","B2","B3"]:
		var good: bool = true
		for seed_value: int in [101,202,303]:
			var baseline := MountainManager.new(seed_value)
			var world = Terrain.new(seed_value)
			world.configure_experiment({"geometry_mode":mode})
			good = good and world.total_length == 1000.0
			for meter: int in range(250):
				good = good and baseline.segment_at(meter) == world.segment_at(meter)
			for segment: Dictionary in world.segments:
				good = good and float(segment.end) > float(segment.start)
			for point: float in world.rest_points:
				good = good and world.is_shelf(point)
			for ledge: Dictionary in world.ledges:
				good = good and is_equal_approx(float(ledge.required_push), 1.6)
		check(good, mode + " preserves first250m, length1000m, real shelves and original ledge requirements")

func potential_grid() -> void:
	var world = Terrain.new(101)
	world.configure_experiment({"geometry_overrides":[{"chunk_index":15,"angle":45.0,"surface":"STONE","climb_length":50.0,"wet_ranges":[]}]})
	var c: float = 3.0 * sin(PI/4.0) - 0.2
	var good: bool = true
	var tested: int = 0
	for v: float in [-3.9,-0.1,-0.001,0.0,0.001,0.15,0.45,1.2,1.5,1.8]:
		for s: float in [0.0,0.00001,19.99,20.0,49.99,50.0,100.0]:
			for slip_value: float in [0.0,99.999]:
				for mask: int in range(8):
					var sim: BoulderController = factory.create(world, {"uphill_recovery_after_m":750.0,"uphill_recovery_scale":0.0})
					sim.distance = 775.0
					sim.velocity = v
					sim.stamina = s
					sim.slip = slip_value
					var before: float = 0.5 * pow(maxf(v,0.0),2.0)
					sim.advance(BoulderController.FIXED_DT, bool(mask & 1), bool(mask & 2), bool(mask & 4))
					var change: float = c * (sim.distance - 775.0) + 0.5 * pow(maxf(sim.velocity,0.0),2.0) - before
					var supplied: float = sim.push_force * maxf(sim.velocity,0.0) * BoulderController.FIXED_DT
					good = good and change <= supplied + 0.00000001 and sim.stamina <= s
					tested += 1
	check(good, "discrete potential and nonincreasing stamina on %d boundary/input states (supporting test, not exhaustive proof)" % tested)

func gate_assumptions() -> void:
	var good: bool = true
	var overrides: Array = []
	for index: int in range(15,18):
		overrides.append({"chunk_index":index,"angle":45.0,"surface":"STONE","climb_length":50.0 if index<17 else 23.0,"wet_ranges":[]})
	for seed_value: int in range(1001,1101):
		for weather: String in ["clear","rain"]:
			var world = Terrain.new(seed_value,false,6,weather)
			world.configure_experiment({"geometry_overrides":overrides})
			for meter: int in range(750,873):
				good = good and not world.is_shelf(meter+0.25) and str(world.surface_at(meter+0.25).id)=="STONE" and is_equal_approx(world.grip_at(meter+0.25),1.0) and is_equal_approx(rad_to_deg(world.angle_at(meter+0.25)),45.0)
			for ledge: Dictionary in world.ledges:
				good = good and not (float(ledge.distance)>=750.0 and float(ledge.distance)<873.0)
			for point: float in world.rest_points:
				good = good and not (point>=750.0 and point<873.0)
			good = good and world.is_shelf(749.0) and world.is_shelf(873.0)
	check(good,"G123 assumptions on100seeds x clear/rain: dry45degree gate, no recovery shelf/ledge/support inside, real safe shelves before and after")

func run() -> void:
	check(factory.build(), "production SHA and unique anchors permit exact scalar instrumentation")
	if failures:
		quit(1)
		return
	parity()
	geometry()
	potential_grid()
	gate_assumptions()
	print("V02 INSTRUMENTATION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
