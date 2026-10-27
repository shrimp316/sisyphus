class_name Progression
extends RefCounted

const MILESTONE_DISTANCE: float = 50.0
const RUN_XP: int = 20
const RECORD_XP: int = 10
const MAX_LEVEL: int = 31
const MAX_RANK: int = 10
const MAX_XP: int = 6150
const MAX_MILESTONES: int = 20
const KINDS: Array[String] = ["strength", "endurance", "recovery"]

var total_xp: int = 0
var run_milestones: int = 0
var record_milestones: int = 0
var ranks: Dictionary = {"strength": 0, "endurance": 0, "recovery": 0}

func level() -> int:
	return _level_for_xp(total_xp)

func pending_points() -> int:
	return level() - 1 - int(ranks.strength) - int(ranks.endurance) - int(ranks.recovery)

func xp_in_level() -> int:
	if level() == MAX_LEVEL:
		return 0
	var remaining: int = total_xp
	for completed_level: int in range(1, level()):
		remaining -= 60 + (completed_level - 1) * 10
	return remaining

func xp_for_next_level() -> int:
	return 0 if level() == MAX_LEVEL else 60 + (level() - 1) * 10

func award_distance(peak: float, total_length: float) -> int:
	if not is_finite(peak) or not is_finite(total_length) or total_length <= 0.0:
		return 0
	var reached: int = mini(MAX_MILESTONES, int(floor(clampf(peak, 0.0, total_length) / MILESTONE_DISTANCE)))
	var earned: int = maxi(0, reached - run_milestones) * RUN_XP + maxi(0, reached - record_milestones) * RECORD_XP
	run_milestones = maxi(run_milestones, reached)
	record_milestones = maxi(record_milestones, reached)
	var previous_xp: int = total_xp
	total_xp = mini(MAX_XP, total_xp + earned)
	return total_xp - previous_xp

func choose(kind: String) -> bool:
	if kind not in KINDS or pending_points() <= 0 or int(ranks[kind]) >= MAX_RANK:
		return false
	ranks[kind] = int(ranks[kind]) + 1
	return true

func begin_run() -> void:
	run_milestones = 0

func snapshot() -> Dictionary:
	return {"version": 1, "total_xp": total_xp, "run_milestones": run_milestones, "record_milestones": record_milestones, "ranks": ranks.duplicate()}

func restore(data: Dictionary) -> bool:
	# Validate everything before changing the profile; JSON numbers can be floats.
	if not _valid_integer(data.get("version"), 1, 1) or not _valid_integer(data.get("total_xp"), 0, MAX_XP):
		return false
	if not _valid_integer(data.get("run_milestones"), 0, MAX_MILESTONES) or not _valid_integer(data.get("record_milestones"), 0, MAX_MILESTONES):
		return false
	if int(data.run_milestones) > int(data.record_milestones) or not data.get("ranks") is Dictionary:
		return false
	var restored_ranks: Dictionary = data.ranks
	if restored_ranks.size() != KINDS.size():
		return false
	var spent: int = 0
	for kind: String in KINDS:
		if not _valid_integer(restored_ranks.get(kind), 0, MAX_RANK):
			return false
		spent += int(restored_ranks[kind])
	if spent > _level_for_xp(int(data.total_xp)) - 1:
		return false
	total_xp = int(data.total_xp)
	run_milestones = int(data.run_milestones)
	record_milestones = int(data.record_milestones)
	for kind: String in KINDS:
		ranks[kind] = int(restored_ranks[kind])
	return true

func migrate_legacy(peak: float, best: float) -> void:
	total_xp = 0
	ranks = {"strength": 0, "endurance": 0, "recovery": 0}
	var safe_peak: float = clampf(peak, 0.0, 1000.0) if is_finite(peak) else 0.0
	var safe_best: float = clampf(best, 0.0, 1000.0) if is_finite(best) else 0.0
	run_milestones = int(floor(safe_peak / MILESTONE_DISTANCE))
	record_milestones = int(floor(maxf(safe_peak, safe_best) / MILESTONE_DISTANCE))

func _level_for_xp(xp: int) -> int:
	var current_level: int = 1
	var remaining: int = xp
	while current_level < MAX_LEVEL:
		var required: int = 60 + (current_level - 1) * 10
		if remaining < required:
			break
		remaining -= required
		current_level += 1
	return current_level

func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum and number <= maximum and number == floor(number)
