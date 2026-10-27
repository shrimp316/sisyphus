extends SceneTree
## Boundary, old-save compatibility, and unchanged economy checks for the earlier unlock schedule.
const Profile = preload("res://scripts/mastery_progression.gd")
const Contract = preload("res://scripts/mvp/save_contract.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void:
	var gates: Array[int] = [150, 400, 700]
	var old_gates: Array[int] = [250, 500, 750]
	for index: int in gates.size():
		var gate: int = gates[index]
		var p = Profile.new()
		p.begin_run("boundary-" + str(gate))
		p.award_distance(gate - 0.001, 1000)
		check(p.permanent_mastery_unlocks.size() == index * 10, "locked immediately below " + str(gate))
		while not p.consume_pending_milestone().is_empty(): pass
		p.award_distance(gate, 1000)
		check(p.permanent_mastery_unlocks.size() == (index + 1) * 10, "ten nodes unlock at " + str(gate))
		var event: Dictionary = p.consume_pending_milestone()
		check(event.distance == gate and event.node_ids.size() == 10, "one exact event " + str(gate))
		check(p.consume_pending_milestone().is_empty(), "no duplicate event " + str(gate))
		check(p.available_exp == gate / 50 * 30, "unchanged 50m EXP at " + str(gate))
		# Simulate a valid old save in the newly eligible interval: remove only this group's unlocks.
		var legacy: Dictionary = p.snapshot()
		for id: String in event.node_ids: legacy.permanent_mastery_unlocks.erase(id)
		var restored = Profile.new()
		check(restored.restore(legacy), "old eligibility gap restores " + str(gate))
		check(restored.permanent_mastery_unlocks.size() == (index + 1) * 10, "eligibility backfilled " + str(gate))
		check(restored.available_exp == p.available_exp and restored.historical_exp_earned == p.historical_exp_earned, "backfill awards no EXP " + str(gate))
		check(restored.consume_pending_milestone().is_empty(), "silent backfill " + str(gate))
		var once: Dictionary = restored.snapshot()
		check(restored.restore(once) and restored.snapshot() == once, "backfill idempotent " + str(gate))
		# Old event requires the actual old distance as well as matching node IDs.
		p.award_distance(old_gates[index], 1000)
		legacy = p.snapshot()
		legacy.pending_milestones = [{"distance":old_gates[index], "node_ids":event.node_ids}]
		check(restored.restore(legacy), "old pending event accepted " + str(old_gates[index]))
		check(restored.consume_pending_milestone().distance == gate, "old event normalized " + str(gate))
		legacy.highest_distance = gate
		legacy.record_milestones = gate / 50
		legacy.run_milestones = gate / 50
		check(not restored.restore(legacy), "unreached old event rejected " + str(gate))
		legacy = p.snapshot()
		legacy.pending_milestones = [{"distance":old_gates[index], "node_ids":["SPC01"]}]
		check(not restored.restore(legacy), "mismatched old event rejected " + str(gate))
		legacy = p.snapshot()
		legacy.pending_milestones = [{"distance":old_gates[index], "node_ids":event.node_ids}, {"distance":gate, "node_ids":event.node_ids}]
		check(not restored.restore(legacy), "aliased duplicate pending event rejected " + str(gate))
	# Keep checked-in pre-change saves intact as compatibility evidence.
	for fixture: String in ["milestone250", "prestige-commit", "after-prestige"]:
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/mvp/fixtures/web/" + fixture + ".json"))
		var before: String = JSON.stringify(saved)
		check(Contract.validate(saved), "legacy full save accepted " + fixture)
		check(JSON.stringify(saved) == before, "contract validation is read-only " + fixture)
		var restored = Profile.new()
		check(restored.restore(saved.mastery), "legacy profile accepted " + fixture)
		check(restored.available_exp == saved.mastery.available_exp and restored.purchased_mastery_nodes == saved.mastery.purchased_mastery_nodes, "legacy wallet and purchases preserved " + fixture)
	var old_modal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/mvp/fixtures/web/milestone250.json"))
	old_modal.mastery.highest_distance = 150
	old_modal.mastery.record_milestones = 3
	old_modal.mastery.run_milestones = 3
	old_modal.run.distance = 150
	old_modal.run.peak = 150
	check(not Contract.validate(old_modal), "old 250 modal rejected below original threshold")
	var imported = Profile.new()
	check(imported.import_legacy_record(1000), "legacy record import")
	var restored = Profile.new()
	check(restored.restore(imported.snapshot()) and restored.permanent_mastery_unlocks.size() == 30, "restore never adds special unlock to record-only import")
	var result: Dictionary = {"suite":"unlock_schedule", "checks":checks, "failures":failures}
	var output := "res://tests/mastery/results/unlock-150-400-700/runtime"
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output + "/unlock-schedule.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print(JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
