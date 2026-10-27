extends RefCounted
## MOCK ONLY. Owns a fresh in-memory Progression; never reads or writes a save.
## A live adapter must call main.choose_upgrade() after its safety checks.
signal changed
signal purchase_succeeded(node_id: String)
const ProgressionModel = preload("res://scripts/progression.gd")
const Resolver = preload("res://scripts/mastery/mastery_state_resolver.gd")
const FIXTURES := "res://data/mastery/mastery_preview_fixtures.json"
var progression = ProgressionModel.new()
var best := 0
var current_distance := 0
var current_run_number := 1
var first_summit_run_number := -1
var first_reach_flags: Dictionary = {"250": false, "500": false, "750": false}
var fixture_id := "zero"
var purchase_busy := false

func snapshot() -> Dictionary:
	return {"total_xp": progression.total_xp, "pending_points": progression.pending_points(),
		"ranks": progression.ranks.duplicate(), "best": best, "current_distance": current_distance,
		"current_run_number": current_run_number, "first_summit_run_number": first_summit_run_number,
		"first_reach_flags": first_reach_flags.duplicate(), "mock": true, "fixture_id": fixture_id}

func apply_fixture(id: String) -> void:
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES))
	for fixture: Dictionary in fixtures:
		if fixture.id != id: continue
		fixture_id = id
		progression = ProgressionModel.new()
		progression.total_xp = int(fixture.total_xp)
		current_distance = int(fixture.current_distance)
		best = int(fixture.best)
		progression.run_milestones = int(current_distance / 50)
		progression.record_milestones = int(best / 50)
		current_run_number = int(fixture.current_run_number)
		first_summit_run_number = int(fixture.first_summit_run_number)
		first_reach_flags = {"250": best >= 250, "500": best >= 500, "750": best >= 750}
		changed.emit()
		return
	push_error("Unknown preview fixture: " + id)

func purchase(node: Dictionary) -> bool:
	if purchase_busy or not Resolver.resolve(node, snapshot()).can_purchase: return false
	purchase_busy = true
	var success: bool = progression.choose(Resolver.KIND[node.track])
	if success:
		changed.emit()
		purchase_succeeded.emit(str(node.node_id))
	purchase_busy = false
	return success

func record_reach(distance: int) -> void:
	current_distance = clampi(distance, 0, 1000)
	best = maxi(best, current_distance)
	progression.award_distance(current_distance, 1000.0)
	for milestone in [250, 500, 750]:
		if best >= milestone: first_reach_flags[str(milestone)] = true
	if current_distance >= 1000 and first_summit_run_number < 0: first_summit_run_number = current_run_number
	changed.emit()

func begin_next_run() -> void:
	current_run_number += 1
	current_distance = 0
	progression.begin_run()
	changed.emit()

func reset_purchased() -> void:
	# Preview-only reset, not a prestige implementation or persistent field.
	progression.ranks = {"strength": 0, "endurance": 0, "recovery": 0}
	changed.emit()

func fund_preview() -> void:
	# Developer fixture at the EXISTING level cap, not an economy recommendation.
	progression.total_xp = ProgressionModel.MAX_XP
	changed.emit()
