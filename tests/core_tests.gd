extends SceneTree

const Mountain = preload("res://scripts/mountain_manager.gd")
const Boulder = preload("res://scripts/boulder_controller.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _run() -> void:
	var mountain: MountainManager = Mountain.new(1, true)
	var sim: BoulderController = Boulder.new(mountain)
	sim.advance(1.0, true, false, false)
	check(sim.velocity > 0.0 and sim.distance > 0.0, "Push overcomes introductory incline")
	var a: BoulderController = Boulder.new(mountain)
	var b: BoulderController = Boulder.new(mountain)
	for index: int in range(600):
		a.advance(1.0 / 60.0, true, false, false)
	for index: int in range(300):
		b.advance(1.0 / 30.0, true, false, false)
	check(absf(a.distance - b.distance) < 0.00001 and absf(a.stamina - b.stamina) < 0.00001, "Fixed-step behavior matches at 30/60fps")
	sim = Boulder.new(mountain)
	sim.distance = 20.0
	sim.advance(1.0, false, false, false)
	check(sim.velocity < 0.0 and sim.distance < 20.0, "Gravity points downhill")
	sim.velocity = -1.0
	for index: int in range(120):
		sim.advance(1.0 / 120.0, false, false, true)
		check(sim.velocity <= 0.0, "Brace cannot propel uphill")
	check(sim.stamina < 100.0, "Sustained bracing spends stamina")
	sim = Boulder.new(mountain)
	sim.distance = 10.0
	sim.slip = 99.999
	sim.advance(1.0 / 120.0, true, true, false)
	check(sim.slip_remaining > 0.9 and sim.slips == 1, "Slip triggers deterministically at100")
	sim.advance(1.1, false, false, false)
	check(sim.slip_remaining <= 0.0, "Slip control loss ends after one second")
	sim = Boulder.new(mountain)
	sim.distance = 400.0
	sim.velocity = -4.1
	sim.advance(1.0 / 120.0, false, false, false)
	check(sim.state == "runaway", "Retreat below-4 enters runaway")
	sim.advance(20.0, true, true, true)
	check(sim.state == "result" and sim.distance == 0.0, "Runaway ignores controls and reaches run result")
	sim = Boulder.new(mountain)
	check(sim.distance == 0.0 and sim.stamina == 100.0 and sim.state == "climbing", "Fresh run resets simulation")
	a = Boulder.new(mountain)
	b = Boulder.new(mountain)
	a.advance(5.0, false, true, false)
	b.advance(5.0, false, false, false)
	check(a.snapshot() == b.snapshot(), "Shift without push has no effect")
	sim = Boulder.new(mountain)
	sim.distance = 44.0
	sim.stamina = 40.0
	sim.slip = 50.0
	sim.advance(2.0, false, false, false)
	check(sim.velocity == 0.0 and sim.stamina > 55.0 and sim.slip < 33.0, "Horizontal shelf permits stamina and slip recovery")
	var restored: BoulderController = Boulder.new(mountain)
	restored.restore(sim.snapshot())
	check(restored.snapshot() == sim.snapshot(), "Suspended-run snapshot round trip preserves state")
	print("CORE TESTS: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
