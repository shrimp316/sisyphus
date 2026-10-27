extends SceneTree

const DT: float = 1.0 / 120.0
var controller: Script
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func fixture(degrees: float = 32.0, version: int = 6) -> Variant:
	var world := MountainManager.new(42, false, version)
	world.weather_id = "clear"
	for chunk: Dictionary in world.chunks:
		chunk.start_angle = degrees
		chunk.end_angle = degrees
		chunk.surface_type = "STONE"
		chunk.ledge_offsets = []
		chunk.wet_ranges = []
	world._build_curve()
	var sim: Variant = controller.new(world)
	sim.distance = 20.0
	sim.peak = 20.0
	sim.stamina = 80.0
	return sim

func equivalent(left: Variant, right: Variant) -> bool:
	if (left is float or left is int) and (right is float or right is int):
		return absf(float(left) - float(right)) < 0.0000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not equivalent(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in range(left.size()):
			if not equivalent(left[index], right[index]):
				return false
		return true
	return left == right

func verify_gravity_and_inertia(version: int) -> void:
	var tag := "v%d " % version
	var flat: Variant = fixture(0.0, version)
	var gentle: Variant = fixture(12.0, version)
	var steep: Variant = fixture(32.0, version)
	for sim: Variant in [flat, gentle, steep]:
		sim.advance(0.5, false, false, false)
	check(flat.velocity == 0.0 and flat.distance == 20.0, tag + "an unattended stationary stone remains still on flat ground")
	check(steep.velocity < gentle.velocity and gentle.velocity < 0.0 and steep.distance < gentle.distance, tag + "steeper ground rolls an unattended stone farther and faster downhill")
	var rolling: Variant = fixture(32.0, version)
	rolling.velocity = -0.6
	rolling.advance(0.3, false, false, false)
	check(rolling.velocity < -0.6, tag + "downhill movement continues accelerating under gravity")
	var uphill: Variant = fixture(32.0, version)
	uphill.velocity = 0.6
	uphill.advance(DT, false, false, false)
	check(uphill.velocity > 0.0 and uphill.velocity < 0.6, tag + "releasing push first slows uphill momentum without snapping direction")
	var pushing: Variant = fixture(32.0, version)
	var bracing: Variant = fixture(32.0, version)
	for sim: Variant in [pushing, bracing]:
		sim.velocity = -1.5
	pushing.advance(DT, true, true, false)
	check(pushing.velocity < 0.0 and absf(pushing.velocity + 1.5) < 0.1, tag + "pressing Shift push during rollback cannot instantly reverse the stone")
	pushing.advance(0.4 - DT, true, true, false)
	bracing.advance(0.4, true, true, true)
	check(pushing.velocity < -0.5 and bracing.velocity > pushing.velocity and bracing.velocity <= 0.0, tag + "Space brakes a rolling stone more effectively than forcing it uphill")
	var forward: Variant = fixture(32.0, version)
	var reverse: Variant = fixture(32.0, version)
	forward.velocity = 0.3
	reverse.velocity = -2.0
	forward.advance(DT, true, true, false)
	reverse.advance(DT, true, true, false)
	check(reverse.push_force < forward.push_force * 0.7, tag + "established rollback visibly weakens transmitted pushing force")
	var gravity_samples: Array[float] = []
	for command: Array in [[false, false, false], [true, true, false], [false, false, true]]:
		var sim: Variant = fixture(32.0, version)
		sim.velocity = -0.5
		sim.advance(DT, command[0], command[1], command[2])
		gravity_samples.append(sim.gravity_force)
	check(gravity_samples[0] > 0.0 and is_equal_approx(gravity_samples[0], gravity_samples[1]) and is_equal_approx(gravity_samples[0], gravity_samples[2]), tag + "gravity remains active and unchanged under rest, push and brace")

func verify_slip_penalty(version: int) -> void:
	var tag := "v%d " % version
	var sim: Variant = fixture(32.0, version)
	sim.velocity = 0.8
	sim.slip = 99.999
	sim.advance(DT, true, true, false)
	check(sim.slips == 1 and sim.velocity < -0.5 and sim.action == "slip" and sim.push_force == 0.0, tag + "new Slip immediately loses uphill momentum and cancels thrust")
	check(sim.stamina <= 75.0 and sim.stamina > 0.0 and is_equal_approx(sim.slip_remaining, 0.7), tag + "Slip applies a meaningful one-time stamina loss and retains the 0.7s lock")
	var previous_velocity: float = sim.velocity
	var post_hit_stamina: float = sim.stamina
	sim.advance(DT, true, true, false)
	check(sim.slips == 1 and absf(sim.velocity - previous_velocity) < 0.05 and sim.stamina == post_hit_stamina and sim.push_force == 0.0, tag + "held input does not repeat the Slip impulse or stamina penalty")
	var locked := true
	var remaining_frames: int = 0
	while sim.slip_remaining > 0.0 and remaining_frames < 100:
		sim.advance(DT, true, true, false)
		locked = locked and sim.push_force == 0.0 and sim.slips == 1
		remaining_frames += 1
	check(locked and sim.slip_remaining == 0.0 and remaining_frames >= 82 and remaining_frames <= 84, tag + "Slip blocks held push through its full remaining lock without retriggering")
	sim.advance(DT, true, true, false)
	check(sim.push_force > 0.0 and sim.action == "exert", tag + "held input resumes normally only after Slip expiry")
	var braced: Variant = fixture(32.0, version)
	var free: Variant = fixture(32.0, version)
	for current: Variant in [braced, free]:
		current.velocity = -0.8
		current.slip_remaining = 0.6
	braced.advance(0.15, true, true, true)
	free.advance(0.15, false, false, false)
	check(braced.velocity > free.velocity and braced.action == "brace" and braced.push_force == 0.0 and braced.stamina < 80.0, tag + "Space retains priority and actively brakes during Slip")
	var exhausted: Variant = fixture(32.0, version)
	exhausted.velocity = 0.8
	exhausted.stamina = 5.0
	exhausted.slip = 99.999
	exhausted.advance(DT, true, true, false)
	check(exhausted.slips == 1 and exhausted.stamina == 0.0, tag + "Slip cost can exhaust a low-stamina climber without going negative")
	var passive: Variant = controller.new(exhausted.mountain)
	passive.restore(exhausted.snapshot())
	exhausted.advance(DT, true, true, true)
	passive.advance(DT, false, false, false)
	check(is_equal_approx(exhausted.velocity, passive.velocity) and exhausted.action != "brace" and exhausted.push_force == 0.0 and exhausted.stamina == 0.0, tag + "exhaustion still denies free braking or thrust during Slip")

func verify_runaway(version: int) -> void:
	var tag := "v%d " % version
	var near: Variant = fixture(32.0, version)
	near.velocity = -3.49
	near.slip = 99.999
	near.advance(DT, true, true, false)
	check(near.slips == 1 and near.state == "climbing" and near.velocity > -4.0, tag + "a Slip impulse near the limit does not immediately manufacture runaway")
	var faster: Variant = fixture(32.0, version)
	faster.velocity = -3.9
	faster.slip = 99.999
	faster.advance(DT, true, true, false)
	check(faster.velocity < -3.9, tag + "the capped Slip impulse cannot improve an already faster rollback")
	var boundary: Variant = fixture(32.0, version)
	boundary.velocity = -3.999
	boundary.advance(DT, false, false, false)
	check(boundary.state == "runaway", tag + "ordinary gravity can still cross the runaway boundary")
	for speed: float in [-4.0, -4.1]:
		var lost: Variant = fixture(32.0, version)
		lost.velocity = speed
		lost.slip_remaining = 0.6
		lost.advance(DT, true, true, true)
		check(lost.state == "runaway", tag + "Space cannot rescue already runaway speed %.1f" % speed)

func verify_save_and_timing(version: int) -> void:
	var tag := "v%d " % version
	var original: Variant = fixture(32.0, version)
	original.velocity = 0.8
	original.slip = 99.999
	original.advance(DT + 0.003, true, true, false)
	var restored_world := MountainManager.from_snapshot(JSON.parse_string(JSON.stringify(original.mountain.snapshot())))
	var clone: Variant = controller.new(restored_world)
	clone.restore(JSON.parse_string(JSON.stringify(original.snapshot())))
	for frame: int in range(90):
		original.advance(0.013, true, true, frame > 35)
		clone.advance(0.013, true, true, frame > 35)
	check(equivalent(original.snapshot(), clone.snapshot()), tag + "saving just after Slip cannot duplicate its penalty on restored fractional steps")
	var slow: Variant = fixture(32.0, version)
	var fast: Variant = fixture(32.0, version)
	for sim: Variant in [slow, fast]:
		sim.velocity = 0.8
		sim.slip = 99.999
	for phase: int in range(3):
		for frame: int in range(30):
			slow.advance(1.0 / 30.0, true, true, phase == 1)
		for frame: int in range(144):
			fast.advance(1.0 / 144.0, true, true, phase == 1)
	check(equivalent(slow.snapshot(), fast.snapshot()), tag + "30 and144 FPS agree through Slip impulse, lock, Space and resumed pushing")

func verify_generation_six() -> void:
	var steeper := true
	var stable := true
	var layout := true
	var limits := true
	var preserves := true
	var draw_matches := true
	var seen_rain := false
	for seed_value: int in range(1, 49):
		var world := MountainManager.new(seed_value)
		var prior := MountainManager.new(seed_value, false, 5)
		steeper = steeper and world.sample(1000.0).y < prior.sample(1000.0).y
		stable = stable and world.snapshot() == MountainManager.new(seed_value, false, 6).snapshot()
		layout = layout and world.generation_version == 6 and world.total_length == 1000.0 and world.rest_points.size() == 10
		preserves = preserves and world.weather_id == prior.weather_id
		seen_rain = seen_rain or world.weather_id == "rain"
		for index: int in range(world.chunks.size()):
			var chunk: Dictionary = world.chunks[index]
			var angle: float = float(chunk.start_angle)
			var start: float = index * 50.0
			layout = layout and is_equal_approx(float(chunk.climb_length), 42.0) and world.is_shelf(start + 46.0)
			preserves = preserves and chunk.id == prior.chunks[index].id and chunk.surface_type == prior.chunks[index].surface_type
			limits = limits and angle >= 8.0 and angle <= 36.0
			if str(chunk.surface_type) == "WET_STONE":
				limits = limits and angle <= (20.0 if world.weather_id == "rain" else 22.0)
			elif world.weather_id == "rain" and str(chunk.surface_type) == "STONE":
				for interval: Variant in chunk.get("wet_ranges", []):
					if float(interval[0]) < 42.0:
						limits = limits and angle <= 22.0
			var direction: Vector2 = world.sample(start + 21.0) - world.sample(start + 20.0)
			draw_matches = draw_matches and absf(-direction.angle() - world.angle_at(start + 20.0)) < 0.001
	check(steeper, "48 generation6 seeds gain more summit elevation than the same generation5 seed")
	check(stable and preserves, "generation6 is deterministic and keeps prior authored chunk order, materials and weather")
	check(layout, "generation6 preserves1000m route,42m climbs,8m shelves and10 spaced supports")
	check(limits and seen_rain, "generation6 dry and rainy slopes respect material-specific recoverable ceilings")
	check(draw_matches, "generation6 rendered slopes agree with physical inclines")
	for version: int in range(1, 7):
		var world := MountainManager.new(42, version == 1, version)
		var restored := MountainManager.from_snapshot(JSON.parse_string(JSON.stringify(world.snapshot())))
		check(restored != null and equivalent(world.snapshot(), restored.snapshot()), "generation%d world snapshots retain their own geometry on reload" % version)

func verify_forced_weather_generation() -> void:
	for weather: String in ["clear", "rain"]:
		var weather_applied := true
		var deterministic := true
		var same_order := true
		var caps := true
		var matching_natural := true
		var opposite_weather_changes_geometry := false
		for seed_value: int in range(1, 17):
			var natural := MountainManager.new(seed_value)
			var forced := MountainManager.new(seed_value, false, MountainManager.CURRENT_GENERATION, weather)
			var repeat := MountainManager.new(seed_value, false, MountainManager.CURRENT_GENERATION, weather)
			weather_applied = weather_applied and forced.weather_id == weather
			deterministic = deterministic and forced.snapshot() == repeat.snapshot()
			if natural.weather_id == weather:
				matching_natural = matching_natural and natural.snapshot() == forced.snapshot()
			else:
				opposite_weather_changes_geometry = opposite_weather_changes_geometry or natural.chunks != forced.chunks
			for index: int in range(forced.chunks.size()):
				var chunk: Dictionary = forced.chunks[index]
				var angle: float = float(chunk.start_angle)
				same_order = same_order and chunk.id == natural.chunks[index].id and chunk.surface_type == natural.chunks[index].surface_type
				caps = caps and angle >= 8.0 and angle <= 36.0
				if str(chunk.surface_type) == "WET_STONE":
					caps = caps and angle <= (20.0 if weather == "rain" else 22.0)
				elif weather == "rain" and str(chunk.surface_type) == "STONE":
					for interval: Variant in chunk.get("wet_ranges", []):
						if float(interval[0]) < 42.0:
							caps = caps and angle <= 22.0
		check(weather_applied, "explicit%s weather is selected for all16 seeds" % weather)
		check(deterministic, "explicit%s weather reproduces identical geometry for the same seed" % weather)
		check(same_order, "explicit%s weather does not reroll authored chunk order or material" % weather)
		check(caps, "explicit%s weather constrains wet-stone and rainy exposed-rock slopes before construction" % weather)
		check(matching_natural, "forcing already selected%s weather preserves the entire natural world" % weather)
		check(opposite_weather_changes_geometry, "switching to%s adjusts geometry where weather-specific caps differ" % weather)

func run() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	controller = load("res://.tools/physics-balance-baseline.gd" if baseline else "res://scripts/boulder_controller.gd")
	for version: int in [3, 4, 5, 6]:
		verify_gravity_and_inertia(version)
		verify_slip_penalty(version)
		verify_runaway(version)
		verify_save_and_timing(version)
	verify_generation_six()
	verify_forced_weather_generation()
	print("PHYSICS BALANCE%s: %d checks, %d failures" % [" BASELINE" if baseline else "", checks, failures])
	quit(1 if failures else 0)
