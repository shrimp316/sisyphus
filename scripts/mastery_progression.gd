class_name MasteryProgression
extends RefCounted
## EXP wallet and permanent eligibility. UI owns safe purchase context and durable writes.
const SAVE_VERSION: int = 2
const MAX_SAFE_INTEGER: int = 9007199254740991
const UNLOCK_DISTANCES: Array[int] = [150, 400, 700, 1000]

static func normalized_unlock_distance(distance: int) -> int:
	# Existing v2 saves retain their schema; old event distances identify the same node groups.
	return int({250: 150, 500: 400, 750: 700}.get(distance, distance))

var definitions: Array[Dictionary] = []
var balance: Dictionary = {}
var feature_flags: Dictionary = {}
var available_exp: int = 0
var cycle_exp_earned: int = 0
var historical_exp_earned: int = 0
var purchased_mastery_nodes: Array[String] = []
var permanent_mastery_unlocks: Array[String] = []
var highest_distance: float = 0.0
var highest_act: int = 1
var first_summit_completed: bool = false
var prestige_count: int = 0
var sephirot_unlocked: bool = false
var malkuth_unlocked: bool = false
var threads_balance: int = 0
var run_ability_charges: Dictionary = {}
var run_ability_cooldowns: Dictionary = {}
var current_run_token: String = ""
var run_milestones: int = 0
var record_milestones: int = 0
var _committed_run_tokens: Array[String] = []
var _pending_milestones: Array[Dictionary] = []
var _by_id: Dictionary = {}

func _init() -> void:
	var node_data: Dictionary = _read_config("res://data/mastery/nodes.json")
	balance = _read_config("res://data/mastery/balance.json")
	feature_flags = _read_config("res://data/mastery/feature_flags.json").get("nodes", {}).duplicate(true)
	for entry: Dictionary in node_data.get("nodes", []):
		var node: Dictionary = entry.duplicate(true)
		var costs: Array = balance.special_costs if node.category == "SPC" else balance.normal_costs
		node.exp_cost = int(costs[int(node.sequence) - 1])
		definitions.append(node)
		_by_id[node.id] = node

func _read_config(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "Invalid mastery configuration: " + path)
	return parsed

func get_node_definition(node_id: String) -> Dictionary:
	return _by_id.get(node_id, {}).duplicate(true)

func set_feature_enabled(node_id: String, enabled: bool) -> bool:
	if not _by_id.has(node_id):
		return false
	feature_flags[node_id] = enabled
	return true

func exp_multiplier() -> int:
	return int(balance.malkuth_multiplier) if malkuth_unlocked else 1

func begin_run(run_token: String = "") -> void:
	current_run_token = run_token if not run_token.is_empty() else _new_token()
	run_milestones = 0
	run_ability_charges.clear()
	run_ability_cooldowns.clear()
	_pending_milestones.clear()

func _new_token() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func award_distance(peak: float, total_length: float) -> int:
	if not is_finite(peak) or not is_finite(total_length) or total_length <= 0.0:
		return 0
	var distance: float = clampf(peak, 0.0, minf(total_length, 1000.0))
	var reached: int = int(floor(distance / float(balance.milestone_distance)))
	var earned: int = (maxi(0, reached - run_milestones) * int(balance.run_exp) + maxi(0, reached - record_milestones) * int(balance.record_exp)) * exp_multiplier()
	if historical_exp_earned > MAX_SAFE_INTEGER - earned:
		return 0
	run_milestones = maxi(run_milestones, reached)
	record_milestones = maxi(record_milestones, reached)
	highest_distance = maxf(highest_distance, distance)
	available_exp += earned
	cycle_exp_earned += earned
	historical_exp_earned += earned
	_unlock_distance(distance, true)
	return earned

func _unlock_distance(distance: float, notify: bool) -> void:
	for milestone: int in UNLOCK_DISTANCES:
		if distance < milestone:
			continue
		var newly_unlocked: Array[String] = []
		for node: Dictionary in definitions:
			if int(node.unlock_milestone) == milestone and node.id not in permanent_mastery_unlocks:
				permanent_mastery_unlocks.append(node.id)
				newly_unlocked.append(node.id)
		if notify and not newly_unlocked.is_empty():
			_pending_milestones.append({"distance": milestone, "node_ids": newly_unlocked})

func get_new_unlocks() -> Array[String]:
	var result: Array[String] = []
	for event: Dictionary in _pending_milestones:
		result.append_array(event.node_ids)
	return result

func consume_pending_milestone() -> Dictionary:
	return {} if _pending_milestones.is_empty() else _pending_milestones.pop_front().duplicate(true)

func get_node_state(node_id: String) -> String:
	if not _by_id.has(node_id):
		return "disabled"
	var node: Dictionary = _by_id[node_id]
	if not node.enabled or not feature_flags.get(node_id, false):
		return "disabled"
	if node_id in purchased_mastery_nodes:
		return "purchased"
	if node_id not in permanent_mastery_unlocks or (node.category == "SPC" and not first_summit_completed):
		return "locked"
	for prerequisite: String in node.prerequisites:
		if prerequisite not in purchased_mastery_nodes:
			return "prerequisite"
	return "available" if available_exp >= int(node.exp_cost) else "insufficient_exp"

func can_purchase_node(node_id: String) -> bool:
	return get_node_state(node_id) == "available"

func purchase_node(node_id: String) -> bool:
	if not can_purchase_node(node_id):
		return false
	available_exp -= int(_by_id[node_id].exp_cost)
	purchased_mastery_nodes.append(node_id)
	return true

func get_mastery_modifiers() -> Dictionary:
	var effects: Dictionary = {}
	var active: Array[String] = []
	for node: Dictionary in definitions:
		if node.id not in purchased_mastery_nodes or not node.enabled or not feature_flags.get(node.id, false):
			continue
		active.append(node.id)
		var key: String = node.effect_type
		if key in ["push_bonus", "capacity_bonus"]:
			effects[key] = float(effects.get(key, 0.0)) + float(node.effect_value)
		else:
			effects[key] = node.effect_value
	return {"purchased_nodes": active, "effects": effects}

func reset_purchased_mastery() -> void:
	purchased_mastery_nodes.clear()

func commit_prestige(run_token: String) -> bool:
	if run_token.is_empty() or run_token != current_run_token or run_token in _committed_run_tokens or run_milestones < 20:
		return false
	if threads_balance > MAX_SAFE_INTEGER - int(balance.threads_per_summit):
		return false
	_committed_run_tokens.append(run_token)
	prestige_count += 1
	first_summit_completed = true
	sephirot_unlocked = true
	malkuth_unlocked = true
	threads_balance += int(balance.threads_per_summit)
	available_exp = 0
	cycle_exp_earned = 0
	reset_purchased_mastery()
	run_milestones = 0
	run_ability_charges.clear()
	run_ability_cooldowns.clear()
	_pending_milestones.clear()
	return true

func import_legacy_record(distance: float) -> bool:
	# Only a new profile can import records; no legacy XP, points or ranks are converted.
	if not is_finite(distance) or distance < 0.0 or distance > 1000.0 or historical_exp_earned != 0 or highest_distance != 0.0:
		return false
	highest_distance = distance
	record_milestones = int(floor(distance / float(balance.milestone_distance)))
	_unlock_distance(minf(distance, 700.0), false)
	return true

func snapshot() -> Dictionary:
	return {"save_version": SAVE_VERSION, "available_exp": available_exp, "cycle_exp_earned": cycle_exp_earned,
		"historical_exp_earned": historical_exp_earned, "purchased_mastery_nodes": purchased_mastery_nodes.duplicate(),
		"permanent_mastery_unlocks": permanent_mastery_unlocks.duplicate(), "highest_distance": highest_distance,
		"highest_act": highest_act, "first_summit_completed": first_summit_completed, "prestige_count": prestige_count,
		"sephirot_unlocked": sephirot_unlocked, "malkuth_unlocked": malkuth_unlocked, "threads_balance": threads_balance,
		"run_ability_charges": run_ability_charges.duplicate(true), "run_ability_cooldowns": run_ability_cooldowns.duplicate(true),
		"current_run_token": current_run_token, "run_milestones": run_milestones, "record_milestones": record_milestones,
		"committed_run_tokens": _committed_run_tokens.duplicate(), "pending_milestones": _pending_milestones.duplicate(true)}

func restore(data: Dictionary) -> bool:
	# Validate into a temporary object, then replace all state together. Config flags never come from a save.
	if not _validate_snapshot(data):
		return false
	available_exp = int(data.available_exp)
	cycle_exp_earned = int(data.cycle_exp_earned)
	historical_exp_earned = int(data.historical_exp_earned)
	purchased_mastery_nodes.assign(data.purchased_mastery_nodes)
	permanent_mastery_unlocks.assign(data.permanent_mastery_unlocks)
	highest_distance = float(data.highest_distance)
	highest_act = int(data.highest_act)
	first_summit_completed = data.first_summit_completed
	prestige_count = int(data.prestige_count)
	sephirot_unlocked = data.sephirot_unlocked
	malkuth_unlocked = data.malkuth_unlocked
	threads_balance = int(data.threads_balance)
	run_ability_charges = data.run_ability_charges.duplicate(true)
	run_ability_cooldowns = data.run_ability_cooldowns.duplicate(true)
	current_run_token = data.current_run_token
	run_milestones = int(data.run_milestones)
	record_milestones = int(data.record_milestones)
	_committed_run_tokens.assign(data.committed_run_tokens)
	_pending_milestones.assign(data.pending_milestones.duplicate(true))
	for event: Dictionary in _pending_milestones:
		event.distance = normalized_unlock_distance(int(event.distance))
	# Grant newly eligible normal nodes silently: loading is not a new climb milestone.
	# Cap at the last normal group so legacy record imports never gain special eligibility.
	_unlock_distance(minf(highest_distance, 700.0), false)
	return true

func _validate_snapshot(data: Dictionary) -> bool:
	if data.size() != snapshot().size() or not _integer(data.get("save_version"), SAVE_VERSION, SAVE_VERSION):
		return false
	for key: String in ["available_exp", "cycle_exp_earned", "historical_exp_earned", "prestige_count", "threads_balance"]:
		if not _integer(data.get(key), 0, MAX_SAFE_INTEGER):
			return false
	if data.available_exp > data.cycle_exp_earned or data.cycle_exp_earned > data.historical_exp_earned:
		return false
	if not _integer(data.get("highest_act"), 1, 1) or not _number(data.get("highest_distance"), 0.0, 1000.0):
		return false
	for key: String in ["run_milestones", "record_milestones"]:
		if not _integer(data.get(key), 0, 20):
			return false
	if int(data.run_milestones) > int(data.record_milestones) or int(data.record_milestones) != int(floor(float(data.highest_distance) / 50.0)):
		return false
	for key: String in ["first_summit_completed", "sephirot_unlocked", "malkuth_unlocked"]:
		if not data.get(key) is bool or data[key] != (int(data.prestige_count) > 0):
			return false
	if int(data.prestige_count) > 0 and float(data.highest_distance) < 1000.0:
		return false
	if not _unique_strings(data.get("committed_run_tokens"), false) or data.committed_run_tokens.size() != int(data.prestige_count):
		return false
	if not data.get("current_run_token") is String or data.current_run_token.length() > 128:
		return false
	if not _unique_strings(data.get("purchased_mastery_nodes"), true) or not _unique_strings(data.get("permanent_mastery_unlocks"), true):
		return false
	var spent: int = 0
	for node_id: String in data.permanent_mastery_unlocks:
		if float(_by_id[node_id].unlock_milestone) > float(data.highest_distance):
			return false
	for node_id: String in data.purchased_mastery_nodes:
		var node: Dictionary = _by_id[node_id]
		if node_id not in data.permanent_mastery_unlocks or (node.category == "SPC" and not data.first_summit_completed):
			return false
		for predecessor: String in node.prerequisites:
			if predecessor not in data.purchased_mastery_nodes:
				return false
		spent += int(node.exp_cost)
	if spent > int(data.cycle_exp_earned) - int(data.available_exp):
		return false
	for key: String in ["run_ability_charges", "run_ability_cooldowns"]:
		if not data.get(key) is Dictionary or not _safe_json(data[key]):
			return false
	if not data.get("pending_milestones") is Array or data.pending_milestones.size() > 4:
		return false
	var seen: Array[int] = []
	for event: Variant in data.pending_milestones:
		if not event is Dictionary or event.size() != 2 or not _integer(event.get("distance"), 150, 1000):
			return false
		# Validate the original distance before normalizing legacy events to an earlier gate.
		if float(event.distance) > float(data.highest_distance):
			return false
		var distance: int = normalized_unlock_distance(int(event.distance))
		if distance not in UNLOCK_DISTANCES or distance in seen or not _unique_strings(event.get("node_ids"), true) or event.node_ids.is_empty():
			return false
		seen.append(distance)
		for node_id: String in event.node_ids:
			if node_id not in data.permanent_mastery_unlocks or int(_by_id[node_id].unlock_milestone) != distance:
				return false
	return true

func _unique_strings(value: Variant, node_ids: bool) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is String or item.is_empty() or item.length() > 128 or seen.has(item) or (node_ids and not _by_id.has(item)):
			return false
		seen[item] = true
	return true

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floor(float(value))

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _safe_json(value: Variant, depth: int = 0) -> bool:
	if depth > 8:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT, TYPE_FLOAT:
			return is_finite(float(value)) and absf(float(value)) <= MAX_SAFE_INTEGER
		TYPE_ARRAY:
			for item: Variant in value:
				if not _safe_json(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _safe_json(value[key], depth + 1):
					return false
			return true
	return false
