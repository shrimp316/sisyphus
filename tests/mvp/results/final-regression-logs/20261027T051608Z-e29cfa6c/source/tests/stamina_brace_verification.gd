extends SceneTree

# --baseline uses the pre-fix controller saved from git HEAD under .tools.
var controller: Script
var checks: int = 0
var failures: int = 0
const DT: float = 1.0 / 120.0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func fixture(version: int, shelf: bool = false) -> Variant:
	var world := MountainManager.new(42, version == 1, version)
	world.weather_id = "clear"
	for chunk: Dictionary in world.chunks:
		chunk.start_angle = 20.0
		chunk.end_angle = 20.0
		chunk.surface_type = "STONE"
		chunk.ledge_offsets = []
		chunk.wet_ranges = []
	world._build_curve()
	world.ledges.clear()
	world.rest_points.clear()
	var sim: Variant = controller.new(world)
	sim.distance = 46.0 if shelf else 20.0
	sim.peak = sim.distance
	return sim

func equal_snapshot(left: Dictionary, right: Dictionary) -> bool:
	for key: String in left:
		if not right.has(key):
			return false
		if left[key] is float or left[key] is int:
			if absf(float(left[key]) - float(right[key])) > 0.0000001:
				return false
		elif left[key] != right[key]:
			return false
	return true

func verify_exhaustion(version: int) -> void:
	var label := "v%d " % version
	for strong: bool in [false, true]:
		var exhausted: Variant = fixture(version, true)
		exhausted.stamina = 0.0
		var stable := true
		for frame: int in range(960):
			exhausted.advance(DT, true, strong, false)
			stable = stable and exhausted.push_force == 0.0 and exhausted.stamina == 0.0 and exhausted.velocity == 0.0
		check(stable and exhausted.distance == 46.0, label + "zero stamina held %s cannot push or recover-pulse for eight seconds" % ("exert" if strong else "push"))
		exhausted.advance(0.5, false, false, false)
		check(exhausted.stamina > 0.0, label + "release exhausted input allows rest recovery")
		exhausted.advance(DT, true, strong, false)
		check(exhausted.push_force > 0.0, label + "recovered stamina permits pushing again")
		var depleting: Variant = fixture(version, true)
		depleting.stamina = 0.0001
		depleting.advance(DT, true, strong, false)
		check(depleting.stamina == 0.0, label + "small positive stamina can deplete while pushing")
		var stays_empty := true
		for frame: int in range(960):
			depleting.advance(DT, true, strong, false)
			stays_empty = stays_empty and depleting.stamina == 0.0 and depleting.push_force == 0.0
		check(stays_empty, label + "held input after depletion never replenishes or pulses thrust")
	var upgraded: Variant = fixture(version, true)
	upgraded.apply_progression({"strength": 10, "endurance": 10, "recovery": 10})
	upgraded.stamina = 0.0
	upgraded.advance(1.0, true, true, false)
	check(is_equal_approx(upgraded.max_stamina, 120.0) and upgraded.stamina_multiplier() == 0.0 and upgraded.push_force == 0.0 and upgraded.stamina == 0.0, label + "maximum progression bonuses do not bypass exhaustion")
	var rolling: Variant = fixture(version, true)
	rolling.stamina = 0.0
	rolling.velocity = 0.8
	rolling.advance(DT, true, true, false)
	check(rolling.push_force == 0.0 and rolling.velocity > 0.0 and rolling.velocity < 0.8 and rolling.distance > 46.0, label + "exhaustion preserves existing momentum and passive resistance")
	var downhill: Variant = fixture(version)
	downhill.stamina = 0.0
	downhill.advance(0.1, true, true, false)
	check(downhill.push_force == 0.0 and downhill.velocity < 0.0 and downhill.distance < 20.0, label + "exhaustion still allows gravity to roll the stone downhill")

func verify_slip_brace(version: int) -> void:
	var label := "v%d " % version
	var held: Variant = fixture(version)
	var released: Variant = fixture(version)
	var brace_only: Variant = fixture(version)
	for sim: Variant in [held, released, brace_only]:
		sim.velocity = -0.8
		sim.stamina = 80.0
		sim.slip = 50.0
		sim.slip_remaining = 0.6
	held.advance(0.1, true, true, true)
	released.advance(0.1, false, false, false)
	brace_only.advance(0.1, false, false, true)
	check(equal_snapshot(held.snapshot(), brace_only.snapshot()) and held.action == brace_only.action and held.push_force == brace_only.push_force, label + "Space plus D and Shift is identical to Space alone including slip recovery")
	check(held.action == "brace" and held.push_force == 0.0 and held.stamina < 80.0, label + "Space wins over D and Shift during slip and consumes stamina")
	check(held.velocity > released.velocity and held.distance > released.distance, label + "slipping brace actively slows rollback compared with released controls")
	check(is_equal_approx(held.slip_remaining, 0.5) and is_equal_approx(held.slip_remaining, released.slip_remaining), label + "bracing does not cancel or freeze slip duration")
	var stand: Variant = fixture(version)
	stand.slip_remaining = 0.6
	var never_uphill := true
	var cost := true
	for frame: int in range(360):
		var previous_stamina: float = stand.stamina
		stand.advance(DT, true, true, true)
		never_uphill = never_uphill and stand.velocity <= 0.0 and stand.push_force == 0.0 and stand.distance <= 20.0
		cost = cost and stand.stamina < previous_stamina
	check(never_uphill and stand.distance > 19.9 and stand.slip_remaining == 0.0, label + "stationary bracing holds through slip expiry without generating uphill propulsion")
	check(cost and stand.action == "brace", label + "held stance keeps draining stamina after stopping")
	var empty: Variant = fixture(version)
	var passive: Variant = fixture(version)
	for sim: Variant in [empty, passive]:
		sim.stamina = 0.0
		sim.velocity = -0.8
		sim.slip_remaining = 0.6
	empty.advance(DT, true, true, true)
	passive.advance(DT, false, false, false)
	check(is_equal_approx(empty.velocity, passive.velocity) and empty.action != "brace" and empty.stamina == 0.0, label + "zero stamina cannot grant free braking during slip")
	var last_energy: Variant = fixture(version)
	last_energy.stamina = 0.0001
	last_energy.slip_remaining = 0.6
	last_energy.velocity = -0.2
	last_energy.advance(DT, true, true, true)
	last_energy.advance(DT, true, true, true)
	check(last_energy.stamina == 0.0 and last_energy.action != "brace" and last_energy.push_force == 0.0, label + "brace stops consuming unavailable effort after depletion")
	var lost: Variant = fixture(version)
	lost.velocity = -4.1
	lost.slip_remaining = 0.6
	lost.advance(DT, true, true, true)
	check(lost.state == "runaway", label + "brace cannot rescue an already runaway stone")

func verify_slip_push_lock(version: int) -> void:
	var label := "v%d " % version
	var triggering: Variant = fixture(version)
	triggering.slip = 99.999
	triggering.velocity = 0.8
	triggering.advance(DT, true, true, false)
	check(triggering.slips == 1 and is_equal_approx(triggering.slip_remaining, 0.7 if version >= 3 else 1.0), label + "triggered slip preserves the existing generation-specific duration")
	for strong: bool in [false, true]:
		var locked: Variant = fixture(version)
		locked.slip_remaining = 0.6
		locked.velocity = -0.2
		var blocked := true
		var frames: int = 0
		while locked.slip_remaining > 0.0 and frames < 100:
			locked.advance(DT, true, strong, false)
			blocked = blocked and locked.push_force == 0.0 and locked.action == "slip"
			frames += 1
		check(blocked and frames >= 72 and frames <= 73 and locked.slip_remaining == 0.0, label + "held %s supplies no thrust throughout slip including expiry substep" % ("Shift push" if strong else "push"))
		locked.advance(DT, true, strong, false)
		check(locked.push_force > 0.0 and locked.action == ("exert" if strong else "push"), label + "held %s resumes normally after slip expires" % ("Shift push" if strong else "push"))
	var fine: Variant = fixture(version)
	var coarse: Variant = fixture(version)
	for sim: Variant in [fine, coarse]:
		sim.slip_remaining = 0.6
		sim.velocity = -0.2
	for frame: int in range(30):
		coarse.advance(1.0 / 30.0, true, true, false)
	for frame: int in range(144):
		fine.advance(1.0 / 144.0, true, true, false)
	check(equal_snapshot(fine.snapshot(), coarse.snapshot()) and fine.push_force > 0.0 and coarse.push_force > 0.0, label + "slip lock and automatic held-input resumption agree at 30 and 144 FPS")

func verify_saves_and_timing(version: int) -> void:
	var label := "v%d " % version
	for empty: bool in [false, true]:
		var original: Variant = fixture(version)
		original.stamina = 0.0 if empty else 80.0
		original.velocity = -0.3
		original.slip_remaining = 0.6
		original.advance(0.003, true, true, true)
		var world := MountainManager.from_snapshot(JSON.parse_string(JSON.stringify(original.mountain.snapshot())))
		var restored: Variant = controller.new(world)
		restored.restore(JSON.parse_string(JSON.stringify(original.snapshot())))
		for frame: int in range(120):
			original.advance(0.013, true, true, true)
			restored.advance(0.013, true, true, true)
		check(equal_snapshot(original.snapshot(), restored.snapshot()), label + "saved %s slip resumes identically with fractional simulation steps" % ("exhausted" if empty else "energized"))
	var slow: Variant = fixture(version)
	var fast: Variant = fixture(version)
	for sim: Variant in [slow, fast]:
		sim.stamina = 0.3
		sim.velocity = -0.3
		sim.slip_remaining = 0.6
	for phase: int in range(4):
		for frame: int in range(30):
			slow.advance(1.0 / 30.0, phase != 2, phase != 2, phase == 0 or phase == 3)
		for frame: int in range(144):
			fast.advance(1.0 / 144.0, phase != 2, phase != 2, phase == 0 or phase == 3)
	check(equal_snapshot(slow.snapshot(), fast.snapshot()), label + "30 and 144 FPS agree across slipping brace, exhausted push, rest and brace")

func run() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var slip_baseline := "--slip-baseline" in OS.get_cmdline_user_args()
	var path := "res://scripts/boulder_controller.gd"
	if baseline:
		path = "res://.tools/stamina-brace-baseline.gd"
	elif slip_baseline:
		path = "res://.tools/slip-hold-baseline.gd"
	controller = load(path)
	for version: int in [1, 2, 3, 4]:
		verify_exhaustion(version)
		verify_slip_brace(version)
		verify_slip_push_lock(version)
		verify_saves_and_timing(version)
	print("Stamina/brace%s: %d checks, %d failures" % [" BASELINE" if baseline or slip_baseline else "", checks, failures])
	quit(1 if failures > 0 else 0)
