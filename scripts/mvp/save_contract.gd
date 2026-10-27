class_name MasterySave
extends RefCounted
## Validate without mutating the live world, controller or profile.
const Profile = preload("res://scripts/mastery_progression.gd")
const Mountain = preload("res://scripts/mountain_manager.gd")
const Controller = preload("res://scripts/mastery_boulder.gd")
const LIMIT: int = 9007199254740991
const PHASES: Array[String] = ["", "SUMMIT_REACHED", "FIRST_SUMMIT_SEQUENCE", "BOULDER_ROLLS_AWAY", "PRESTIGE_COMMIT", "SEPHIROT_REVEAL", "MALKUTH_UNLOCK", "NEW_RUN"]
const KEYS: Array[String] = ["version", "save_version", "saved_at_unix_msec", "revision", "world", "run", "mastery", "run_number", "falls_seen", "previous_best", "prestige_phase", "phase_elapsed", "modal_milestone", "settings"]

static func validate(payload: Dictionary) -> bool:
	if not _exact_keys(payload, KEYS) or not _safe_json(payload):
		return false
	if not _integer(payload.version, 5, 5) or not _integer(payload.save_version, 1, 1):
		return false
	if not _number(payload.saved_at_unix_msec, 0, LIMIT) or not _integer(payload.revision, 1, LIMIT):
		return false
	if not _integer(payload.run_number, 1, LIMIT) or not _integer(payload.falls_seen, 0, LIMIT):
		return false
	if not _number(payload.previous_best, 0, 1000) or not _number(payload.phase_elapsed, 0, 60):
		return false
	if not payload.prestige_phase is String or payload.prestige_phase not in PHASES:
		return false
	if not payload.mastery is Dictionary or not payload.run is Dictionary or not payload.world is Dictionary:
		return false
	var profile = Profile.new()
	if not profile.restore(payload.mastery) or profile.current_run_token.is_empty():
		return false
	if not _validate_world(payload.world):
		return false
	var world = Mountain.from_snapshot(payload.world)
	if world == null or not is_equal_approx(world.total_length, float(payload.world.total_length)):
		return false
	if not validate_run(payload.run, profile) or float(payload.run.peak) > world.total_length:
		return false
	if world.generation_version >= 3 and float(payload.run.velocity) > 1.8:
		return false
	var abilities: Dictionary = payload.run.mastery_run
	var charges: Dictionary = {"bre10_used": abilities.exhaustion_rescue_used, "spc02_charge": abilities.reserve_charge,
		"bre07_ready": abilities.inertia_ready, "spc05_remaining_m": abilities.departure_remaining}
	var cooldowns: Dictionary = {"str10_seconds": abilities.burst_seconds, "str10_cooldown": abilities.burst_cooldown,
		"bre07_seconds": abilities.inertia_seconds}
	if not _same_json(profile.run_ability_charges, charges) or not _same_json(profile.run_ability_cooldowns, cooldowns):
		return false
	if payload.run.state == "summit" and not is_equal_approx(float(payload.run.distance), world.total_length):
		return false
	if float(payload.previous_best) > profile.highest_distance or float(payload.run.peak) > profile.highest_distance + 0.000001:
		return false
	var committed: bool = profile.current_run_token in profile.snapshot().committed_run_tokens
	if payload.prestige_phase.is_empty():
		if committed or profile.run_milestones != int(floor(float(payload.run.peak) / 50.0)):
			return false
	else:
		if payload.run.state != "summit" or float(payload.run.peak) < 1000.0:
			return false
		if payload.prestige_phase in ["SUMMIT_REACHED", "FIRST_SUMMIT_SEQUENCE", "BOULDER_ROLLS_AWAY"] and committed:
			return false
		if payload.prestige_phase in ["SEPHIROT_REVEAL", "MALKUTH_UNLOCK", "NEW_RUN"] and not committed:
			return false
		if (committed and profile.run_milestones != 0) or (not committed and profile.run_milestones != 20):
			return false
	if not _validate_modal(payload.modal_milestone, profile) or (not payload.modal_milestone.is_empty() and not payload.prestige_phase.is_empty()):
		return false
	if not _exact_keys(payload.settings, ["muted", "volume", "fullscreen"]):
		return false
	if not payload.settings.muted is bool or not payload.settings.fullscreen is bool or not _number(payload.settings.volume, 0, 1):
		return false
	return true

static func validate_run(snapshot: Dictionary, profile: RefCounted) -> bool:
	if not profile is Profile:
		return false
	var prototype = Controller.new()
	prototype.apply_mastery_effects(profile.get_mastery_modifiers())
	if not _exact_keys(snapshot, prototype.snapshot().keys()) or not _safe_json(snapshot):
		return false
	for field: String in ["distance", "peak"]:
		if not _number(snapshot[field], 0, 1000):
			return false
	if float(snapshot.peak) < float(snapshot.distance):
		return false
	if not _number(snapshot.velocity, -65, 2.5) or not _number(snapshot.stamina, 0, prototype.max_stamina + 0.000001):
		return false
	if not _number(snapshot.slip, 0, 100) or not _number(snapshot.slip_remaining, 0, 1):
		return false
	if not _number(snapshot.accumulator, 0, 1.0 / 120.0 + 0.00000001):
		return false
	for field: String in ["elapsed", "runaway_elapsed"]:
		if not _number(snapshot[field], 0, LIMIT):
			return false
	for field: String in ["slips", "partial_falls"]:
		if not _integer(snapshot[field], 0, LIMIT):
			return false
	if not snapshot.state is String or snapshot.state not in ["climbing", "runaway", "result", "summit"] or not snapshot.falling_active is bool:
		return false
	if not _boolean_map(snapshot.cleared_ledges, false) or not _validate_abilities(snapshot.mastery_run, prototype.ability):
		return false
	return true

static func _validate_abilities(ability: Variant, template: Dictionary) -> bool:
	if not _exact_keys(ability, template.keys()):
		return false
	for key: String in template:
		if template[key] is bool:
			if not ability[key] is bool:
				return false
		elif template[key] is Dictionary:
			if not _boolean_map(ability[key], true):
				return false
		elif template[key] is String:
			if not ability[key] is String or (not ability[key].is_empty() and not _shelf_key(ability[key])):
				return false
		elif not _number(ability[key], 0, LIMIT):
			return false
	for key: String in ["inertia_activations", "brake_reductions", "reserve_uses"]:
		if not _integer(ability[key], 0, LIMIT):
			return false
	if not _integer(ability.reserve_charge, 0, 1):
		return false
	var bounds: Dictionary = {"burst_seconds": .5, "burst_cooldown": 2.0, "inertia_seconds": 1.0,
		"inertia_budget": 2.0, "inertia_frontier": 1000.0, "departure_remaining": 10.0}
	for key: String in bounds:
		if float(ability[key]) > float(bounds[key]) + 0.000000001:
			return false
	if float(ability.inertia_progress) >= 5.0:
		return false
	return true

static func _validate_world(data: Dictionary) -> bool:
	if not _exact_keys(data, ["generation_version", "seed", "legacy", "weather", "chunks", "surfaces", "total_length", "debug_mode"]):
		return false
	if not _integer(data.generation_version, 1, 6) or not _integer(data.seed, -LIMIT, LIMIT):
		return false
	if not data.legacy is bool or not data.debug_mode is bool or not data.weather is String:
		return false
	if data.legacy != (int(data.generation_version) == 1) or not _number(data.total_length, 1, 1000):
		return false
	if not data.chunks is Array or not data.surfaces is Dictionary or data.chunks.is_empty():
		return false
	for chunk: Variant in data.chunks:
		if not chunk is Dictionary:
			return false
		for key: String in ["length", "climb_length", "start_angle", "end_angle"]:
			if not _number(chunk.get(key), 0, 1000):
				return false
		for key: String in ["zone_index", "difficulty"]:
			if not _integer(chunk.get(key), 0, 5):
				return false
		if not chunk.get("id") is String or not chunk.get("surface_type") is String:
			return false
		if not chunk.get("ledge_offsets", []) is Array or not chunk.get("wet_ranges", []) is Array:
			return false
		for offset: Variant in chunk.get("ledge_offsets", []):
			if not _number(offset, 0, float(chunk.length)):
				return false
		for wet: Variant in chunk.get("wet_ranges", []):
			if not wet is Array or wet.size() != 2 or not _number(wet[0], 0, float(chunk.length)) or not _number(wet[1], 0, float(chunk.length)):
				return false
	for surface: Variant in data.surfaces.values():
		if not surface is Dictionary:
			return false
		for key: String in ["grip", "resistance", "slipperiness"]:
			if not _number(surface.get(key), 0, 5):
				return false
	return true

static func _validate_modal(value: Variant, profile: RefCounted) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not _exact_keys(value, ["distance", "node_ids"]) or not _integer(value.distance, 150, 750):
		return false
	var distance: int = Profile.normalized_unlock_distance(int(value.distance))
	if distance not in [150, 400, 700] or float(value.distance) > profile.highest_distance:
		return false
	if not value.node_ids is Array or value.node_ids.size() != 10:
		return false
	var seen: Dictionary = {}
	for id: Variant in value.node_ids:
		if not id is String or seen.has(id) or id not in profile.permanent_mastery_unlocks:
			return false
		if int(profile.get_node_definition(id).unlock_milestone) != distance:
			return false
		seen[id] = true
	return true

static func _boolean_map(value: Variant, shelf_keys: bool) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if not key is String or key.is_empty() or value[key] != true or not value[key] is bool:
			return false
		if shelf_keys and not _shelf_key(key):
			return false
	return true

static func _shelf_key(key: String) -> bool:
	var parts: PackedStringArray = key.split(":")
	if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
		return false
	return _number(float(parts[0]), 0, 1000) and _number(float(parts[1]), 0, 1000) and float(parts[0]) < float(parts[1]) and key == "%.6f:%.6f" % [float(parts[0]), float(parts[1])]

static func _exact_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: Variant in keys:
		if not value.has(key):
			return false
	return true

static func _same_json(first: Variant, second: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(first)) == JSON.parse_string(JSON.stringify(second))

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floor(float(value))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _safe_json(value: Variant, depth: int = 0) -> bool:
	if depth > 16:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT, TYPE_FLOAT:
			return is_finite(float(value)) and absf(float(value)) <= LIMIT
		TYPE_ARRAY:
			for item: Variant in value:
				if not _safe_json(item, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not _safe_json(value[key], depth + 1): return false
			return true
	return false
