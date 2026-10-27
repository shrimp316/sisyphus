extends SceneTree

const Climb = preload("res://scripts/mvp/climb_boulder.gd")
const Original = preload("res://scripts/mastery_boulder.gd")
const DT: float = 1.0 / 120.0
var checks: int = 0
var failures: Array = []
var observations: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func near(a: float, b: float) -> bool: return absf(a - b) < 0.0000001
func same(a: Dictionary, b: Dictionary) -> bool:
	for key: String in a:
		if a[key] is Dictionary:
			if not same(a[key], b[key]): return false
		elif a[key] is float or a[key] is int:
			if not near(float(a[key]), float(b[key])): return false
		elif a[key] != b[key]: return false
	return a.size() == b.size()
func terrain(angle: float = 35.0, surface: String = "STONE", shelf: bool = false) -> MountainManager:
	var world := MountainManager.new(101, false, 6, "clear")
	world.segments = [{"start":0.0,"end":1000.0,"angle":deg_to_rad(angle),"surface":surface,"shelf":shelf}]
	world.ledges.clear()
	world.rest_points.clear()
	return world
func stone(angle: float = 35.0, surface: String = "STONE", shelf: bool = false):
	var result = Climb.new(terrain(angle, surface, shelf))
	result.distance = 500.0
	result.peak = 500.0
	result.velocity = 0.8
	return result

func run() -> void:
	for seed_value: int in [101, 202, 303]:
		var world := MountainManager.new(seed_value, false, 6)
		var a = Original.new(world)
		var b = Climb.new(world)
		b.configure_difficulty({"enabled":false})
		for step: int in range(1200):
			var push: bool = step % 240 < 180
			var exert: bool = step % 120 < 30
			var brace: bool = step % 240 >= 210
			a.advance(DT, push, exert, brace)
			b.advance(DT, push, exert, brace)
		check(same(a.snapshot(), b.snapshot()), "disabled profile matches original on seed %d" % seed_value)
	var s = stone()
	check(near(s._stamina_drain_rate(1.0, false, false, false), 4.0), "normal late drain x4")
	check(near(s._stamina_drain_rate(3.0, true, false, false), 9.0), "exert drain x3")
	check(near(s._stamina_drain_rate(4.0, false, false, true), 4.0), "brace cost preserved")
	s.distance = 100.0
	check(near(s._stamina_drain_rate(1.0, false, false, false), 3.0), "first250 normal drain x3")
	check(near(s.environment_info().normal_drain_multiplier, 3.0), "HUD includes training multiplier")
	s.distance = 500.0
	var info: Dictionary = s.environment_info()
	check(info.surface_label == s.mountain.surface_at(s.distance).label and info.multiplier_scope == "environment_before_mastery", "HUD uses actual surface and explicit coefficient scope")
	s.apply_mastery_effects({"effects":{"normal_drain_reduction":0.1,"capacity_bonus":0.2}})
	check(near(s._stamina_drain_rate(1.0, false, false, false), 3.6), "mastery drain reduction applied after environment once")
	var snapshot: Dictionary = s.snapshot()
	s.configure_difficulty(s.difficulty)
	s.apply_mastery_effects({"effects":{"normal_drain_reduction":0.1,"capacity_bonus":0.2}})
	check(near(s._stamina_drain_rate(1.0, false, false, false), 3.6) and s.max_stamina == 120.0, "reconfiguration and reapplication never compound")
	check(s.stamina == snapshot.stamina, "reconfiguration does not refill stamina")
	var mud = stone(35.0, "MUD")
	var gravel = stone(35.0, "GRAVEL")
	var wet = stone(35.0, "WET_STONE")
	check(mud._stamina_drain_rate(1.0, false, false, false) > stone()._stamina_drain_rate(1.0, false, false, false), "mud costs more stamina than stone")
	check(wet._slip_gain_rate(4.0, false, true) > gravel._slip_gain_rate(4.0, false, true), "wet extra Slip coefficient exceeds gravel")
	check(gravel._slip_gain_rate(4.0, false, true) > stone()._slip_gain_rate(4.0, false, true), "gravel extra Slip coefficient exceeds stone")
	check(wet.mountain.grip_at(500.0) < stone().mountain.grip_at(500.0), "original terrain grip remains different")
	check(mud.mountain.resistance_at(500.0) > stone().mountain.resistance_at(500.0), "original terrain resistance remains different")
	s = stone()
	check(near(s._slip_decay_rate(4.0, false, true), 0.0), "normal pushing on slopes does not decay Slip")
	check(near(s._slip_decay_rate(4.0, false, false), 4.0), "release and bracing keep original decay")
	check(stone(0.0)._slip_gain_rate(4.0, false, true) == 0.0, "flat never creates Slip")
	check(stone(35.0, "STONE", true)._slip_gain_rate(4.0, false, true) == 0.0, "shelter never creates Slip")
	var gentle = stone(10.0)
	gentle.advance(DT, true, false, false)
	check(gentle.slip > 0.0, "actual normal input accumulates Slip even on gentle10degree slope")
	s.slip = 50.0
	s.advance(DT, true, false, false)
	check(s.slip > 50.0, "actual normal push increases Slip on35degree slope")
	s = stone()
	s.slip = 50.0
	s.advance(DT, false, false, false)
	check(s.slip < 50.0, "actual release decays Slip")
	s.slip = 50.0
	s.advance(DT, false, false, true)
	check(s.slip < 50.0, "actual brace decays Slip")
	s = stone()
	var first_slip_stamina: float = -1.0
	for step: int in range(120 * 60):
		s.advance(DT, true, false, false)
		if s.slips > 0:
			first_slip_stamina = s.stamina
			break
		if s.stamina == 0.0: break
	observations.normal_push = {"slips":s.slips,"stamina_at_first_slip":first_slip_stamina,"seconds":s.elapsed,"distance":s.distance,"state":s.state}
	check(s.slips > 0 and first_slip_stamina > 0.0, "held normal push alone causes actual Slip before exhaustion")
	check(near(s.slip_remaining, 0.7), "actual Slip lock still0.7seconds")
	s = stone()
	s.velocity = 0.0
	check(near(s._stamina_recovery_rate(7.0, 35.0, false), 1.4), "non-shelter stationary recovery reduced7to1.4")
	s.apply_mastery_effects({"effects":{"steep_stationary_recovery":1.5}})
	check(near(s._stamina_recovery_rate(7.0, 35.0, false), 1.5), "BRE steep recovery floor survives scaling")
	s.apply_mastery_effects({"effects":{"recovery_bonus":0.05,"stationary_recovery_bonus":0.1}})
	check(near(s._stamina_recovery_rate(7.0, 35.0, false) * s.recovery_multiplier, 1.4 * 1.15), "BRE speed bonuses applied once")
	s = stone(12.0)
	s.apply_mastery_effects({"effects":{"gentle_coast_recovery":2.0}})
	check(near(s._stamina_recovery_rate(0.0, 12.0, false), 2.0), "BRE moving recovery floor survives scaling")
	check(near(stone(0.0, "STONE", true)._stamina_recovery_rate(10.0, 0.0, true), 10.0), "shelter recovery preserved")
	var fps30 = stone()
	var fps144 = stone()
	for frame: int in range(30 * 20): fps30.advance(1.0/30.0, true, false, false)
	for frame: int in range(144 * 20): fps144.advance(1.0/144.0, true, false, false)
	check(same(fps30.snapshot(), fps144.snapshot()), "normal Slip and drains invariant at30and144FPS")
	var frozen: Dictionary = fps30.snapshot()
	fps30.advance(0.0, true, true, false)
	check(same(frozen, fps30.snapshot()), "zero simulation time freezes Slip and stamina")
	var restored = Climb.new(fps30.mountain)
	restored.restore(frozen)
	check(same(frozen, restored.snapshot()), "difficulty adds no mutable run state to restore")
	s = stone()
	s.velocity = -4.0
	s.advance(DT, false, false, true)
	check(s.state == "runaway", "brace cannot cancel unchanged runaway boundary")
	s = stone()
	s.stamina = 0.0
	s.velocity = 0.0
	s.advance(DT, true, false, false)
	check(s.stamina == 0.0, "exhausted held push cannot obtain recovery")
	var result: Dictionary = {"suite":"climb_difficulty","checks":checks,"failures":failures,"observations":observations,"profile":JSON.parse_string(FileAccess.get_file_as_string(Climb.DIFFICULTY_PATH))}
	var file := FileAccess.open("res://tests/mvp/results/climb-difficulty-unit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
