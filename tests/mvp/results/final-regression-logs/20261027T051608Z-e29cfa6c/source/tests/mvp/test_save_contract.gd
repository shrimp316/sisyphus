extends SceneTree
const Contract = preload("res://scripts/mvp/save_contract.gd")
const Profile = preload("res://scripts/mastery_progression.gd")
const Controller = preload("res://scripts/mastery_boulder.gd")
const Mountain = preload("res://scripts/mountain_manager.gd")
var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func payload(profile: RefCounted, controller: RefCounted, phase: String = "") -> Dictionary:
	profile.run_ability_charges = controller.get_run_ability_charges()
	profile.run_ability_cooldowns = controller.get_run_ability_cooldowns()
	return {"version": 5, "save_version": 1, "saved_at_unix_msec": 123456.5, "revision": 1,
		"world": controller.mountain.snapshot(), "run": controller.snapshot(), "mastery": profile.snapshot(),
		"run_number": 1, "falls_seen": 0, "previous_best": 0.0, "prestige_phase": phase,
		"phase_elapsed": 0.0, "modal_milestone": {}, "settings": {"muted": false, "volume": .7, "fullscreen": false}}

func _initialize() -> void:
	var p = Profile.new()
	p.begin_run("contract-run")
	var b = Controller.new(Mountain.new(202, false, 6, "clear"))
	b.apply_mastery_effects(p.get_mastery_modifiers())
	var original: Dictionary = payload(p, b)
	check(Contract.validate(original), "initial save")
	check(Contract.validate(JSON.parse_string(JSON.stringify(original))), "JSON save")
	check(Contract.validate_run(b.snapshot(), p), "standalone run validation")
	var unchanged: String = JSON.stringify(original)
	var invalid: Array[Dictionary] = []
	for key: String in original:
		var missing: Dictionary = original.duplicate(true)
		missing.erase(key)
		invalid.append(missing)
	for key: String in ["version", "save_version", "revision", "run_number", "falls_seen", "saved_at_unix_msec", "previous_best", "phase_elapsed"]:
		for bad: Variant in [-1, "1", true, NAN, INF]:
			var mutated: Dictionary = original.duplicate(true)
			mutated[key] = bad
			invalid.append(mutated)
	for key: String in ["distance", "peak", "velocity", "stamina", "slip", "slip_remaining", "accumulator", "elapsed", "runaway_elapsed", "slips", "partial_falls"]:
		for bad: Variant in [NAN, INF, "0", true]:
			var mutated: Dictionary = original.duplicate(true)
			mutated.run[key] = bad
			invalid.append(mutated)
	for key: String in b.ability:
		var mutated: Dictionary = original.duplicate(true)
		mutated.run.mastery_run[key] = "corrupt" if not b.ability[key] is String else 999
		invalid.append(mutated)
	for entry: Array in [["distance", 1001], ["peak", 1001], ["stamina", 101], ["velocity", 1.81], ["accumulator", .1], ["state", "hacked"]]:
		var mutated: Dictionary = original.duplicate(true)
		mutated.run[entry[0]] = entry[1]
		invalid.append(mutated)
	for entry: Array in [["burst_seconds", .51], ["burst_cooldown", 2.01], ["inertia_progress", 5], ["inertia_budget", 3], ["inertia_seconds", 2], ["reserve_charge", 2], ["reserve_uses", .5], ["departure_remaining", 11]]:
		var mutated: Dictionary = original.duplicate(true)
		mutated.run.mastery_run[entry[0]] = entry[1]
		invalid.append(mutated)
	var bad_world: Dictionary = original.duplicate(true)
	bad_world.world = {}
	invalid.append(bad_world)
	var bad_material: Dictionary = original.duplicate(true)
	bad_material.world.surfaces.STONE.grip = "1"
	invalid.append(bad_material)
	var bad_phase: Dictionary = original.duplicate(true)
	bad_phase.prestige_phase = "MALKUTH_UNLOCK"
	invalid.append(bad_phase)
	var bad_modal: Dictionary = original.duplicate(true)
	bad_modal.modal_milestone = {"distance": 250, "node_ids": ["STR01"]}
	invalid.append(bad_modal)
	var bad_summary: Dictionary = original.duplicate(true)
	bad_summary.mastery.run_ability_charges.bre10_used = true
	invalid.append(bad_summary)
	var alias_shelf: Dictionary = original.duplicate(true)
	alias_shelf.run.mastery_run.reserve_shelves = {"42:50": true}
	invalid.append(alias_shelf)
	for index: int in invalid.size():
		check(not Contract.validate(invalid[index]), "corrupt save rejected " + str(index))
	check(JSON.stringify(original) == unchanged, "validation does not mutate input")
	# Active snapshots at actual fixed steps must also satisfy the contract.
	for second: int in range(10):
		for tick: int in range(120): b._step(1.0 / 120.0, true, true, false)
		p.award_distance(b.peak, 1000)
		check(Contract.validate(payload(p, b)), "actual simulation snapshot " + str(second))
	p.award_distance(250, 1000)
	b.distance = 250
	b.peak = 250
	var at_milestone: Dictionary = payload(p, b)
	at_milestone.modal_milestone = p.consume_pending_milestone()
	check(Contract.validate(at_milestone), "milestone modal save")
	check(p.purchase_node("END01"), "capacity upgrade fixture")
	b.apply_mastery_effects(p.get_mastery_modifiers())
	b.stamina = 104.0
	check(Contract.validate(payload(p, b)), "purchased capacity is the stamina ceiling")
	p.award_distance(1000, 1000)
	b.distance = 1000
	b.peak = 1000
	b.state = "summit"
	for phase: String in ["SUMMIT_REACHED", "FIRST_SUMMIT_SEQUENCE", "BOULDER_ROLLS_AWAY", "PRESTIGE_COMMIT"]:
		check(Contract.validate(payload(p, b, phase)), "before commit " + phase)
	check(p.commit_prestige("contract-run"), "prestige commit fixture")
	b.apply_mastery_effects(p.get_mastery_modifiers())
	for phase: String in ["PRESTIGE_COMMIT", "SEPHIROT_REVEAL", "MALKUTH_UNLOCK", "NEW_RUN"]:
		check(Contract.validate(payload(p, b, phase)), "after commit " + phase)
	check(not Contract.validate(payload(p, b)), "committed token requires journal phase")
	p.begin_run("next-run")
	b = Controller.new(Mountain.new(203))
	check(Contract.validate(payload(p, b)), "new run after commit")
	print(JSON.stringify({"suite": "save_contract", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
