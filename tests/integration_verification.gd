extends SceneTree

var failures: int = 0

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var terrain := MountainManager.new(1, true)
	var resting := BoulderController.new(terrain)
	resting.distance = 40.0
	resting.stamina = 10.0
	resting.advance(20.0, false, false, false)
	check(is_equal_approx(resting.distance, 40.0) and resting.stamina == 100.0, "horizontal shelf holds a resting stone and fully restores stamina")
	var brake := BoulderController.new(terrain)
	brake.distance = 920.0
	brake.velocity = -2.0
	var brake_start: float = brake.distance
	for i in range(240):
		brake.advance(1.0 / 120.0, false, false, true)
		check(brake.velocity <= 0.0001, "brace never produces uphill speed") if brake.velocity > 0.0001 else null
	check(brake.distance <= brake_start and brake.state == "climbing" and brake.velocity > -0.1, "brace arrests retreat on late steep terrain")
	var coarse := BoulderController.new(terrain)
	var fine := BoulderController.new(terrain)
	for i in range(300): coarse.advance(1.0 / 30.0, true, true, false)
	for i in range(1440): fine.advance(1.0 / 144.0, true, true, false)
	check(absf(coarse.distance - fine.distance) < 0.0001 and absf(coarse.stamina - fine.stamina) < 0.0001, "30 FPS and 144 FPS produce equal simulation results")
	var climb := BoulderController.new(terrain)
	var resting_segment: int = -1
	for i in range(120 * 1800):
		var segment: Dictionary = terrain.segment_at(climb.distance)
		var index: int = int(climb.distance / 50.0)
		var shelf: bool = terrain.is_shelf(climb.distance)
		var should_rest: bool = (shelf and resting_segment != index) or (not shelf and terrain.distance_to_shelf(climb.distance) < 3.0 and climb.velocity > 0.8)
		if shelf and climb.stamina > 99.9:
			resting_segment = index
			should_rest = false
		if climb.velocity < -0.1:
			climb.advance(1.0 / 120.0, false, false, true)
		else:
			climb.advance(1.0 / 120.0, not should_rest, terrain.angle_at(climb.distance) > deg_to_rad(19.0), false)
		if climb.state != "climbing": break
	print("SUMMIT POLICY state=%s distance=%.3f peak=%.3f stamina=%.2f time=%.1f slips=%d" % [climb.state, climb.distance, climb.peak, climb.stamina, climb.elapsed, climb.slips])
	check(climb.state == "summit", "base stats can reach summit through pushing, exerting, and shelf recovery")
	var restored := BoulderController.new(terrain)
	var record: Dictionary = fine.snapshot()
	restored.restore(record)
	for i in range(120):
		fine.advance(1.0 / 120.0, true, false, false)
		restored.advance(1.0 / 120.0, true, false, false)
	check(fine.snapshot() == restored.snapshot(), "save restore continues the exact fixed-step simulation")
	print("INDEPENDENT VERIFICATION: %d failures" % failures)
	quit(1 if failures else 0)

