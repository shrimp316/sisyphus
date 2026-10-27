extends SceneTree
const Profile = preload("res://scripts/mastery_progression.gd")
const Contract = preload("res://scripts/mvp/save_contract.gd")
const Mountain = preload("res://scripts/mountain_manager.gd")
const Boulder = preload("res://scripts/mastery_boulder.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func old_snapshot(distance: float) -> Dictionary:
	var p = Profile.new()
	p.begin_run("independent-legacy")
	p.award_distance(distance, 1000)
	var s: Dictionary = p.snapshot()
	s.permanent_mastery_unlocks = []
	s.pending_milestones = []
	for old_gate: int in [250, 500, 750]:
		if distance < old_gate: continue
		var ids: Array[String] = []
		for node: Dictionary in p.definitions:
			if int(node.unlock_milestone) == Profile.normalized_unlock_distance(old_gate):
				ids.append(node.id)
				s.permanent_mastery_unlocks.append(node.id)
		s.pending_milestones.append({"distance": old_gate, "node_ids": ids})
	return s

func envelope(s: Dictionary, modal: Dictionary) -> Dictionary:
	var p = Profile.new()
	p.restore(s)
	var b = Boulder.new(Mountain.new(202, false, 6, "clear"))
	b.distance = float(s.highest_distance)
	b.peak = b.distance
	s = s.duplicate(true)
	s.run_ability_charges = b.get_run_ability_charges()
	s.run_ability_cooldowns = b.get_run_ability_cooldowns()
	return {"version":5,"save_version":1,"saved_at_unix_msec":123456.5,"revision":1,
		"world":b.mountain.snapshot(),"run":b.snapshot(),"mastery":s,
		"run_number":1,"falls_seen":0,"previous_best":0.0,"prestige_phase":"",
		"phase_elapsed":0.0,"modal_milestone":modal,"settings":{"muted":false,"volume":.7,"fullscreen":false}}

func _initialize() -> void:
	for pair: Array in [[149.99,0],[150.0,10],[399.99,10],[400.0,20],[699.99,20],[700.0,30]]:
		var p = Profile.new()
		p.begin_run("independent-boundary")
		p.award_distance(pair[0],1000)
		check(p.permanent_mastery_unlocks.size()==pair[1],"boundary %s" % pair[0])
		check(p.available_exp==int(floor(pair[0]/50))*30,"unchanged XP %s" % pair[0])
		check(p.get_node_definition("STR01").exp_cost==30,"unchanged cost")
		var before: int = p.available_exp
		check(p.award_distance(pair[0],1000)==0 and p.available_exp==before,"no repeat XP")
	for distance: int in [0,149,150,200,249,250,399,400,450,499,500,699,700,725,749,750]:
		var s := old_snapshot(distance)
		var original := JSON.stringify(s)
		var p = Profile.new()
		check(p.restore(s),"legacy restore %d" % distance)
		check(JSON.stringify(s)==original,"input immutable %d" % distance)
		var count: int = (10 if distance>=150 else 0)+(10 if distance>=400 else 0)+(10 if distance>=700 else 0)
		check(p.permanent_mastery_unlocks.size()==count,"silent eligibility backfill %d" % distance)
		check(p.available_exp==s.available_exp and p.historical_exp_earned==s.historical_exp_earned,"wallet preserved %d" % distance)
		var normalized: Dictionary = p.snapshot()
		check(normalized.pending_milestones.size()==s.pending_milestones.size(),"no extra modal on load %d" % distance)
		var r = Profile.new()
		check(r.restore(normalized) and r.snapshot()==normalized,"idempotent reload %d" % distance)
		var full := envelope(s,{})
		check(Contract.validate(full),"legacy full save %d" % distance)
		for event: Dictionary in s.pending_milestones:
			full.modal_milestone=event.duplicate(true)
			check(Contract.validate(full),"legacy modal %d:%d" % [distance,event.distance])
	var old250 := old_snapshot(250)
	var wrong_group: Dictionary = old250.duplicate(true)
	wrong_group.pending_milestones[0].distance=500
	check(not Profile.new().restore(wrong_group),"unreached legacy queue rejected")
	var duplicate: Dictionary = old250.duplicate(true)
	duplicate.pending_milestones.append(duplicate.pending_milestones[0].duplicate(true))
	duplicate.pending_milestones[1].distance=150
	check(not Profile.new().restore(duplicate),"old/new duplicate queue rejected")
	var forged := envelope(old_snapshot(200),old250.pending_milestones[0])
	check(not Contract.validate(forged),"unreached legacy modal rejected")
	var mismatched := envelope(old_snapshot(750),old250.pending_milestones[0].duplicate(true))
	mismatched.modal_milestone.distance=500
	check(not Contract.validate(mismatched),"wrong group legacy modal rejected")
	var file := FileAccess.open("res://tests/mastery/results/unlock-150-400-700/independent_migration.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()},"\t"))
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
