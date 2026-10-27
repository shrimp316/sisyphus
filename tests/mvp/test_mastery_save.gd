extends SceneTree
const Mastery = preload("res://scripts/mastery_progression.gd")
var checks: int = 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	var p = Mastery.new()
	p.begin_run("saved-run")
	p.award_distance(750, 1000)
	p.purchase_node("BRE01")
	p.run_ability_charges = {"BRE10_used": true, "reserve": 1, "spent_shelters": ["s1"]}
	p.run_ability_cooldowns = {"STR10": 1.125, "inertia": {"remaining": .5}}
	var snapshot: Dictionary = p.snapshot()
	var restored = Mastery.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(snapshot))), "JSON restore")
	check(JSON.parse_string(JSON.stringify(restored.snapshot())) == JSON.parse_string(JSON.stringify(snapshot)), "all state roundtrip")
	snapshot = restored.snapshot()
	check(restored.get_mastery_modifiers() == p.get_mastery_modifiers(), "same effects after restore")
	check(restored.award_distance(750, 1000) == 0, "no duplicate award after restore")
	var bad_states: Array[Dictionary] = []
	for key: String in snapshot:
		var missing: Dictionary = snapshot.duplicate(true)
		missing.erase(key)
		bad_states.append(missing)
	for key: String in ["available_exp", "prestige_count", "threads_balance", "run_milestones"]:
		for value: Variant in [-1, .5, "1", true, NAN, INF]:
			var invalid: Dictionary = snapshot.duplicate(true)
			invalid[key] = value
			bad_states.append(invalid)
	var duplicate: Dictionary = snapshot.duplicate(true)
	duplicate.purchased_mastery_nodes.append("BRE01")
	bad_states.append(duplicate)
	var forged: Dictionary = snapshot.duplicate(true)
	forged.purchased_mastery_nodes = ["STR02"]
	bad_states.append(forged)
	var unearned: Dictionary = snapshot.duplicate(true)
	unearned.available_exp = 100000
	bad_states.append(unearned)
	var bad_charge: Dictionary = snapshot.duplicate(true)
	bad_charge.run_ability_charges = {"bad": INF}
	bad_states.append(bad_charge)
	var legacy: Dictionary = {"version": 1, "total_xp": 6150, "ranks": {"strength": 10}}
	bad_states.append(legacy)
	for index: int in bad_states.size():
		check(not restored.restore(bad_states[index]), "invalid rejected " + str(index))
		check(restored.snapshot() == snapshot, "restore is atomic " + str(index))
	# A before-commit save can retry once; an after-commit save cannot duplicate rewards.
	p.award_distance(1000, 1000)
	var before: Dictionary = p.snapshot()
	check(restored.restore(before) and restored.commit_prestige("saved-run"), "before transaction retry")
	var after: Dictionary = restored.snapshot()
	var reopened = Mastery.new()
	check(reopened.restore(JSON.parse_string(JSON.stringify(after))), "after transaction restore")
	check(not reopened.commit_prestige("saved-run") and reopened.threads_balance == 1, "duplicate commit blocked after reload")
	var imported = Mastery.new()
	check(imported.import_legacy_record(1000), "explicit legacy record import")
	check(imported.available_exp == 0 and imported.purchased_mastery_nodes.is_empty(), "no legacy XP/rank conversion")
	check(imported.permanent_mastery_unlocks.size() == 30 and not imported.malkuth_unlocked, "record import does not grant prestige")
	check(reopened.restore(imported.snapshot()), "record import can save")
	print(JSON.stringify({"suite": "mastery_save", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
