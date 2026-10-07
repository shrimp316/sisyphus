extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func sim_at(world: MountainManager, d: float, v: float = 0.0) -> BoulderController:
	var sim: BoulderController = BoulderController.new(world)
	sim.distance = d
	sim.velocity = v
	sim.stamina = 75.0
	sim.peak = d
	return sim

func run() -> void:
	var world: MountainManager = MountainManager.debug_course()
	check(world.debug_mode and world.total_length == 98.0, "Debug course has its own finite path length")
	var sweet: BoulderController = sim_at(world, 20.0, 0.8)
	var normal: BoulderController = sim_at(world, 20.0, 1.3)
	sweet.advance(BoulderController.FIXED_DT, true, false, false)
	normal.advance(BoulderController.FIXED_DT, true, false, false)
	check(is_equal_approx(sweet.push_force, normal.push_force * 1.1), "Sweet speed raises push10percent")
	check(is_equal_approx(75.0 - sweet.stamina, (75.0 - normal.stamina) * 0.8), "Sweet speed reduces stamina drain20percent")
	var start: BoulderController = sim_at(world, 20.0)
	var moving: BoulderController = sim_at(world, 20.0, 0.3)
	start.advance(BoulderController.FIXED_DT, true, false, false)
	moving.advance(BoulderController.FIXED_DT, true, false, false)
	check(start.acceleration < moving.acceleration, "Starting torque requires greater force")
	var slow: BoulderController = sim_at(world, 46.0, 1.3)
	var fast: BoulderController = sim_at(world, 46.0, 1.6)
	slow.slip = 30.0
	fast.slip = 30.0
	slow.advance(BoulderController.FIXED_DT, true, true, false)
	fast.advance(BoulderController.FIXED_DT, true, true, false)
	check(is_equal_approx(fast.slip - 30.0, (slow.slip - 30.0) * 1.4), "High speed multiplies slip gain1.4")
	check(fast.push_force < slow.push_force and fast.control_multiplier == 0.9, "High speed reduces force control")
	var exhausted: BoulderController = sim_at(world, 3.0)
	exhausted.stamina = 0.0
	exhausted.advance(BoulderController.FIXED_DT, true, false, false)
	check(exhausted.push_force > 0.0 and exhausted.velocity > 0.0, "Exhaustion retains45percent push and input control")
	for boundary: Array in [[0.0, 0], [-0.001, 1], [-0.8, 2], [-2.0, 3], [-4.0, 4]]:
		var sim: BoulderController = sim_at(world, 20.0, float(boundary[0]))
		check(sim.fall_stage() == int(boundary[1]), "Fall-stage inclusive boundary")
	var groove: float = world.rest_points[1]
	var catching: BoulderController = sim_at(world, groove + 0.005, -1.5)
	catching.advance(BoulderController.FIXED_DT, false, false, false)
	check(catching.partial_falls == 1 and catching.velocity == 0.0 and is_equal_approx(catching.distance, groove), "Backward groove crossing catches a partialfall")
	check(catching.stamina < 76.0, "Groove catch never grants instant stamina")
	var runaway: BoulderController = sim_at(world, groove + 0.005, -4.0)
	runaway.advance(BoulderController.FIXED_DT, false, false, true)
	check(runaway.state == "runaway" and runaway.partial_falls == 0, "Exact-4 runaway wins before a groove or brace")
	runaway.advance(1.5, true, true, true)
	check(runaway.runaway_elapsed > 1.49, "Runaway timer tracks minimum spectacle time")
	var slipping: BoulderController = sim_at(world, 46.0, 0.8)
	slipping.slip = 99.999
	slipping.advance(BoulderController.FIXED_DT, true, true, false)
	check(slipping.slips == 1 and is_equal_approx(slipping.slip_remaining, 0.7), "Slip starts a deterministic0.7second control loss")
	slipping.advance(BoulderController.FIXED_DT, true, true, false)
	check(slipping.push_force > 0.0 and slipping.push_force < 0.5, "Slipping retains10percent push instead of disabling control")
	var ledge: Dictionary = world.ledges[0]
	var blocked: BoulderController = sim_at(world, float(ledge.distance) - 0.002, 0.8)
	blocked.advance(BoulderController.FIXED_DT, true, false, false)
	check(blocked.ledge_blocked and blocked.distance < float(ledge.distance), "Weak push cannot cross a visible ledge")
	blocked.stamina = 100.0
	blocked.advance(0.5, true, true, false)
	check(blocked.distance > float(ledge.distance) and blocked.cleared_ledges.size() == 1, "A prepared burst clears the ledge")
	var restored: BoulderController = BoulderController.new(world)
	blocked.advance(0.002, false, false, false)
	restored.restore(JSON.parse_string(JSON.stringify(blocked.snapshot())) as Dictionary)
	check(is_equal_approx(restored.accumulator, blocked.accumulator) and restored.cleared_ledges == blocked.cleared_ledges, "Snapshot preserves frame accumulator and ledge passage")
	blocked.advance(0.033, true, false, false)
	restored.advance(0.033, true, false, false)
	check(is_equal_approx(restored.distance, blocked.distance) and is_equal_approx(restored.slip, blocked.slip), "Restored fractional frame continues identically")
	var restored_world: MountainManager = MountainManager.from_snapshot(JSON.parse_string(JSON.stringify(world.snapshot())) as Dictionary)
	check(restored_world != null and restored_world.total_length == world.total_length and restored_world.ledges == world.ledges, "Debug terrain definitions and obstacles roundtrip")
	var dry: MountainManager = MountainManager.new(42)
	dry.weather_id = "clear"
	var rain: MountainManager = MountainManager.from_snapshot(dry.snapshot())
	rain.weather_id = "rain"
	var changed: int = 0
	var unchanged: int = 0
	for distance: int in range(1000):
		if is_equal_approx(dry.grip_at(float(distance)), rain.grip_at(float(distance))):
			unchanged += 1
		else:
			changed += 1
	check(changed > 0 and unchanged > 0, "Rain affects local patches instead of the entire mountain")
	check(is_equal_approx(float(dry.surfaces.GRAVEL.resistance), 1.15) and is_equal_approx(float(dry.surfaces.WET_STONE.grip), 0.55), "v0.2 material parameters replace older values")
	print("V02 CORE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
