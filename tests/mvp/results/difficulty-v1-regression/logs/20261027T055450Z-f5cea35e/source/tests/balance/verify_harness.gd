extends "res://tests/balance/simulator.gd"

# Independent tests of the experiment harness, not a second physics model.
var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func job_for(policy_name: String = "regular", limit: float = 15.0) -> Dictionary:
	return {"id": "verification", "policy": policy_name, "seeds": [1001], "growth_mode": "actual", "mode": "single", "level": 0, "max_run_seconds": limit}

func replay(fps: int) -> Dictionary:
	var sim := BoulderController.new(MountainManager.new(1001, false, 6, "rain"))
	# Recorded one-second held commands have identical boundaries at both FPS.
	var commands: Array = [[true, true, false], [true, false, false], [false, false, false], [false, false, true]]
	for command: Array in commands:
		for frame: int in range(fps):
			sim.advance(1.0 / fps, command[0], command[1], command[2])
	return sim.snapshot()

func test_replay() -> void:
	var slow: Dictionary = replay(30)
	var fast: Dictionary = replay(144)
	var same: bool = true
	for key: String in slow:
		if typeof(slow[key]) == TYPE_FLOAT:
			same = same and absf(float(slow[key]) - float(fast[key])) < 0.000001
		else:
			same = same and slow[key] == fast[key]
	check(same, "recorded held-input replay agrees at 30 and 144 FPS")
	check(is_equal_approx(BoulderController.FIXED_DT, DT), "harness uses production 1/120-second integration step")

func test_rollouts() -> void:
	for policy_name: String in ["novice", "regular", "skilled", "optimized"]:
		var job: Dictionary = job_for(policy_name)
		var first: Dictionary = simulate_run(job, 1001, new_profile(job), 1, "")
		var repeated: Dictionary = simulate_run(job, 1001, new_profile(job), 1, "")
		check(first == repeated, policy_name + " same terrain and policy RNG seed reproduce every output field")
		var cadence: float = float(first.decision_cadence_seconds)
		check(first.decision_count == int(ceil(first.seconds / cadence - 0.000001)) and first.input_switches <= first.decision_count, policy_name + " commands change only on bounded decision cadence")
		check(first.status == "timeout" and first.censored and not first.completed and first.failure_cause == "time_limit", policy_name + " short time limit is censored rather than counted as a fall")
		var exposure: float = 0.0
		var rollback: float = 0.0
		var slips: int = 0
		for band: Dictionary in first.bands:
			exposure += float(band.exposure_seconds)
			rollback += float(band.rollback_m)
			slips += int(band.slips)
		check(absf(exposure - first.seconds) < 0.000001 and absf(rollback - first.rollback_m) < 0.000001 and slips == first.slips, policy_name + " band metrics partition run exposure, rollback and slip counts")
		check(first.bands[0].entered and not first.bands[1].entered and first.bands[0].first_passage_seconds == null, policy_name + " unreached bands and incomplete passage remain distinct")
	var long_job: Dictionary = job_for("optimized", 1200.0)
	var summit: Dictionary = simulate_run(long_job, 1001, new_profile(long_job), 1, "")
	var total_passage: float = 0.0
	var valid_bands: bool = true
	for band: Dictionary in summit.bands:
		valid_bands = valid_bands and band.entered and band.first_passage_seconds != null and not band.death
		if band.first_passage_seconds != null:
			total_passage += float(band.first_passage_seconds)
	check(summit.completed and summit.peak_m == 1000.0 and not summit.censored, "optimized baseline reaches genuine production summit")
	check(valid_bands and absf(total_passage - summit.seconds) < 0.000001, "four first-passage intervals partition completed climb time")
	check(summit.earned_xp == 600, "first unpurchased summit awards exactly 20 markers times 30 XP")
	var event_total: int = 0
	var previous_event_time: float = -1.0
	var valid_events: bool = true
	for event: Dictionary in summit.xp_events:
		event_total += int(event.earned_xp)
		valid_events = valid_events and int(event.total_xp) == event_total and float(event.seconds) > previous_event_time
		previous_event_time = float(event.seconds)
	check(valid_events and summit.xp_events.size() == 20 and event_total == 600 and summit.starting_level == 1 and summit.ending_level == 7, "actual XP event timeline preserves awards, ordering and level progression")

func test_economy() -> void:
	var job: Dictionary = job_for()
	var profile: Dictionary = new_profile(job)
	var sim := Controller.new(MountainManager.new(1001))
	sim.peak = 100.0
	check(award(profile, sim) == 60 and award(profile, sim) == 0, "repeated marker claims cannot duplicate actual XP")
	(profile.progression as Progression).begin_run()
	sim.peak = 50.0
	var repeat_xp: int = award(profile, sim)
	sim.peak = 150.0
	check(repeat_xp == 20 and award(profile, sim) == 50 and profile.earned == 130, "new run resets run claims while preserving lifetime record bonus")
	var campaign_job: Dictionary = job_for()
	campaign_job.mode = "campaign"
	var maximum: Dictionary = new_profile(campaign_job)
	(maximum.progression as Progression).total_xp = 6150
	maximum.earned = 6150
	var stone := Controller.new(MountainManager.new(1001))
	stone.distance = 45.0
	stone.stamina = 70.0
	purchase(campaign_job, maximum, stone)
	var points: int = 0
	for item: Dictionary in maximum.purchases:
		points += int(item.points_spent)
	var growth: Progression = maximum.progression
	check(maximum.ranks == {"strength": 10, "endurance": 10, "recovery": 10} and points == 30 and growth.level() == 31 and growth.pending_points() == 0, "actual maximum level31 grants thirty upgrades capped at rank10 per stat")
	check(growth.total_xp == 6150 and maximum.earned == 6150 and stone.stamina == 70.0, "actual upgrades spend points without consuming XP or refilling stamina")
	check(is_equal_approx(stone.push_multiplier, 1.2) and stone.max_stamina == 120.0 and is_equal_approx(stone.recovery_multiplier, 1.2) and not growth.choose("strength"), "existing +2 percent stat effects cap at +20 percent")
	var blocked: Dictionary = new_profile(campaign_job)
	(blocked.progression as Progression).total_xp = 60
	stone.distance = 10.0
	purchase(campaign_job, blocked, stone)
	check(blocked.purchases.is_empty() and (blocked.progression as Progression).pending_points() == 1, "growth cannot be purchased on an unsafe slope")
	for kind: String in Progression.KINDS:
		var isolated_job: Dictionary = job_for()
		isolated_job.ranks = {"strength": 0, "endurance": 0, "recovery": 0}
		isolated_job.ranks[kind] = 10
		var isolated: Dictionary = new_profile(isolated_job)
		var isolated_stone := Controller.new(MountainManager.new(1001))
		apply_growth(isolated_stone, isolated.ranks, {})
		check(valid_job(isolated_job) and is_equal_approx(isolated_stone.push_multiplier, 1.2 if kind == "strength" else 1.0) and isolated_stone.max_stamina == (120.0 if kind == "endurance" else 100.0) and is_equal_approx(isolated_stone.recovery_multiplier, 1.2 if kind == "recovery" else 1.0), kind + " isolated fixture modifies only the existing intended stat")
		check((isolated.progression as Progression).pending_points() == 0 and (isolated.progression as Progression).total_xp == 0, kind + " physical fixture creates no invalid economic profile")
	var unknown: Dictionary = job_for()
	unknown.growth_mode = "virtual_proxy"
	check(not valid_job(unknown), "unsupported virtual growth mode is rejected before simulation")

func test_fall_censoring() -> void:
	var job: Dictionary = job_for("novice", 1200.0)
	var fallen: Dictionary = simulate_run(job, 101, new_profile(job), 1, "")
	check(fallen.status == "fall" and not fallen.censored and fallen.runaways == 1, "ordinary novice input produces a measured terminal fall")
	if fallen.status != "fall":
		return
	var active_seconds: float = 0.0
	var deaths: int = 0
	var terrain_seconds: float = 0.0
	for band: Dictionary in fallen.bands:
		active_seconds += float(band.exposure_seconds)
		deaths += int(band.death)
	for terrain: Dictionary in fallen.terrain:
		terrain_seconds += float(terrain.exposure_seconds)
	check(fallen.fall_animation_seconds > 0.0 and absf(active_seconds + fallen.fall_animation_seconds - fallen.seconds) < 0.000001 and absf(active_seconds - terrain_seconds) < 0.000001, "runaway cinematic time is excluded from active band and terrain exposure")
	check(deaths == 1 and fallen.bands[fallen.failure_band].death and fallen.fall_descent_m > 0.0, "terminal fall belongs to its runaway origin band, with descent separately measured")
	job.max_run_seconds = active_seconds + DT
	var cutoff: Dictionary = simulate_run(job, 101, new_profile(job), 1, "")
	var cutoff_deaths: int = 0
	for band: Dictionary in cutoff.bands:
		cutoff_deaths += int(band.death)
	check(cutoff.status == "timeout" and cutoff.censored and cutoff.runaways == 1 and cutoff_deaths == 0, "cutoff during runaway remains censored rather than becoming a completed death")

func run() -> void:
	policies = JSON.parse_string(FileAccess.get_file_as_string("res://tests/balance/policies.json")).policies
	test_replay()
	test_rollouts()
	test_economy()
	test_fall_censoring()
	print("BALANCE HARNESS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
