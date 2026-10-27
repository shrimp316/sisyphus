extends "res://tests/balance/adjustment_v02/simulator.gd"

# Replay every recorded stall from an output JSONL file with exact held inputs.
# CLI: -- --input PATH.jsonl [--job JOB_ID] [--seed INTEGER]
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = ""
	var job_filter: String = ""
	var seed_filter: int = -1
	for index: int in range(args.size() - 1):
		if args[index] == "--input":
			path = args[index + 1]
		elif args[index] == "--job":
			job_filter = args[index + 1]
		elif args[index] == "--seed":
			seed_filter = int(args[index + 1])
	if not factory.build() or path.is_empty():
		quit(2)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		quit(2)
		return
	var checked: int = 0
	var failures: int = 0
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary or str(parsed.get("type", "")) != "run":
			continue
		var row: Dictionary = parsed
		if (not job_filter.is_empty() and str(row.job_id) != job_filter) or (seed_filter >= 0 and int(row.seed) != seed_filter):
			continue
		for stall: Dictionary in row.get("stall_events", []):
			var world := create_world(int(row.seed), {"generation": row.generation, "weather": row.weather})
			configure_world(world, row.candidate)
			var controller: BoulderController = factory.create(world, row.candidate)
			apply_growth(controller, row.start_ranks, row.candidate)
			if not stall.input_history.is_empty():
				controller.max_stamina = float(stall.input_history[0].stats[1])
			controller.restore(stall.replay_start_state)
			for segment: Dictionary in stall.input_history:
				controller.push_multiplier = float(segment.stats[0])
				controller.max_stamina = float(segment.stats[1])
				controller.recovery_multiplier = float(segment.stats[2])
				for step: int in range(int(segment.steps)):
					controller.advance(DT, segment.command[0], segment.command[1], segment.command[2])
			var equal: bool = snapshots_equal(controller.snapshot(), stall.replay_end_state)
			checked += 1
			failures += 0 if equal else 1
			print("STALL REPLAY %s seed%d %s" % [row.job_id, row.seed, "PASS" if equal else "FAIL"])
	file.close()
	print("STALL REPLAY: %d checked, %d failures" % [checked, failures])
	quit(1 if failures else 0)

func snapshots_equal(left: Dictionary, right: Dictionary) -> bool:
	for key: String in left:
		if typeof(left[key]) in [TYPE_FLOAT, TYPE_INT]:
			if absf(float(left[key]) - float(right[key])) > 0.0000001:
				return false
		elif left[key] != right[key]:
			return false
	return true
