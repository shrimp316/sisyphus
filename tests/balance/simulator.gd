extends SceneTree

# Run: Godot --headless --path . --script tests/balance/simulator.gd --
#      --config tests/balance/pilot.json --output tests/balance/results.jsonl
# No save manager, scene, user profile, or production resource is written.
const Controller = preload("res://tests/balance/balance_controller.gd")
const DT: float = 1.0 / 120.0
var policies: Dictionary
var output: FileAccess
var emitted_runs: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var config_path: String = ""
	var output_path: String = ""
	for index: int in range(args.size() - 1):
		if args[index] == "--config":
			config_path = args[index + 1]
		elif args[index] == "--output":
			output_path = args[index + 1]
	if config_path.is_empty() or output_path.is_empty():
		printerr("Required: --config CONFIG.json --output OUTPUT.jsonl")
		quit(2)
		return
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	var policy_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(policy_path()))
	if not config is Dictionary or not config.get("jobs") is Array or not policy_data is Dictionary:
		printerr("Invalid configuration or policies JSON")
		quit(2)
		return
	policies = policy_data.policies
	# Optional policy overrides are recorded in the metadata for reproducibility.
	for key: String in config.get("policy_overrides", {}):
		if not policies.has(key):
			printerr("Unknown overridden policy: " + key)
			quit(2)
			return
		policies[key].merge(config.policy_overrides[key], true)
	for job: Dictionary in config.jobs:
		if not valid_job(job):
			quit(2)
			return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	output = FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		printerr("Cannot open output: " + output_path)
		quit(2)
		return
	var revision_output: Array = []
	OS.execute("git", ["rev-parse", "HEAD"], revision_output)
	var revision: String = str(revision_output[0]).strip_edges() if not revision_output.is_empty() else "unavailable"
	emit({"type": "metadata", "schema_version": 2, "fixed_dt": DT, "godot_version": Engine.get_version_info().string, "code_revision": revision, "config": config, "policies": policies, "growth_system": "existing Progression only: cumulative nonspend EXP grants upgrade points; each existing stat rank adds 2%", "timeout_handling": "right-censored; campaigns stop at first run timeout, never reinterpret timeout as fall", "clock_semantics": "controller elapsed includes runaway descent; excludes menus, purchase selection, retry UI and loading time", "candidate_semantics": "push_scale multiplies player push_multiplier only, not BASE_PUSH constant/ledge threshold; slip_scale multiplies material slip gain only, recovery unchanged; drain_scale overrides slope drain multiplier only", "controller": "production BoulderController inherited without copied integration"})
	var additional_metadata: Dictionary = metadata_additions()
	if not additional_metadata.is_empty():
		emit(additional_metadata)
	for job: Dictionary in config.jobs:
		for seed_variant: Variant in job.seeds:
			if str(job.get("mode", "single")) == "campaign":
				simulate_campaign(job, int(seed_variant))
			else:
				var profile: Dictionary = new_profile(job)
				emit(simulate_run(job, int(seed_variant), profile, 1, ""))
	output.close()
	print("BALANCE: %d actual simulated runs; output %s" % [emitted_runs, output_path])
	quit(0)

func valid_job(job: Dictionary) -> bool:
	if not policies.has(str(job.get("policy", ""))) or not job.get("seeds") is Array or job.seeds.is_empty():
		printerr("Job needs a known policy and nonempty seeds: " + str(job))
		return false
	if str(job.get("growth_mode", "actual")) != "actual" or str(job.get("mode", "single")) not in ["single", "campaign"]:
		printerr("Unknown growth mode or experiment mode")
		return false
	if int(job.get("level", 0)) < 0 or int(job.get("level", 0)) > 10 or float(job.get("max_run_seconds", 1800)) <= 0:
		printerr("Invalid growth level or time limit")
		return false
	if job.has("ranks"):
		if not job.ranks is Dictionary or job.ranks.size() != 3:
			printerr("ranks must contain exactly strength, endurance, recovery")
			return false
		for kind: String in Progression.KINDS:
			var rank: Variant = job.ranks.get(kind)
			if not (rank is int or rank is float) or float(rank) < 0.0 or float(rank) > 10.0 or float(rank) != floor(float(rank)):
				printerr("Each rank must be an integer from 0 to 10")
				return false
	if str(job.get("mode", "single")) == "campaign" and (int(job.get("level", 0)) != 0 or fixture_ranks(job).values().any(func(rank: Variant) -> bool: return int(rank) != 0)):
		printerr("Campaigns must start at level 0; nonzero fixtures are single-run only")
		return false
	for key: String in job.get("candidate", {}):
		if key not in ["id", "push_scale", "slope_offset_deg", "grip_scale", "slip_scale", "drain_scale", "ledge_scale", "shelf_length", "grooves"]:
			printerr("Unsupported candidate coefficient: " + key)
			return false
	return true

func fixture_ranks(job: Dictionary) -> Dictionary:
	var rank: int = int(job.get("level", 0))
	return job.get("ranks", {"strength": rank, "endurance": rank, "recovery": rank}).duplicate()

# Extension points for isolated experiments; default behavior is unchanged.
func policy_path() -> String:
	return "res://tests/balance/policies.json"

func metadata_additions() -> Dictionary:
	return {}

func create_controller(world: MountainManager, _candidate: Dictionary) -> BoulderController:
	return Controller.new(world)

func create_world(seed_value: int, job: Dictionary) -> MountainManager:
	return MountainManager.new(seed_value, false, int(job.get("generation", 6)), str(job.get("weather", "")))

func augment_result(_result: Dictionary, _boulder: BoulderController, _job: Dictionary) -> void:
	pass

func emit(record: Dictionary) -> void:
	output.store_line(JSON.stringify(record))
	output.flush()

func new_profile(job: Dictionary) -> Dictionary:
	var progression := Progression.new()
	var ranks: Dictionary = fixture_ranks(job)
	# Fixed physical ranks are fixtures, not purchased points. The separate
	# actual XP ledger starts at zero, so pending_points never becomes negative.
	return {"progression": progression, "ranks": ranks, "earned": 0, "time": 0.0, "purchases": [], "milestone_times": {}}

func simulate_campaign(job: Dictionary, seed_value: int) -> void:
	var profile: Dictionary = new_profile(job)
	var campaign_id: String = "%s:%d" % [str(job.get("id", "job")), seed_value]
	var max_seconds: float = float(job.get("max_campaign_seconds", 10800))
	var max_runs: int = int(job.get("max_runs", 30))
	var seeds: Array[int] = []
	var status: String = "run_limit"
	var count: int = 0
	for index: int in range(max_runs):
		if float(profile.time) >= max_seconds:
			status = "campaign_timeout"
			break
		# Bijective sequence within the ordinary positive 31-bit seed range.
		var fresh_seed: int = 1 + posmod(seed_value - 1 + index * 104729, 2147483646)
		seeds.append(fresh_seed)
		var limited: Dictionary = job.duplicate(true)
		limited.max_run_seconds = minf(float(job.get("max_run_seconds", 1800)), max_seconds - float(profile.time))
		var row: Dictionary = simulate_run(limited, fresh_seed, profile, index + 1, campaign_id)
		count += 1
		emit(row)
		if row.completed:
			status = "summit"
			break
		if row.censored:
			status = "campaign_timeout" if float(profile.time) >= max_seconds - DT else "run_timeout"
			break
	var result: Dictionary = identifiers(job, seed_value, campaign_id)
	result.merge({"type": "campaign", "status": status, "completed": status == "summit", "censored": status != "summit", "seconds": profile.time, "runs": count, "run_seeds": seeds, "cumulative_xp": profile.earned, "total_xp": (profile.progression as Progression).total_xp, "pending_points": (profile.progression as Progression).pending_points(), "end_ranks": profile.ranks.duplicate(), "purchases": profile.purchases, "milestone_times": profile.milestone_times, "threshold_times": {"all_8_seconds": profile.milestone_times.get("8"), "all_9_seconds": profile.milestone_times.get("9")}, "max_campaign_seconds": max_seconds, "max_runs": max_runs})
	emit(result)

func identifiers(job: Dictionary, seed_value: int, campaign_id: String) -> Dictionary:
	return {"job_id": str(job.get("id", "job")), "campaign_id": campaign_id, "policy": str(job.policy), "growth_mode": str(job.get("growth_mode", "actual")), "level": int(job.get("level", 0)), "ranks": fixture_ranks(job), "growth_id": str(job.get("growth_id", "balanced_%d" % int(job.get("level", 0)))) if not job.has("ranks") else str(job.get("growth_id", JSON.stringify(fixture_ranks(job)))), "strategy": str(job.get("strategy", "balanced")), "seed": seed_value, "candidate": job.get("candidate", {}), "generation": int(job.get("generation", 6)), "unrealistic_policy": bool(policies[str(job.policy)].unrealistic)}

func configure_world(world: MountainManager, candidate: Dictionary) -> void:
	for chunk: Dictionary in world.chunks:
		if candidate.has("slope_offset_deg"):
			chunk.start_angle = clampf(float(chunk.start_angle) + float(candidate.slope_offset_deg), 0.0, 45.0)
			chunk.end_angle = chunk.start_angle
		if candidate.has("shelf_length"):
			var old_climb: float = float(chunk.climb_length)
			var new_climb: float = float(chunk.length) - clampf(float(candidate.shelf_length), 1.0, 25.0)
			var offsets: Array = []
			for offset: Variant in chunk.get("ledge_offsets", []):
				offsets.append(new_climb + (float(offset) - old_climb) * (float(chunk.length) - new_climb) / (float(chunk.length) - old_climb) if float(offset) >= old_climb else float(offset))
			chunk.ledge_offsets = offsets
			chunk.climb_length = new_climb
	world._build_curve()
	for material: Dictionary in world.surfaces.values():
		material.grip = float(material.grip) * float(candidate.get("grip_scale", 1.0))
		material.slipperiness = float(material.slipperiness) * float(candidate.get("slip_scale", 1.0))
	for ledge: Dictionary in world.ledges:
		ledge.required_push = float(ledge.required_push) * float(candidate.get("ledge_scale", 1.0))
	var grooves: String = str(candidate.get("grooves", "current"))
	if grooves == "none":
		world.rest_points.clear()
	elif grooves == "all":
		world.rest_points.clear()
		for segment: Dictionary in world.segments:
			if segment.shelf:
				world.rest_points.append(float(segment.end) - 0.25)

func apply_growth(boulder: BoulderController, ranks: Dictionary, candidate: Dictionary) -> void:
	boulder.apply_progression(ranks)
	boulder.push_multiplier *= float(candidate.get("push_scale", 1.0))
	boulder.drain_scale = float(candidate.get("drain_scale", 1.0))

func choose_kind(ranks: Dictionary, strategy: String) -> String:
	var order: Array[String] = ["strength", "endurance", "recovery"]
	if strategy == "stability":
		order = ["endurance", "recovery", "strength"]
	if strategy == "balanced" or strategy == "stability":
		var best: String = ""
		var score: float = INF
		for kind: String in order:
			if int(ranks[kind]) >= 10:
				continue
			var candidate_score: float = float(ranks[kind])
			if strategy == "stability" and kind == "strength":
				candidate_score += 3.0
			if candidate_score < score:
				score = candidate_score
				best = kind
		return best
	for kind: String in order:
		if int(ranks[kind]) < 10:
			return kind
	return ""

func purchase(job: Dictionary, profile: Dictionary, boulder: BoulderController) -> void:
	if str(job.get("mode", "single")) != "campaign" or boulder.state != "climbing" or not boulder.mountain.is_shelf(boulder.distance) or absf(boulder.velocity) > 0.05:
		return
	var progression: Progression = profile.progression
	while true:
		var kind: String = choose_kind(profile.ranks, str(job.get("strategy", "balanced")))
		if kind.is_empty():
			break
		if not progression.choose(kind):
			break
		profile.ranks = progression.ranks.duplicate()
		profile.purchases.append({"seconds": float(profile.time) + boulder.elapsed, "kind": kind, "rank": profile.ranks[kind], "points_spent": 1, "distance_m": boulder.distance, "ranks": profile.ranks.duplicate(), "cumulative_xp": profile.earned, "total_xp": progression.total_xp, "pending_points": progression.pending_points()})
		for target: int in [3, 5, 7, 8, 9, 10]:
			if not profile.milestone_times.has(str(target)) and int(profile.ranks.strength) >= target and int(profile.ranks.endurance) >= target and int(profile.ranks.recovery) >= target:
				profile.milestone_times[str(target)] = float(profile.time) + boulder.elapsed
		apply_growth(boulder, profile.ranks, job.get("candidate", {}))

func award(profile: Dictionary, boulder: BoulderController) -> int:
	var earned: int = (profile.progression as Progression).award_distance(boulder.peak, boulder.mountain.total_length)
	profile.earned = int(profile.earned) + earned
	return earned

func decide(boulder: BoulderController, policy: Dictionary, memory: Dictionary, rng: RandomNumberGenerator, name: String) -> Array:
	var world: MountainManager = boulder.mountain
	var fraction: float = boulder.stamina / boulder.max_stamina
	var shelf: bool = world.is_shelf(boulder.distance)
	if shelf and fraction < float(policy.shelter_enter_below):
		memory.resting = true
	if not shelf or (fraction >= float(policy.shelter_recover_to) and absf(boulder.velocity) <= 0.05):
		memory.resting = false
	var command: Array = [true, false, false]
	if bool(memory.resting):
		command = [false, false, false]
	elif boulder.velocity < float(policy.brace_velocity) and boulder.stamina > 0.0:
		command = [false, false, true]
	elif boulder.slip_remaining > 0.0 and name != "novice":
		command = [false, false, boulder.velocity < -0.03]
	else:
		var near_ledge: bool = false
		for ledge: Dictionary in world.ledges:
			if not bool(boulder.cleared_ledges.get(str(ledge.id), false)) and float(ledge.distance) >= boulder.distance and float(ledge.distance) - boulder.distance < float(policy.ledge_lookahead_m):
				near_ledge = true
		var exert: bool = fraction > float(policy.exert_stamina_fraction) and boulder.slip < float(policy.slip_limit) and (name == "novice" or boulder.velocity < float(policy.target_speed) or near_ledge)
		if name == "skilled":
			exert = exert and (near_ledge or boulder.velocity < 0.55 or (rad_to_deg(world.angle_at(boulder.distance)) > 24.0 and boulder.velocity < 0.9))
		if name == "optimized":
			var force: float = BoulderController.BASE_PUSH * boulder.push_multiplier * boulder.stamina_multiplier() * world.grip_at(boulder.distance)
			var need: float = BoulderController.GRAVITY * sin(world.angle_at(boulder.distance)) + world.resistance_at(boulder.distance)
			exert = near_ledge or (force < need * 1.12 and boulder.velocity < 1.1) or boulder.velocity < 0.25
			# Exact-state coast control is intentionally labeled non-human.
			if boulder.velocity > float(policy.target_speed) and not near_ledge:
				command = [false, false, false]
			else:
				command = [true, exert, false]
		else:
			command = [true, exert, false]
	if rng.randf() < float(policy.error_probability):
		var mistake: int = rng.randi_range(0, 2)
		command = [[false, false, false], [true, true, false], [false, false, true]][mistake]
	return command

func simulate_run(job: Dictionary, seed_value: int, profile: Dictionary, run_index: int, campaign_id: String) -> Dictionary:
	var world := create_world(seed_value, job)
	var candidate: Dictionary = job.get("candidate", {})
	configure_world(world, candidate)
	var boulder = create_controller(world, candidate)
	apply_growth(boulder, profile.ranks, candidate)
	boulder.stamina = boulder.max_stamina
	var start_ranks: Dictionary = profile.ranks.duplicate()
	var starting_level: int = (profile.progression as Progression).level()
	var xp_events: Array = []
	(profile.progression as Progression).begin_run()
	var policy: Dictionary = policies[str(job.policy)]
	var rng := RandomNumberGenerator.new()
	var policy_seed: int = seed_value ^ 0x4150494C
	rng.seed = policy_seed
	var cadence: int = maxi(1, int(round(float(policy.decision_seconds) / DT)))
	var command: Array = [false, false, false]
	var memory: Dictionary = {"resting": false}
	var max_steps: int = int(floor(float(job.get("max_run_seconds", 1800)) / DT))
	var bands: Array = []
	for index: int in range(4):
		bands.append({"index": index, "entered": index == 0, "entry_seconds": 0.0 if index == 0 else null, "exposure_seconds": 0.0, "first_passage_seconds": null, "death": false, "rollback_m": 0.0, "slips": 0, "exhaustion_episodes": 0, "ledge_block_episodes": 0, "shelter_seconds": 0.0, "shelter_rest_seconds": 0.0, "shelter_visits": 0})
	var terrains: Dictionary = {}
	var exhausted: bool = false
	var ledge_active: bool = false
	var last_ledge_time: float = -100.0
	var ledge_episodes: int = 0
	var exhaustion_episodes: int = 0
	var runaway_count: int = 0
	var failure_band: int = -1
	var failure_cause: String = ""
	var last_slip_time: float = -100.0
	var rollback: float = 0.0
	var shelf_seconds: float = 0.0
	var shelf_rest_seconds: float = 0.0
	var fall_animation_seconds: float = 0.0
	var fall_descent_m: float = 0.0
	var previous_shelf: bool = false
	var earned: int = 0
	var previous_action: Array = command.duplicate()
	var switches: int = 0
	var decision_count: int = 0
	for step: int in range(max_steps):
		if boulder.state in ["result", "summit"]:
			break
		# Main pauses for upgrades as soon as a safe stationary shelf is reached.
		# Selection is instantaneous here; no UI-thinking time is synthesized.
		purchase(job, profile, boulder)
		if step % cadence == 0:
			command = decide(boulder, policy, memory, rng, str(job.policy))
			decision_count += 1
			if command != previous_action:
				switches += 1
			previous_action = command.duplicate()
		var before_distance: float = boulder.distance
		var before_state: String = boulder.state
		var before_slips: int = boulder.slips
		var band: int = clampi(int(before_distance / 250.0), 0, 3)
		var degrees: float = rad_to_deg(world.angle_at(before_distance))
		var surface: String = str(world.surface_at(before_distance).id)
		var angle_bin: String = "%02d-%02d" % [int(floor(degrees / 5.0)) * 5, int(floor(degrees / 5.0)) * 5 + 5]
		var terrain_key: String = surface + ":" + angle_bin
		if not terrains.has(terrain_key):
			terrains[terrain_key] = {"surface": surface, "angle_bin": angle_bin, "exposure_seconds": 0.0, "slips": 0, "exhaustion_episodes": 0, "ledge_block_episodes": 0, "runaways": 0}
		boulder.advance(DT, command[0], command[1], command[2])
		var award_amount: int = award(profile, boulder)
		earned += award_amount
		if award_amount > 0:
			var progression: Progression = profile.progression
			xp_events.append({"seconds": float(profile.time) + boulder.elapsed, "run_seconds": boulder.elapsed, "peak_m": boulder.peak, "milestone": progression.run_milestones, "earned_xp": award_amount, "total_xp": progression.total_xp, "level": progression.level(), "pending_points": progression.pending_points()})
		if before_state == "runaway":
			fall_animation_seconds += DT
			fall_descent_m += maxf(0.0, before_distance - boulder.distance)
			continue
		bands[band].exposure_seconds += DT
		terrains[terrain_key].exposure_seconds += DT
		var back: float = maxf(0.0, before_distance - boulder.distance)
		bands[band].rollback_m += back
		rollback += back
		var on_shelf: bool = world.is_shelf(before_distance)
		if on_shelf:
			bands[band].shelter_seconds += DT
			shelf_seconds += DT
			if not previous_shelf:
				bands[band].shelter_visits += 1
			if absf(boulder.velocity) <= 0.05 and not command[0] and not command[2]:
				bands[band].shelter_rest_seconds += DT
				shelf_rest_seconds += DT
		previous_shelf = on_shelf
		if boulder.slips > before_slips:
			bands[band].slips += 1
			terrains[terrain_key].slips += 1
			last_slip_time = boulder.elapsed
		if boulder.stamina <= 0.0 and not exhausted:
			exhaustion_episodes += 1
			bands[band].exhaustion_episodes += 1
			terrains[terrain_key].exhaustion_episodes += 1
		exhausted = boulder.stamina <= 0.0
		if boulder.ledge_blocked:
			if not ledge_active:
				ledge_episodes += 1
				bands[band].ledge_block_episodes += 1
				terrains[terrain_key].ledge_block_episodes += 1
			ledge_active = true
			last_ledge_time = boulder.elapsed
		elif boulder.elapsed - last_ledge_time >= 1.0:
			ledge_active = false
		if before_state != "runaway" and boulder.state == "runaway":
			runaway_count += 1
			failure_band = band
			terrains[terrain_key].runaways += 1
			failure_cause = "exhaustion_then_runaway" if boulder.stamina <= 0.0 else ("slip_then_runaway" if boulder.elapsed - last_slip_time < 3.0 else ("ledge_then_runaway" if boulder.elapsed - last_ledge_time < 3.0 else "rollback_runaway"))
		for index: int in range(4):
			if boulder.peak >= index * 250.0 and not bands[index].entered:
				bands[index].entered = true
				bands[index].entry_seconds = boulder.elapsed
			if boulder.peak >= (index + 1) * 250.0 and bands[index].first_passage_seconds == null:
				bands[index].first_passage_seconds = boulder.elapsed - float(bands[index].entry_seconds)
	var status: String = "summit" if boulder.state == "summit" else ("fall" if boulder.state == "result" else "timeout")
	if failure_band >= 0 and status == "fall":
		bands[failure_band].death = true
	var result: Dictionary = identifiers(job, seed_value, campaign_id)
	result.merge({"type": "run", "run_index": run_index, "policy_seed": policy_seed, "weather": world.weather_id, "status": status, "completed": status == "summit", "censored": status == "timeout", "seconds": boulder.elapsed, "peak_m": boulder.peak, "final_distance_m": boulder.distance, "slips": boulder.slips, "runaways": runaway_count, "exhaustion_episodes": exhaustion_episodes, "ledge_block_episodes": ledge_episodes, "rollback_m": rollback, "shelter_seconds": shelf_seconds, "earned_xp": earned, "cumulative_xp": profile.earned, "total_xp": (profile.progression as Progression).total_xp, "start_ranks": start_ranks, "end_ranks": profile.ranks.duplicate(), "bands": bands, "terrain": terrains.values(), "failure_band": failure_band, "failure_cause": failure_cause if status == "fall" else ("time_limit" if status == "timeout" else ""), "decision_count": decision_count, "input_switches": switches, "decision_cadence_seconds": cadence * DT, "max_run_seconds": float(job.get("max_run_seconds", 1800)), "final_state": boulder.snapshot(), "terrain_snapshot": world.snapshot()})
	profile.time = float(profile.time) + boulder.elapsed
	result.xp_events = xp_events
	result.starting_level = starting_level
	result.ending_level = (profile.progression as Progression).level()
	result.ranks_are_fixture = str(job.get("mode", "single")) == "single"
	result.shelter_rest_seconds = shelf_rest_seconds
	result.fall_animation_seconds = fall_animation_seconds
	result.fall_descent_m = fall_descent_m
	augment_result(result, boulder, job)
	emitted_runs += 1
	return result
