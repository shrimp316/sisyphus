extends "res://tests/balance/simulator.gd"

# Reproduce measured candidate timeouts without changing experiment policies.
# Run from project root with --script tests/balance/ledge_diagnostics.gd.
func run() -> void:
	var source_path: String = "res://tests/balance/results/current-pilot/results.jsonl"
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		printerr("Missing completed pilot dataset: " + source_path)
		quit(2)
		return
	var cases: Array = []
	while not source.eof_reached():
		var line: String = source.get_line()
		if line.is_empty():
			continue
		var record: Dictionary = JSON.parse_string(line)
		if str(record.get("type", "")) != "run" or str(record.get("status", "")) != "timeout" or str(record.get("policy", "")) != "regular" or int(record.get("level", -1)) != 0:
			continue
		var candidate: Dictionary = record.get("candidate", {})
		if candidate not in [{"push_scale": 0.95}, {"ledge_scale": 1.05}]:
			continue
		var trials: Array = []
		for method: String in ["held_exert", "coast_after_block", "sweet_fixture", "runup_fixture", "strength_1", "strength_2", "strength_8"]:
			var world := MountainManager.from_snapshot(record.terrain_snapshot)
			# Snapshots retain chunk/surface settings. Runtime ledge requirements
			# are reconstructed by from_snapshot and must be reapplied once.
			for ledge: Dictionary in world.ledges:
				ledge.required_push *= float(candidate.get("ledge_scale", 1.0))
			var boulder = Controller.new(world)
			apply_growth(boulder, {"strength": 0, "endurance": 0, "recovery": 0}, candidate)
			boulder.restore(record.final_state)
			var target: Dictionary = {}
			for ledge: Dictionary in world.ledges:
				if float(ledge.distance) > boulder.distance:
					target = ledge
					break
			if target.is_empty():
				printerr("No upcoming ledge for " + str(record.job_id))
				quit(2)
				return
			if method == "sweet_fixture":
				boulder.distance = float(target.distance) - 0.001
				boulder.velocity = 0.8
				boulder.stamina = boulder.max_stamina
			elif method == "runup_fixture":
				boulder.distance = float(target.distance) - 0.1
				boulder.velocity = 0.0
				boulder.stamina = boulder.max_stamina
			elif method.begins_with("strength_"):
				var rank: int = int(method.trim_prefix("strength_"))
				apply_growth(boulder, {"strength": rank, "endurance": 0, "recovery": 0}, candidate)
			var initial: Dictionary = boulder.snapshot()
			var phase: int = 0
			var trace: Array = []
			var block_count: int = 0
			var steps: int = 0
			for frame: int in range(600):
				var exert: bool = true
				if method == "coast_after_block" and phase == 1:
					exert = false
					if boulder.velocity >= 0.0:
						phase = 2
						exert = true
				var prior_velocity: float = boulder.velocity
				boulder.advance(DT, exert, exert, false)
				steps += 1
				if boulder.ledge_blocked:
					block_count += 1
					if trace.size() < 8:
						trace.append({"event": "blocked", "step": frame, "before_velocity": prior_velocity, "push_force": boulder.push_force, "required_force": BoulderController.BASE_PUSH * world.grip_at(float(target.distance)) * float(target.required_push), "distance_m": boulder.distance})
					if method == "coast_after_block" and phase == 0:
						phase = 1
				if boulder.cleared_ledges.has(str(target.id)):
					trace.append({"event": "cleared", "step": frame, "before_velocity": prior_velocity, "push_force": boulder.push_force, "distance_m": boulder.distance})
					break
			trials.append({"method": method, "is_state_fixture": method.ends_with("fixture"), "initial_state": initial, "target": target, "shelf": world.is_shelf(float(target.distance)), "grip": world.grip_at(float(target.distance)), "surface": world.surface_at(float(target.distance)).id, "cleared": boulder.cleared_ledges.has(str(target.id)), "block_events": block_count, "simulated_seconds": steps * DT, "final_state": boulder.snapshot(), "trace": trace})
		cases.append({"source_job_id": record.job_id, "seed": record.seed, "candidate": candidate, "source_record_sha256": line.sha256_text(), "original_final_state": record.final_state, "terrain_snapshot": record.terrain_snapshot, "trials": trials})
	source.close()
	if cases.size() != 6:
		printerr("Expected six completed measured timeout records, got " + str(cases.size()))
		quit(2)
		return
	var file := FileAccess.open("res://tests/balance/results/ledge-diagnostics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "source": source_path, "method": "Production physics replay of actual final states. held_exert/coast_after_block use ordinary inputs from measured states; strength trials change only existing rank. sweet/runup fixtures deliberately change initial state and demonstrate local passability, not a legal recovery from the blocked state. Failed bounded trials do not prove universal impossibility.", "cases": cases}, "\t"))
	file.close()
	print("LEDGE DIAGNOSTICS: %d recorded timeout cases, %d bounded trials" % [cases.size(), cases.size() * 7])
	quit(0)
